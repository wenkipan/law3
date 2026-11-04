extends RefCounted

const INPUT_ROUTES := [
	{"source": "storage_box", "target": "purifier", "item": "raw_water", "amount": 4},
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
		game.world.water_sources.clear()
		for cell in game.world.terrain:
			game.world.terrain[cell] = 1
			game.cache.navigation.set_point_solid(cell, true)
		clear_area(Rect2i(game.BASE - Vector2i(4, 2), Vector2i(9, 5)))
		var source := Vector2i(29, 10)
		game.world.water_sources[source] = true
		game.world.terrain[source] = 0
	game.world.workers.resize(population)
	# Business contracts retain their hungry starting fixture; birth is tested separately.
	for worker in game.world.workers:
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
		game.world.water_sources[source] = true
		game.world.terrain[source] = 0
		game.cache.navigation.set_point_solid(source, true)
	game.world.benches[p] = game.production_station(kind)
	game.world.benches[p].stock = stock

func materials(amount: int, ore := 1) -> void:
	for mineral in range(1, game.ORES.size()):
		game.add_stock(game.BASE, mineral, -game.stock_at(game.BASE, mineral))
	game.add_stock(game.BASE, ore, amount)

func stock_recipe(p: Vector2i, recipe: Dictionary) -> void:
	for item in recipe:
		game.add_stock(p, item, recipe[item])

func service_customer(kind: String, p: Vector2i, person: Dictionary, debt := false) -> void:
	person.pos = Vector2(p)
	person.hunger = 100
	person.bread = game.SERVICES[kind].price
	person.loan_principal = 1.0 if debt else 0.0
	if kind == "laundry":
		person.equipment.clothes = game.ITEM_USES.clothes.uses
		person.clothes_pollution = 50.0
	else:
		person.pollution = 80.0 if kind == "hospital" else 60.0

func shop_customer(kind: String, p: Vector2i, person: Dictionary, debt: bool, affordable: bool) -> void:
	person.pos = Vector2(p)
	person.hunger = 100
	person.fatigue = 40.0 if kind == "brewery" else 0.0
	person.bread = game.PRODUCTS[kind].price - (0.0 if affordable else 0.25)
	person.loan_principal = 1.0 if debt else 0.0
	person.loan_interest = 0.2 if debt else 0.0

func wastewater(p: Vector2i, water: float, load: float) -> void:
	game.add_stock(p, "wastewater", water)
	game.world.add_waste(p, load)

func tired_observer(p: Vector2i) -> Dictionary:
	var person: Dictionary = game.create_worker(p)
	person.hunger = 100
	person.fatigue = game.MAX_FATIGUE
	return person

func personal_feedback_world(kind: String) -> void:
	scenario("Personal item feedback: " + kind, 1)
	var person: Dictionary = game.world.workers[0]
	person.hunger = 100
	match kind:
		"income":
			person.pos = Vector2(36, 13)
			person.loan_principal = 4.0
			person.loan_interest = 0.8
		"purchase":
			var shop := Vector2i(28, 11)
			station("barn", shop)
			stock_recipe(shop, {"meat": 1})
			person.pos = Vector2(shop)
			person.bread = 1
			person.hunger = 60
		"use":
			person.pos = Vector2(29, 15)
			person.fatigue = 40
			person.items = {"ale": 1}
			person.gun_uses = 4
			person.backpack_uses = 3
			person.equipment = {"clothes": game.ITEM_USES.clothes.uses, "tools": 8}
			person.clothes_pollution = 10
			person.mood.value = -35.0
	game.world_view.rebuild(game)

func snapshot_world(kind: String) -> void:
	scenario("Save and resume an evolving world: " + kind, 2)
	var p := Vector2i(28, 11)
	match kind:
		"construction":
			building_materials("bed")
		"production":
			station("workbench", p)
			game.add_stock(p, 4, 4)
			game.add_stock(p, "bread", 20)
		"transport":
			station("storage_box", p)
			station("purifier", Vector2i(35, 13))
			game.add_stock(p, "raw_water", 8)
			var path: Array[Vector2i] = [Vector2i(29, 12), Vector2i(30, 12), Vector2i(31, 12), Vector2i(32, 12), Vector2i(33, 12), Vector2i(34, 12)]
			for i in path.size(): belt(path[i], Vector2i.RIGHT if i + 1 < path.size() else Vector2i(0, 1))
		"backpack", "water_backpack":
			game.world.workers[0].pos = Vector2(36, 13)
			game.world.workers[0].carry = 1
			game.world.workers[0].extra_cargo = ["clean_water" if kind == "water_backpack" else 2]
			game.world.workers[0].backpack_uses = 1
		"service":
			station("bathhouse", p)
			stock_recipe(p, game.BATH_MATERIALS)
			service_customer("bathhouse", p, game.world.workers[0])
		"life":
			bed(p)
			game.world.workers[0].bread = 10.0
			game.world.workers[0].fatigue = 70.0
			game.world.workers[1].items = {"ale": 1, "clothes": 1}
			game.world.workers[1].fatigue = 40.0
		"buffs":
			game.world.workers[0].buffs.apply("tipsy", game.HOUR_SECONDS * 2)
			game.world.workers[0].buffs.apply("hydrated", game.HOUR_SECONDS * 3)
			game.world.workers[0].buffs.apply("bathed", game.HOUR_SECONDS * 4)
			game.world.workers[0].mood.value = -35.0
			game.world.workers[0].equipment = {"clothes": game.HOUR_SECONDS * 20, "tools": 6}
			game.world.workers[0].clothes_pollution = 15.0
			game.world.workers[1].loan_principal = 2.0
			game.world.workers[1].loan_interest = 0.4
			bank(p)
			game.world.workers[1].loan_bank = p
		"power":
			power_facilities(1, 1)
		"economy":
			bank(p)
			station("purifier", Vector2i(35, 13), 4)

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
	game.world.beds[p] = {"remaining": 0.0, "assigned": -1}

func isolated_warehouse(contents: Dictionary) -> void:
	var p := Vector2i(50, 20)
	clear_area(Rect2i(p, Vector2i(2, 1)))
	bed(p)
	for item in contents:
		game.add_stock(p, item, contents[item])

func bank(p: Vector2i) -> void:
	game.world.banks[p] = {"interest_received": 0.0}
	var cash: float = minf(game.LOAN_LIMIT, game.stock_at(game.BASE, "bread"))
	game.add_stock(game.BASE, "bread", -cash)
	game.add_stock(p, "bread", cash)

func belt(p: Vector2i, direction: Vector2i) -> void:
	var inputs: Array = game.DIRS.duplicate()
	inputs.erase(direction)
	game.world.belts[p] = {"direction": direction, "inputs": inputs, "last_input": -1, "materials": {1: game.BELT_BLOCKS}}

func clear_area(area: Rect2i) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := Vector2i(x, y)
			game.world.terrain[p] = 0
			game.world.water_sources.erase(p)
			game.world.explored[p] = true
			game.cache.navigation.set_point_solid(p, false)

func cable(p: Vector2i, kind := "low_line", axis := Vector2i.RIGHT) -> void:
	game.world.power_lines[p] = {"kind": kind, "axis": axis, "materials": game.building_materials(kind).duplicate()}

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
