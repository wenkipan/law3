extends RefCounted

var game: Node
var scenario_name := ""

func _init(world: Node) -> void:
	game = world

# Only initial world facts belong here. Commands and autonomous activity stay in suites.
func scenario(label: String, population := 0, generated := false, seed_value := 1020, researched := true) -> void:
	scenario_name = label
	print("CASE: ", label)
	game.reset_world(seed_value)
	if not generated: game.world.starting_point = Vector2i(32, 13)
	game.world_view.camera.position = game.tile_center(game.BASE)
	game.world.workers.clear()
	game.world.known_people.clear()
	game.world.next_worker_id = 0
	game.world.clear_buildings()
	for collection in [game.world.wild_resources, game.world.deposits,
			game.world.mining_contracts, game.world.estates, game.world.forest_regrowth, game.world.oil_deposits]:
		collection.clear()
	game.world.delivery_tasks.clear()
	game.world.smart_objects.clear()
	game.world.storage_at(game.BASE, true).add("money", 600.0)
	if not generated:
		game.world.water_sources.clear()
		clear_area(Rect2i(Vector2i(0, 0), Vector2i(96, 64)))
	if researched:
		for project in game.Technology.PROJECTS:
			game.world.research_progress[project] = game.Technology.PROJECTS[project].points
	for i in population: resident("building_logistics", game.BASE + Vector2i(i, 3))
	game.cache.invalidate_delivery()
	game.update_fog()
	game.world_view.rebuild(game)

func resident(skill: String, p: Vector2i, _legacy_diet := "grain", contents: Dictionary = {}) -> Dictionary:
	var person: Dictionary = game.create_worker(p)
	person.skill = skill
	person.hunger = 130.0
	person.items = contents.duplicate()
	return person

func clear_area(area: Rect2i) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := Vector2i(x, y)
			game.world.terrain[p] = 0
			game.world.biomes[p] = game.MapGenerator.Biome.PLAIN
			game.world.water_sources.erase(p)
			game.cache.navigation.set_point_solid(p, false)

func station(kind: String, p: Vector2i) -> void:
	clear_area(Rect2i(p, Vector2i(game.building_size(p, kind) / game.CELL)))
	if game.REGION_BUILDINGS.has(kind): region(Rect2i(p, Vector2i(game.building_size(p, kind) / game.CELL)), game.REGION_BUILDINGS[kind])
	var building = game.create_building(p, kind, game.production_station(kind))
	if kind == "bank":
		building.state.interest_received = 0.0
	if kind in game.WorldState.BLOCKING_KINDS: game.cache.navigation.set_point_solid(p, true)
	game.cache.invalidate_delivery()

func stock_recipe(p: Vector2i, recipe: Dictionary) -> void:
	for item in recipe: game.add_stock(p, item, recipe[item])

func building_materials(kind: String, count := 1) -> void:
	for item in game.building_materials(kind):
		game.add_stock(game.BASE, item, game.building_materials(kind)[item] * count)

func materials(amount: int, ore := 1) -> void:
	for mineral in range(1, game.ORES.size()):
		game.add_stock(game.BASE, mineral, -game.stock_at(game.BASE, mineral))
	game.add_stock(game.BASE, ore, amount)

func region(area: Rect2i, biome: int) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x): game.world.biomes[Vector2i(x, y)] = biome

func deposit(p: Vector2i, ore := 2, remaining := 3) -> void:
	region(Rect2i(p, Vector2i(2, 2)), game.MapGenerator.Biome.FOREST if ore == 7 else game.MapGenerator.Biome.MOUNTAIN)
	game.world.terrain[p] = ore
	game.world.deposits[p] = remaining
	game.cache.navigation.set_point_solid(p, false)

func wild(p: Vector2i, item: String) -> void:
	game.world.add_wild_resource(p, game.wild_resource(item))

func bed(p: Vector2i) -> void:
	game.create_building(p, "bed", {"remaining": 0.0, "assigned": -1})
	game.cache.invalidate_delivery()

func belt(p: Vector2i, direction: Vector2i) -> void:
	var inputs: Array = game.DIRS.duplicate()
	inputs.erase(direction)
	game.create_building(p, "belt", {"direction": direction, "inputs": inputs, "last_input": -1, "materials": {1: game.BELT_BLOCKS}})
	game.cache.invalidate_delivery()

func cable(p: Vector2i, kind := "low_line", axis := Vector2i.RIGHT) -> void:
	game.create_building(p, kind, {"axis": axis, "materials": game.building_materials(kind).duplicate()})

func research_materials(p: Vector2i, project: String, batches := 1) -> void:
	for item in game.Technology.PROJECTS[project].materials:
		game.add_stock(p, item, game.Technology.PROJECTS[project].materials[item] * batches)
