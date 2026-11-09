extends RefCounted

const Portal = preload("res://scripts/portal.gd")
const SmartObjects = preload("res://scripts/simulation/smart_objects.gd")

# Authoritative simulation state, explicitly encoded by persistence/world_snapshot.gd.
# This runtime object is not itself a serialized save format.
var world_seed := 0
var generated_chunks: Dictionary = {}
var terrain: Dictionary = {}
var water_sources: Dictionary = {}
var explored: Dictionary = {}
var mining_contracts: Dictionary = {}
var sites: Dictionary = {}
var beds: Dictionary = {}
var benches: Dictionary = {}
var banks: Dictionary = {}
var belts: Dictionary = {}
var power_lines: Dictionary = {}
var belt_cargo: Dictionary = {}
var next_cargo_id := 0
# Free stock and task-bound stock together form the source's physical inventory.
var stores: Dictionary = {}
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
var wastewater: Dictionary = {}
# Last step's actual emissions are the source facts for the displayed field.
var pollution_operations: Dictionary = {}
var research_progress: Dictionary = {}

func reset(seed_value: int, base: Vector2i, starting_bread: float) -> void:
	world_seed = seed_value
	for collection in [generated_chunks, terrain, water_sources, explored,
			mining_contracts, sites, beds, benches, banks, belts, power_lines,
			belt_cargo, stores, daily_records, daily_mined, resource_flows,
			wastewater, pollution_operations, research_progress]:
		collection.clear()
	delivery_tasks.clear()
	# Keep the registry's serials monotonic across worlds, invalidating old claims.
	smart_objects.clear()
	newborns.clear()
	workers.clear()
	inventory_history.clear()
	stores[base] = {"bread": starting_bread}
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
	var load: float = wastewater.get(p, 0.0) * clampf(amount / stock, 0, 1) if stock > 0 else 0.0
	add_waste(p, -load)
	return load

func add_waste(p: Vector2i, amount: float) -> void:
	var total := maxf(0, wastewater.get(p, 0.0) + amount)
	if total <= 0.0000001: wastewater.erase(p)
	else: wastewater[p] = total
