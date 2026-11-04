extends RefCounted

const P := Vector2i(28, 11)
const ORE := Vector2i(37, 13)

func run(t) -> void:
	var g = t.game
	var sales_observed := 0
	# Compare accounting for actual choices, not whether every missing item is bought.
	for kind in ["bench", "workbench", "tailor", "smithy"]:
		t.fixtures.scenario("Last item has one buyer: " + kind, 2)
		t.fixtures.station(kind, P, 1)
		var product: Dictionary = g.PRODUCTS[kind]
		for worker in g.world.workers:
			worker.bread = product.price
			worker.hunger = 100
		g.designate(Vector2i(37, 12), Vector2i(37, 14))
		g.simulate(11)
		var sold: int = 1 - g.world.benches[P].stock
		sales_observed += sold
		var held := 0
		for worker in g.world.workers:
			held += int(g.equipped_amount(worker, g.product_item(kind)) > 0) + worker.items.get(g.product_item(kind), 0)
		t.check(sold in [0, 1] and held == sold, "One stocked item can belong to at most one competing buyer")
		t.near(g.resource_inventory()[g.product_item(kind)], 1, "Equipping a purchased item transfers inventory instead of destroying it")
		t.near(g.resource_activity(g.product_item(kind), 1).produced + g.resource_activity(g.product_item(kind), 1).consumed, 0, "An equipment sale is neither production nor consumption")
		t.near(g.world.workers[0].shop_spent_today + g.world.workers[1].shop_spent_today, product.price * sold, "Only actual transferred equipment can charge, without a second buyer")
	t.check(sales_observed > 0, "The shared equipment accounting contract includes real autonomous sales")

	t.fixtures.scenario("Sale does not replenish today's completed quota", 1)
	t.fixtures.station("bench", P)
	t.fixtures.materials(1, 2)
	g.world.workers[0].bread = 3.0
	g.world.workers[0].hunger = 100
	g.adjust_production(P, 1)
	g.simulate(20)
	g.designate(ORE, ORE)
	g.simulate(120)
	g.simulate(30)
	t.near(g.resource_activity("bench", 1).produced, 1, "Completed daily quota cannot manufacture another item, whether sold or retained")

	var plain_time := 0.0
	var plain_fatigue := 0.0
	for equipment in ["none", "gun", "water"]:
		t.fixtures.scenario("Mining outcome with " + equipment, 1)
		var w: Dictionary = g.world.workers[0]
		w.pos = Vector2(36, 13)
		w.gun_uses = 1 if equipment == "gun" else 0
		w.water = 1 if equipment == "water" else 0
		g.designate(ORE, ORE)
		var elapsed: float = t.advance_until(func(): return g.world.mined == 1, 20, "Equipped worker actually excavates ore")
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
		t.advance_until(func(): return g.world.delivered == 1, 10, "Ore is delivered after using equipment")

	t.fixtures.scenario("Backpack delivers two blocks; exhaustion restores single trips", 1)
	var w: Dictionary = g.world.workers[0]
	w.pos = Vector2(36, 13)
	w.backpack_uses = 1
	w.gun_uses = 4
	g.world.terrain[ORE] = 1
	g.world.terrain[ORE + Vector2i.RIGHT] = 2
	g.designate(ORE, ORE + Vector2i.RIGHT)
	t.advance_until(func(): return g.world.delivered >= 1, 25, "Backpack starts unloading its first load")
	# One receiver accepts the whole load; a per-item re-selection used to strand the second ore here.
	g.simulate(0.7)
	t.check(g.world.delivered == 2, "The same-receiver load continues unloading without another activity between items")
	t.check(g.world.delivered == 2 and g.player_blocks == 2 and w.backpack_uses == 0, "First trip delivers two blocks and spends one backpack use")
	t.near(g.resource_activity("workbench", 1).consumed, 1, "An exhausted backpack is consumed once, not once per ore delivered")
	t.check(g.materials.get(1, 0) == 1 and g.materials.get(2, 0) == 1, "Backpack preserves both mineral types after delivery")
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
	t.check(g.world.workers[0].water <= 4 and g.world.workers[1].water <= 4, "Neither worker carries more than four water")
	t.near(g.world.workers[0].water + g.world.workers[1].water + g.resource_activity("clean_water", 1).consumed, water_sold, "Actual competing water purchases reconcile held and consumed portions")
	t.near(g.world.workers[0].shop_spent_today + g.world.workers[1].shop_spent_today, water_sold, "Water revenue equals actual portions sold")

	for available in [false, true]:
		t.fixtures.scenario("Unavailable water never blocks work: " + str(available), 1)
		t.fixtures.station("purifier", P, 4 if available else 0)
		g.designate(ORE, ORE)
		t.advance_until(func(): return g.world.delivered == 1, 30, "Worker mines without money or available water")

	check_local_prices(t)
	check_consumption_conditions(t)
	check_item_effects(t)
	check_cleaning(t)
	check_bathing(t)
	check_services(t)
	check_delivery_recovery(t)
	check_pollution(t)

func check_cleaning(t) -> void:
	var g = t.game
	# The garment absorbs pollution before the body, without gaining lifetime from a wash.
	t.fixtures.scenario("Clothes absorb fifty pollution before it reaches the body", 1)
	var w: Dictionary = g.world.workers[0]
	w.equipment.clothes = g.ITEM_USES.clothes.uses
	g.simulate(24 * g.HOUR_SECONDS)
	t.near(w.clothes_pollution, 25, "A day of base exposure fills half the external slot")
	t.near(w.pollution, 0, "Available clothing capacity protects the body")
	g.select_worker(w.id)
	t.check(t.effect_description("clothes").contains("污染 25.0 / 50") and t.effect_description("clothes").contains("心情 +7.5"), "The clothing effect uses the actual pollution slot")
	g.simulate(24 * g.HOUR_SECONDS)
	t.near(w.clothes_pollution, 50, "Clothing pollution is bounded by capacity")
	g.select_worker(w.id)
	t.check(t.effect_description("clothes").contains("心情 +0.0"), "Completely dirty clothing no longer grants the clean-clothing bonus")
	t.near(g.resource_inventory().clothes, 1, "Dirt alone does not destroy the garment")
	g.simulate(g.HOUR_SECONDS)
	t.check(w.pollution > 1 and w.clothes_pollution == 50, "A full external slot passes further pollution to the body")

	# Facilities cannot charge for absent, clean or expired clothing, or sell cleaner directly.
	for setting in ["clean", "unclothed", "expires"]:
		t.fixtures.scenario("Laundry retains supplies when washing is not useful: " + setting, 1)
		t.fixtures.station("laundry", P)
		t.fixtures.station("soapworks", Vector2i(31, 11), 4)
		t.fixtures.stock_recipe(P, g.SERVICES.laundry.materials)
		w = g.world.workers[0]
		t.fixtures.service_customer("laundry", P, w)
		if setting == "unclothed": w.equipment.clear()
		if setting == "expires": w.equipment.clothes = 1.0
		if setting == "clean": w.clothes_pollution = 0.0
		g.simulate(g.WASH_HOURS * g.HOUR_SECONDS + 1)
		t.near(g.resource_activity("cleaner", 1).consumed, 0, "No cleaner is wasted on absent, clean or expired clothes")
		t.near(w.shop_spent_today, 0, "An unusable laundry service or cleaning product cannot charge")
		t.near(g.resource_inventory().cleaner, 5, "Cleaner remains in facility stock, not personal use")

func check_services(t) -> void:
	var g = t.game
	# Shared service settlement prevents remote charging, double consumption and prepaid failures.
	for kind in ["laundry", "bathhouse", "hospital"]:
		var service: Dictionary = g.SERVICES[kind]
		for setting in ["local", "delivered", "remote", "missing", "unaffordable", "debt", "cargo"]:
			t.fixtures.scenario("Service settlement: %s / %s" % [kind, setting], 1)
			t.fixtures.station(kind, P)
			var w: Dictionary = g.world.workers[0]
			t.fixtures.service_customer(kind, P, w, setting == "debt")
			if setting == "cargo": w.carry = 1
			var stock: Dictionary = service.materials.duplicate()
			if setting == "missing": stock.erase(stock.keys()[0])
			if setting == "remote": t.fixtures.isolated_warehouse(stock)
			else: t.fixtures.stock_recipe(g.BASE if setting == "delivered" else P, stock)
			if setting == "unaffordable": w.bread = 0.0
			var cash: float = g.resource_inventory().bread
			var lifetime: float = w.equipment.get("clothes", 0.0)
			var elapsed: float = service.hours * g.HOUR_SECONDS * 0.4
			g.simulate(elapsed)
			t.near(w.shop_spent_today, 0, "An incomplete service charges nothing")
			for item in service.materials:
				t.near(g.resource_activity(item, 1).consumed, 0, "An incomplete service consumes no ingredients")
			var succeeds: bool = setting in ["local", "delivered", "debt", "cargo"]
			if succeeds:
				elapsed += t.advance_until(func(): return w.shop_spent_today > 0, 60, "A completed service settles with delivered local supplies")
				t.near(w.shop_spent_today, service.price, "Exactly one service fee is paid")
				for item in service.materials:
					t.near(g.resource_activity(item, 1).consumed, service.materials[item], "Local ingredients are consumed once")
				if kind == "laundry":
					t.check(w.clothes_pollution < 1, "Actual washing empties the external pollution slot")
					t.near(w.equipment.clothes, lifetime - elapsed, "Washing never renews clothing lifetime", 0.05)
				else:
					t.check(w.pollution < 50, "The completed bath or treatment actually reduces body pollution")
				if kind != "hospital":
					t.near(g.resource_inventory().wastewater, 1, "One consumed clean-water portion becomes one wastewater portion")
					t.near(g.world.wastewater.get(P, 0.0), 25, "Fifty removed pollution becomes twenty-five wastewater pollution after cleaner")
				else:
					t.near(g.resource_inventory().wastewater, 0, "Medical treatment does not invent a water recipe")
				t.near(w.loan_principal, 1 if setting == "debt" else 0, "A service neither blocks on nor changes existing debt")
				t.near(g.resource_inventory().bread, cash, "A service transfers, never creates or consumes payment bread")
				if setting == "cargo":
					t.near(g.resource_inventory()[1], 1, "Service and delivery choices neither discard nor duplicate carried ore")
			else:
				g.simulate(service.hours * g.HOUR_SECONDS + 1)
				t.near(w.shop_spent_today, 0, "Unavailable or interrupted service never charges")
				for item in service.materials:
					t.near(g.resource_activity(item, 1).consumed, 0, "Rejected or interrupted service retains every ingredient")
				t.near(g.resource_inventory().wastewater, 0, "An incomplete service produces no wastewater")

func check_delivery_recovery(t) -> void:
	var g = t.game
	# Illness arising during a real supply trip must not lose or duplicate its building materials.
	t.fixtures.scenario("Illness and a long supply trip preserve treatment and material settlement", 1)
	var target := Vector2i(100, 13)
	t.fixtures.clear_area(Rect2i(Vector2i(28, 11), Vector2i(74, 4)))
	t.fixtures.station("hospital", P)
	t.fixtures.stock_recipe(P, g.SERVICES.hospital.materials)
	t.fixtures.building_materials("bed")
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

func check_pollution(t) -> void:
	var g = t.game
	# Pollution penalties change real labor duration, never the agreed batch payment.
	for initial in [0.0, 40.0, 80.0]:
		t.fixtures.scenario("Pollution changes paid labor duration: " + str(initial), 1)
		t.fixtures.station("workbench", P)
		var person: Dictionary = g.world.workers[0]
		person.pollution = initial
		g.adjust_production(P, 1)
		t.advance_until(func(): return g.resource_activity("workbench", 1).produced == 1, 60, "A real ordered batch completes under the initial pollution condition")
		var factor := 0.75 if initial >= 70 else (0.9 if initial > 30 else 1.0)
		t.near(g.report_totals(1)["工作"] / g.HOUR_SECONDS, 2.0 / factor, "Recorded labor reflects the pollution tier", 0.02)
		t.near(person.earned_today, 2, "Pollution cannot increase or discount the fixed batch wage")
	# A lightly dirty bath must transfer the actual dirt, not its maximum recovery capacity.
	t.fixtures.scenario("A partial wash transfers only actual pollution", 1)
	t.fixtures.station("bathhouse", P)
	t.fixtures.stock_recipe(P, g.BATH_MATERIALS)
	var lightly_dirty: Dictionary = g.world.workers[0]
	t.fixtures.service_customer("bathhouse", P, lightly_dirty)
	lightly_dirty.pollution = 10.0
	var elapsed: float = t.advance_until(func(): return lightly_dirty.shop_spent_today > 0, 20, "The lightly dirty customer finishes an actual bath")
	var transferred: float = g.world.wastewater.get(P, 0.0)
	t.near(lightly_dirty.pollution + transferred * 2, 10.0 + elapsed * g.Pollution.BASE_PER_HOUR / g.HOUR_SECONDS, "Removed pollution is conserved between remaining dirt, wastewater and the cleaner's equal share", 0.03)
	t.check(transferred < 6, "A partial wash cannot invent a full fifty-pollution transfer")
	# Compare actual exposure from a real pollutant, not an assigned activity or private AI state.
	var baseline := 0.0
	for polluted in [false, true]:
		t.fixtures.scenario("Wastewater exposure and disease transmission: " + str(polluted), 2)
		t.fixtures.clear_area(Rect2i(23, 7, 20, 14))
		if polluted: t.fixtures.wastewater(g.BASE, 2, 40)
		g.simulate(g.HOUR_SECONDS)
		var total: float = g.world.workers[0].pollution + g.world.workers[1].pollution
		if polluted:
			t.check(total > baseline, "Stored wastewater exposes nearby workers through the shared field")
			t.near(g.world.wastewater.get(g.BASE, 0.0), 40, "Ambient exposure does not accidentally consume or duplicate wastewater load")
		else: baseline = total

	var healthy_total := 0.0
	for sick in [false, true]:
		t.fixtures.scenario("Nearby illness adds exposure: " + str(sick), 2)
		g.world.workers[0].pollution = 80.0 if sick else 0.0
		g.simulate(g.HOUR_SECONDS)
		if sick: t.check(g.world.workers[1].pollution > healthy_total, "A diseased worker transmits through the environment")
		else: healthy_total = g.world.workers[1].pollution

	# Clean surroundings do not heal a patient, and a bath cannot replace medical treatment.
	t.fixtures.scenario("Disease requires medicine, with death still a placeholder", 1)
	t.fixtures.station("bathhouse", P)
	t.fixtures.stock_recipe(P, g.BATH_MATERIALS)
	var w: Dictionary = g.world.workers[0]
	t.fixtures.service_customer("hospital", P, w)
	g.simulate(g.HOUR_SECONDS * 2)
	t.check(w.pollution >= 80 and w.shop_spent_today == 0, "Fresh surroundings and a stocked bath cannot heal disease")
	t.near(g.resource_activity("cleaner", 1).consumed, 0, "A bath cannot consume supplies pretending to treat disease")
	g.simulate(24 * g.HOUR_SECONDS)
	t.near(w.pollution, 100, "Body pollution caps at one hundred")
	t.check(g.world.workers.size() == 1, "The death placeholder does not remove the worker")

func check_bathing(t) -> void:
	var g = t.game
	# Two customers cannot share one recipe, pay before completion, or receive permanent mood.
	t.fixtures.scenario("One bath recipe serves one competing customer", 2)
	t.fixtures.station("bathhouse", P)
	t.fixtures.stock_recipe(P, g.BATH_MATERIALS)
	for w in g.world.workers:
		w.hunger = 100
		w.bread = g.BATH_PRICE
	var cash: float = g.resource_inventory().bread
	g.simulate(g.BATH_HOURS * g.HOUR_SECONDS * 0.5)
	t.near(g.stock_at(P, "bread"), 0, "An incomplete bath has not charged either customer")
	for item in g.BATH_MATERIALS:
		t.near(g.resource_activity(item, 1).consumed, 0, "An incomplete bath does not consume supplies")
	t.advance_until(func(): return g.stock_at(P, "bread") == g.BATH_PRICE, 30, "A completed bath pays the facility once")
	var bathed := 0
	for w in g.world.workers:
		g.select_worker(w.id)
		if t.effect_description("bathed").contains("心情 +15\n剩余"):
			bathed += 1
		t.near(w.fatigue, 0, "Bathing supplies a mood effect, not labor fatigue")
	t.check(bathed == 1, "Only the customer who completed the bath receives its timed mood effect")
	for item in g.BATH_MATERIALS:
		t.near(g.resource_activity(item, 1).consumed, g.BATH_MATERIALS[item], "Each local bath ingredient is consumed exactly once")
	t.near(g.resource_inventory().bread, cash, "The service transfers bread rather than creating or consuming it")
	g.simulate(g.WorkerBuffs.BATH_EFFECT_HOURS * g.HOUR_SECONDS + 0.1)
	for w in g.world.workers:
		g.select_worker(w.id)
		t.check(t.effect_description("bathed").is_empty(), "The bath effect expires without becoming permanent mood")
	t.near(g.stock_at(P, "bread"), g.BATH_PRICE, "A missing recipe cannot charge a second customer")

	# Plenty of money and supplies cannot stack or refresh an already active bath effect.
	t.fixtures.scenario("Bath mood lasts without repeat charges or washing clothes", 1)
	t.fixtures.station("bathhouse", P)
	var supplies: Dictionary = g.BATH_MATERIALS.duplicate()
	for item in supplies: supplies[item] *= 2
	t.fixtures.stock_recipe(P, supplies)
	var customer: Dictionary = g.world.workers[0]
	customer.hunger = 100
	customer.bread = g.BATH_PRICE * 2
	customer.equipment.clothes = g.ITEM_USES.clothes.uses
	customer.clothes_pollution = 40.0
	t.advance_until(func(): return customer.shop_spent_today > 0, 30, "The first bath is completed and paid for")
	g.simulate(g.HOUR_SECONDS)
	g.select_worker(customer.id)
	t.near(customer.shop_spent_today, g.BATH_PRICE, "Active bath mood prevents a second fee despite available money and supplies")
	t.check(t.effect_description("bathed").contains("剩余 7.0h"), "The bath benefit counts down instead of refreshing itself")
	t.check(customer.clothes_pollution > 40, "Bath mood does not silently wash or replace the worn garment")
	t.near(customer.mood.value, 0, "Bath mood is not written as a permanent positive experience")
	t.near(g.resource_activity("cleaner", 1).consumed, 1, "An active bath effect does not consume a second portion")

	# Remote goods are not a completed service; neither missing ingredients nor insufficient cash can fund it.
	for setting in ["remote", "missing", "unaffordable"]:
		t.fixtures.scenario("Bathing requires local supplies and personal payment: " + setting, 1)
		t.fixtures.station("bathhouse", P)
		if setting == "remote": t.fixtures.isolated_warehouse(g.BATH_MATERIALS)
		else:
			var recipe: Dictionary = g.BATH_MATERIALS.duplicate()
			if setting == "missing": recipe.erase("cleaner")
			t.fixtures.stock_recipe(P, recipe)
		var w: Dictionary = g.world.workers[0]
		w.hunger = 100
		w.bread = 0.0 if setting == "unaffordable" else g.BATH_PRICE
		g.simulate(15)
		t.near(w.shop_spent_today, 0, "An unavailable or unaffordable bath never charges")
		for item in g.BATH_MATERIALS:
			t.near(g.resource_activity(item, 1).consumed, 0, "A rejected bath consumes no local or remote ingredients")

	# The usual supply flow must deliver every service ingredient, without special remote charging.
	t.fixtures.scenario("Bathhouse restocks through normal worker delivery", 2)
	t.fixtures.station("bathhouse", P)
	t.fixtures.stock_recipe(g.BASE, g.BATH_MATERIALS)
	for w in g.world.workers:
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
	var buyer: Dictionary = g.world.workers[0]
	buyer.bread = 2
	buyer.hunger = 100
	buyer.fatigue = 40
	t.observe_until(func(): return buyer.shop_spent_today > 0, 15)
	var bought: bool = buyer.shop_spent_today > 0
	t.near(g.resource_activity("ale", 1).consumed, 0, "Payment does not consume the drink or grant its effect")
	t.near(g.resource_inventory().ale, 1, "The purchased serving remains in physical inventory")
	t.near(buyer.shop_spent_today, 2 if bought else 0, "An actual sale pays once; choosing free sleep cannot incur a drink charge")
	# Owned consumption is a separate contract, independent of choosing to purchase rather than sleep.
	t.fixtures.scenario("Owned ale is consumed once and grants its actual effects", 1)
	buyer = g.world.workers[0]
	buyer.hunger = 100
	buyer.fatigue = 40
	buyer.items.ale = 1
	t.advance_until(func(): return g.resource_activity("ale", 1).consumed == 1, 10, "Actual drinking consumes the owned serving")
	t.near(buyer.fatigue, 20, "Actual drinking applies recovery once", 0.1)
	g.simulate(1)
	t.near(g.resource_activity("ale", 1).consumed, 1, "A sold-out shop and empty personal stock cannot duplicate a drink")
	var plain_hours := 0.0
	# Compare paid output, not a prescribed routine or private efficiency cache.
	for item in ["none", "tools", "clothes", "dirty_clothes", "ale"]:
		t.fixtures.scenario("Owned item use changes real production: " + item, 1)
		t.fixtures.station("workbench", P)
		var w: Dictionary = g.world.workers[0]
		w.pos = Vector2(P)
		w.fatigue = 40
		if item == "dirty_clothes":
			w.equipment.clothes = g.ITEM_USES.clothes.uses
			w.clothes_pollution = 50.0
		elif item == "ale": w.buffs.apply("tipsy", g.WorkerBuffs.ALE_HOURS * g.HOUR_SECONDS)
		elif item != "none": w.items[item] = 1
		g.adjust_production(P, 1)
		if item == "ale":
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
		var w: Dictionary = g.world.workers[0]
		w.equipment.tools = 1
		if kind == "farm": t.fixtures.stock_recipe(P, {"raw_water": 4})
		if kind == "printer": t.fixtures.stock_recipe(P, {1: 10})
		g.adjust_production(P, 1)
		t.advance_until(func(): return g.world.workers.size() == 2 if kind == "printer" else g.resource_activity(g.product_item(kind), 1).produced > 0, 150, "Ordered production completes with initially equipped tools")
		t.near(g.resource_activity("tools", 1).consumed, 0 if kind == "printer" else 1, "Only farm and processing labor wear out tools; printing does not")
		if kind == "farm":
			t.near(g.report_totals(1)["工作"] / g.HOUR_SECONDS, 1.0 / 1.3 + 1.0, "One remaining use accelerates watering but not later growth or unequipped harvesting", 0.02)

	t.fixtures.scenario("Clothing expiration removes its condition and consumes one item", 1)
	var w: Dictionary = g.world.workers[0]
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
	w = g.world.workers[0]
	w.bread = 1
	w.hunger = 60
	t.advance_until(func(): return g.resource_activity("meat", 1).consumed == 1, 40, "A hungry buyer purchases and eats meat from the barn")
	t.near(w.shop_spent_today, 1, "Meat charges its own listed price once")
	t.near(g.resource_inventory().meat, 0, "Eaten meat is not also held or left for sale")
	t.check(w.hunger > 60, "Eating meat restores hunger")

func check_consumption_conditions(t) -> void:
	var g = t.game
	# Debt and carried ore cannot replace actual cash and stock checks or destroy cargo.
	for kind in ["purifier", "brewery"]:
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
	# All saleable goods share local pricing, arrival-time checks and physical payment.
	for kind in ["bench", "workbench", "purifier"]:
		for setting in ["one", "two", "disconnect", "outside"]:
			t.fixtures.scenario("Local sale price: " + kind + " / " + setting, 0)
			t.fixtures.power_facilities(1, 0)
			t.fixtures.station("spotlight", Vector2i(32, 9))
			if setting == "two": t.fixtures.station("spotlight", Vector2i(35, 9))
			t.advance_until(func():
				g.select_entity(Vector2i(32, 9))
				return g.hud.entity_details.text.contains("运行中"), 15, "A staffed circuit supplies the sale light")
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
			t.observe_until(func(): return buyer.shop_spent_today > 0, 50)
			var unit_price: float = g.PRODUCTS[kind].price * (1.0 if setting in ["disconnect", "outside"] else 1.2)
			var quantity: int = (4 if kind == "purifier" else 1) - g.world.benches[destination].stock
			t.check(quantity >= 0 and quantity <= (4 if kind == "purifier" else 1), "Autonomous purchases cannot exceed the actual listed stock")
			t.near(g.stock_at(destination, "bread"), unit_price * quantity, "Stock transfer and payment use the same current price")
			t.near(buyer.shop_spent_today, unit_price * quantity, "Actual spending reports include the local premium exactly once")
			t.check(buyer.bread >= 0, "A price premium cannot overdraw personal funds")
