extends RefCounted

signal traced(worker_id: int, event: String, data: Dictionary)

const Definitions = preload("res://scripts/simulation/smart_object_definitions.gd")
const ObjectInstance = preload("res://scripts/simulation/smart_object_instance.gd")
const MapGenerator = preload("res://scripts/map_generator.gd")
const Technology = preload("res://scripts/technology.gd")
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
var _domains: Dictionary = {}
var _types: Dictionary = {}
var _items: Dictionary = {}
var _materials: Dictionary = {}
var _locations: Dictionary = {}
var _instances: Dictionary = {}
var _orders: Dictionary = {}
var _next_order := 0
var _building_open: Callable
var _labor_offer: Callable

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
	_labor_offer = game.labor_offer

func clear_derived() -> void:
	for collection in [instances, endpoints, _actions, _domains, _types, _items, _materials, _locations, _instances, _orders]: collection.clear()
	_next_order = 0

func begin_rebuild() -> void:
	clear_derived()
	for id in slots:
		_orders[id] = _next_order
		_next_order += 1

func finish_rebuild() -> void:
	# Older snapshots may include slots left over from the last simulation step.
	for id in slots.keys():
		if not endpoints.has(id): invalidate(id)

func register_building(entity, p: Vector2i, primary: bool) -> void:
	var id := building_id(entity.id)
	if entity.in_group("site") and entity.state.get("cancelled", false):
		unregister(id)
		return
	var blueprint: bool = entity.in_group("site")
	var definition = definitions.demolitions[entity.kind] if entity.phase == entity.Phase.DEMOLISHING else definitions.blueprints[entity.kind] if blueprint else definitions.buildings[entity.kind]
	var object = bind_instance(id, definition, entity.state, p)
	var present: Dictionary = {}
	for interaction in definition.interactions:
		if interaction.action == Action.STORE and not primary: continue
		var materials: Array = []
		if interaction.method != "" or interaction.action == Action.SERVICE:
			materials = entity.state.materials.keys() if blueprint else definition.materials.keys()
			if entity.kind == "research_bench" and not blueprint:
				materials = Technology.PROJECTS.get(entity.state.get("research", ""), {}).get("materials", {}).keys()
		for offset in interaction.offsets:
			var slot_id := key(interaction.name, p + offset)
			present[slot_id] = true
			publish(slot_id, object, interaction, p + offset, interaction.items, materials)
	for slot_id in object.slot_ids.keys():
		if not present.has(slot_id): invalidate(slot_id)

func register_ground(p: Vector2i, source: Dictionary) -> void:
	register_point("ground", p, source, definitions.stock, definitions.stock.interactions[0].items)

func register_resource(p: Vector2i, source: Dictionary) -> void:
	var definition = definitions.resources[source.item]
	register_point("resource", p, source, definition, definition.interactions[0].items)

func register_deposit(p: Vector2i, source: Dictionary, item) -> void:
	register_point("deposit", p, source, definitions.deposit, [item])

func register_point(kind: String, p: Vector2i, source: Dictionary, definition, items: Array) -> void:
	var object = bind_instance(StringName(key(kind, p)), definition, source, p)
	var interaction = definition.interactions[0]
	publish(key(interaction.name, p), object, interaction, p, items)

func register_delivery(task: Dictionary) -> void:
	var id := delivery_key(task)
	var definition = definitions.delivery
	var object = bind_instance(StringName(id), definition, task, task.target)
	var item = task.item if task.bound else task.requested_item
	var items: Array = Definitions.MINERALS if is_same(item, 0) else [item]
	publish(id, object, definition.interactions[0], task.target, items)

func unregister(id: StringName) -> void:
	if not instances.has(id): return
	for slot_id in instances[id].slot_ids.keys(): invalidate(slot_id)
	instances.erase(id)

func bind_instance(id: StringName, definition: Definitions.ObjectDefinition, source: Dictionary, p: Vector2i):
	if instances.has(id):
		var object = instances[id]
		if object.definition == definition and is_same(object.source, source):
			object.position = p
			return object
		unregister(id)
	var object := ObjectInstance.new(id, definition, source, p)
	instances[id] = object
	return object

func publish(id: String, object, interaction: Definitions.SlotDefinition, p: Vector2i, items: Array, materials: Array = []) -> void:
	var source: Dictionary = object.source
	if not slots.has(id) or not is_same(slots[id].source, source):
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
	index_entry(_domains, endpoint.instance.definition.domain, endpoint, adding)
	index_entry(_types, endpoint.instance.definition.kind, endpoint, adding)
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

func query(action: String, filters: Dictionary = {}) -> Array:
	var buckets: Array = [_actions.get(action, {})]
	if filters.has("type"): buckets.append(_types.get(StringName(filters.type), {}))
	if filters.has("domain"): buckets.append(_domains.get(filters.domain, {}))
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

func positions(action: String, filters: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for endpoint in query(action, filters): result.append(endpoint.position)
	return result

func labor_offer(endpoint, worker_id = null) -> Dictionary:
	return _labor_offer.call(endpoint, worker_id)

func building_labor_demand(id: int) -> String:
	var object = instances.get(building_id(id))
	if object == null: return ""
	for slot_id in object.slot_ids:
		var endpoint = endpoints[slot_id]
		if endpoint.definition.method != "" and not labor_offer(endpoint).has("reason"):
			return endpoint.definition.action
	return ""

func delivery_demands(area: Rect2i) -> Dictionary:
	# Include claimed and belt shipments: a request is outstanding until delivery.
	var by_receiver: Dictionary = {}
	var action: String = definitions.delivery.interactions[0].action
	for endpoint in query(action, {"domain": Definitions.Domain.REQUEST, "area": area}):
		var task: Dictionary = endpoint.instance.source
		if task.receiver_id < 0: continue
		if not by_receiver.has(task.receiver_id): by_receiver[task.receiver_id] = {}
		var goods: Dictionary = by_receiver[task.receiver_id]
		goods[task.requested_item] = goods.get(task.requested_item, 0.0) + task.amount
	return by_receiver

func available(id: String, worker_id := -1) -> bool:
	return slots.has(id) and (slots[id].owner == -1 or slots[id].owner == worker_id)

func identity(id: String) -> int:
	return slots.get(id, {}).get("identity", -1)

func snapshot_claims() -> Dictionary:
	# Pointer-held labor is a gesture, not a resumable resident activity.
	var saved := slots.duplicate()
	for id in slots:
		if slots[id].owner >= -1: continue
		saved[id] = slots[id].duplicate()
		saved[id].merge({"owner": -1, "claim": 0, "occupied": false}, true)
	return saved

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
