extends RefCounted

signal traced(worker_id: int, event: String, data: Dictionary)

const Definitions = preload("res://scripts/simulation/smart_object_definitions.gd")
const ObjectInstance = preload("res://scripts/simulation/smart_object_instance.gd")
const MapGenerator = preload("res://scripts/map_generator.gd")
const Action = Definitions.Action

var tracing := false
# Only claim state is authoritative and saved. Definitions, bindings and indexes are derived.
var slots: Dictionary = {}
var next_identity := 1
var next_claim := 1
var definitions := Definitions.new()
var instances: Dictionary = {}
var endpoints: Dictionary = {}
var _actions: Dictionary = {}
var _types: Dictionary = {}
var _skills: Dictionary = {}
var _items: Dictionary = {}
var _materials: Dictionary = {}
var _locations: Dictionary = {}
var _instances: Dictionary = {}
var _orders: Dictionary = {}
var _next_order := 0
var _building_open: Callable

static func key(kind: String, p: Vector2i) -> String:
	return "%s:%d:%d" % [kind, p.x, p.y]

static func delivery_key(task: Dictionary) -> String:
	return "delivery:%d" % task.id

static func building_id(id: int) -> StringName:
	return StringName("building:%d" % id)

func clear() -> void:
	for id in slots:
		note(slots[id].owner, "invalidated", {"slot": id, "reason": "world_reset"})
	slots.clear()
	clear_derived()
	# Keep serials monotonic so stale handles cannot refer to a reset world's slots.

func configure(game) -> void:
	definitions.configure(game)
	_building_open = game.building_open

func clear_derived() -> void:
	for collection in [instances, endpoints, _actions, _types, _skills, _items, _materials, _locations, _instances, _orders]: collection.clear()
	_next_order = 0

func rebuild(game, world) -> void:
	configure(game)
	clear_derived()
	for id in slots:
		_orders[id] = _next_order
		_next_order += 1
	refresh(game, world, false)

func sync(game) -> void:
	configure(game)
	game.sync_mining_contracts()
	game.sync_delivery_tasks()
	refresh(game, game.world, true)

func refresh(game, world, create_claims: bool) -> void:
	var present: Dictionary = {}
	var physical: Dictionary = {}
	for entity in world.buildings.values():
		var p: Vector2i = world.building_map.origin(entity.id)
		var source: Dictionary = entity.state
		var blueprint: bool = entity.in_group("site")
		var definition = definitions.blueprints[entity.kind] if blueprint else definitions.buildings[entity.kind]
		var object = bind_instance(physical, building_id(entity.id), definition, source, p, create_claims)
		if blueprint and source.get("cancelled", false): continue
		for interaction in definition.interactions:
			if interaction.action == Action.STORE and not is_same(world.building_at(p), entity): continue
			var materials: Array = []
			if interaction.action in [Action.WORK, Action.BUILD, Action.SERVICE]:
				materials = source.materials.keys() if blueprint else definition.materials.keys()
				if entity.kind == "research_bench" and not blueprint:
					materials = game.Technology.PROJECTS.get(source.get("research", ""), {}).get("materials", {}).keys()
			for offset in interaction.offsets:
				publish(present, key(interaction.name, p + offset), object, interaction, source, p + offset, interaction.items, create_claims, materials)
	for p in world.ground_items:
		if world.has_building(p): continue
		var object = bind_instance(physical, StringName(key("ground", p)), definitions.stock, world.ground_items[p].items, p, create_claims)
		var interaction = definitions.stock.interactions[0]
		publish(present, key(interaction.name, p), object, interaction, object.source, p, interaction.items, create_claims)
	for p in world.wild_resources:
		var source: Dictionary = world.wild_resources[p]
		if source.stock <= 0: continue
		var definition = definitions.resources[source.item]
		var object = bind_instance(physical, StringName(key("resource", p)), definition, source, p, create_claims)
		var interaction = definition.interactions[0]
		publish(present, key(interaction.name, p), object, interaction, source, p, interaction.items, create_claims)
	for p in world.mining_contracts:
		var source: Dictionary = world.mining_contracts[p]
		var object = bind_instance(physical, StringName(key("deposit", p)), definitions.deposit, source, p, create_claims)
		var interaction = definitions.deposit.interactions[0]
		var ore: int = world.terrain.get(p, 0)
		var item = game.ORES[ore].get("item", ore)
		publish(present, key(interaction.name, p), object, interaction, source, p, [item], create_claims)
	for task in world.delivery_tasks: publish_delivery(world, task, present, physical, create_claims)
	if create_claims:
		for id in slots.keys():
			if not present.has(id): invalidate(id)
	for id in endpoints.keys():
		if not present.has(id): remove_endpoint(id)
	for id in instances.keys():
		if not physical.has(id): instances.erase(id)

func add_delivery(game, task: Dictionary) -> void:
	configure(game)
	publish_delivery(game.world, task, {}, {}, true)

func publish_delivery(world, task: Dictionary, present: Dictionary, physical: Dictionary, create_claims: bool) -> void:
	var skill: String = "construction" if world.has_building(task.target, "site") else Definitions.JOB_SKILLS.get(world.building_state(task.target, "station", {}).get("kind", "bank" if world.has_building(task.target, "bank") else ""), "")
	var definition = definitions.requests[skill]
	var object = bind_instance(physical, StringName(delivery_key(task)), definition, task, task.target, create_claims)
	var interaction = definition.interactions[0]
	var item = task.item if task.bound else task.requested_item
	var items: Array = Definitions.MINERALS if is_same(item, 0) else [item]
	publish(present, delivery_key(task), object, interaction, task, task.target, items, create_claims)

func bind_instance(present: Dictionary, id: StringName, definition: Definitions.ObjectDefinition, source: Dictionary, p: Vector2i, create_claims: bool):
	present[id] = true
	if instances.has(id):
		var object = instances[id]
		if object.definition == definition and is_same(object.source, source):
			object.position = p
			return object
		for slot_id in object.slot_ids.keys():
			if create_claims: invalidate(slot_id)
			else: remove_endpoint(slot_id)
	var object := ObjectInstance.new(id, definition, source, p)
	instances[id] = object
	return object

func publish(present: Dictionary, id: String, object, interaction: Definitions.SlotDefinition, source: Dictionary, p: Vector2i, items: Array, create_claims: bool, materials: Array = []) -> void:
	present[id] = true
	if not slots.has(id) or not is_same(slots[id].source, source):
		if not create_claims: return
		invalidate(id)
		slots[id] = {"identity": next_identity, "source": source, "position": p, "shared": interaction.shared,
			"owner": -1, "claim": 0, "occupied": false}
		next_identity += 1
	slots[id].position = p
	if endpoints.has(id):
		var endpoint = endpoints[id]
		if endpoint.instance == object and endpoint.definition == interaction and endpoint.position == p and endpoint.items == items and endpoint.materials == materials: return
		remove_endpoint(id)
	if not _orders.has(id):
		_orders[id] = _next_order
		_next_order += 1
	var endpoint := ObjectInstance.Endpoint.new(id, object, interaction, slots[id], p, items, materials, _orders[id])
	endpoints[id] = endpoint
	object.slot_ids[id] = true
	index_endpoint(endpoint, true)

func index_entry(index: Dictionary, value, endpoint, adding: bool) -> void:
	if adding:
		if not index.has(value): index[value] = {}
		index[value][endpoint.id] = endpoint
	elif index.has(value):
		index[value].erase(endpoint.id)
		if index[value].is_empty(): index.erase(value)

func index_endpoint(endpoint, adding: bool) -> void:
	index_entry(_actions, endpoint.definition.action, endpoint, adding)
	index_entry(_types, endpoint.instance.definition.kind, endpoint, adding)
	if endpoint.definition.skill != &"": index_entry(_skills, endpoint.definition.skill, endpoint, adding)
	for item in endpoint.items: index_entry(_items, item, endpoint, adding)
	for item in endpoint.materials: index_entry(_materials, item, endpoint, adding)
	index_entry(_locations, MapGenerator.chunk_at(endpoint.position), endpoint, adding)
	index_entry(_instances, endpoint.instance.id, endpoint, adding)

func remove_endpoint(id: String) -> void:
	if not endpoints.has(id): return
	var endpoint = endpoints[id]
	index_endpoint(endpoint, false)
	endpoint.instance.slot_ids.erase(id)
	endpoints.erase(id)

func query(action: int, filters: Dictionary = {}) -> Array:
	var buckets: Array = [_actions.get(action, {})]
	if filters.has("type"): buckets.append(_types.get(StringName(filters.type), {}))
	if filters.has("skill"): buckets.append(_skills.get(StringName(filters.skill), {}))
	if filters.has("item"): buckets.append(_items.get(filters.item, {}))
	if filters.has("material"): buckets.append(_materials.get(filters.material, {}))
	if filters.has("instance"): buckets.append(_instances.get(StringName(filters.instance), {}))
	var goods: Dictionary = {}
	if filters.has("items"):
		for item in filters.items: goods.merge(_items.get(item, {}))
		buckets.append(goods)
	var nearby: Dictionary = {}
	if filters.has("area"):
		var area: Rect2i = filters.area
		if not area.has_area(): return []
		var first := MapGenerator.chunk_at(area.position)
		var last := MapGenerator.chunk_at(area.end - Vector2i.ONE)
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1): nearby.merge(_locations.get(Vector2i(x, y), {}))
		buckets.append(nearby)
	var smallest: Dictionary = buckets[0]
	for bucket in buckets:
		if bucket.size() < smallest.size(): smallest = bucket
	var result: Array = []
	for id in smallest:
		var matching := true
		for bucket in buckets:
			if not bucket.has(id):
				matching = false
				break
		if not matching: continue
		var endpoint = smallest[id]
		if endpoint.definition.gate == Definitions.Gate.STAFFED and not _building_open.call(endpoint.instance.position): continue
		if filters.has("available_to") and not endpoint.available_to(filters.available_to): continue
		if filters.has("area") and not filters.area.has_point(endpoint.position): continue
		result.append(endpoint)
	result.sort_custom(func(a, b): return a.order < b.order)
	return result

func positions(action: int, filters: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for endpoint in query(action, filters): result.append(endpoint.position)
	return result

func delivery_requests(filters: Dictionary = {}) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	for endpoint in query(Action.DELIVERY, filters):
		if not endpoint.available_to(-1): continue
		var task: Dictionary = endpoint.state.source
		if task.get("on_belt", false): continue
		if not task.bound or task.owner == -1: requests.append(task)
	return requests

func available(id: String, worker_id := -1) -> bool:
	return slots.has(id) and (slots[id].owner == -1 or slots[id].owner == worker_id)

func identity(id: String) -> int:
	return slots.get(id, {}).get("identity", -1)

func acquire(ids: Array[String], worker_id: int) -> Array[Dictionary]:
	# Validate the entire bundle before writing any slot (e.g. drill + mineral).
	for id in ids:
		if not available(id) or slots[id].shared:
			note(worker_id, "claim_rejected", {"slots": ids, "blocked_slot": id,
				"owner": owner(id), "reason": "missing" if not slots.has(id) else "shared" if slots[id].shared else "occupied"})
			return []
	var handles: Array[Dictionary] = []
	for id in ids:
		var slot: Dictionary = slots[id]
		slot.owner = worker_id
		slot.claim = next_claim
		next_claim += 1
		handles.append({"key": id, "identity": slot.identity, "claim": slot.claim, "owner": worker_id})
	if not handles.is_empty():
		note(worker_id, "reserved", {"claims": handles})
	return handles

func valid(handle: Dictionary) -> bool:
	var slot: Dictionary = slots.get(handle.key, {})
	return not slot.is_empty() and slot.identity == handle.identity and slot.claim == handle.claim and slot.owner == handle.owner

func occupy(handles: Array[Dictionary]) -> bool:
	for handle in handles:
		if not valid(handle):
			note(handle.owner, "occupy_rejected", {"claim": handle, "reason": "stale_handle"})
			return false
	for handle in handles:
		slots[handle.key].occupied = true
	if not handles.is_empty():
		note(handles[0].owner, "occupied", {"claims": handles})
	return true

func release(handles: Array[Dictionary]) -> void:
	for handle in handles:
		if valid(handle):
			note(handle.owner, "released", {"claim": handle})
			var slot: Dictionary = slots[handle.key]
			slot.owner = -1
			slot.occupied = false
			slot.claim = 0
		else:
			note(handle.owner, "release_ignored", {"claim": handle, "reason": "stale_handle"})

func invalidate(id: String) -> void:
	remove_endpoint(id)
	if slots.has(id): note(slots[id].owner, "invalidated", {"slot": id, "reason": "removed"})
	slots.erase(id)
	_orders.erase(id)

func note(worker_id: int, event: String, data: Dictionary) -> void:
	if tracing and worker_id >= 0:
		traced.emit(worker_id, event, data)

func owner(id: String) -> int:
	return slots.get(id, {}).get("owner", -1)
