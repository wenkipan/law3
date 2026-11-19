extends RefCounted

const Portal = preload("res://scripts/portal.gd")
const SmartObjects = preload("res://scripts/simulation/smart_objects.gd")
const Building = preload("res://scripts/entities/building.gd")
const Storage = preload("res://scripts/entities/storage.gd")
const BuildingMap = preload("res://scripts/building_map.gd")
const ChunkIndex = preload("res://scripts/chunk_index.gd")
const Migration = preload("res://scripts/simulation/migration.gd")
const BLOCKING_KINDS := ["wall", "fence"]

# Authoritative simulation state, explicitly encoded by persistence/world_snapshot.gd.
# This runtime object is not itself a serialized save format.
var world_seed := 0
var starting_point := Vector2i.ZERO
var generated_chunks: Dictionary = {}
var terrain: Dictionary = {}
var biomes: Dictionary = {}
var oil_deposits: Dictionary = {}
# Absolute next-growth times, only for harvested forest cells.
var forest_regrowth: Dictionary = {}
var deposits: Dictionary = {}
var wild_resources: Dictionary = {}
var estates: Dictionary = {}
var water_sources: Dictionary = {}
var known_people: Dictionary = {}
var mining_contracts: Dictionary = {}
var buildings: Dictionary = {}
var next_building_id := 0
var building_map := BuildingMap.new()
var belt_cargo: Dictionary = {}
var next_cargo_id := 0
# Only loose ground goods live here. Every building owns its own Storage.
var ground_items: Dictionary = {}
var delivery_tasks: Array[Dictionary] = []
var next_delivery_task_id := 0
var workers: Array[Dictionary] = []
var next_worker_id := 0
# Reservations affect future actions and must not be discarded with caches.
var smart_objects := SmartObjects.new()
var newborns: Array[Dictionary] = []
# Completed lifecycle events are drained before a snapshot can be captured.
var emigrants: Array[int] = []
var migration_entry := Vector2i.ZERO
var living_quality := Migration.OUTSIDE_LIVING_QUALITY
var migration_rng := RandomNumberGenerator.new()
# Actual border flows, separate from production, consumption and local transfers.
var migration_goods: Dictionary = {}
var transactions: Array = []
var delivered := 0
var mined := 0
var day := 1
var day_elapsed := 0.0
var portal := Portal.new()
var wander_rng := RandomNumberGenerator.new()
var daily_records: Dictionary = {}
var daily_mined: Dictionary = {}
var resource_flows: Dictionary = {}
var inventory_history: Array[Dictionary] = []
var inventory_sample_time := 0.0
var fog_timer := 0.0
var recovery_timer := 0.0
# Last step's actual emissions are the source facts for the displayed field.
var pollution_operations: Dictionary = {}
var research_progress: Dictionary = {}

# Derived spatial lookups; no viewport or scene nodes belong to the world.
var worker_chunks := ChunkIndex.new()
var ground_chunks := ChunkIndex.new()
var cargo_chunks := ChunkIndex.new()
var building_revision := 0
# Derived from building ownership. Phase and position changes keep the same membership.
var _building_ids_by_owner: Dictionary = {}
var _building_ids_by_group: Dictionary[String, Array] = {}
var _built_ids_by_kind: Dictionary[String, Array] = {}

func rebuild_chunk_indexes() -> void:
	for index in [worker_chunks, ground_chunks, cargo_chunks]: index.clear()
	for w in workers: worker_chunks.place(w.id, Vector2i(w.pos.round()))
	for p in ground_items: ground_chunks.place(p, p)
	for id in belt_cargo: cargo_chunks.place(id, belt_cargo[id].to)

func rebuild_building_indexes() -> void:
	_building_ids_by_owner.clear()
	_building_ids_by_group.clear()
	_built_ids_by_kind.clear()
	for building in buildings.values():
		_index_building_owner(building)
		_index_building_categories(building, true)

func _index_building_owner(building: Building) -> void:
	var owner = building.state.get("owner", "player")
	var ids: Dictionary = _building_ids_by_owner.get_or_add(owner, {})
	ids[building.id] = true

func _index_building_categories(building: Building, adding: bool) -> void:
	for group in Building.GROUPS:
		if building.in_group(group):
			_update_building_category(_building_ids_by_group, group, building.id, adding)
	if building.phase == Building.Phase.BUILT:
		_update_building_category(_built_ids_by_kind, building.kind, building.id, adding)

func _update_building_category(index: Dictionary[String, Array], category: String, id: int, adding: bool) -> void:
	if adding:
		var ids: Array = index.get_or_add(category, [])
		# IDs follow creation order even when an older blueprint completes later.
		ids.insert(ids.bsearch(id), id)
	else:
		var ids: Array = index[category]
		ids.erase(id)
		if ids.is_empty(): index.erase(category)

func walkable(p: Vector2i) -> bool:
	if not terrain.has(p) or water_sources.has(p): return false
	for id in building_map.at_cell(p):
		var building = buildings[id]
		if building.phase in [Building.Phase.BUILT, Building.Phase.DEMOLISHING] and building.kind in BLOCKING_KINDS: return false
	return true

func create_building(kind: String, p: Vector2i, cells: Array[Vector2i], settings: Dictionary, blueprint := false):
	var building := Building.new()
	building.id = next_building_id
	next_building_id += 1
	building.state = settings
	building.state.kind = kind
	building.phase = Building.Phase.BLUEPRINT if blueprint else Building.Phase.BUILT
	buildings[building.id] = building
	_index_building_owner(building)
	_index_building_categories(building, true)
	building_map.place(building.id, p, cells)
	if ground_items.has(p):
		ground_items[p].transfer_to(building.inventory)
		ground_items.erase(p)
		ground_chunks.remove(p)
		smart_objects.unregister(StringName(SmartObjects.key("ground", p)))
	refresh_interactions_at(p)
	return building

func remove_building(building) -> void:
	# A removed container leaves any remaining actual goods on the ground.
	var p := building_map.origin(building.id)
	if not building.inventory.is_empty():
		if not ground_items.has(p): ground_items[p] = Storage.new()
		building.inventory.transfer_to(ground_items[p])
		ground_chunks.place(p, p)
	smart_objects.unregister(SmartObjects.building_id(building.id))
	building_map.remove(building.id)
	var owner = building.state.get("owner", "player")
	var ids: Dictionary = _building_ids_by_owner[owner]
	ids.erase(building.id)
	if ids.is_empty(): _building_ids_by_owner.erase(owner)
	_index_building_categories(building, false)
	buildings.erase(building.id)
	refresh_interactions_at(p)

func set_building_phase(building: Building, phase: Building.Phase, settings: Dictionary) -> void:
	_index_building_categories(building, false)
	building.state = settings
	building.phase = phase
	_index_building_categories(building, true)

func set_building_growth(building: Building, remaining: float) -> void:
	var was_growing := building.in_group("growing")
	building.state.growth = remaining
	var growing := building.in_group("growing")
	if growing != was_growing:
		_update_building_category(_building_ids_by_group, "growing", building.id, growing)

func move_building(building, target: Vector2i, cells: Array[Vector2i]) -> void:
	var origin := building_map.origin(building.id)
	building_map.place(building.id, target, cells)
	refresh_interactions_at(target)
	refresh_interactions_at(origin)

func refresh_interactions_at(p: Vector2i) -> void:
	building_revision += 1
	# A power line may share an origin with the primary storage container.
	var primary = building_at(p)
	for id in building_map.at_origin(p):
		smart_objects.register_building(buildings[id], p, is_same(buildings[id], primary))
	if primary == null and ground_items.has(p):
		smart_objects.register_ground(p, ground_items[p].items)
	else:
		smart_objects.unregister(StringName(SmartObjects.key("ground", p)))

func add_wild_resource(p: Vector2i, resource: Dictionary) -> void:
	wild_resources[p] = resource
	smart_objects.register_resource(p, resource)

func harvest_wild_resource(p: Vector2i) -> int:
	var resource: Dictionary = wild_resources[p]
	var amount := mini(1, resource.stock)
	resource.stock -= amount
	resource.task = {}
	if resource.stock <= 0:
		smart_objects.unregister(StringName(SmartObjects.key("resource", p)))
	return amount

func register_delivery(task: Dictionary) -> void:
	smart_objects.register_delivery(task)

func available_delivery_requests(work_type: String) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	for endpoint in smart_objects.query(work_type, {"domain": SmartObjects.Definitions.Domain.REQUEST, "available_to": -1}):
		var task: Dictionary = endpoint.instance.source
		if not task.get("on_belt", false) and task.owner == -1:
			requests.append(task)
	return requests

func rebuild_interactions(game) -> void:
	smart_objects.configure(game)
	smart_objects.begin_rebuild()
	for building in buildings.values():
		var p := building_map.origin(building.id)
		smart_objects.register_building(building, p, is_same(building, building_at(p)))
	for p in ground_items:
		if not has_building(p): smart_objects.register_ground(p, ground_items[p].items)
	for p in wild_resources:
		if wild_resources[p].stock > 0: smart_objects.register_resource(p, wild_resources[p])
	for p in mining_contracts:
		var ore: int = terrain.get(p, 0)
		smart_objects.register_deposit(p, mining_contracts[p], game.ORES[ore].get("item", ore))
	for task in delivery_tasks: register_delivery(task)
	smart_objects.finish_rebuild()

func building_at(p, group := ""):
	if not p is Vector2i: return null
	var fallback = null
	for id in building_map.at_origin(p):
		var building = buildings[id]
		if not building.in_group(group): continue
		if building.kind not in Building.LINES: return building
		fallback = building
	return fallback

func has_building(p, group := "") -> bool:
	return building_at(p, group) != null

func building_state(p, group := "", fallback: Dictionary = {}) -> Dictionary:
	var building = building_at(p, group)
	return building.state if building != null else fallback

func _positions_for_building_ids(ids: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for id in ids: result.append(building_map.origin(id))
	return result

func building_positions(group := "") -> Array[Vector2i]:
	return _positions_for_building_ids(buildings.keys() if group.is_empty() else _building_ids_by_group.get(group, []))

func has_buildings_in(group: String) -> bool:
	return not buildings.is_empty() if group.is_empty() else _building_ids_by_group.has(group)

func built_building_positions(kinds: Array) -> Array[Vector2i]:
	if kinds.size() == 1:
		return _positions_for_building_ids(_built_ids_by_kind.get(kinds[0], []))
	var ids: Array = []
	for kind in kinds: ids.append_array(_built_ids_by_kind.get(kind, []))
	ids.sort()
	return _positions_for_building_ids(ids)

func buildings_in(group := "") -> Array:
	if group.is_empty(): return buildings.values()
	var result: Array = []
	for id in _building_ids_by_group.get(group, []): result.append(buildings[id])
	return result

func buildings_owned_by(owner) -> Array[Building]:
	var result: Array[Building] = []
	for id in _building_ids_by_owner.get(owner, {}):
		result.append(buildings[id])
	return result

func storage_at(p: Vector2i, create := false):
	var building = building_at(p)
	if building != null: return building.inventory
	if create and not ground_items.has(p):
		ground_items[p] = Storage.new()
		ground_chunks.place(p, p)
		smart_objects.register_ground(p, ground_items[p].items)
	return ground_items.get(p)

func storage_locations() -> Array:
	var locations: Array = ground_items.keys()
	for id in buildings:
		var p := building_map.origin(id)
		if p not in locations: locations.append(p)
	return locations

func inventories() -> Array:
	var result: Array = ground_items.values()
	for building in buildings.values(): result.append(building.inventory)
	return result

func clear_buildings() -> void:
	building_revision += 1
	buildings.clear()
	_building_ids_by_owner.clear()
	_building_ids_by_group.clear()
	_built_ids_by_kind.clear()
	building_map.clear()
	ground_items.clear()
	ground_chunks.clear()
	next_building_id = 0

func reset(seed_value: int, base: Vector2i, starting_money: float) -> void:
	world_seed = seed_value
	starting_point = base
	for collection in [generated_chunks, terrain, biomes, oil_deposits, forest_regrowth, deposits, wild_resources, estates, water_sources, known_people,
			mining_contracts, belt_cargo, daily_records, daily_mined, resource_flows,
			pollution_operations, research_progress]:
		collection.clear()
	clear_buildings()
	delivery_tasks.clear()
	# Keep the registry's serials monotonic across worlds, invalidating old claims.
	smart_objects.clear()
	newborns.clear()
	emigrants.clear()
	migration_entry = base
	living_quality = Migration.OUTSIDE_LIVING_QUALITY
	migration_goods.clear()
	transactions.clear()
	migration_rng.seed = (str(seed_value) + ":migration").hash()
	workers.clear()
	worker_chunks.clear()
	cargo_chunks.clear()
	inventory_history.clear()
	storage_at(base, true).add("money", starting_money)
	next_cargo_id = 0
	next_delivery_task_id = 0
	next_worker_id = 0
	delivered = 0
	mined = 0
	day = 1
	day_elapsed = 0.0
	inventory_sample_time = 0.0
	fog_timer = 0.0
	recovery_timer = 0.0
	portal = Portal.new()
	wander_rng.seed = 1020

func worker(id: int) -> Dictionary:
	var first := 0
	var last := workers.size() - 1
	while first <= last:
		var middle := (first + last) / 2
		var person: Dictionary = workers[middle]
		if person.id == id: return person
		if person.id < id: first = middle + 1
		else: last = middle - 1
	return {}

func take_waste(p: Vector2i, amount: float, stock: float) -> float:
	var storage = storage_at(p)
	return storage.take_waste(amount, stock) if storage != null else 0.0

func add_waste(p: Vector2i, amount: float) -> void:
	var storage = storage_at(p, true)
	storage.wastewater_load = maxf(0.0, storage.wastewater_load + amount)

func waste_at(p: Vector2i) -> float:
	var storage = storage_at(p)
	return storage.wastewater_load if storage != null else 0.0
