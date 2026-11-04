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

func reset(seed_value: int, starting_area: Rect2i) -> void:
	generator = MapGenerator.new(seed_value, starting_area)
	navigation.clear()
	for collection in [visible_tiles, powered_devices, ready_drills, power_output,
			power_graph, power_nodes]:
		collection.clear()
	power_signature = 0
	pollution.clear()

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
