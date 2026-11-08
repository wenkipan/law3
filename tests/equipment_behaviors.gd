extends RefCounted

const P := Vector2i(28, 11)
const ORE := Vector2i(37, 13)

func run(t) -> void:
	var g = t.game
	# One equipment sale represents ownership transfer and competing buyers.
	t.fixtures.scenario("One stocked item cannot be sold to two buyers", 2)
	t.fixtures.station("bench", P, 1)
	var product: Dictionary = g.PRODUCTS.bench
	for worker in g.world.workers:
		worker.bread = product.price
		worker.hunger = 100
	g.designate(Vector2i(37, 12), Vector2i(37, 14))
	g.simulate(11)
	var sold: int = 1 - g.world.benches[P].stock
	var held := 0
	for worker in g.world.workers:
		held += int(g.equipped_amount(worker, "bench") > 0) + worker.items.get("bench", 0)
	t.check(sold in [0, 1] and held == sold, "Stock transfers to at most one competing buyer")
	t.near(g.resource_inventory().bench, 1, "Purchasing and equipping transfer the existing item")
	t.near(g.resource_activity("bench", 1).produced + g.resource_activity("bench", 1).consumed, 0, "A sale is neither production nor consumption")
	t.near(g.world.workers[0].shop_spent_today + g.world.workers[1].shop_spent_today, product.price * sold, "Only transferred goods charge")

	t.fixtures.scenario("Equipment wear consumes one actual item", 1)
	var miner: Dictionary = g.world.workers[0]
	miner.pos = Vector2(36, 13)
	miner.gun_uses = 1
	g.designate(ORE, ORE)
	t.advance_until(func(): return g.world.delivered == 1, 30, "Ordered mining completes with the initially equipped item")
	t.check(miner.gun_uses == 0, "The completed labor spends the remaining durability")
	t.near(g.resource_activity("bench", 1).consumed, 1, "An exhausted item is consumed exactly once")

	var w: Dictionary
	# Equal items still need distinct one-item deliveries; neither case may strand its second block.
	for second_item in [1, 2]:
		t.fixtures.scenario("Backpack delivers two blocks; exhaustion restores single trips: " + str(second_item), 1)
		w = g.world.workers[0]
		w.pos = Vector2(36, 13)
		w.backpack_uses = 1
		w.gun_uses = 4
		g.world.terrain[ORE] = 1
		g.world.terrain[ORE + Vector2i.RIGHT] = second_item
		g.designate(ORE, ORE + Vector2i.RIGHT)
		t.advance_until(func(): return g.world.delivered >= 1, 25, "Backpack starts unloading its first load")
		g.simulate(0.7)
		t.check(g.world.delivered == 2, "The same-receiver load continues unloading without another activity between items")
		t.check(g.world.delivered == 2 and g.player_blocks == 2 and w.backpack_uses == 0, "First trip delivers two blocks and spends one backpack use")
		t.near(g.resource_activity("workbench", 1).consumed, 1, "An exhausted backpack is consumed once, not once per ore delivered")
		t.check(g.materials.get(1, 0) == (2 if second_item == 1 else 1) and g.materials.get(2, 0) == (0 if second_item == 1 else 1), "Backpack preserves the actual mineral quantities after delivery")
		g.designate(Vector2i(39, 13), Vector2i(40, 13))
		t.advance_until(func(): return g.world.delivered > 2, 25, "Worker continues after backpack wears out")
		t.check(g.world.delivered == 3, "Worn-out backpack delivers only one block per trip")

	t.fixtures.scenario("Cancelled second block still delivers a partial load", 1)
	w = g.world.workers[0]
	w.pos = Vector2(36, 13)
	w.backpack_uses = 1
	g.designate(ORE, ORE + Vector2i.RIGHT)
	t.advance_until(func(): return g.world.mined == 1, 20, "First block is excavated")
	g.designate(ORE + Vector2i.RIGHT, ORE + Vector2i.RIGHT, true)
	t.advance_until(func(): return g.world.delivered == 1, 10, "Cancellation does not strand cargo")
	t.check(w.backpack_uses == 1, "Single-block delivery does not spend a backpack use")

	t.fixtures.scenario("Water sales conserve stock and respect carrying capacity", 2)
	t.fixtures.station("purifier", P, 6)
	for worker in g.world.workers:
		worker.bread = 9.0
		worker.hunger = 100
	g.designate(Vector2i(37, 11), Vector2i(37, 15))
	g.simulate(10)
	var water_sold: int = 6 - g.world.benches[P].stock
	t.near(g.world.workers[0].water + g.world.workers[1].water + g.resource_activity("clean_water", 1).consumed, water_sold, "Actual competing water purchases reconcile held and consumed portions")
	t.near(g.world.workers[0].shop_spent_today + g.world.workers[1].shop_spent_today, water_sold * g.PRODUCTS.purifier.price, "Water revenue equals actual portions sold")

	check_item_accounting(t)
	check_services(t)
	check_delivery_recovery(t)
	check_consumption_conditions(t)
	check_local_prices(t)
	check_adjusted_fees(t)
	check_hard_need_limits(t)

func check_hard_need_limits(t) -> void:
	var g = t.game
	# Real threshold crossings settle earned labor, never an unfinished product or duplicate recipe.
	for setting in ["starvation", "illness_crossing"]:
		t.fixtures.need_interrupt_production(setting)
		g.adjust_production(P, 1)
		t.advance_until(func(): return g.world.workers[0].earned_today > 0, 10, "Crossing the hard need limit settles actual unfinished labor")
		var person: Dictionary = g.world.workers[0]
		t.check(person.earned_today < 2 and g.world.benches[P].stock == 0, "The interruption pays only completed labor and cannot create an unfinished product")
		if setting == "starvation":
			t.advance_until(func(): return g.resource_activity("bread", 1).consumed > 0, 10, "The interruption's real wages can fund an actual meal")
		else:
			t.check(person.pollution >= 90, "Real environmental exposure has crossed the severe-illness limit")
			t.near(g.resource_activity("medical", 1).consumed, 0, "Crossing the illness limit cannot bypass the treatment's actual price")
		t.advance_until(func(): return g.world.benches[P].stock == 1, 90, "Production can finish after responding to the need limit")
		t.near(person.earned_today, 2, "Interrupted and resumed production pays its one contract exactly once")
		t.near(g.resource_activity(2, 1).consumed, 1, "Need interruptions never consume the batch ingredients twice")

	# Simultaneous limits must not keep canceling a bite or restarting sleep without recovery.
	t.fixtures.need_interrupt_production("exhaustion")
	g.adjust_production(P, 1)
	g.simulate(0.1)
	t.near(g.report_totals(1)["工作"], 0, "An exhausted worker cannot start the pending production instead of responding")
	t.advance_until(func(): return g.resource_activity("bread", 1).consumed > 0 and g.world.workers[0].fatigue < g.MAX_FATIGUE, 20, "Zero hunger and maximum fatigue permit actual food use and recovery")
	t.check(g.world.workers[0].bread >= 0, "Combined need responses cannot overdraw food")

	# Disease at 70 is not the new emergency at 90; no hourly timer may settle this batch.
	t.fixtures.need_interrupt_production("ordinary_illness")
	g.adjust_production(P, 1)
	t.advance_until(func(): return g.report_totals(1)["工作"] > 0, 10, "The ordered batch begins with actual local ingredients")
	g.simulate(g.HOUR_SECONDS * 1.1)
	t.check(g.world.workers[0].pollution >= g.Pollution.DISEASE and g.world.workers[0].pollution < 90, "Exposure crosses the ordinary disease threshold without reaching the hard limit")
	t.near(g.world.workers[0].earned_today, 0, "Neither an elapsed hour nor ordinary illness settles unfinished labor")
	t.near(g.resource_activity("medical", 1).consumed, 0, "Ordinary illness cannot interrupt the running batch for treatment")
	t.advance_until(func(): return g.world.benches[P].stock == 1, 60, "The batch still completes normally")

	# At 90, a stocked affordable hospital is a response, not another optional purchase.
	t.fixtures.need_interrupt_production("severe_illness")
	g.adjust_production(P, 1)
	var cash: float = g.resource_inventory().bread
	t.advance_until(func(): return g.resource_activity("medical", 1).consumed == 1, 30, "The hard illness limit receives actual treatment")
	t.near(g.world.workers[0].shop_spent_today, g.SERVICES.hospital.price, "The emergency treatment charges once on completion")
	t.check(g.world.workers[0].pollution < 90, "Completed treatment removes the severe-illness condition")
	t.near(g.resource_inventory().bread + g.resource_activity("bread", 1).consumed, cash, "Emergency treatment transfers payment without creating bread")

	# No remedy must not turn a persistent threshold, or loading it, into repeated exits.
	for setting in ["no_food", "no_medical"]:
		t.fixtures.need_interrupt_production(setting)
		g.adjust_production(P, 1)
		t.advance_until(func(): return g.report_totals(1)["工作"] > 0, 10, "Unavailable remedies do not prevent real productive work")
		var before: Dictionary = t.world_observations()
		var saved: Dictionary = g.capture_snapshot()
		g.simulate(0.1)
		var loaded: Dictionary = g.restore_snapshot(saved.data) if saved.ok else saved
		t.check(loaded.ok and t.world_observations() == before, "Loading a persistent need limit replays neither wages nor consumption")
		g.simulate(1)
		t.near(g.world.workers[0].earned_today, 0, "An unchanged unserviceable limit cannot repeatedly settle and restart labor")
		t.advance_until(func(): return g.world.benches[P].stock == 1, 90, "The same ordered batch can finish despite an unavailable remedy")
		t.near(g.world.workers[0].earned_today, 2, "Unavailable remedies cannot duplicate resumed wages")
		t.near(g.resource_activity(2, 1).consumed, 1, "Unavailable remedies cannot duplicate ingredient consumption")

func check_item_accounting(t) -> void:
	var g = t.game
	# Actual use and expiry remove goods; their balance effects are not test contracts.
	t.fixtures.scenario("Owned drink is consumed exactly once", 1)
	var person: Dictionary = g.world.workers[0]
	person.hunger = 100
	person.fatigue = 40
	person.items.ale = 1
	t.advance_until(func(): return g.resource_activity("ale", 1).consumed == 1, 10, "The owned serving is actually consumed")
	g.simulate(1)
	t.near(g.resource_inventory().ale, 0, "Consumed drink is not also retained as personal stock")
	t.near(g.resource_activity("ale", 1).consumed, 1, "An empty personal inventory cannot consume another serving")

	t.fixtures.scenario("Expired equipment leaves physical inventory once", 1)
	g.world.workers[0].equipment.clothes = 2.0
	g.simulate(3)
	t.near(g.resource_inventory().clothes, 0, "Expired clothing leaves physical inventory")
	t.near(g.resource_activity("clothes", 1).consumed, 1, "Expiry is recorded as one consumed item")

	t.fixtures.scenario("Actual food purchase and use reconcile payment and inventory", 1)
	t.fixtures.station("barn", P)
	t.fixtures.stock_recipe(P, {"meat": 1})
	person = g.world.workers[0]
	person.bread = 1
	person.hunger = 60
	var cash: float = g.resource_inventory().bread
	t.advance_until(func(): return g.resource_activity("meat", 1).consumed == 1, 40, "A real sale transfers food that is subsequently eaten")
	t.near(person.shop_spent_today, 1, "Only the actual sale charges")
	t.near(g.resource_inventory().meat, 0, "Eaten food is neither held nor still for sale")
	t.near(g.resource_inventory().bread + g.resource_activity("bread", 1).consumed, cash, "The purchase transfers existing payment bread")

func check_services(t) -> void:
	var g = t.game
	var kind := "bathhouse"
	var service: Dictionary = g.SERVICES[kind]
	# One service represents shared supply, payment, debt and exclusivity safeguards.
	for setting in ["local", "delivered", "remote", "missing", "unaffordable", "debt", "cargo", "competing"]:
		t.fixtures.scenario("Service settlement: " + setting, 2 if setting == "competing" else 1)
		t.fixtures.station(kind, P)
		for person in g.world.workers:
			t.fixtures.service_customer(kind, P, person, setting == "debt")
		var customer: Dictionary = g.world.workers[0]
		if setting == "cargo": customer.carry = 1
		var stock: Dictionary = service.materials.duplicate()
		if setting == "missing": stock.erase(stock.keys()[0])
		if setting == "remote": t.fixtures.isolated_warehouse(stock)
		else: t.fixtures.stock_recipe(g.BASE if setting == "delivered" else P, stock)
		if setting == "unaffordable": customer.bread = 0.0
		var cash: float = g.resource_inventory().bread
		g.simulate(service.hours * g.HOUR_SECONDS * 0.4)
		t.near(g.stock_at(P, "bread"), 0, "An incomplete service charges nothing")
		for item in service.materials:
			t.near(g.resource_activity(item, 1).consumed, 0, "An incomplete service consumes no ingredients")
		if setting in ["remote", "missing", "unaffordable"]:
			g.simulate(service.hours * g.HOUR_SECONDS + 1)
			t.near(customer.shop_spent_today, 0, "An unavailable service cannot charge")
			for item in service.materials:
				t.near(g.resource_activity(item, 1).consumed, 0, "Rejected service retains every ingredient")
			t.near(g.resource_inventory().wastewater, 0, "Incomplete service produces no wastewater")
			continue
		t.advance_until(func(): return g.stock_at(P, "bread") > 0, 60, "A completed service settles using actual local supplies")
		if setting == "competing": g.simulate(service.hours * g.HOUR_SECONDS + 1)
		var spent := 0.0
		for person in g.world.workers: spent += person.shop_spent_today
		t.near(spent, service.price, "One supplied service can charge only one customer")
		for item in service.materials:
			t.near(g.resource_activity(item, 1).consumed, service.materials[item], "The local recipe is consumed exactly once")
		t.near(g.resource_inventory().wastewater, service.materials.clean_water, "Consumed clean water becomes actual wastewater")
		t.near(customer.loan_principal, 1 if setting == "debt" else 0, "A service does not change existing debt")
		t.near(g.resource_inventory().bread, cash, "Service payment transfers existing bread")
		if setting == "cargo": t.near(g.resource_inventory()[1], 1, "Seeking service does not lose carried goods")

func check_delivery_recovery(t) -> void:
	var g = t.game
	# Illness arising during a real supply trip must not lose or duplicate its building materials.
	t.fixtures.scenario("Illness and a long supply trip preserve treatment and material settlement", 1)
	var target := Vector2i(100, 13)
	t.fixtures.clear_area(Rect2i(Vector2i(28, 11), Vector2i(74, 4)))
	t.fixtures.station("hospital", P)
	t.fixtures.stock_recipe(P, g.SERVICES.hospital.materials)
	t.fixtures.building_materials("bed")
	t.fixtures.station("storage_box", Vector2i(40, 13))
	t.fixtures.wastewater(Vector2i(40, 13), 1, 200)
	var person: Dictionary = g.world.workers[0]
	person.hunger = 100
	person.bread = g.SERVICES.hospital.price
	person.pollution = 69.0
	var initial_cash: float = g.resource_inventory().bread
	t.check(g.place_building(target, "bed"), "The player orders a distant bed with physical materials available")
	t.advance_until(func(): return g.resource_activity("medical", 1).consumed > 0, 150, "Illness arising after the order can receive real treatment")
	t.advance_until(func(): return g.world.beds.has(target), 150, "The ordered bed can still receive all materials and finish")
	t.near(g.resource_activity("medical", 1).consumed, 1, "One treatment consumes one medical supply")
	t.near(person.shop_spent_today, g.SERVICES.hospital.price, "Treatment charges once, independently of the delivery")
	t.near(g.resource_activity(1, 1).consumed, g.building_blocks("bed"), "Construction consumes exactly its delivered recipe")
	t.near(g.resource_inventory()[1], 0, "Treatment and resumed delivery leave no lost or duplicate sandstone")
	t.near(g.resource_inventory().bread + g.resource_activity("bread", 1).consumed, initial_cash, "Treatment and actual labor conserve payment bread")

func check_consumption_conditions(t) -> void:
	var g = t.game
	# Debt and carried ore cannot replace actual cash and stock checks or destroy cargo.
	var kind := "purifier"
	for setting in ["plain", "debt", "cargo"]:
		for affordable in [false, true]:
			var debt: bool = setting == "debt"
			t.fixtures.scenario("Goods depend on cash and stock: %s / %s / affordable %s" % [kind, setting, affordable], 1)
			t.fixtures.station(kind, P, 1)
			var customer: Dictionary = g.world.workers[0]
			t.fixtures.shop_customer(kind, P, customer, debt, affordable)
			if setting == "cargo": customer.carry = 1
			var price: float = g.PRODUCTS[kind].price
			var initial_cash: float = g.resource_inventory().bread
			g.simulate(10)
			var sold: float = 1 - g.stock_at(P, g.product_item(kind))
			t.check(sold in [0.0, 1.0] and (affordable or sold == 0), "Only an affordable chosen drink can leave the shop")
			t.near(customer.shop_spent_today, price * sold, "Only an actual completed sale charges the listed price, irrespective of debt or cargo")
			t.near(g.resource_inventory().bread, initial_cash, "A purchase conserves physical payment bread")
			t.check(customer.bread >= 0, "Neither debt nor insufficient funds permits overdrawing")
			t.near(customer.loan_principal, 1 if debt else 0, "Shopping does not modify existing principal")
			t.near(customer.loan_interest, 0.2 if debt else 0, "Shopping does not modify existing interest")
			t.near(g.world.portal.lent_bread, 0, "Optional consumption does not issue an extra loan")
			if setting == "cargo":
				t.near(g.resource_inventory()[1], 1, "Shopping and delivery choices preserve the initial carried ore")

func check_local_prices(t) -> void:
	var g = t.game
	var meal_bread := ceili(g.MAX_HUNGER / g.HUNGER_PER_BREAD)
	# One quoted good covers payment at the current price, including a change before arrival.
	for setting in ["powered", "disconnect"]:
		t.fixtures.scenario("Stock and payment reconcile at the current sale price: " + setting, 0)
		t.fixtures.power_facilities(1, 0)
		t.fixtures.station("spotlight", Vector2i(32, 9))
		var shop := Vector2i(34, 10)
		t.advance_until(func(): return g.has_powered_effect(Vector2(shop), "spotlight"), 15, "A real staffed circuit enables the price condition")
		t.fixtures.station("bench", shop, 1)
		g.set_fee(shop, 3)
		var buyer: Dictionary = g.create_worker(Vector2i(35, 13))
		buyer.hunger = 0
		buyer.bread = meal_bread + 10
		g.simulate(0.25)
		g.set_fee(shop, 6)
		if setting == "disconnect":
			g.remove_power_line(Vector2i(31, 8))
		t.observe_until(func(): return buyer.shop_spent_today > 0, 50)
		var unit_price: float = 6 * (1.0 if setting == "disconnect" else 1.0 + g.LIGHT_BONUS)
		var quantity: int = 1 - g.world.benches[shop].stock
		t.check(quantity in [0, 1], "A sale cannot exceed listed physical stock")
		t.near(g.stock_at(shop, "bread"), unit_price * quantity, "The store receives only payment for actual transferred goods at the current price")
		t.near(buyer.shop_spent_today, unit_price * quantity, "Recorded spending equals the store receipt")
		t.check(buyer.bread >= 0, "A changed price cannot overdraw personal funds")

func check_adjusted_fees(t) -> void:
	var g = t.game
	# Bed admission, service completion and goods transfer have distinct payment
	# boundaries, but share the same adjusted-price and real-bread contract.
	for kind in ["bed", "hospital", "purifier"]:
		for fee in [3, 9]:
			t.fixtures.fee_customer(kind)
			g.set_fee(P, fee)
			var bread: float = g.resource_inventory().bread
			if kind == "hospital" and fee == 3:
				t.advance_until(func(): return g.resource_activity("medical", 1).consumed > 0, 60, "Treatment can actually complete at the new affordable fee")
			else:
				g.simulate(30)
			var person: Dictionary = g.world.workers[0]
			var spent: float = person.bed_spent_today if kind == "bed" else person.shop_spent_today
			var count: float = (1.0 if spent > 0 else 0.0) if kind == "bed" else (g.resource_activity("medical", 1).consumed if kind == "hospital" else 1 - g.stock_at(P, "clean_water"))
			t.near(spent, fee * count, "Only actual admissions, completed services or transferred goods charge the adjusted fee")
			t.near(g.stock_at(P, "bread"), spent, "The selected building receives exactly the customer's actual payment")
			if fee == 9: t.near(spent, 0, "An unaffordable player price cannot overdraw or grant paid use")
			t.near(g.resource_inventory().bread + g.resource_activity("bread", 1).consumed, bread, "Changing prices transfers bread without creating it")
			t.check(person.bread >= 0, "Actual adjusted payments leave no negative personal balance")
			print("DIAGNOSTIC: ", kind, " fee ", fee, " actual transactions = ", count)
