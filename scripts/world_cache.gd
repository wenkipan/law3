extends RefCounted

const MapGenerator = preload("res://scripts/map_generator.gd")
const WorldNavigation = preload("res://scripts/world_navigation.gd")
const Pollution = preload("res://scripts/simulation/pollution.gd")

# Derived indexes and sampled fields, never inventories, contracts or claims.
var generator: RefCounted
var navigation := WorldNavigation.new()
var visible_tiles: Dictionary = {}
var powered_devices: Dictionary = {}
var ready_drills: Dictionary = {}
var power_output: Dictionary = {}
var power_graph: Dictionary = {}
var power_nodes: Dictionary = {}
var power_signature := 0
var pollution := Pollution.new()
var delivery_dirty := true
var delivery_receivers: Dictionary = {}
var belt_next: Dictionary = {}
var belt_destinations: Dictionary = {}
var receiver_belts: Dictionary = {}

func reset(seed_value: int, starting_area: Rect2i) -> void:
	generator = MapGenerator.new(seed_value, starting_area)
	navigation.clear()
	for collection in [visible_tiles, powered_devices, ready_drills, power_output,
			power_graph, power_nodes]:
		collection.clear()
	power_signature = 0
	pollution.clear()
	invalidate_delivery()
	delivery_receivers.clear()
	belt_next.clear()
	belt_destinations.clear()
	receiver_belts.clear()

func invalidate_delivery() -> void:
	delivery_dirty = true

func sync_delivery(g) -> void:
	if not delivery_dirty: return
	delivery_receivers = {g.BASE: g.BASE}
	belt_next.clear()
	belt_destinations.clear()
	receiver_belts.clear()
	for collection in [g.world.sites, g.world.benches, g.world.banks, g.world.beds]:
		for origin in collection:
			var kind: String = g.building_kind(origin)
			if is_same(collection, g.world.sites) and (collection[origin].get("cancelled", false) or kind in g.BELT_KINDS or kind in g.LINE_KINDS):
				continue
			for cell in g.building_cells(origin, kind):
				if not delivery_receivers.has(cell): delivery_receivers[cell] = origin
	for p in g.world.belts:
		var direction: Vector2i = g.world.belts[p].direction
		if direction == Vector2i.ZERO: continue
		var next: Vector2i = p + direction
		if delivery_receivers.has(next) or (g.world.belts.has(next) and -direction in g.world.belts[next].inputs):
			belt_next[p] = next
	# Resolve each downstream chain once, including dead ends and cycles.
	for start in g.world.belts:
		if belt_destinations.has(start): continue
		var trail: Array[Vector2i] = []
		var visited: Dictionary = {}
		var p: Vector2i = start
		var receiver = null
		while not visited.has(p):
			if belt_destinations.has(p):
				receiver = belt_destinations[p]
				break
			visited[p] = true
			trail.append(p)
			if not belt_next.has(p): break
			p = belt_next[p]
			if delivery_receivers.has(p):
				receiver = delivery_receivers[p]
				break
		for cell in trail: belt_destinations[cell] = receiver
	# Preserve belt iteration order so equal-length loading choices keep their ties.
	for p in g.world.belts:
		var receiver = belt_destinations[p]
		if receiver == null: continue
		if not receiver_belts.has(receiver): receiver_belts[receiver] = []
		receiver_belts[receiver].append(p)
	delivery_dirty = false

func rebuild(world, starting_area: Rect2i, sample: Dictionary) -> void:
	reset(world.world_seed, starting_area)
	for cell in world.terrain:
		if world.terrain[cell] == 0 and not world.water_sources.has(cell):
			navigation.set_point_solid(cell, false)
	visible_tiles = sample.visible_tiles
	powered_devices = sample.powered_devices
	ready_drills = sample.ready_drills
	power_output = sample.power_output
	pollution.rebuild_world(world)
