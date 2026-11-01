extends RefCounted

const P := Vector2i(28, 11)
const ORE := Vector2i(37, 13)

func run(t) -> void:
	var g = t.game
	for kind in ["bench", "workbench", "tailor", "smithy"]:
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
			if g.equipped_amount(worker, g.product_item(kind)) > 0:
				equipped += 1
		t.check(equipped == 1 and g.benches[P].stock == 0, "One stocked item equips only one competing buyer")
		t.near(g.resource_inventory()[g.product_item(kind)], 1, "Equipping a purchased item transfers inventory instead of destroying it")
		t.near(g.resource_activity(g.product_item(kind), 1).produced + g.resource_activity(g.product_item(kind), 1).consumed, 0, "An equipment sale is neither production nor consumption")
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
	check_item_effects(t)
	check_cleaning(t)
	check_bathing(t)

func check_cleaning(t) -> void:
	var g = t.game
	# Dirt weakens the worn garment without consuming it or adding a permanent mood event.
	t.fixtures.scenario("Worn clothing loses cleanliness and its displayed benefit", 1)
	var w: Dictionary = g.workers[0]
	w.equipment.clothes = g.ITEM_USES.clothes.uses
	g.simulate(24 * g.HOUR_SECONDS)
	t.near(w.clothes_cleanliness, 50, "A day of wearing loses half the initial cleanliness")
	g.select_worker(w.id)
	t.check(t.effect_description("clothes").contains("清洁度 50.0 / 100") and t.effect_description("clothes").contains("心情 +7.5"), "The actual clothing effect scales with its cleanliness")
	g.simulate(24 * g.HOUR_SECONDS)
	t.near(w.clothes_cleanliness, 0, "Clothing dirt is bounded at zero")
	g.select_worker(w.id)
	t.check(t.effect_description("clothes").contains("心情 +0.0"), "Completely dirty clothing no longer grants the clean-clothing bonus")
	t.near(g.resource_inventory().clothes, 1, "Dirt alone does not destroy the garment")

	# Buying transfers stock; only completed washing restores the existing garment.
	t.fixtures.scenario("Cleaning purchase, delayed use and unchanged clothing lifetime", 1)
	t.fixtures.station("soapworks", P, 1)
	w = g.workers[0]
	w.hunger = 100
	w.bread = g.PRODUCTS.soapworks.price
	w.equipment.clothes = g.ITEM_USES.clothes.uses
	w.clothes_cleanliness = 20.0
	var elapsed: float = t.advance_until(func(): return w.shop_spent_today > 0, 20, "A buyer pays for an available cleaning product")
	t.near(g.resource_activity("cleaner", 1).consumed, 0, "Payment alone does not wash clothing")
	t.near(g.resource_inventory().cleaner, 1, "Purchased cleaner remains physically owned before use")
	t.check(w.clothes_cleanliness <= 20, "Buying does not prematurely improve cleanliness")
	elapsed += t.advance_until(func(): return g.resource_activity("cleaner", 1).consumed == 1, 20, "The owned cleaner is spent by an actual wash")
	t.near(w.clothes_cleanliness, 80.0 - elapsed * 100.0 / (g.CLOTHES_DIRTY_HOURS * g.HOUR_SECONDS), "One use restores sixty cleanliness, accounting for elapsed wear", 0.05)
	t.near(w.equipment.clothes, g.ITEM_USES.clothes.uses - elapsed, "Cleaning cannot renew the garment's lifetime", 0.05)
	t.near(g.resource_inventory().cleaner, 0, "Consumed cleaner is not left in personal or shop stock")
	t.near(g.resource_inventory().clothes, 1, "Washing neither duplicates nor destroys clothing")
	g.simulate(g.HOUR_SECONDS)
	t.near(g.resource_activity("cleaner", 1).consumed, 1, "One owned portion cannot wash repeatedly")

	# Unneeded or unusable cleaner must not vanish, including clothes expiring during a wash.
	for setting in ["clean", "unclothed", "expires"]:
		t.fixtures.scenario("Cleaner is retained when washing is not useful: " + setting, 1)
		w = g.workers[0]
		w.hunger = 100
		w.items.cleaner = 1
		if setting != "unclothed": w.equipment.clothes = 1.0 if setting == "expires" else g.ITEM_USES.clothes.uses
		w.clothes_cleanliness = 20.0 if setting == "expires" else 100.0
		g.simulate(g.WASH_HOURS * g.HOUR_SECONDS + 1)
		t.near(g.resource_activity("cleaner", 1).consumed, 0, "No cleaner is wasted on absent, clean or expired clothes")
		t.near(g.resource_inventory().cleaner, 1, "The unused portion remains available")

func check_bathing(t) -> void:
	var g = t.game
	# Two customers cannot share one recipe, pay before completion, or receive permanent mood.
	t.fixtures.scenario("One bath recipe serves one competing customer", 2)
	t.fixtures.station("bathhouse", P)
	t.fixtures.stock_recipe(P, g.BATH_MATERIALS)
	for w in g.workers:
		w.hunger = 100
		w.bread = g.BATH_PRICE
	var cash: float = g.resource_inventory().bread
	g.simulate(g.BATH_HOURS * g.HOUR_SECONDS * 0.5)
	t.near(g.stock_at(P, "bread"), 0, "An incomplete bath has not charged either customer")
	for item in g.BATH_MATERIALS:
		t.near(g.resource_activity(item, 1).consumed, 0, "An incomplete bath does not consume supplies")
	t.advance_until(func(): return g.stock_at(P, "bread") == g.BATH_PRICE, 30, "A completed bath pays the facility once")
	var bathed := 0
	for w in g.workers:
		g.select_worker(w.id)
		if t.effect_description("bathed").contains("心情 +15\n剩余"):
			bathed += 1
		t.near(w.fatigue, 0, "Bathing supplies a mood effect, not labor fatigue")
	t.check(bathed == 1, "Only the customer who completed the bath receives its timed mood effect")
	for item in g.BATH_MATERIALS:
		t.near(g.resource_activity(item, 1).consumed, g.BATH_MATERIALS[item], "Each local bath ingredient is consumed exactly once")
	t.near(g.resource_inventory().bread, cash, "The service transfers bread rather than creating or consuming it")
	g.simulate(g.WorkerBuffs.BATH_EFFECT_HOURS * g.HOUR_SECONDS + 0.1)
	for w in g.workers:
		g.select_worker(w.id)
		t.check(t.effect_description("bathed").is_empty(), "The bath effect expires without becoming permanent mood")
	t.near(g.stock_at(P, "bread"), g.BATH_PRICE, "A missing recipe cannot charge a second customer")

	# Plenty of money and supplies cannot stack or refresh an already active bath effect.
	t.fixtures.scenario("Bath mood lasts without repeat charges or washing clothes", 1)
	t.fixtures.station("bathhouse", P)
	var supplies: Dictionary = g.BATH_MATERIALS.duplicate()
	for item in supplies: supplies[item] *= 2
	t.fixtures.stock_recipe(P, supplies)
	var customer: Dictionary = g.workers[0]
	customer.hunger = 100
	customer.bread = g.BATH_PRICE * 2
	customer.equipment.clothes = g.ITEM_USES.clothes.uses
	customer.clothes_cleanliness = 20.0
	t.advance_until(func(): return customer.shop_spent_today > 0, 30, "The first bath is completed and paid for")
	g.simulate(g.HOUR_SECONDS)
	g.select_worker(customer.id)
	t.near(customer.shop_spent_today, g.BATH_PRICE, "Active bath mood prevents a second fee despite available money and supplies")
	t.check(t.effect_description("bathed").contains("剩余 7.0h"), "The bath benefit counts down instead of refreshing itself")
	t.check(customer.clothes_cleanliness < 20, "Bath mood does not silently wash or replace the worn garment")
	t.near(customer.mood.value, 0, "Bath mood is not written as a permanent positive experience")
	t.near(g.resource_activity("cleaner", 1).consumed, 1, "An active bath effect does not consume a second portion")

	# Remote goods are not a completed service, and neither missing ingredients nor debt funds it.
	for setting in ["remote", "missing", "unaffordable", "debt"]:
		t.fixtures.scenario("Bathing requires local supplies and personal payment: " + setting, 1)
		t.fixtures.station("bathhouse", P)
		if setting == "remote": t.fixtures.isolated_warehouse(g.BATH_MATERIALS)
		else:
			var recipe: Dictionary = g.BATH_MATERIALS.duplicate()
			if setting == "missing": recipe.erase("cleaner")
			t.fixtures.stock_recipe(P, recipe)
		var w: Dictionary = g.workers[0]
		w.hunger = 100
		w.bread = 0.0 if setting == "unaffordable" else g.BATH_PRICE
		if setting == "debt": w.loan_principal = 1.0
		g.simulate(15)
		t.near(w.shop_spent_today, 0, "An unavailable or unaffordable bath never charges")
		for item in g.BATH_MATERIALS:
			t.near(g.resource_activity(item, 1).consumed, 0, "A rejected bath consumes no local or remote ingredients")

	# The usual supply flow must deliver every service ingredient, without special remote charging.
	t.fixtures.scenario("Bathhouse restocks through normal worker delivery", 2)
	t.fixtures.station("bathhouse", P)
	t.fixtures.stock_recipe(g.BASE, g.BATH_MATERIALS)
	for w in g.workers:
		w.hunger = 100
		w.bread = g.BATH_PRICE
	t.advance_until(func(): return g.stock_at(P, "bread") >= g.BATH_PRICE, 50, "Delivered supplies enable a completed paid bath")
	for item in g.BATH_MATERIALS:
		t.near(g.resource_inventory()[item], 0, "The bath consumes its delivered supply without duplicate reservations")

func check_item_effects(t) -> void:
	var g = t.game
	# Buying is only a transfer; the effect belongs to a later actual use.
	t.fixtures.scenario("Ale is bought, held and then consumed", 1)
	t.fixtures.station("brewery", P, 1)
	var buyer: Dictionary = g.workers[0]
	buyer.bread = 2
	buyer.hunger = 100
	buyer.fatigue = 40
	t.advance_until(func(): return buyer.shop_spent_today == 2, 15, "The buyer reaches the brewery and pays for one serving")
	t.near(g.resource_activity("ale", 1).consumed, 0, "Payment does not consume the drink or grant its effect")
	t.near(buyer.fatigue, 40, "Possession alone does not recover fatigue")
	t.near(g.resource_inventory().ale, 1, "The purchased serving remains in physical inventory")
	t.advance_until(func(): return g.resource_activity("ale", 1).consumed == 1, 10, "Actual drinking consumes the owned serving")
	t.near(buyer.fatigue, 20, "Actual drinking applies recovery once", 0.1)
	g.simulate(1)
	t.near(g.resource_activity("ale", 1).consumed, 1, "A sold-out shop and empty personal stock cannot duplicate a drink")
	var plain_hours := 0.0
	# Compare paid output, not a prescribed routine or private efficiency cache.
	for item in ["none", "tools", "clothes", "dirty_clothes", "ale"]:
		t.fixtures.scenario("Owned item use changes real production: " + item, 1)
		t.fixtures.station("workbench", P)
		var w: Dictionary = g.workers[0]
		w.pos = Vector2(P)
		w.fatigue = 40
		if item == "dirty_clothes":
			w.equipment.clothes = g.ITEM_USES.clothes.uses
			w.clothes_cleanliness = 0.0
		elif item != "none": w.items[item] = 1
		g.adjust_production(P, 1)
		if item == "ale":
			t.advance_until(func(): return g.resource_activity("ale", 1).consumed == 1, 10, "The owned drink is actually used before any effect is claimed")
			t.near(w.fatigue, 20, "Ale immediately removes twenty fatigue", 0.1)
			g.select_worker(w.id)
			t.check(t.effect_description("tipsy").contains("酒意") and t.effect_description("tipsy").contains("效率 -20%"), "The inspector exposes both benefit and penalty")
		t.advance_until(func(): return g.resource_activity("workbench", 1).produced == 1, 90, "A worker completes a real paid batch with the owned item")
		var hours: float = g.report_totals(1)["工作"] / g.HOUR_SECONDS
		t.near(w.earned_today, 2, "Effects change speed, not the fixed full-batch wage")
		match item:
			"none": plain_hours = hours
			"tools": t.near(hours, plain_hours / 1.3, "Iron tools accelerate processing labor", 0.02)
			"clothes":
				t.check(hours < plain_hours, "Clothing's mood condition affects actual labor efficiency")
				t.near(g.resource_inventory().clothes, 1, "Wearing clothes is ownership, not immediate consumption")
			"dirty_clothes":
				t.near(hours, plain_hours, "Fully dirty clothing no longer accelerates real production", 0.02)
				t.near(g.resource_inventory().clothes, 1, "Losing the mood benefit does not consume the garment")
			"ale":
				t.check(hours > plain_hours, "Tipsiness lowers actual output speed despite its mood benefit")
				g.simulate(g.WorkerBuffs.ALE_HOURS * g.HOUR_SECONDS)
				g.select_worker(w.id)
				t.check(t.effect_description("tipsy").is_empty(), "Timed alcohol effects expire without another action")

	for kind in ["farm", "workbench", "printer"]:
		t.fixtures.scenario("Tool wear follows eligible labor: " + kind, 1)
		t.fixtures.station(kind, P)
		var w: Dictionary = g.workers[0]
		w.equipment.tools = 1
		if kind == "farm": t.fixtures.stock_recipe(P, {"raw_water": 4})
		if kind == "printer": t.fixtures.stock_recipe(P, {1: 10})
		g.adjust_production(P, 1)
		t.advance_until(func(): return g.workers.size() == 2 if kind == "printer" else g.resource_activity(g.product_item(kind), 1).produced > 0, 150, "Ordered production completes with initially equipped tools")
		t.near(g.resource_activity("tools", 1).consumed, 0 if kind == "printer" else 1, "Only farm and processing labor wear out tools; printing does not")
		if kind == "farm":
			t.near(g.report_totals(1)["工作"] / g.HOUR_SECONDS, 1.0 / 1.3 + 1.0, "One remaining use accelerates watering but not later growth or unequipped harvesting", 0.02)

	t.fixtures.scenario("Clothing expiration removes its condition and consumes one item", 1)
	var w: Dictionary = g.workers[0]
	w.equipment.clothes = 2.0
	g.select_worker(w.id)
	t.check(t.effect_description("clothes").contains("衣物"), "Initially worn clothes appear in live details")
	g.simulate(3)
	g.select_worker(w.id)
	t.check(t.effect_description("clothes").is_empty(), "Expired clothing no longer grants a displayed condition")
	t.near(g.resource_inventory().clothes, 0, "Worn-out clothes leave physical inventory")
	t.near(g.resource_activity("clothes", 1).consumed, 1, "Clothing expiration is recorded once")

	# Secondary meat stock uses the same buy/own/use path, not wool or factory cash.
	t.fixtures.scenario("Meat sale and actual consumption conserve inventory", 1)
	t.fixtures.station("barn", P)
	t.fixtures.stock_recipe(P, {"meat": 1})
	w = g.workers[0]
	w.bread = 1
	w.hunger = 60
	t.advance_until(func(): return g.resource_activity("meat", 1).consumed == 1, 40, "A hungry buyer purchases and eats meat from the barn")
	t.near(w.shop_spent_today, 1, "Meat charges its own listed price once")
	t.near(g.resource_inventory().meat, 0, "Eaten meat is not also held or left for sale")
	t.check(w.hunger > 60, "Eating meat restores hunger")

func check_local_prices(t) -> void:
	var g = t.game
	var meal_bread := ceili(g.MAX_HUNGER / g.HUNGER_PER_BREAD)
	# All saleable goods share local pricing, arrival-time checks and physical payment.
	for kind in ["bench", "workbench", "purifier", "soapworks"]:
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
			if kind == "soapworks":
				buyer.equipment.clothes = g.ITEM_USES.clothes.uses
				buyer.clothes_cleanliness = 20.0
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
