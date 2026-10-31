extends RefCounted

const INPUT_ROUTES := [
	{"source": "pump", "target": "purifier", "item": "raw_water", "amount": 4},
	{"source": "pump", "target": "farm", "item": "raw_water", "amount": 4},
]

var game: Node
var scenario_name := ""

func _init(world: Node) -> void:
	game = world

# Fixtures describe starting worlds, never in-flight tasks or decision state.
func scenario(label: String, population := 3, generated := false, seed_value := 1020) -> void:
	scenario_name = label
	print("CASE: ", label)
	game.reset_world(seed_value)
	if not generated:
		# Business scenarios use a quarry fixture, not a lucky generated starting area.
		game.water_sources.clear()
		for cell in game.terrain:
			game.terrain[cell] = 1
			game.navigation.set_point_solid(cell, true)
		clear_area(Rect2i(game.BASE - Vector2i(4, 2), Vector2i(9, 5)))
		var source := Vector2i(29, 10)
		game.water_sources[source] = true
		game.terrain[source] = 0
	game.workers.resize(population)
	# Business contracts retain their hungry starting fixture; birth is tested separately.
	for worker in game.workers:
		worker.hunger = 0
	game.world_view.rebuild(game)
	game.ai_trace.record(game, {}, "test", "scenario", {"name": label, "population": population})

func hungry_worker(p: Vector2i) -> Dictionary:
	var person: Dictionary = game.create_worker(p)
	person.hunger = 0
	return person

func station(kind: String, p: Vector2i, stock := 0) -> void:
	if kind == "pump" and not game.near_water_source(p):
		var source := p + Vector2i.UP
		game.water_sources[source] = true
		game.terrain[source] = 0
		game.navigation.set_point_solid(source, true)
	game.benches[p] = game.production_station(kind)
	game.benches[p].stock = stock

func materials(amount: int, ore := 1) -> void:
	for mineral in range(1, game.ORES.size()):
		game.add_stock(game.BASE, mineral, -game.stock_at(game.BASE, mineral))
	game.add_stock(game.BASE, ore, amount)

func stock_recipe(p: Vector2i, recipe: Dictionary) -> void:
	for item in recipe:
		game.add_stock(p, item, recipe[item])

func building_materials(kind: String, count := 1) -> void:
	materials(0)
	for ore in game.building_materials(kind):
		var amount: int = game.building_materials(kind)[ore] * count
		if is_same(ore, 0):
			game.add_stock(game.BASE, 1, maxi(0, amount - 2))
			game.add_stock(game.BASE, 2, mini(2, amount))
		else:
			game.add_stock(game.BASE, ore, amount)

func bed(p: Vector2i) -> void:
	game.beds[p] = {"remaining": 0.0, "assigned": -1}

func isolated_warehouse(contents: Dictionary) -> void:
	var p := Vector2i(50, 20)
	clear_area(Rect2i(p, Vector2i(2, 1)))
	bed(p)
	for item in contents:
		game.add_stock(p, item, contents[item])

func bank(p: Vector2i) -> void:
	game.banks[p] = {"interest_received": 0.0}
	var cash: float = minf(game.LOAN_LIMIT, game.stock_at(game.BASE, "bread"))
	game.add_stock(game.BASE, "bread", -cash)
	game.add_stock(p, "bread", cash)

func belt(p: Vector2i, direction: Vector2i) -> void:
	var inputs: Array = game.DIRS.duplicate()
	inputs.erase(direction)
	game.belts[p] = {"direction": direction, "inputs": inputs, "cargo": -1, "last_input": -1, "materials": {1: game.BELT_BLOCKS}}

func clear_area(area: Rect2i) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := Vector2i(x, y)
			game.terrain[p] = 0
			game.water_sources.erase(p)
			game.explored[p] = true
			game.navigation.set_point_solid(p, false)

func cable(p: Vector2i, kind := "low_line", axis := Vector2i.RIGHT) -> void:
	game.power_lines[p] = {"kind": kind, "axis": axis, "materials": game.building_materials(kind).duplicate()}

# A valid staffed circuit starts with facilities, fuel and people, never assigned jobs.
func power_facilities(transformers := 1, lamps := 4, offset := Vector2i.ZERO) -> Vector2i:
	clear_area(Rect2i(Vector2i(23, 6) + offset, Vector2i(25, 8 + transformers * 4)))
	var plant := Vector2i(24, 8) + offset
	station("power_plant", plant)
	game.add_stock(plant, 3, 10)
	game.add_stock(plant, "bread", 30)
	hungry_worker(plant)
	cable(plant + Vector2i(2, 0), "high_line")
	for y in range(8, 9 + (transformers - 1) * 4):
		cable(Vector2i(27, y) + offset, "high_line", Vector2i.DOWN)
	for i in transformers:
		var p := Vector2i(29, 8 + i * 4) + offset
		station("transformer", p)
		game.add_stock(p, "bread", 30)
		hungry_worker(p)
		for x in range(31, 45):
			cable(Vector2i(x + offset.x, p.y))
		for j in lamps:
			station("grow_light", Vector2i(32 + j * 3, p.y + 1) + Vector2i(offset.x, 0))
	return plant
