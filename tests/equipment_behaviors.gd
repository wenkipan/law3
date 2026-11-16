extends RefCounted

const P := Vector2i(28, 11)

func run(t) -> void:
	check_diets(t)
	check_market(t)
	check_market_repricing(t)
	check_loans(t)
	check_services(t)
	check_equipment(t)

func check_diets(t) -> void:
	var g = t.game
	for item in ["berries", "meat", "wheat", "bread"]:
		t.fixtures.scenario("Every resident can eat every food: " + item)
		var resident: Dictionary = t.fixtures.resident("mining", P, "grain", {item: 2})
		resident.hunger = 40.0
		resident.money = 10.0
		t.advance_until(func(): return resident.eaten_today > 0, 20, "The resident eats the available personal food")
		t.near(resident.money, 10, "Eating cannot consume payment currency")
		t.check(g.resource_inventory()[item] < 2, "An actual bite reduces physical food")

func market_fixture(t, label: String) -> void:
	t.fixtures.scenario(label)
	t.fixtures.station("market", t.game.BASE)
	t.fixtures.resident("operations", t.game.BASE + Vector2i.DOWN)
	t.game.set_wage(t.game.BASE, 2)

func check_market(t) -> void:
	var g = t.game
	market_fixture(t, "A funded market only sells its existing stock")
	var seller: Dictionary = t.fixtures.resident("mining", Vector2i(26, 15), "meat", {"berries": 8})
	var buyer: Dictionary = t.fixtures.resident("operations", Vector2i(37, 15), "fruit", {"bread": 6})
	buyer.money = 12.0
	t.fixtures.stock_recipe(g.BASE, {"meat": 8})
	g.simulate(60)
	t.near(g.stock_at(g.BASE, "berries"), 0, "Personal goods cannot enter even a funded market")
	t.near(seller.items.berries, 8, "The market does not take a resident's own goods")
	t.near(seller.money, 0, "The market does not pay for a resident's goods")
	t.near(buyer.money, 12, "No stocked food means no charge to the buyer")
	t.near(g.resource_inventory().money, 612, "Market wages conserve the initial money supply")

func check_market_repricing(t) -> void:
	var g = t.game
	market_fixture(t, "Decision quotes cannot authorize a later unaffordable purchase")
	t.fixtures.stock_recipe(g.BASE, {"berries": 8})
	g.set_market_price(g.BASE, "berries", 1)
	var checkpoint: Dictionary = g.capture_snapshot()
	t.check(checkpoint.ok and g.restore_snapshot(checkpoint.data).ok, "Per-item market prices can be saved and restored")
	t.near(g.market_price(g.BASE, "berries"), 1, "Restoring preserves the player sale price")
	t.near(g.stock_at(g.BASE, "berries"), 8, "Restoring preserves the actual shelf stock")
	g.simulate(4)
	var customer: Dictionary = t.fixtures.resident("mining", Vector2i(46, 17), "fruit")
	customer.money = 6.0
	customer.hunger = 30.0
	g.simulate(0.1)
	g.set_market_price(g.BASE, "berries", 9)
	g.simulate(6)
	t.near(g.stock_at(g.BASE, "berries"), 8, "An old decision quote cannot sell stock at a now unaffordable price")
	t.near(customer.money, 6, "Repricing cannot overdraw or charge the travelling customer")
	g.set_market_price(g.BASE, "berries", 1)
	t.advance_until(func(): return customer.items.get("berries", 0) > 0 or customer.eaten_today > 0, 90, "A later decision uses the current affordable quote and completes a physical purchase")
	t.near(g.resource_inventory().money, 606, "Repricing and renewed shopping preserve the real currency supply")

func check_loans(t) -> void:
	var g = t.game
	market_fixture(t, "A staffed bank funds an actual compatible-food purchase without minting money")
	t.fixtures.stock_recipe(g.BASE, {"wheat": 8})
	t.fixtures.station("bank", P)
	t.fixtures.resident("operations", P)
	t.fixtures.stock_recipe(g.BASE, {"money": -g.LOAN_LIMIT})
	t.fixtures.stock_recipe(P, {"money": g.LOAN_LIMIT})
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
		t.fixtures.resident("medicine" if kind == "hospital" else "operations", P)
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
	var customer: Dictionary = t.fixtures.resident("operations", P)
	customer.money = 12.0
	t.fixtures.stock_recipe(g.BASE, {"clothes": 1})
	var starting: float = g.resource_inventory().money
	t.advance_until(func(): return customer.equipment.get("clothes", 0) > 0, 100, "A resident buys real clothing and autonomously wears it")
	t.near(g.stock_at(g.BASE, "clothes"), 0, "Equipment is removed from the market once")
	t.near(g.resource_inventory().money, starting, "Buying equipment transfers payment instead of destroying it")
	t.near(g.player_inventory().clothes, 0, "Worn personal equipment is not player inventory")
