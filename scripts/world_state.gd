extends RefCounted

const Portal = preload("res://scripts/portal.gd")
const SmartObjects = preload("res://scripts/simulation/smart_objects.gd")
const Building = preload("res://scripts/entities/building.gd")
const Storage = preload("res://scripts/entities/storage.gd")
const BuildingMap = preload("res://scripts/building_map.gd")
const BLOCKING_KINDS := ["wall", "fence"]

# Authoritative simulation state, explicitly encoded by persistence/world_snapshot.gd.
# This runtime object is not itself a serialized save format.
var world_seed := 0
var generated_chunks: Dictionary = {}
var terrain: Dictionary = {}
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
# Actual goods held by the mouse, not a second player inventory.
var player_cargo: Dictionary = {}
var delivery_tasks: Array[Dictionary] = []
var next_delivery_task_id := 0
var workers: Array[Dictionary] = []
var next_worker_id := 0
# Reservations affect future actions and must not be discarded with caches.
var smart_objects := SmartObjects.new()
var newborns: Array[Dictionary] = []
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

func walkable(p: Vector2i) -> bool:
	return terrain.has(p) and not water_sources.has(p) and building_state(p, "station").get("kind", "") not in BLOCKING_KINDS

func create_building(kind: String, p: Vector2i, cells: Array[Vector2i], settings: Dictionary, blueprint := false):
	var building := Building.new()
	building.id = next_building_id
	next_building_id += 1
	building.state = settings
	building.state.kind = kind
	building.phase = Building.Phase.BLUEPRINT if blueprint else Building.Phase.BUILT
	buildings[building.id] = building
	building_map.place(building.id, p, cells)
	if ground_items.has(p):
		ground_items[p].transfer_to(building.inventory)
		ground_items.erase(p)
	return building

func remove_building(building) -> void:
	# A removed container leaves any remaining actual goods on the ground.
	var p := building_map.origin(building.id)
	if not building.inventory.is_empty():
		if not ground_items.has(p): ground_items[p] = Storage.new()
		building.inventory.transfer_to(ground_items[p])
	building_map.remove(building.id)
	buildings.erase(building.id)

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

func building_positions(group := "") -> Array:
	var result: Array = []
	for id in buildings:
		if buildings[id].in_group(group): result.append(building_map.origin(id))
	return result

func buildings_in(group := "") -> Array:
	var result: Array = []
	for id in buildings:
		if buildings[id].in_group(group): result.append(buildings[id])
	return result

func storage_at(p: Vector2i, create := false):
	var building = building_at(p)
	if building != null: return building.inventory
	if create and not ground_items.has(p): ground_items[p] = Storage.new()
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
	buildings.clear()
	building_map.clear()
	ground_items.clear()
	next_building_id = 0

func reset(seed_value: int, base: Vector2i, starting_money: float) -> void:
	world_seed = seed_value
	for collection in [generated_chunks, terrain, deposits, wild_resources, estates, water_sources, known_people,
			mining_contracts, belt_cargo, daily_records, daily_mined, resource_flows,
			pollution_operations, research_progress]:
		collection.clear()
	clear_buildings()
	delivery_tasks.clear()
	player_cargo.clear()
	# Keep the registry's serials monotonic across worlds, invalidating old claims.
	smart_objects.clear()
	newborns.clear()
	workers.clear()
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
