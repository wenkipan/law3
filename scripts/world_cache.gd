extends RefCounted

const MapGenerator = preload("res://scripts/map_generator.gd")
const WorldNavigation = preload("res://scripts/world_navigation.gd")
const Pollution = preload("res://scripts/simulation/pollution.gd")

# Derived indexes and sampled fields, never inventories, contracts or claims.
var generator: RefCounted
var navigation := WorldNavigation.new()
var visible_tiles: Dictionary = {}
var sight_origins: Dictionary = {}
var sight_coverage: Dictionary = {}
var sight_offsets: Array[Vector2i] = []
var sight_ready := false
var sight_buildings: Dictionary = {}
var sight_building_revision := -1
var powered_devices: Dictionary = {}
var ready_drills: Dictionary = {}
var power_output: Dictionary = {}
var power_graph: Dictionary = {}
var power_nodes: Dictionary = {}
var power_building_revision := -1
var pollution := Pollution.new()
var delivery_dirty := true
var delivery_receivers: Dictionary = {}
var belt_next: Dictionary = {}
var belt_destinations: Dictionary = {}
var receiver_belts: Dictionary = {}
var supply_receivers: Dictionary = {}
var mining_drills: Dictionary = {}

func reset(seed_value: int) -> void:
	generator = MapGenerator.new(seed_value)
	navigation.clear()
	for collection in [visible_tiles, powered_devices, ready_drills, power_output,
			power_graph, power_nodes, sight_origins, sight_coverage, sight_buildings]:
		collection.clear()
	sight_ready = false
	sight_building_revision = -1
	power_building_revision = -1
	pollution.clear()
	invalidate_delivery()
	delivery_receivers.clear()
	belt_next.clear()
	belt_destinations.clear()
	receiver_belts.clear()
	supply_receivers.clear()
	mining_drills.clear()

func update_sight(origins: Dictionary, radius: int, terrain: Dictionary) -> Dictionary:
	if sight_ready and origins == sight_origins: return {}
	if sight_offsets.is_empty():
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if x * x + y * y <= radius * radius: sight_offsets.append(Vector2i(x, y))
	# On restore, compare against the last gameplay sample, not an empty mask.
	var changed: Dictionary = {} if sight_ready else visible_tiles.duplicate()
	for origin in sight_origins:
		if not origins.has(origin): change_coverage(origin, -1, changed)
	for origin in origins:
		if not sight_origins.has(origin): change_coverage(origin, 1, changed)
	sight_origins = origins
	sight_ready = true
	for p in changed.keys():
		var revealed := sight_coverage.has(p) and terrain.has(p)
		if revealed == visible_tiles.has(p):
			changed.erase(p)
		elif revealed:
			visible_tiles[p] = true
		else:
			visible_tiles.erase(p)
	return changed

func change_coverage(origin: Vector2i, amount: int, changed: Dictionary) -> void:
	for offset in sight_offsets:
		var p := origin + offset
		var count: int = sight_coverage.get(p, 0) + amount
		if count == 0: sight_coverage.erase(p)
		else: sight_coverage[p] = count
		changed[p] = true

func invalidate_delivery() -> void:
	delivery_dirty = true

func sync_delivery(g) -> void:
	if not delivery_dirty: return
	delivery_receivers = {g.BASE: g.BASE}
	belt_next.clear()
	belt_destinations.clear()
	receiver_belts.clear()
	for id in g.world.buildings:
		var building = g.world.buildings[id]
		var origin: Vector2i = g.world.building_map.origin(id)
		if building.in_group("site"):
			if building.state.get("cancelled", false) or building.kind in g.BELT_KINDS or building.kind in g.LINE_KINDS: continue
		elif building.kind in g.BARRIER_KINDS or building.kind in g.BELT_KINDS or building.kind in g.LINE_KINDS:
			continue
		for cell in g.world.building_map.placements[id].cells:
			if not delivery_receivers.has(cell): delivery_receivers[cell] = origin
	for p in g.world.building_positions("belt"):
		var direction: Vector2i = g.world.building_state(p, "belt").direction
		if direction == Vector2i.ZERO: continue
		var next: Vector2i = p + direction
		if delivery_receivers.has(next) or (g.world.has_building(next, "belt") and -direction in g.world.building_state(next, "belt").inputs):
			belt_next[p] = next
	# Resolve each downstream chain once, including dead ends and cycles.
	for start in g.world.building_positions("belt"):
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
	for p in g.world.building_positions("belt"):
		var receiver = belt_destinations[p]
		if receiver == null: continue
		if not receiver_belts.has(receiver): receiver_belts[receiver] = []
		receiver_belts[receiver].append(p)
	delivery_dirty = false

func rebuild(world, sample: Dictionary) -> void:
	reset(world.world_seed)
	for cell in world.terrain:
		if world.walkable(cell):
			navigation.set_point_solid(cell, false)
	visible_tiles = sample.visible_tiles
	powered_devices = sample.powered_devices
	ready_drills = sample.ready_drills
	power_output = sample.power_output
	pollution.rebuild_world(world)
