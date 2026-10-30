extends RefCounted

const P := Vector2i(28, 11)
const ORE := Vector2i(37, 13)

func run(t) -> void:
	var g = t.game
	for kind in ["bench", "workbench"]:
		t.fixtures.scenario("Last item has one buyer: " + kind, 2)
		t.fixtures.station(kind, P, 1)
		var product: Dictionary = g.PRODUCTS[kind]
		for worker in g.workers:
			worker.bread = product.price
			worker.hunger = 100
		g.designate(Vector2i(37, 12), Vector2i(37, 14))
		t.advance_until(func(): return g.workers[0].shop_spent_today + g.workers[1].shop_spent_today == product.price, 10, "Purchase records the listed payment even if the shop cash is subsequently collected for wages")
		g.simulate(1)
		var equipped := 0
		for worker in g.workers:
			if worker[product.durability] > 0:
				equipped += 1
		t.check(equipped == 1 and g.benches[P].stock == 0, "One stocked item equips only one competing buyer")
		t.near(g.resource_inventory()[kind], 1, "Equipping a purchased item transfers inventory instead of destroying it")
		t.near(g.resource_activity(kind, 1).produced + g.resource_activity(kind, 1).consumed, 0, "An equipment sale is neither production nor consumption")
		t.near(g.workers[0].shop_spent_today + g.workers[1].shop_spent_today, product.price, "Sold-out shop cannot charge a second buyer")

	t.fixtures.scenario("Sale does not replenish today's completed quota", 1)
	t.fixtures.station("bench", P)
	t.fixtures.materials(1, 2)
	g.workers[0].bread = 3.0
	g.workers[0].hunger = 100
	g.adjust_production(P, 1)
	g.simulate(20)
	g.designate(ORE, ORE)
	t.advance_until(func(): return g.workers[0].shop_spent_today == 5, 120, "Worker earns and buys the produced gun when income becomes useful")
	g.simulate(30)
	t.check(g.benches[P].stock == 0, "Selling today's output does not manufacture another item")

	var plain_time := 0.0
	var plain_fatigue := 0.0
	for equipment in ["none", "gun", "water"]:
		t.fixtures.scenario("Mining outcome with " + equipment, 1)
		var w: Dictionary = g.workers[0]
		w.pos = Vector2(36, 13)
		w.gun_uses = 1 if equipment == "gun" else 0
		w.water = 1 if equipment == "water" else 0
		g.designate(ORE, ORE)
		var elapsed: float = t.advance_until(func(): return g.mined == 1, 20, "Equipped worker actually excavates ore")
		if equipment == "none":
			plain_time = elapsed
			plain_fatigue = w.fatigue
		elif equipment == "gun":
			t.check(elapsed < plain_time * 0.8 and w.gun_uses == 0, "Gun speeds up excavation and spends one use")
			t.near(g.resource_activity("bench", 1).consumed, 1, "Only the final durability use consumes the equipped gun")
		else:
			t.near(w.fatigue, plain_fatigue * 0.7, "Drinking reduces labor fatigue by 30%", 0.15)
			t.check(w.water == 0 and elapsed > plain_time, "Drinking consumes water and takes time")
			t.near(g.resource_activity("clean_water", 1).consumed, 1, "Drinking records the actual portion consumed")
		t.advance_until(func(): return g.delivered == 1, 10, "Ore is delivered after using equipment")

	t.fixtures.scenario("Backpack delivers two blocks; exhaustion restores single trips", 1)
	var w: Dictionary = g.workers[0]
	w.pos = Vector2(36, 13)
	w.backpack_uses = 1
	w.gun_uses = 4
	g.terrain[ORE] = 1
	g.terrain[ORE + Vector2i.RIGHT] = 2
	g.designate(ORE, ORE + Vector2i.RIGHT)
	t.advance_until(func(): return g.delivered == 2, 25, "Backpack delivers both items of its first load")
	t.check(g.delivered == 2 and g.player_blocks == 2 and w.backpack_uses == 0, "First trip delivers two blocks and spends one backpack use")
	t.near(g.resource_activity("workbench", 1).consumed, 1, "An exhausted backpack is consumed once, not once per ore delivered")
	t.check(g.materials.get(1, 0) == 1 and g.materials.get(2, 0) == 1, "Backpack preserves both mineral types after delivery")
	g.designate(Vector2i(39, 13), Vector2i(40, 13))
	t.advance_until(func(): return g.delivered > 2, 25, "Worker continues after backpack wears out")
	t.check(g.delivered == 3, "Worn-out backpack delivers only one block per trip")

	t.fixtures.scenario("Cancelled second block still delivers a partial load", 1)
	w = g.workers[0]
	w.pos = Vector2(36, 13)
	w.backpack_uses = 1
	g.designate(ORE, ORE + Vector2i.RIGHT)
	t.advance_until(func(): return g.mined == 1, 20, "First block is excavated")
	g.designate(ORE + Vector2i.RIGHT, ORE + Vector2i.RIGHT, true)
	t.advance_until(func(): return g.delivered == 1, 10, "Cancellation does not strand cargo")
	t.check(w.backpack_uses == 1, "Single-block delivery does not spend a backpack use")

	t.fixtures.scenario("Water sales conserve stock and respect carrying capacity", 2)
	t.fixtures.station("purifier", P, 6)
	for worker in g.workers:
		worker.bread = 9.0
		worker.hunger = 100
	g.designate(Vector2i(37, 11), Vector2i(37, 15))
	t.advance_until(func(): return g.benches[P].stock == 0, 10, "Workers buy the available water")
	t.check(g.workers[0].water <= 4 and g.workers[1].water <= 4, "Neither worker carries more than four water")
	t.check(g.workers[0].water + g.workers[1].water == 6, "Competing purchases conserve the six stocked portions")
	t.near(g.workers[0].shop_spent_today + g.workers[1].shop_spent_today, 6, "Water revenue equals portions sold")

	for available in [false, true]:
		t.fixtures.scenario("Unavailable water never blocks work: " + str(available), 1)
		t.fixtures.station("purifier", P, 4 if available else 0)
		g.designate(ORE, ORE)
		t.advance_until(func(): return g.delivered == 1, 30, "Worker mines without money or available water")

	check_local_prices(t)

func check_local_prices(t) -> void:
	var g = t.game
	var meal_bread := ceili(g.MAX_HUNGER / g.HUNGER_PER_BREAD)
	# All saleable goods share local pricing, arrival-time checks and physical payment.
	for kind in ["bench", "workbench", "purifier"]:
		for setting in ["one", "two", "disconnect", "outside"]:
			t.fixtures.scenario("Local sale price: " + kind + " / " + setting, 0)
			t.fixtures.power_facilities(1, 0)
			t.fixtures.station("spotlight", Vector2i(32, 9))
			if setting == "two": t.fixtures.station("spotlight", Vector2i(35, 9))
			t.advance_until(func():
				g.select_entity(Vector2i(32, 9))
				return g.entity_details.text.contains("运行中"), 15, "A staffed circuit supplies the sale light")
			var shop := Vector2i(34, 10) if setting != "outside" else Vector2i(40, 10)
			t.fixtures.station(kind, shop, 4 if kind == "purifier" else 1)
			var buyer: Dictionary = g.create_worker(Vector2i(35, 13))
			buyer.hunger = 0
			buyer.bread = meal_bread + (20 if kind == "purifier" else 10)
			buyer.mood.value = 60 if kind == "purifier" else 0
			if setting == "disconnect":
				g.simulate(0.25)
				g.remove_power_line(Vector2i(31, 8))
			var destination: Vector2i = shop
			t.advance_until(func(): return g.stock_at(destination, "bread") > 0, 50, "Buyer reaches a stocked shop and pays its effective price")
			var unit_price: float = g.PRODUCTS[kind].price * (1.0 if setting in ["disconnect", "outside"] else 1.2)
			var quantity: int = 4 - g.benches[destination].stock if kind == "purifier" else 1
			t.check(quantity > 0, "A completed sale transfers at least one item")
			t.near(g.stock_at(destination, "bread"), unit_price * quantity, "Stock transfer and payment use the same current price")
			t.near(buyer.shop_spent_today, unit_price * quantity, "Actual spending reports include the local premium exactly once")
			t.check(buyer.bread >= 0, "A price premium cannot overdraw personal funds")
