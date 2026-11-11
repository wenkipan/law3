extends RefCounted

const P := Vector2i(28, 11)

func run(t) -> void:
	check_diets(t)
	check_market(t)
	check_market_limits(t)
	check_loans(t)
	check_services(t)
	check_equipment(t)

func check_diets(t) -> void:
	var g = t.game
	for diet in ["fruit", "meat", "grain"]:
		t.fixtures.scenario("Diet-specific food consumes goods, never currency: " + diet)
		var resident: Dictionary = t.fixtures.resident("mining", P, diet, {"berries": 2, "meat": 2, "wheat": 2})
		resident.hunger = 40.0
		resident.money = 10.0
		var food: String = g.DIETS[diet][0]
		t.advance_until(func(): return resident.eaten_today > 0, 20, "The resident eats a compatible personal food")
		for other in ["berries", "meat", "wheat"]:
			if other != food: t.near(resident.items[other], 2, "An incompatible food is not consumed")
		t.near(resident.money, 10, "Eating cannot consume payment currency")
		t.check(g.resource_inventory()[food] < 2, "An actual bite reduces physical food")

func market_fixture(t, label: String) -> void:
	t.fixtures.scenario(label)
	t.fixtures.station("market", t.game.BASE)
	t.fixtures.resident("trade", t.game.BASE + Vector2i.DOWN)
	t.game.set_wage(t.game.BASE, 2)

func check_market(t) -> void:
	var g = t.game
	market_fixture(t, "Personal goods reach other residents only through a funded market")
	var seller: Dictionary = t.fixtures.resident("mining", Vector2i(26, 15), "meat", {"berries": 8})
	var buyer: Dictionary = t.fixtures.resident("research", Vector2i(37, 15), "fruit")
	buyer.money = 12.0
	t.fixtures.stock_recipe(g.BASE, {"meat": 8})
	g.simulate(0.1)
	t.near(g.stock_at(g.BASE, "berries"), 0, "Goods cannot transfer before a real seller arrives")
	t.advance_until(func(): return seller.items.berries < 8 and (buyer.items.get("berries", 0) > 0 or buyer.eaten_today > 0), 90, "Selling and buying create actual market-mediated exchange")
	t.check(seller.money > 0 or seller.items.get("meat", 0) > 0 or seller.eaten_today > 0, "A seller receives money or spends it on real needs")
	t.near(g.resource_inventory().money, 612, "Sales, purchases and wages conserve the initial money supply")
	t.near(g.resource_inventory().berries + g.resource_activity("berries", g.world.day).get("consumed", 0), 8, "Trading cannot duplicate berries")

func check_market_limits(t) -> void:
	var g = t.game
	market_fixture(t, "Market prices and closure respect physical cash and stock")
	var seller: Dictionary = t.fixtures.resident("mining", g.BASE, "meat", {"berries": 8})
	g.set_market_price(g.BASE, "berries", 0, true)
	g.simulate(4)
	t.near(seller.items.berries, 8, "Zero buy price disables purchasing that commodity")
	g.set_market_price(g.BASE, "berries", 3, true)
	g.add_stock(g.BASE, "money", -g.stock_at(g.BASE, "money"))
	g.simulate(3)
	t.near(seller.items.berries, 8, "An unfunded market cannot buy goods")
	g.set_wage(g.BASE, 0)
	g.add_stock(g.BASE, "money", 30)
	g.simulate(3)
	t.near(seller.items.berries, 8, "A closed market cannot trade even after funds arrive")
	g.set_wage(g.BASE, 2)
	t.advance_until(func(): return g.stock_at(g.BASE, "berries") > 0, 60, "Reopening permits a qualified employee and funded purchases")
	var checkpoint: Dictionary = g.capture_snapshot()
	t.check(checkpoint.ok, "Per-item market prices can be saved")
	if checkpoint.ok:
		t.check(g.restore_snapshot(checkpoint.data).ok, "Per-item market prices restore safely")
		t.near(g.market_price(g.BASE, "berries", true), 3, "Restoring preserves the player buy quote")
	market_fixture(t, "Decision quotes cannot authorize a later unaffordable purchase")
	t.fixtures.stock_recipe(g.BASE, {"berries": 8})
	g.simulate(4)
	var customer: Dictionary = t.fixtures.resident("mining", Vector2i(46, 17), "fruit")
	customer.money = 6.0
	customer.hunger = 30.0
	g.set_market_price(g.BASE, "berries", 1, false)
	g.simulate(0.1)
	g.set_market_price(g.BASE, "berries", 9, false)
	g.simulate(6)
	t.near(g.stock_at(g.BASE, "berries"), 8, "An old decision quote cannot sell stock at a now unaffordable price")
	t.near(customer.money, 6, "Repricing cannot overdraw or charge the travelling customer")
	g.set_market_price(g.BASE, "berries", 1, false)
	t.advance_until(func(): return customer.items.get("berries", 0) > 0 or customer.eaten_today > 0, 90, "A later decision uses the current affordable quote and completes a physical purchase")
	t.near(g.resource_inventory().money, 606, "Repricing and renewed shopping preserve the real currency supply")

func check_loans(t) -> void:
	var g = t.game
	market_fixture(t, "A staffed bank funds an actual compatible-food purchase without minting money")
	t.fixtures.stock_recipe(g.BASE, {"wheat": 8})
	t.fixtures.station("bank", P)
	t.fixtures.resident("trade", P)
	var borrower: Dictionary = t.fixtures.resident("mining", P + Vector2i.DOWN)
	borrower.hunger = 30.0
	t.advance_until(func(): return g.has_debt(borrower) and (borrower.items.get("wheat", 0) > 0 or borrower.eaten_today > 0), 100, "Borrowing leads to a real market food purchase")
	t.check(g.worker_special_items(borrower).has("loan"), "The outstanding loan remains visible as a personal contract")
	t.near(g.resource_inventory().money, 600, "Bank funding, lending and shopping preserve the currency supply")
	g.set_wage(P, 0)
	t.check(g.demolish_building(P), "The player may demolish the closed bank")
	t.check(not g.world.has_building(P, "bank"), "Demolition cannot leave a ghost lending facility")

func check_services(t) -> void:
	var g = t.game
	for kind in ["hospital", "laundry"]:
		t.fixtures.scenario("Staffed services preserve local goods and actual payments: " + kind)
		t.fixtures.station(kind, P)
		t.fixtures.resident("medicine" if kind == "hospital" else "processing", P)
		var customer: Dictionary = t.fixtures.resident("mining", P + Vector2i(0, 2))
		customer.money = 10.0
		customer.pollution = 80.0 if kind == "hospital" else 0.0
		if kind == "laundry":
			customer.equipment.clothes = g.ITEM_USES.clothes.uses
			customer.clothes_pollution = 50.0
		t.fixtures.stock_recipe(P, g.SERVICES[kind].materials)
		t.advance_until(func(): return customer.pollution < 70 if kind == "hospital" else customer.clothes_pollution < 1, 100, "The completed service applies its actual recovery")
		t.near(customer.shop_spent_today, g.SERVICES[kind].price, "A completed service charges exactly once")
		for item in g.SERVICES[kind].materials:
			t.near(g.resource_inventory()[item], 0, "The completed service consumes only its actual local supplies")
		if kind == "laundry":
			t.near(g.resource_inventory().wastewater, 1, "Cleaning retains its physical wastewater")
			t.near(g.world.waste_at(P), 25, "The retained wastewater carries the actual remaining pollution")

func check_equipment(t) -> void:
	var g = t.game
	market_fixture(t, "Market equipment purchases remain separate from use and personal ownership")
	var customer: Dictionary = t.fixtures.resident("processing", P)
	customer.money = 12.0
	t.fixtures.stock_recipe(g.BASE, {"clothes": 1})
	var starting: float = g.resource_inventory().money
	t.advance_until(func(): return customer.equipment.get("clothes", 0) > 0, 100, "A resident buys real clothing and autonomously wears it")
	t.near(g.stock_at(g.BASE, "clothes"), 0, "Equipment is removed from the market once")
	t.near(g.resource_inventory().money, starting, "Buying equipment transfers payment instead of destroying it")
	t.near(g.player_inventory().clothes, 0, "Worn personal equipment is not player inventory")
