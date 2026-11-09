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
func scenario(label: String, population := 3, generated := false, seed_value := 1020, researched := true) -> void:
	scenario_name = label
	print("CASE: ", label)
	game.reset_world(seed_value)
	if researched:
		for project in game.Technology.PROJECTS:
			game.world.research_progress[project] = game.Technology.PROJECTS[project].points
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
	game.world.next_worker_id = population
	# Business contracts retain their hungry starting fixture; birth is tested separately.
	for worker in game.world.workers:
		worker.hunger = 0
	game.world_view.rebuild(game)
	game.ai_trace.record(game, {}, "test", "scenario", {"name": label, "population": population})

func hungry_worker(p: Vector2i) -> Dictionary:
	var person: Dictionary = game.create_worker(p)
	person.hunger = 0
	return person

func population_world(setting: String) -> void:
	scenario("Population lifecycle: " + setting, 3 if setting == "support" else 2 if setting in ["death", "metabolism"] else 1)
	var person: Dictionary = game.world.workers[0]
	match setting:
		"metabolism":
			person.hunger = game.MAX_HUNGER
			game.world.workers[1].hunger = game.MAX_HUNGER
			game.world.workers[1].age_days = 1.0
		"clone":
			person.age_days = 31.0
			person.pollution = 12.0
			station("printer", Vector2i(28, 11))
			materials(20)
		"birth", "low_mood":
			person.hunger = game.MAX_HUNGER
			person.mood.value = 100.0 if setting == "birth" else 80.0
			person.bread = 40.0
			game.add_stock(game.BASE, "bread", -person.bread)
			if setting == "birth": person.equipment = {"clothes": game.ITEM_USES.clothes.uses}
		"support":
			person.pos = Vector2(28, 11)
			person.hunger = 100.0
			person.bread = 10.0
			game.add_stock(game.BASE, "bread", -person.bread)
			for i in [1, 2]:
				var child: Dictionary = game.world.workers[i]
				child.age_days = 1.0
				child.pos = Vector2(36, 15)
				child.hunger = 10.0
			game.world.workers[1].producer = person.id
		"death":
			person.age_days = 45.0 - 2.0 / game.DAY_SECONDS
			person.pos = Vector2(36, 13)
			person.hunger = 100.0
			person.bread = 3.5
			person.carry = 2
			person.items = {"ale": 1}
			game.add_stock(game.BASE, "bread", -person.bread)
			game.world.workers[1].hunger = 100.0
			bed(Vector2i(28, 11))
			game.assign_bed(Vector2i(28, 11), person.id)

func age_labor(days: float, kind := "workbench") -> void:
	scenario("Age-gated labor: %.1f / %s" % [days, kind], 1)
	game.world.workers[0].age_days = days
	station(kind, Vector2i(28, 11))
	stock_recipe(Vector2i(28, 11), game.production_materials(kind))
	stock_recipe(Vector2i(28, 11), {"bread": 20.0})

func mined_backpack(person: Dictionary, p: Vector2i, second_item = 2) -> void:
	person.pos = Vector2(p)
	person.carry = 1
	person.extra_cargo = [second_item]
	person.backpack_uses = 1

func unit_supply_inventory() -> void:
	scenario("One-item supply claims preserve source inventory across cancellation and loading", 2)
	station("storage_box", Vector2i(28, 11))
	stock_recipe(Vector2i(28, 11), {2: 3})
	for person in game.world.workers:
		person.hunger = 120
		person.pos = Vector2(36, 13)

func new_goods_storage() -> void:
	scenario("New goods use nearby storage without redistributing existing or personal goods", 1)
	station("storage_box", Vector2i(35, 13))
	stock_recipe(Vector2i(35, 13), {2: 3})
	stock_recipe(game.BASE, {4: 2})
	mined_backpack(game.world.workers[0], Vector2i(36, 13), "raw_water")
	game.world.workers[0].items["bench"] = 1

func need_interrupt_production(setting: String) -> void:
	scenario("Production and hard need limits: " + setting, 1)
	var p := Vector2i(28, 11)
	station("bench", p)
	stock_recipe(p, {2: 1, "bread": 8})
	var person: Dictionary = game.world.workers[0]
	person.pos = Vector2(p)
	person.hunger = 100.0
	match setting:
		"starvation": person.hunger = 0.5
		"exhaustion":
			person.hunger = 0.0
			person.fatigue = game.MAX_FATIGUE
			person.bread = 1.0
		"ordinary_illness", "severe_illness", "illness_crossing", "no_medical":
			var hospital := Vector2i(32, 11)
			station("hospital", hospital)
			person.bread = 0.0 if setting == "illness_crossing" else game.SERVICES.hospital.price
			person.pollution = {"ordinary_illness": 69.9, "illness_crossing": 89.9}.get(setting, 90.0)
			if setting != "no_medical": stock_recipe(hospital, game.SERVICES.hospital.materials)
			if setting in ["ordinary_illness", "illness_crossing"]: wastewater(p, 1, 10)
		"no_food": person.hunger = 0.0

func station(kind: String, p: Vector2i, stock := 0) -> void:
	clear_area(Rect2i(p, Vector2i(game.building_size(p, kind) / game.CELL)))
	if kind == "pump" and not game.near_water_source(p):
		var source := p + Vector2i.UP
		game.world.water_sources[source] = true
		game.world.terrain[source] = 0
		game.cache.navigation.set_point_solid(source, true)
	game.world.benches[p] = game.production_station(kind)
	game.world.benches[p].stock = stock
	game.cache.invalidate_delivery()

func materials(amount: int, ore := 1) -> void:
	for mineral in range(1, game.ORES.size()):
		game.add_stock(game.BASE, mineral, -game.stock_at(game.BASE, mineral))
	game.add_stock(game.BASE, ore, amount)

func stock_recipe(p: Vector2i, recipe: Dictionary) -> void:
	for item in recipe:
		game.add_stock(p, item, recipe[item])

func research_world(label: String, projects: Array, population := 1, progress: Dictionary = {}) -> void:
	scenario(label, population, false, 1020, false)
	for project in projects: research_prerequisites(project)
	for project in progress: game.world.research_progress[project] = progress[project]
	for i in projects.size(): station("research_bench", Vector2i(28 + i * 3, 11))
	game.world_view.rebuild(game)

func research_prerequisites(project: String) -> void:
	for required in game.Technology.PROJECTS[project].requires:
		research_prerequisites(required)
		game.world.research_progress[required] = game.Technology.PROJECTS[required].points

func research_materials(p: Vector2i, project: String, batches := 1) -> void:
	for item in game.Technology.PROJECTS[project].materials:
		game.add_stock(p, item, game.Technology.PROJECTS[project].materials[item] * batches)

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

func snapshot_world(kind: String) -> void:
	scenario("Save and resume an evolving world: " + kind, 2, false, 1020, kind != "research")
	var p := Vector2i(28, 11)
	match kind:
		"research":
			station("research_bench", p)
			research_materials(p, "tools", 2)
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
			mined_backpack(game.world.workers[0], Vector2i(36, 13), "raw_water" if kind == "water_backpack" else 2)
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

func wage_contract(kind: String) -> Vector2i:
	scenario("Repricing and saving preserve earned labor: " + kind, 1)
	if kind == "mine":
		game.world.workers[0].gun_uses = 1
		return Vector2i(37, 13)
	building_materials("bed")
	return Vector2i(28, 11)

func fee_controls_world() -> void:
	scenario("Independent fee brush and bottom selectors", 0)
	bed(Vector2i(28, 11))
	station("purifier", Vector2i(31, 11))
	station("hospital", Vector2i(34, 11))
	building_materials("bed")

func fee_customer(kind: String) -> void:
	scenario("Adjusted payment and affordability: " + kind, 1)
	var p := Vector2i(28, 11)
	var person: Dictionary = game.world.workers[0]
	person.pos = Vector2(p)
	person.bread = 3.0
	person.hunger = 180.0
	if kind == "bed":
		bed(p)
		person.fatigue = game.MAX_FATIGUE
	else:
		station(kind, p, 1 if kind == "purifier" else 0)
		if kind == "hospital":
			person.pollution = 80.0
			stock_recipe(p, game.SERVICES.hospital.materials)

func bed(p: Vector2i) -> void:
	game.world.beds[p] = {"remaining": 0.0, "assigned": -1}
	game.cache.invalidate_delivery()

func isolated_warehouse(contents: Dictionary) -> void:
	var p := Vector2i(50, 20)
	clear_area(Rect2i(p, Vector2i(2, 1)))
	bed(p)
	for item in contents:
		game.add_stock(p, item, contents[item])

func bank(p: Vector2i) -> void:
	clear_area(Rect2i(p, Vector2i(game.building_size(p, "bank") / game.CELL)))
	game.world.banks[p] = {"interest_received": 0.0}
	game.cache.invalidate_delivery()
	var cash: float = minf(game.LOAN_LIMIT, game.stock_at(game.BASE, "bread"))
	game.add_stock(game.BASE, "bread", -cash)
	game.add_stock(p, "bread", cash)

func belt(p: Vector2i, direction: Vector2i) -> void:
	var inputs: Array = game.DIRS.duplicate()
	inputs.erase(direction)
	game.world.belts[p] = {"direction": direction, "inputs": inputs, "last_input": -1, "materials": {1: game.BELT_BLOCKS}}
	game.cache.invalidate_delivery()

func track_backpacks(shared: bool, second_item := 2, stalled := false) -> void:
	scenario("Track backpack loading: shared %s / second item %d / stalled %s" % [shared, second_item, stalled], 2 if shared else 1)
	for x in range(33, 37): belt(Vector2i(x, 13), Vector2i.LEFT)
	if stalled: game.world.belts[Vector2i(36, 13)].kind = "electric_belt"
	for person in game.world.workers:
		mined_backpack(person, Vector2i(36, 13), second_item)
		# Transfer enough real cash to cover transport even after a full meal.
		game.add_stock(game.BASE, "bread", -20.0)
		person.bread = 20.0

func receiver_track(p: Vector2i, kind: String) -> Vector2i:
	var corner: Vector2i = game.building_cells(p, kind).back()
	clear_area(Rect2i(Vector2i(29, corner.y + 1), Vector2i(corner.x - 28, 1)))
	for x in range(29, corner.x + 1):
		belt(Vector2i(x, corner.y + 1), Vector2i.RIGHT if x < corner.x else Vector2i.ZERO)
	return corner

func large_blueprint(obstacle := "ore") -> Vector2i:
	scenario("Multi-row footprint clearance: " + obstacle, 1 if obstacle == "ore" else 0)
	var p := Vector2i(28, 11)
	var corner := Vector2i(31, 13)
	building_materials("farm")
	match obstacle:
		"building": station("storage_box", corner)
		"water":
			game.world.water_sources[corner] = true
			game.cache.navigation.set_point_solid(corner, true)
		"unexplored": game.world.explored.erase(corner)
		"ore":
			game.world.terrain[corner] = 2
			game.cache.navigation.set_point_solid(corner, true)
	return p

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
	clear_area(Rect2i(Vector2i(21, 6) + offset, Vector2i(27, 8 + transformers * 4)))
	var plant := Vector2i(22, 8) + offset
	station("power_plant", plant)
	game.add_stock(plant, 3, 10)
	game.add_stock(plant, "bread", 30)
	hungry_worker(plant)
	cable(plant + Vector2i(4, 0), "high_line")
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
