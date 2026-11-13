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
	check_wild_food_sites(t)
	check_farming(t)
	check_barn(t)
	check_research(t)
	check_market_restock(t)
	check_power(t)

func check_market_restock(t) -> void:
	var g = t.game
	for kind in ["mine", "sawmill"]:
		t.fixtures.scenario("Local output joins market stock through actual employee transport: " + kind)
		t.fixtures.station("market", g.BASE)
		t.fixtures.resident("trade", g.BASE)
		t.fixtures.resident("mining" if kind == "mine" else "processing", P)
		t.fixtures.station(kind, P)
		var item = 2 if kind == "mine" else g.product_item(kind)
		if kind == "mine":
			t.fixtures.deposit(P, 2, 2)
		else:
			t.fixtures.stock_recipe(P, g.production_materials(kind))
			g.adjust_production(P, 1)
		t.advance_until(func(): return g.stock_at(g.BASE, item) == 2, 150, "Produced goods physically reach the market warehouse")
		t.near(g.resource_inventory()[item], 2, "Restocking neither duplicates nor consumes the output")

func check_single_employee(t) -> void:
	var g = t.game
	t.fixtures.scenario("A resident has one skill and one persistent building employer")
	t.fixtures.resident("processing", P)
	t.fixtures.resident("mining", Q)
	for p in [P, Q]:
		t.fixtures.station("workbench", p)
		g.adjust_production(p, 1)
	t.advance_until(func(): return g.stock_at(P, "workbench") + g.stock_at(Q, "workbench") >= 1, 100, "A qualified resident can produce at one of the workshops")
	g.simulate(50)
	t.near(g.stock_at(P, "workbench") + g.stock_at(Q, "workbench"), 1, "A single employee cannot also fill another building or substitute for another skill")
	t.fixtures.resident("processing", Q)
	t.advance_until(func(): return g.stock_at(P, "workbench") + g.stock_at(Q, "workbench") == 2, 100, "Another qualified resident can fill the remaining vacancy")
	t.check(g.world.workers[1].earned_today == 0, "An incompatible skill never earns workshop wages")

func check_closure(t) -> void:
	var g = t.game
	t.fixtures.scenario("Zero wage closes a building and settles only completed labor")
	t.fixtures.resident("processing", P)
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
	t.fixtures.resident("construction", P)
	t.fixtures.resident("processing", Q)
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
			t.fixtures.resident("power", plant)
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
		t.fixtures.scenario("A building employee supplies its own real recipe: belt " + str(belt_delivery))
		t.fixtures.resident("processing", P)
		t.fixtures.station("purifier", P)
		t.fixtures.stock_recipe(g.BASE, {"raw_water": 4})
		if belt_delivery:
			for x in range(29, 33):
				t.fixtures.belt(Vector2i(x, 13), Vector2i.LEFT if x > 29 else Vector2i.UP)
			t.fixtures.belt(Vector2i(29, 12), Vector2i.UP)
		g.adjust_production(P, 1)
		if belt_delivery:
			t.advance_until(func(): return not g.world.belt_cargo.is_empty(), 60, "The employee physically loads the connected transport line")
		t.advance_until(func(): return g.stock_at(P, "clean_water") == 4, 150, "Ingredients arrive physically before the batch can finish")
		t.near(g.resource_inventory().raw_water, 0, "A recipe consumes only the four actual delivered units")
		t.near(g.world.workers[0].earned_today, 1, "Supply does not invent an additional production wage")

func check_local_inventory(t) -> void:
	var g = t.game
	# Existing goods must not be overwritten by output or lost on restore/demolition.
	for kind in ["sawmill", "purifier"]:
		t.fixtures.scenario("Local ingredients and products survive production, saving and recovery: " + kind)
		t.fixtures.station(kind, P)
		t.fixtures.resident("processing", P)
		t.fixtures.station("storage_box", Q)
		t.fixtures.resident("transport", Q)
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
	for entry in [["farm", "wheat", "farming"], ["hunting_ground", "meat", "hunting"], ["gathering_garden", "berries", "gathering"]]:
		var kind: String = entry[0]
		var item: String = entry[1]
		t.fixtures.scenario("Food workplaces require a matching wild cell within the full footprint: " + kind, 0, false, 1020, false)
		t.fixtures.wild(P + Vector2i.ONE, item)
		t.fixtures.wild(Q, "meat" if item != "meat" else "berries")
		t.fixtures.wild(Q + Vector2i.ONE, item)
		t.fixtures.resident("construction", g.BASE)
		t.fixtures.resident(entry[2], P + Vector2i(0, 4))
		t.fixtures.building_materials(kind)
		t.check(not g.place_building(P - Vector2i(0, 4), kind), "Empty ground is not a food source")
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
	t.fixtures.stock_recipe(g.BASE, {"raw_water": 4})
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
		t.fixtures.resident("research", p)
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
	t.fixtures.resident("power", plant)
	t.fixtures.station("manual_generator", plant)
	t.fixtures.station("grow_light", Vector2i(29, 11))
	for x in [27, 28]: t.fixtures.cable(Vector2i(x, 11))
	var power: Dictionary = t.measure_power([plant], 50)
	t.check(power.energy > 0, "A qualified operator can supply a connected device")
	t.check(power.peak <= 400, "A single operator cannot exceed generator output")
	g.set_wage(plant, 0)
	var closed: Dictionary = t.measure_power([plant], 3)
	t.near(closed.energy, 0, "Closing the generator stops its physical output")
