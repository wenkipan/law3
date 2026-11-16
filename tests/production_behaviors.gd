extends RefCounted

const P := Vector2i(28, 11)
const Q := Vector2i(35, 11)

func run(t) -> void:
	check_single_employee(t)
	check_completed_job(t)
	check_closure(t)
	check_finite_mining(t)
	check_supply(t)
	check_local_inventory(t)
	check_regional_sites(t)
	check_forest_recovery(t)
	check_oil_discovery(t)
	check_wild_food_sites(t)
	check_farming(t)
	check_barn(t)
	check_research(t)
	check_market_stock(t)
	check_power(t)

func check_market_stock(t) -> void:
	var g = t.game
	t.fixtures.scenario("Market shelves and production supply remain separate")
	t.fixtures.station("market", g.BASE)
	t.fixtures.station("mill", P)
	t.fixtures.station("storage_box", Q)
	var market_worker: Dictionary = t.fixtures.resident("operations", g.BASE)
	var mill_worker: Dictionary = t.fixtures.resident("operations", P)
	var carrier: Dictionary = t.fixtures.resident("building_logistics", Q)
	for person in [market_worker, mill_worker, carrier]: person.items.bread = 6
	var source := Q + Vector2i.DOWN
	var recipe: Dictionary = g.production_materials("mill")
	var wheat: int = recipe.wheat
	t.fixtures.stock_recipe(g.BASE, recipe)
	t.fixtures.stock_recipe(source, recipe)
	g.adjust_production(P, 1)
	t.advance_until(func(): return g.stock_at(P, "bread") > 0, 120, "The mill can still receive real inputs and produce")
	g.adjust_production(P, 1)
	g.simulate(60)
	t.near(g.stock_at(g.BASE, "wheat"), wheat, "The mill cannot draw ingredients from market shelves")
	t.near(g.stock_at(source, "wheat"), 0, "The mill uses ordinary supply stock instead")
	t.near(g.stock_at(g.BASE, "bread"), 0, "The market does not automatically take the mill's finished product")
	t.near(g.stock_at(P, "bread"), g.PRODUCTS.mill.amount, "Finished goods remain where produced")
	t.check(g.demolish_building(P), "A mill with stock can still be demolished")
	t.advance_until(func(): return not g.world.has_building(P, "site"), 180, "Normal demolition recovery still works with a market on the starting point")
	t.near(g.stock_at(g.BASE, "bread"), 0, "Returning recovered stock to the starting point does not list it for sale")
	t.near(g.player_inventory().bread, g.PRODUCTS.mill.amount, "Demolition preserves all recovered bread")

func check_single_employee(t) -> void:
	var g = t.game
	t.fixtures.scenario("A resident has one skill and one persistent building employer")
	t.fixtures.resident("operations", P)
	t.fixtures.resident("mining", Q)
	for p in [P, Q]:
		t.fixtures.station("workbench", p)
		g.adjust_production(p, 1)
	t.advance_until(func(): return g.stock_at(P, "workbench") + g.stock_at(Q, "workbench") >= 1, 100, "A qualified resident can produce at one of the workshops")
	g.simulate(50)
	t.near(g.stock_at(P, "workbench") + g.stock_at(Q, "workbench"), 1, "A single employee cannot also fill another building or substitute for another skill")
	t.fixtures.resident("operations", Q)
	t.advance_until(func(): return g.stock_at(P, "workbench") + g.stock_at(Q, "workbench") == 2, 100, "Another qualified resident can fill the remaining vacancy")
	t.check(g.world.workers[1].earned_today == 0, "An incompatible skill never earns workshop wages")

func check_closure(t) -> void:
	var g = t.game
	t.fixtures.scenario("Zero wage closes a building and settles only completed labor")
	t.fixtures.resident("operations", P)
	t.fixtures.station("sawmill", P)
	t.fixtures.stock_recipe(P, {7: 1})
	g.adjust_production(P, 1)
	t.advance_until(func(): return g.report_totals(g.world.day)["工作"] > 1, 40, "Real labor begins before the player closes the building")
	t.check(g.set_wage(P, 0), "The player can set employment price to zero")
	var earned: float = g.world.workers[0].earned_today
	t.check(earned > 0 and earned < 1, "Closure pays the completed share, not a whole unfinished product")
	var stock: Dictionary = g.resource_inventory()
	g.simulate(20)
	t.near(g.stock_at(P, "planks"), 0, "A closed building cannot finish its interrupted batch")
	t.check(g.resource_inventory() == stock, "Closure neither refunds consumed inputs nor creates output")
	t.near(g.world.workers[0].earned_today, earned, "A closed building does not keep paying wages")
	g.set_wage(P, 9)
	t.advance_until(func(): return g.stock_at(P, "planks") == 2, 90, "Reopening allows the preserved batch to resume")
	t.near(g.world.workers[0].earned_today, 1, "Repricing does not change a batch's locked wage")
	t.near(g.resource_inventory()[7], 0, "Resuming does not charge the input twice")

func check_completed_job(t) -> void:
	var g = t.game
	t.fixtures.scenario("A completed blueprint becomes a specialized workplace across a save")
	t.fixtures.resident("building_logistics", P)
	t.fixtures.resident("operations", Q)
	t.fixtures.building_materials("workbench")
	t.check(g.place_building(P, "workbench"), "The player can commission the real workshop")
	t.advance_until(func(): return g.world.has_building(P, "station"), 180, "Construction completes before production is requested")
	# Prevent a stale construction binding from hiding the new workplace after restoration.
	var saved: Dictionary = g.capture_snapshot()
	t.check(saved.ok and g.restore_snapshot(saved.data).ok, "The newly completed building can be restored without replaying construction")
	g.adjust_production(P, 1)
	t.advance_until(func(): return g.stock_at(P, "workbench") == 1, 120, "The restored workshop accepts qualified production and produces the ordered item")
	t.near(g.resource_inventory()[1], 0, "Transitioning workplace roles does not refund construction materials")
	t.near(g.resource_inventory().money, 600, "The temporary job and production job transfer only actual currency")

func check_finite_mining(t) -> void:
	var g = t.game
	# Both surface and powered extraction must resolve a real deposit, not a stale target.
	for kind in ["mine", "drill"]:
		t.fixtures.scenario("Mining yields repeatedly, then exhausts a finite deposit: " + kind)
		t.fixtures.resident("mining", P)
		t.fixtures.station(kind, P)
		var ore := 2 if kind == "mine" else 5
		t.fixtures.deposit(P, ore, 3)
		if kind == "drill":
			var plant := Vector2i(25, 11)
			t.fixtures.station("manual_generator", plant)
			t.fixtures.resident("operations", plant)
			t.fixtures.cable(Vector2i(27, 11))
		t.check(g.world.walkable(P), "A mineral does not block walking")
		t.check(not g.building_space_valid(Q, "mine"), "A mine requires a mineral footprint")
		# Power and mining residents choose their own breaks; the contract is finite yield,
		# not continuous staffing or a prescribed first-batch deadline.
		t.advance_until(func(): return g.stock_at(P, 2) >= 1, 400, "The first batch produces before the whole deposit is exhausted")
		t.check(g.world.terrain[P] == ore, "The first extraction does not erase the deposit")
		t.advance_until(func(): return g.stock_at(P, 2) == 3, 400, "Repeated work reaches the finite physical yield")
		g.simulate(40)
		t.near(g.stock_at(P, 2), 3, "An exhausted deposit cannot keep producing")
		t.check(g.world.has_building(P, "station"), "Exhaustion does not delete the mine building")
		if kind == "drill":
			g.begin_drill_move(P)
			t.check(g.move_drill_to(Q), "The player can relocate the exhausted drill with its stored output")
			t.near(g.stock_at(P, 2), 0, "Relocation leaves no copy of the drill's inventory at its old position")
			t.near(g.stock_at(Q, 2), 3, "The relocated building keeps its actual stored output")
			var checkpoint: Dictionary = g.capture_snapshot()
			t.check(checkpoint.ok and g.restore_snapshot(checkpoint.data).ok, "The relocated building and its employment survive saving")
			t.near(g.resource_inventory()[2], 3, "Restoring relocation does not duplicate or lose goods")

func check_supply(t) -> void:
	var g = t.game
	for belt_delivery in [false, true]:
		t.fixtures.scenario("Only logistics residents supply a production recipe: belt " + str(belt_delivery))
		t.fixtures.resident("operations", P)
		t.fixtures.station("purifier", P)
		var source := Vector2i(32, 13)
		t.fixtures.stock_recipe(source, {"raw_water": 4})
		t.fixtures.station("storage_box", Q)
		t.fixtures.resident("building_logistics", Q)
		if belt_delivery:
			for x in range(29, 33):
				t.fixtures.belt(Vector2i(x, 13), Vector2i.LEFT if x > 29 else Vector2i.UP)
			t.fixtures.belt(Vector2i(29, 12), Vector2i.UP)
		g.set_wage(Q, 0)
		g.adjust_production(P, 1)
		g.simulate(45)
		t.near(g.stock_at(source, "raw_water"), 4, "An operator cannot take a hauling task to supply their own workplace")
		t.near(g.stock_at(P, "clean_water"), 0, "A production order cannot pull stock from a remote source")
		g.set_wage(Q, 1)
		if belt_delivery:
			t.advance_until(func(): return not g.world.belt_cargo.is_empty(), 90, "The logistics worker physically loads the connected transport line")
		t.advance_until(func(): return g.stock_at(P, "clean_water") == 4, 150, "Ingredients arrive physically before the batch can finish")
		t.near(g.resource_inventory().raw_water, 0, "A recipe consumes only the four actual delivered units")
		t.near(g.world.workers[0].earned_today, 1, "Supply does not invent an additional production wage")

func check_local_inventory(t) -> void:
	var g = t.game
	# Existing goods must not be overwritten by output or lost on restore/demolition.
	for kind in ["sawmill", "purifier"]:
		t.fixtures.scenario("Local ingredients and products survive production, saving and recovery: " + kind)
		t.fixtures.station(kind, P)
		t.fixtures.resident("operations", P)
		t.fixtures.station("storage_box", Q)
		t.fixtures.resident("building_logistics", Q)
		var recipe: Dictionary = g.production_materials(kind)
		var product = g.product_item(kind)
		var amount: int = 1 + g.PRODUCTS[kind].get("amount", 1)
		t.fixtures.stock_recipe(P, recipe)
		t.fixtures.stock_recipe(P, recipe)
		t.fixtures.stock_recipe(P, {product: 1})
		g.adjust_production(P, 1)
		t.advance_until(func(): return g.stock_at(P, product) == amount, 120, "Production adds to the product already stored beside its ingredients")
		for item in recipe:
			t.near(g.stock_at(P, item), recipe[item], "Production leaves unused ingredients in the same building")
		var local: Dictionary = g.storage_contents(P)
		var total: Dictionary = g.resource_inventory()
		t.near(total[product], amount, "Global inventory counts stored production exactly once")
		var saved: Dictionary = g.capture_snapshot()
		t.check(saved.ok, "Mixed building inventory can be saved")
		if not saved.ok: return
		var restored: Dictionary = g.restore_snapshot(saved.data)
		t.check(restored.ok, "Mixed building inventory can be restored")
		if not restored.ok: return
		t.check(g.storage_contents(P) == local and g.resource_inventory() == total, "Restoring preserves both local goods and physical totals")
		t.check(g.demolish_building(P), "The stocked production building can be demolished")
		t.near(g.resource_inventory()[product], amount, "Demolition does not lose or duplicate stored products")
		t.advance_until(func(): return not g.world.has_building(P, "site"), 180, "Actual products, unused ingredients and recovered materials reach storage")
		t.near(g.stock_at(g.BASE, product), amount, "All stored products are recovered through ordinary transport")
		for item in recipe:
			var expected: float = recipe[item] + g.building_materials(kind).get(item, 0)
			t.near(g.stock_at(g.BASE, item), expected, "Recovery returns unused ingredients without refunding the consumed batch")

func check_wild_food_sites(t) -> void:
	var g = t.game
	for entry in [["farm", "wheat"], ["hunting_ground", "meat"], ["gathering_garden", "berries"]]:
		var kind: String = entry[0]
		var item: String = entry[1]
		t.fixtures.scenario("Food workplaces require their region and preserve matching natural sources: " + kind, 0, false, 1020, false)
		t.fixtures.region(Rect2i(P, Vector2i(g.building_size(P, kind) / g.CELL)), g.REGION_BUILDINGS[kind])
		t.fixtures.region(Rect2i(Q, Vector2i(g.building_size(Q, kind) / g.CELL)), g.REGION_BUILDINGS[kind])
		t.fixtures.region(Rect2i(P - Vector2i(0, 4), Vector2i(g.building_size(P, kind) / g.CELL)), g.MapGenerator.Biome.MOUNTAIN)
		t.fixtures.wild(P + Vector2i.ONE, item)
		t.fixtures.wild(Q, "meat" if item != "meat" else "berries")
		t.fixtures.wild(Q + Vector2i.ONE, item)
		t.fixtures.resident("building_logistics", g.BASE)
		t.fixtures.resident("farming", P + Vector2i(0, 4))
		t.fixtures.building_materials(kind)
		t.check(not g.place_building(P - Vector2i(0, 4), kind), "A one-shot food outcrop does not qualify the wrong region")
		t.check(not g.place_building(Q, kind), "Matching wild food does not authorize covering a different wild resource")
		t.check(g.place_building(P, kind), "A matching non-origin tile qualifies even before any research")
		t.advance_until(func(): return g.world.has_building(P, "station"), 190, "The occupied resource cell does not block supplied construction")
		if kind == "farm": continue # Water and harvest stages are covered separately.
		var amount: int = g.PRODUCTS[kind].amount
		g.adjust_production(P, 2)
		t.advance_until(func(): return g.stock_at(P, item) >= amount * 2, 200, "The specialist produces repeated batches into the workplace, not a personal inventory")
		t.near(g.resource_activity(item, 1).produced, amount * 2, "Repeated production reports exactly the two ordered batches")

func check_farming(t) -> void:
	var g = t.game
	t.fixtures.scenario("A specialized farmer completes watering, independent growth and harvest")
	t.fixtures.wild(P + Vector2i.ONE, "wheat")
	t.fixtures.resident("farming", P)
	t.fixtures.station("farm", P)
	t.fixtures.stock_recipe(P, {"raw_water": 4})
	g.adjust_production(P, 1)
	t.advance_until(func(): return g.stock_at(P, "wheat") == 8, 200, "Watering and harvest produce the actual crop")
	t.near(g.resource_inventory().raw_water, 0, "A crop consumes one local water recipe")
	t.near(g.world.workers[0].earned_today, 2, "Only watering and harvesting earn wages")
	g.simulate(20)
	t.near(g.stock_at(P, "wheat"), 8, "Growth does not create a second crop without another recipe")

func check_barn(t) -> void:
	var g = t.game
	t.fixtures.scenario("A stocked barn still converts feed into wool, not meat")
	t.fixtures.station("barn", P)
	t.fixtures.resident("farming", P)
	t.fixtures.stock_recipe(P, g.production_materials("barn"))
	g.adjust_production(P, 1)
	t.advance_until(func(): return g.stock_at(P, "wool") > 0, 300, "Feeding, wool growth and shearing remain available")
	t.near(g.resource_activity("meat", 1).produced, 0, "A completed wool batch cannot introduce meat")

func check_research(t) -> void:
	var g = t.game
	t.fixtures.scenario("Qualified researchers cooperate without spending beyond the last point", 0, false, 1020, false)
	for p in [P, Q]:
		t.fixtures.resident("operations", p)
		t.fixtures.station("research_bench", p)
		t.fixtures.research_materials(p, "tools", 2)
	g.world.research_progress.tools = g.Technology.PROJECTS.tools.points - 1
	for p in [P, Q]: g.assign_research(p, "tools")
	t.advance_until(func(): return g.Technology.completed(g.world.research_progress, "tools"), 120, "The last real research point completes")
	t.near(g.research_value("tools"), g.Technology.PROJECTS.tools.points, "Competing benches cannot overproduce the final point")
	var input: float = g.resource_inventory()[2]
	g.simulate(20)
	t.near(g.resource_inventory()[2], input, "Completed research stops charging new material batches")

func check_power(t) -> void:
	var g = t.game
	t.fixtures.scenario("Power labor still obeys the physical circuit and employee qualification")
	var plant := Vector2i(25, 11)
	t.fixtures.resident("operations", plant)
	t.fixtures.station("manual_generator", plant)
	t.fixtures.station("grow_light", Vector2i(29, 11))
	for x in [27, 28]: t.fixtures.cable(Vector2i(x, 11))
	var power: Dictionary = t.measure_power([plant], 50)
	t.check(power.energy > 0, "A qualified operator can supply a connected device")
	t.check(power.peak <= 400, "A single operator cannot exceed generator output")
	g.set_wage(plant, 0)
	var closed: Dictionary = t.measure_power([plant], 3)
	t.near(closed.energy, 0, "Closing the generator stops its physical output")

# A matching resource must not bypass a wrong or straddling region.
func check_regional_sites(t) -> void:
	var g = t.game
	for kind in ["farm", "barn", "mine", "logging_camp"]:
		t.fixtures.scenario("Strict productive regions, including the far footprint edge: " + kind)
		if kind in g.EXTRACTIVE_KINDS: t.fixtures.deposit(P, 7 if kind == "logging_camp" else 2)
		var area := Rect2i(P, Vector2i(g.building_size(P, kind) / g.CELL))
		t.fixtures.region(area, g.REGION_BUILDINGS[kind])
		t.check(g.building_space_valid(P, kind), "The matching productive region permits an unfunded blueprint")
		t.fixtures.region(Rect2i(area.end - Vector2i.ONE, Vector2i.ONE), g.MapGenerator.Biome.FOREST if kind == "farm" else g.MapGenerator.Biome.PLAIN)
		t.check(not g.place_building(P, kind), "A correct source tile cannot authorize a footprint crossing into another region")

# Harvested forest regenerates actual standing stock; loose opening timber does not.
# Saving partway through recovery must not restart or replay it.
func check_forest_recovery(t) -> void:
	var g = t.game
	t.fixtures.scenario("Forest regrowth resumes after a save without duplicating harvested goods")
	t.fixtures.station("logging_camp", P)
	t.fixtures.deposit(P, 7, 1)
	t.fixtures.resident("mining", P)
	t.advance_until(func(): return g.stock_at(P, 7) == 1, 100, "A logging worker harvests the actual standing timber")
	g.set_wage(P, 0)
	g.simulate(80)
	var saved: Dictionary = g.capture_snapshot()
	t.check(saved.ok and g.restore_snapshot(saved.data).ok, "Forest recovery and its productive terrain survive saving")
	g.simulate(105)
	t.check(g.mine_deposit(P) != null, "The forest produces harvestable standing timber after the remaining recovery")
	t.near(g.stock_at(P, 7), 1, "Regrowth does not create goods in the logging camp's warehouse")
	g.set_wage(P, 1)
	t.advance_until(func(): return g.stock_at(P, 7) == 2, 100, "Regenerated timber requires another real paid harvest")
	t.near(g.resource_activity(7, 1).produced, 2, "Only actual extraction is reported as produced timber")

# Research reveals existing oil in sight, including already generated cells;
# hidden/unseen oil must not leak through clicked details.
func check_oil_discovery(t) -> void:
	var g = t.game
	t.fixtures.scenario("Oil becomes visible only through completed research and current sight", 0, false, 1020, false)
	t.fixtures.region(Rect2i(P, Vector2i.ONE), g.MapGenerator.Biome.FOREST)
	g.world.oil_deposits[P] = 240
	for project in ["tools", "woodworking", "metallurgy", "electricity", "coal_power", "mechanical_mining", "chemistry"]:
		g.world.research_progress[project] = g.Technology.PROJECTS[project].points
	g.world.research_progress.oil_survey = g.Technology.PROJECTS.oil_survey.points - 1
	t.check(not g.tile_details(P).title.contains("石油"), "An unresearched oil deposit exposes only its ordinary surface")
	t.fixtures.station("research_bench", Q)
	t.fixtures.resident("operations", Q)
	t.fixtures.research_materials(Q, "oil_survey")
	g.assign_research(Q, "oil_survey")
	t.advance_until(func(): return g.Technology.completed(g.world.research_progress, "oil_survey"), 120, "Real materials and researcher labor complete the discovery technology")
	t.check(g.tile_details(P).title == "石油", "Finishing research reveals an already generated forest oil deposit")
	var saved: Dictionary = g.capture_snapshot()
	t.check(saved.ok and g.restore_snapshot(saved.data).ok and g.tile_details(P).title == "石油", "Restoring preserves oil and its researched visibility")
	g.cache.visible_tiles.erase(P)
	t.check(g.tile_details(P).is_empty(), "Research never reveals deposits outside current sight")
