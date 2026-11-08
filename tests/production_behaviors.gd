extends RefCounted

const P := Vector2i(28, 11)
const OTHER := Vector2i(31, 11)

func check_research(t) -> void:
	var g = t.game
	# Remote stock cannot unlock buildings or pay wages without delivery and research.
	t.fixtures.research_world("Research uses actual delivered materials, not global stock", ["tools"], 0)
	t.fixtures.research_materials(g.BASE, "tools")
	t.fixtures.building_materials("bench")
	t.check(not g.can_plan_building("bench") and not g.place_building(Vector2i(34, 14), "bench"), "A locked building cannot be planned even with every material available")
	t.check(not g.assign_research(P, "finance"), "Research cannot skip its prerequisite")
	t.check(g.assign_research(P, "population"), "Population research can start without completing tools")
	t.check(g.assign_research(P, "tools"), "An available project can be assigned to a completed research bench")
	var before: Dictionary = g.resource_inventory()
	g.simulate(10)
	t.near(g.research_value("tools"), 0, "No workers means no remote material consumption or research progress")
	t.check(g.resource_inventory() == before, "Assigning research does not consume or teleport warehouse goods")
	# Leave one complete research batch, independent of the building's copper above.
	t.fixtures.stock_recipe(g.BASE, {4: 1})
	t.fixtures.hungry_worker(g.BASE)
	t.advance_until(func(): return g.research_value("tools") >= 1, 120, "Workers deliver the actual ingredients and complete one research point")
	t.near(g.research_value("tools"), 1, "One batch yields one project point, not an inventory item")
	t.near(g.resource_activity(2, 1).consumed, 1, "The point consumes copper once at the bench")
	t.near(g.resource_activity(4, 1).consumed, 1, "The point consumes its granite, not an unlocked building's recipe")
	t.near(g.world.workers[0].earned_today, 2, "Research pays its configured labor from actual employer bread")
	t.check(not g.is_building_unlocked("bench"), "A partial project does not unlock its buildings")

	# Separate projects progress concurrently rather than replacing a global selection.
	t.fixtures.research_world("Independent projects share no global research queue", ["tools", "logistics"], 2)
	t.fixtures.research_materials(P, "tools")
	t.fixtures.research_materials(OTHER, "logistics")
	g.assign_research(P, "tools")
	g.assign_research(OTHER, "logistics")
	t.advance_until(func(): return g.research_value("tools") >= 1 and g.research_value("logistics") >= 1, 120, "Both selected projects earn their own point through autonomous labor")
	t.near(g.research_value("tools"), 1, "Research points cannot spill into another project")
	t.near(g.research_value("logistics"), 1, "The second project's different labor cost is honored")
	t.near(g.world.workers[0].earned_today + g.world.workers[1].earned_today, 3, "Parallel research pays only the two actual batches")

	# Switching must not refund consumed goods, lose paid labor, or replay it on load.
	t.fixtures.research_world("Switch and save preserve a suspended research batch", ["tools"], 1)
	t.fixtures.research_materials(P, "tools")
	t.fixtures.research_materials(P, "logistics")
	g.set_wage(P, 3)
	g.assign_research(P, "tools")
	t.advance_until(func(): return g.report_totals(1)["工作"] > 0, 30, "Actual research labor begins before the player changes project")
	var partial: float = g.research_value("tools")
	t.check(partial > 0 and partial < 1, "The selected project exposes partial research progress")
	g.set_wage(P, 7)
	t.check(g.assign_research(P, "logistics"), "A bench can switch projects without discarding the old batch")
	t.near(g.world.workers[0].earned_today, partial * 2 * 3, "Changing project settles only labor at its original wage")
	var observations: Dictionary = t.world_observations()
	var saved: Dictionary = g.capture_snapshot()
	g.simulate(0.5)
	var loaded: Dictionary = g.restore_snapshot(saved.data) if saved.ok else saved
	t.check(loaded.ok and t.world_observations() == observations, "Loading preserves suspended progress, goods and wages without replay")
	t.advance_until(func(): return g.research_value("logistics") >= 1, 90, "The replacement project can complete its own batch")
	t.near(g.research_value("tools"), partial, "The paused project gains no labor from another project")
	g.assign_research(P, "tools")
	t.advance_until(func(): return g.research_value("tools") >= 1, 90, "The original research resumes using its already consumed materials")
	t.near(g.resource_activity(2, 1).consumed, 1, "Resuming does not charge copper twice")
	t.near(g.resource_activity(4, 1).consumed, 2, "Only the original and replacement material batches are consumed")
	t.near(g.world.workers[0].earned_today, 2 * 3 + 7, "The paused point retains its quote while the new point uses the changed wage")

	# Cooperation and the final-point race share the same material/point contract.
	for sample in [{"project": "tools", "remaining": 2}, {"project": "tools", "remaining": 1}]:
		var project: String = sample.project
		var definition: Dictionary = g.Technology.PROJECTS[project]
		t.fixtures.research_world("Cooperating benches finish without excess research: %s / %d points" % [project, sample.remaining],
			[project, project], 2, {project: definition.points - sample.remaining})
		for p in [P, OTHER]:
			t.fixtures.research_materials(p, project, 2)
			g.assign_research(p, project)
		t.advance_until(func(): return g.is_building_unlocked(definition.unlocks[0]), 120, "Completing the last point unlocks the project's buildings")
		g.simulate(15)
		t.near(g.research_value(project), definition.points, "Cooperating benches stop exactly at the project's required points")
		for item in definition.materials:
			t.near(g.resource_activity(item, 1).consumed, definition.materials[item] * sample.remaining, "Cooperating benches consume only the project's remaining local recipes")
		t.near(g.world.workers[0].earned_today + g.world.workers[1].earned_today, definition.hours * sample.remaining, "Completed research does not keep creating work or wages")
		t.fixtures.building_materials(definition.unlocks[0])
		t.check(g.place_building(Vector2i(34, 14), definition.unlocks[0]), "The newly unlocked building accepts a normal player construction command")

func run(t) -> void:
	check_research(t)
	var g = t.game
	var kind := "bench"
	t.fixtures.scenario("Recurring output: " + kind, 1)
	t.fixtures.station(kind, P)
	t.fixtures.materials(2, 2)
	g.world.terrain[Vector2i(27, 13)] = 2
	g.adjust_production(P, 1)
	var batch_amount: int = g.PRODUCTS[kind].get("amount", 1)
	t.advance_until(func(): return g.world.benches[P].produced_today == batch_amount, g.HOUR_SECONDS * 16, "One daily batch is produced despite personal breaks")
	g.simulate(30)
	t.check(g.world.benches[P].stock == batch_amount, "Daily target does not repeat within the day")
	g.simulate(g.DAY_SECONDS)
	t.check(g.world.benches[P].stock == batch_amount * 2, "Tomorrow produces again without another order")
	g.adjust_production(P, -1)
	g.simulate(g.DAY_SECONDS)
	t.check(g.world.benches[P].stock == batch_amount * 2, "Zero output stops production across days")
	t.check(g.materials.get(2, 0) == 0, "Each produced gun consumes one copper ore")
	g.adjust_production(P, 1)
	var earned: float = g.report_totals(g.world.day, 0)["工作"]
	g.simulate(g.DAY_SECONDS)
	g.select_entity(P)
	t.check(g.world.benches[P].stock == 2, "An unfunded daily gun order waits for copper")
	t.near(g.report_totals(g.world.day - 1, 0)["工作"], earned, "No copper means no idle production labor")
	g.designate(Vector2i(27, 13), Vector2i(27, 13))
	g.simulate(g.HOUR_SECONDS * 6)
	t.check(g.world.benches[P].stock == 3 and g.materials.get(2, 0) == 0, "Mining copper resumes the existing daily order")

	t.fixtures.scenario("Water chain and no backlog", 1)
	t.fixtures.station("pump", P)
	t.fixtures.station("purifier", OTHER)
	g.adjust_production(OTHER, 1)
	g.simulate(g.DAY_SECONDS * 2)
	g.select_entity(OTHER)
	t.check(g.world.benches[OTHER].stock == 0, "Missing raw water waits instead of creating output")
	t.near(g.world.workers[0].bread, 0, "Waiting for materials pays no wages")
	g.adjust_production(P, 3)
	t.advance_until(func(): return g.world.benches[OTHER].stock == 4 and g.world.benches[P].stock == 8, 120, "Current daily orders finish across actual collection and meals")
	t.check(g.world.benches[P].produced_today == 12 and g.world.benches[OTHER].produced_today == 4, "Missed days do not accumulate catch-up batches")

	t.fixtures.scenario("Paid batch survives zero target and midnight", 0)
	t.fixtures.station("workbench", OTHER)
	g.simulate(g.DAY_SECONDS - 4)
	t.fixtures.hungry_worker(OTHER)
	g.adjust_production(OTHER, 1)
	t.advance_until(func(): return g.report_totals(1, 0)["工作"] > 0, 3, "A real production batch begins before midnight")
	g.adjust_production(OTHER, -1)
	t.advance_until(func(): return g.world.benches[OTHER].produced_today == 1, 150, "The committed batch finishes despite zero target")
	t.check(g.world.day == 2, "The unfinished batch crosses midnight")
	t.near((g.report_totals(1, 0)["工作"] + g.report_totals(2, 0)["工作"]) / g.HOUR_SECONDS, 2, "The batch pays exactly its actual labor")
	g.simulate(20)
	t.check(g.world.benches[OTHER].produced_today == 1, "A finished zero-target batch does not restart")

	t.fixtures.scenario("Overnight output counts on its completion day", 1)
	t.fixtures.station("bench", P)
	t.fixtures.materials(2, 2)
	g.simulate(g.DAY_SECONDS - 5)
	g.adjust_production(P, 1)
	g.simulate(g.HOUR_SECONDS * 6)
	t.check(g.world.day == 2 and g.world.benches[P].stock == 1, "Midnight does not duplicate an unfinished daily batch")
	g.adjust_production(P, 1)
	g.simulate(g.HOUR_SECONDS * 4)
	t.check(g.world.benches[P].stock == 2, "Increasing target makes only the missing output")

	# Competing destinations must not reserve, carry, or consume the same batch twice.
	for entry in t.fixtures.INPUT_ROUTES:
		t.fixtures.scenario("Competing local recipes: " + entry.target)
		var source: Vector2i = g.BASE if entry.source == "" else P
		if entry.source != "":
			t.fixtures.station(entry.source, source)
		g.add_stock(source, entry.item, entry.amount)
		var first := Vector2i(33, 11) if entry.target == "farm" else OTHER
		t.fixtures.station(entry.target, first)
		var second := Vector2i(38, 11) if entry.target == "farm" else Vector2i(34, 11)
		t.fixtures.station(entry.target, second)
		g.adjust_production(first, 1)
		g.adjust_production(second, 1)
		g.simulate(g.HOUR_SECONDS * 12)
		var amount: int = g.PRODUCTS[entry.target].amount
		t.check(g.world.benches[first].produced_today + g.world.benches[second].produced_today == amount, "One shared input batch produces only one batch across competing buildings")
		t.near(g.stock_at(source, entry.item), 0, "Delivered ingredients leave their source exactly once")

	t.fixtures.scenario("Printing is finite, material-limited, and adds a working person")
	t.fixtures.station("printer", P)
	t.fixtures.station("printer", OTHER)
	g.adjust_production(P, 1)
	g.adjust_production(OTHER, 1)
	g.simulate(8)
	t.check(g.world.workers.size() == 3 and g.world.workers[0].bread == 0, "No ore means no new person or idle wages")
	t.fixtures.materials(10)
	t.advance_until(func(): return g.world.workers.size() == 4, g.HOUR_SECONDS * 6, "Available ore prints one worker")
	var born_at: float = g.world.day_elapsed
	g.simulate(10)
	t.check(g.world.workers.size() == 4 and g.player_blocks == 0, "Competing printer cannot reuse spent ore")
	t.near(t.report_seconds(3), g.world.day_elapsed - born_at, "New worker has no report time before birth", 0.11)
	# A second player order is already waiting; earned mining material supplies it.
	g.designate(Vector2i(37, 11), Vector2i(37, 15))
	g.simulate(30)
	t.check(g.world.delivered > 0, "Mining orders remain usable after population changes")
	g.adjust_production(OTHER, -1)
	g.adjust_production(P, -1)
	g.simulate(g.DAY_SECONDS)
	t.check(g.world.workers.size() == 4, "Printing does not automatically recur tomorrow")

	t.fixtures.scenario("Finite printing with enough materials for another worker", 1)
	t.fixtures.station("printer", P)
	t.fixtures.materials(20)
	g.adjust_production(P, 1)
	g.simulate(g.DAY_SECONDS + 40)
	t.check(g.world.workers.size() == 2 and g.player_blocks == 10, "One order creates only one person even with tomorrow's materials available")

	# Reservations and carried goods are not local inputs; stopped orders retain delivered material.
	for entry in t.fixtures.INPUT_ROUTES:
		t.fixtures.scenario("Actual material arrival: " + entry.target, 0)
		var receiver := Vector2i(33, 11) if entry.target == "farm" else OTHER
		var source: Vector2i = g.BASE if entry.source == "" else P
		if entry.source != "":
			t.fixtures.station(entry.source, source)
		t.fixtures.station(entry.target, receiver)
		g.set_wage(receiver, 3)
		g.add_stock(source, entry.item, 1024 + entry.amount)
		g.adjust_production(receiver, 1)
		g.simulate(30)
		t.check(g.stock_at(receiver, entry.item) == 0 and g.world.benches[receiver].produced_today == 0, "Without workers, a stocked remote warehouse cannot supply a recipe")
		t.fixtures.hungry_worker(Vector2i(36, 15))
		g.simulate(0.5)
		g.select_entity(source)
		t.check(t.inventory_description(entry.item).contains("数量 " + str(1024 + entry.amount)), "Reserved goods remain visible in their source warehouse until pickup")
		var carried := "搬运 " + str(entry.amount)
		t.advance_until(func():
			g.select_worker(0)
			return t.inventory_description(entry.item).contains(carried), 10, "Worker visibly carries the actual ingredient after visiting its source")
		t.check(g.stock_at(receiver, entry.item) == 0 and g.world.benches[receiver].produced_today == 0, "Ingredients in transit cannot be consumed at the destination")
		g.update_ui()
		t.near(g.resource_inventory()[entry.item], 1024 + entry.amount, "Inventory includes transported material exactly once")
		t.near(g.resource_activity(entry.item, g.world.day).consumed, 0, "Reservation and transport are not consumption")
		t.near(g.stock_at(source, entry.item), 1024, "Pickup preserves the source's remaining stock without a capacity limit")
		g.adjust_production(receiver, -1)
		t.advance_until(func(): return g.stock_at(receiver, entry.item) == entry.amount, 10, "Stopping production still lets the carried goods arrive in the local warehouse")
		t.near(g.world.workers[0].earned_today, 0, "No production wages are paid while inputs are traveling or the order is stopped")
		g.adjust_production(receiver, 1)
		var amount: int = g.PRODUCTS[entry.target].amount
		t.advance_until(func(): return g.world.benches[receiver].produced_today == amount, g.HOUR_SECONDS * 12, "Resuming consumes the delivered local batch and produces output")
		t.near(g.stock_at(receiver, entry.item), 0, "The local recipe consumes its ingredients once")
		t.near(g.stock_at(source, entry.item), 1024, "Resuming does not fetch or consume a second batch from elsewhere")
		t.near(g.world.workers[0].earned_today, g.PRODUCTS[entry.target].hours * 3, "Only actual production earns the adjusted wage; supply stays unpaid")
		t.near(g.resource_activity(entry.item, g.world.day).consumed, entry.amount, "Only the local recipe records material consumption")
		t.near(g.resource_activity(g.product_item(entry.target), g.world.day).produced, amount, "Completed output is recorded on the day it is produced")
		t.near(g.resource_activity("bread", g.world.day).consumed, g.world.workers[0].eaten_today, "Only actual personal eating consumes bread; wages do not")
		t.near(g.resource_inventory()[entry.item], 1024, "Consumed ingredients disappear from total physical inventory")
		var yesterday: Dictionary = g.resource_activity(entry.item, g.world.day)
		g.adjust_production(receiver, -1)
		g.simulate(g.DAY_SECONDS - g.world.day_elapsed)
		t.check(g.resource_activity(entry.item, g.world.day - 1) == yesterday, "Yesterday's material use survives the midnight rollover")
		t.near(g.resource_activity(entry.item, g.world.day).consumed, 0, "The new day starts with no phantom material use")

	check_track_deliveries(t)
	check_farming(t)
	check_power(t)
	check_drilling(t)
	check_electric_freight(t)
	check_livestock(t)

func check_livestock(t) -> void:
	var g = t.game
	# Sheep remain alive between wool harvests; slaughter cannot regenerate livestock.
	t.fixtures.scenario("Sheep wool, queued slaughter and permanent removal", 1)
	t.fixtures.station("barn", P)
	t.fixtures.stock_recipe(g.BASE, {"wheat": 6, "raw_water": 6})
	g.adjust_production(P, 2)
	t.advance_until(func(): return g.resource_activity("wheat", 1).consumed == 2, 30, "Feed is physically delivered before wool grows")
	g.request_slaughter(P)
	g.request_slaughter(P)
	t.advance_until(func(): return g.resource_activity("meat", 1).produced == g.SHEEP_MEAT, g.HOUR_SECONDS * 20, "Slaughter follows the already fed wool cycle")
	t.near(g.resource_activity("wool", 1).produced, 2, "Queued slaughter preserves the paid wool batch")
	t.near(g.resource_activity("wheat", 1).consumed, 2, "Slaughter does not consume another feed recipe")
	g.request_slaughter(P)
	g.adjust_production(P, 1)
	g.simulate(g.DAY_SECONDS)
	t.check(g.world.benches[P].sheep == 0, "The barn remains empty after slaughter, including after midnight")
	t.near(g.resource_inventory().meat + g.resource_activity("meat", 1).consumed + g.resource_activity("meat", 2).consumed, g.SHEEP_MEAT, "Repeated slaughter cannot duplicate meat")
	t.near(g.resource_inventory().wool, 2, "An empty barn cannot regrow wool")

func check_farming(t) -> void:
	var g = t.game
	# No worker may be held for growth, and ripe wheat still requires harvesting labor.
	t.fixtures.scenario("Unattended growth followed by paid harvest", 1)
	t.fixtures.station("farm", P)
	var workshop := Vector2i(33, 11)
	t.fixtures.station("workbench", workshop)
	g.add_stock(P, "raw_water", 8)
	g.adjust_production(P, 2)
	t.advance_until(func():
		g.select_entity(P)
		return g.hud.entity_details.text.contains("生长中"), 25, "One watering hour starts growth")
	g.update_ui()
	g.adjust_production(workshop, 1)
	t.advance_until(func(): return g.stock_at(workshop, "workbench") == 1, g.HOUR_SECONDS * 4, "The same worker makes a backpack while crops grow")
	t.check(g.stock_at(P, "wheat") == 0, "Growing crops do not produce premature wheat")
	g.adjust_production(P, -2)
	t.advance_until(func(): return g.stock_at(P, "wheat") == 8, g.HOUR_SECONDS * 9, "Stopping future batches still harvests the already-watered crop")
	t.near(g.resource_inventory().bread + g.resource_activity("bread", 1).consumed, g.STARTING_BREAD, "Watering, other labor and harvesting transfer existing payment bread")
	t.near(g.stock_at(P, "raw_water"), 4, "A stopped farm uses only one batch of water")
	g.adjust_production(P, 2)
	t.advance_until(func(): return g.stock_at(P, "wheat") == 16, g.HOUR_SECONDS * 12, "The same farmland can be watered and harvested again")

func check_power(t) -> void:
	var g = t.game
	# A cable corridor must not isolate real work on its opposite side.
	t.fixtures.scenario("Workers cross a high-voltage corridor to deliver ore", 1)
	t.fixtures.clear_area(Rect2i(28, 8, 1, 8))
	for x in range(28, 37):
		t.fixtures.cable(Vector2i(x, 10), "high_line")
	g.world.workers[0].pos = Vector2(28, 8)
	var ore := Vector2i(27, 8)
	g.world.terrain[ore] = 2
	g.cache.navigation.set_point_solid(ore, true)
	g.world.explored[ore] = true
	g.designate(ore, ore)
	t.advance_until(func(): return g.stock_at(g.BASE, 2) == 1, 60, "Mined copper is carried across the corridor into the portal")
	# Capacity applies per transformer, per shared wire and per plant, not per consumer.
	for entry in [[1, 1, 200.0], [1, 5, 800.0], [5, 4, 3200.0]]:
		t.fixtures.scenario("Metered coal and circuit limits: %s" % str(entry), 0)
		var plant: Vector2i = t.fixtures.power_facilities(entry[0], entry[1])
		t.advance_until(func():
			g.select_entity(plant)
			return g.hud.entity_details.text.contains("输出  %.0fW" % entry[2]), 15, "Operators bring the circuit up to its allowed output")
		var coal: float = g.resource_activity(3, 1).consumed
		var measured: Dictionary = t.measure_power([plant], g.HOUR_SECONDS * 0.5)
		t.near(g.resource_activity(3, 1).consumed - coal, measured.energy / 1600.0, "Coal follows actual output rather than assuming uninterrupted attendance", 0.003)
		t.check(measured.peak <= entry[2], "Actual output cannot exceed the circuit's limit")
		g.remove_power_line(plant + Vector2i(4, 0))
		coal = g.resource_activity(3, 1).consumed
		g.simulate(g.HOUR_SECONDS)
		t.near(g.resource_activity(3, 1).consumed, coal, "Disconnecting the high-voltage supply stops fuel consumption")

	t.fixtures.scenario("Independent generators keep independent output limits", 0)
	var first: Vector2i = t.fixtures.power_facilities(3, 4)
	var second: Vector2i = t.fixtures.power_facilities(3, 4, Vector2i(30, 0))
	t.advance_until(func():
		for p in [first, second]:
			g.select_entity(p)
			if not g.hud.entity_details.text.contains("输出  2400W"): return false
		return true, 15, "Separate circuits can jointly exceed one generator's 3200W rating")
	var fuel_used: float = g.resource_activity(3, 1).consumed
	var measured: Dictionary = t.measure_power([first, second], g.HOUR_SECONDS * 0.5)
	t.near(g.resource_activity(3, 1).consumed - fuel_used, measured.energy / 1600.0, "Each generator pays only for the load it actually supplies", 0.003)

	t.fixtures.scenario("Low-voltage trunk shared by two transformers", 0)
	var plant: Vector2i = t.fixtures.power_facilities(2, 0)
	# Both feeds meet before one 800W trunk, so their ratings cannot be added downstream.
	for y in range(8, 13):
		t.fixtures.cable(Vector2i(31, y))
	for x in range(32, 45):
		g.world.power_lines.erase(Vector2i(x, 12))
	t.fixtures.clear_area(Rect2i(32, 8, 19, 4))
	for x in range(32, 50):
		t.fixtures.cable(Vector2i(x, 8))
	for i in 5:
		t.fixtures.station("grow_light", Vector2i(35 + i * 3, 9))
	t.advance_until(func():
		g.select_entity(plant)
		return g.hud.entity_details.text.contains("输出  800W"), 15, "Shared trunk carries at most 800W even with two staffed feeders")
	var coal: float = g.resource_activity(3, 1).consumed
	measured = t.measure_power([plant], g.HOUR_SECONDS)
	t.near(g.resource_activity(3, 1).consumed - coal, measured.energy / 1600.0, "A shared trunk charges only actual output", 0.003)
	t.check(measured.peak <= 800, "An extra transformer cannot bypass the line bottleneck")

	# Attendance and fuel remain necessary; neither wire type requires voltage conversion.
	for missing in ["operator", "coal", "transformer", "low_line"]:
		t.fixtures.scenario("Disconnected or unavailable supply: " + missing, 0)
		plant = t.fixtures.power_facilities(1, 1)
		if missing == "operator": g.world.workers.clear()
		if missing == "coal": g.add_stock(plant, 3, -10)
		if missing == "transformer":
			g.world.benches.erase(Vector2i(29, 8))
			g.cache.invalidate_delivery()
			t.fixtures.cable(Vector2i(29, 8), "high_line")
			t.fixtures.cable(Vector2i(30, 8), "high_line")
		if missing == "low_line":
			for x in range(31, 45):
				g.world.power_lines[Vector2i(x, 8)].kind = "high_line"
		g.simulate(20)
		g.select_entity(Vector2i(32, 9))
		if missing in ["operator", "coal"]:
			t.check(g.hud.entity_details.text.contains("未供电"), "Lights still require staffed and fueled generation")
			t.near(g.resource_activity(3, 1).consumed, 0, "An unavailable circuit burns no coal")
		else:
			t.check(g.resource_activity(3, 1).consumed > 0, "Directly connected consumers use real fuel")

	# A shared narrow segment limits the circuit even when the rest uses thick cable.
	for generator in ["manual_generator", "power_plant"]:
		for wire in (["low_line"] if generator == "manual_generator" else ["low_line", "high_line", "mixed"]):
			t.fixtures.scenario("Direct generation and per-wire limits: " + generator + " / " + wire, 0)
			t.fixtures.clear_area(Rect2i(23, 5, 25, 7))
			plant = Vector2i(22, 8) if generator == "power_plant" else Vector2i(24, 8)
			t.fixtures.station(generator, plant)
			g.set_wage(plant, 2)
			g.add_stock(plant, "bread", 30)
			g.add_stock(plant, 3, 10)
			var operator: Dictionary = t.fixtures.hungry_worker(plant)
			for x in range(26, 46):
				t.fixtures.cable(Vector2i(x, 8), "low_line" if wire == "low_line" or (wire == "mixed" and x == 29) else "high_line")
			for i in 5:
				t.fixtures.station("grow_light", Vector2i(32 + i * 3, 7))
			var expected := 400 if generator == "manual_generator" else (1000 if wire == "high_line" else 800)
			t.advance_until(func():
				g.select_entity(plant)
				return g.hud.entity_details.text.contains("输出  %dW" % expected), 15, "Generator powers loads directly up to the smallest shared capacity")
			var fuel: float = g.resource_activity(3, 1).consumed
			var wages: float = operator.earned_today
			g.set_wage(plant, 9)
			g.simulate(g.HOUR_SECONDS * 0.5)
			t.near(g.resource_activity(3, 1).consumed - fuel, 0 if generator == "manual_generator" else expected / 1600.0 * 0.5, "Only coal generation consumes coal", 0.003)
			t.near(operator.earned_today, wages, "Half a duty period does not trigger a partial payment")
			g.remove_power_line(Vector2i(29, 8))
			g.simulate(0.1)
			t.near(operator.earned_today - wages, g.report_totals(1, operator.id)["工作"] / g.HOUR_SECONDS * 2, "A broken circuit settles the partial duty period at its original wage", 0.01)
			wages = operator.earned_today
			g.simulate(g.HOUR_SECONDS)
			t.near(operator.earned_today, wages, "A disconnected manual or coal generator releases its operator")
			g.select_entity(Vector2i(32, 7))
			t.check(g.hud.entity_details.text.contains("未供电"), "Breaking either cable type disables downstream loads")

	for fountains in [1, 2]:
		t.fixtures.scenario("Fountain daily water consumption: %d" % fountains, 0)
		t.fixtures.power_facilities(1, 0)
		for i in fountains:
			var p := Vector2i(32 + i * 3, 9)
			t.fixtures.station("fountain", p)
			g.add_stock(p, "raw_water", 10)
		t.advance_until(func():
			g.select_entity(Vector2i(32, 9))
			return g.hud.entity_details.text.begins_with("运行中"), 15, "Delivered daily water enables the fountain")
		g.simulate(g.HOUR_SECONDS)
		t.near(g.resource_activity("raw_water", 1).consumed, fountains * 10, "Each fountain consumes one daily refill, not water every frame")
		g.simulate(g.DAY_SECONDS - g.world.day_elapsed + 0.1)
		g.select_entity(Vector2i(32, 9))
		t.check(g.hud.entity_details.text.contains("等待原水"), "A new day without water disables recovery")
		t.near(g.resource_activity("raw_water", 2).produced, 0, "Fountains do not create free raw water at midnight")

func check_drilling(t) -> void:
	var g = t.game
	# Outages and relocation preserve the output of whatever drilling actually occurs.
	t.fixtures.scenario("Dense mining, outage, cancellation and relocation", 0)
	t.fixtures.power_facilities(1, 0)
	var drill := Vector2i(34, 9)
	var deposit := Vector2i(35, 11)
	t.fixtures.station("drill", drill)
	g.add_stock(drill, "bread", 30)
	g.world.terrain[deposit] = 5
	g.cache.navigation.set_point_solid(deposit, true)
	var miner: Dictionary = t.fixtures.hungry_worker(drill)
	miner.gun_uses = 10
	g.designate(deposit, deposit)
	t.observe_until(func(): return g.stock_at(drill, 2) >= 2, 65)
	print("DIAGNOSTIC: drilling output before outage = ", g.stock_at(drill, 2))
	t.near(g.stock_at(drill, 2), g.resource_activity(2, 1).produced, "Actual extraction reaches the drill warehouse exactly once")
	t.check(g.world.terrain[deposit] == 5 and miner.gun_uses == 10, "Dense deposits remain and do not consume ordinary mining tools")
	g.remove_power_line(Vector2i(31, 8))
	var stock: float = g.stock_at(drill, 2)
	g.simulate(20)
	t.near(g.stock_at(drill, 2), stock, "Drilling pauses without electricity rather than mining by hand")
	g.designate(deposit, deposit, true)
	g.add_stock(g.BASE, 2, 1)
	var copper: float = g.resource_inventory()[2]
	var extracted: int = g.world.mined
	g.place_building(Vector2i(31, 8), "low_line")
	t.advance_until(func(): return not g.world.sites.has(Vector2i(31, 8)), 30, "Player repairs the cut power cable")
	g.simulate(20)
	t.check(g.world.mined == extracted, "Canceled dense mining does not resume when power returns")
	# A repair may use nearby drill output instead of the portal; location is not ownership.
	t.near(g.resource_inventory()[2], copper - 1, "Repair consumes exactly one actual copper block, wherever it was stored")
	stock = g.stock_at(drill, 2)
	g.begin_drill_move(drill)
	var destination := Vector2i(40, 14)
	t.check(g.move_drill_to(destination), "Drill can relocate to reachable clear ground without new building materials")
	t.near(g.stock_at(destination, 2), stock, "Moving carries its extracted stock exactly once")
	var next_deposit := destination + Vector2i(1, 2)
	g.world.terrain[next_deposit] = 6
	g.cache.navigation.set_point_solid(next_deposit, true)
	g.designate(next_deposit, next_deposit)
	g.simulate(20)
	t.near(g.stock_at(destination, 3), 0, "A moved drill does not retain its previous electrical connection")
	var cable_path: Array[Vector2i] = []
	for y in range(9, 14): cable_path.append(Vector2i(40, y))
	g.add_stock(g.BASE, 2, cable_path.size())
	t.check(g.place_building_batch(cable_path, "low_line"), "A new low-voltage branch can reach the moved drill")
	t.advance_until(func(): return cable_path.all(func(p): return not g.world.sites.has(p)), g.DAY_SECONDS * 3, "The reconnection command completes its full physical cable branch")
	for p in cable_path:
		t.check(g.building_kind_at(p) == "low_line", "Every segment of the commanded branch is completed")
	# Resuming a distant shift is autonomous, not a promised three-day work schedule.
	g.simulate(20)
	print("DIAGNOSTIC: relocated drill output after reconnection = ", g.stock_at(destination, 3))
	t.near(g.resource_inventory()[2], copper - 1, "Reconnection uses its added copper without duplicating or losing relocated inventory")

	# Two machines sharing one deposit must not double its physical extraction rate.
	t.fixtures.scenario("Competing drills share one deposit without duplicate labor", 0)
	t.fixtures.power_facilities(1, 0)
	var shared := Vector2i(36, 11)
	g.world.terrain[shared] = 5
	g.cache.navigation.set_point_solid(shared, true)
	for machine in [Vector2i(34, 9), Vector2i(37, 9)]:
		t.fixtures.station("drill", machine)
		g.add_stock(machine, "bread", 30)
		var person: Dictionary = t.fixtures.hungry_worker(machine)
		person.payroll = 4
	g.designate(shared, shared)
	var elapsed: float = t.observe_until(func(): return g.world.mined >= 2, 90)
	var shared_extracted: int = g.world.mined
	var maximum_rate: float = 1.0 + g.world.workers[0].mood.MAX_EFFICIENCY_CHANGE
	t.check(elapsed >= shared_extracted * 2.0 * g.HOUR_SECONDS / maximum_rate - 0.1, "Two drills cannot accelerate one deposit beyond the maximum real labor rate")
	t.near(g.stock_at(Vector2i(34, 9), 2) + g.stock_at(Vector2i(37, 9), 2), shared_extracted, "Each actual completed extraction enters exactly one machine warehouse")
	g.designate(shared, shared, true)
	g.simulate(3)
	t.check(g.world.mined == shared_extracted, "Canceling the shared order stops both machines")
	g.designate(shared, shared)
	t.observe_until(func(): return g.world.mined > shared_extracted, g.DAY_SECONDS * 3)
	print("DIAGNOSTIC: shared deposit output after a fresh order = ", g.world.mined)

	t.fixtures.scenario("Ordinary tools cannot excavate dense deposits", 1)
	var p := Vector2i(37, 13)
	g.world.terrain[p] = 5
	g.world.workers[0].gun_uses = 10
	g.designate(p, p)
	g.simulate(50)
	t.check(g.world.terrain[p] == 5 and g.world.mined == 0 and g.world.workers[0].earned_today == 0, "Hand mining and a mining gun cannot consume or get paid for dense ore")

func check_electric_freight(t) -> void:
	var g = t.game
	# Electricity is charged for all four physical items, not one shipment icon.
	t.fixtures.scenario("Powered freight pauses and survives a cable repair", 0)
	var plant: Vector2i = t.fixtures.power_facilities(1, 0)
	var source := Vector2i(32, 11)
	var target := Vector2i(39, 9)
	t.fixtures.station("pump", source, 4)
	t.fixtures.station("purifier", target)
	t.fixtures.hungry_worker(source)
	for x in range(33, 39):
		t.fixtures.belt(Vector2i(x, 9), Vector2i.RIGHT)
		g.world.belts[Vector2i(x, 9)].kind = "electric_belt"
	g.adjust_production(target, 1)
	t.advance_until(func(): return t.track_shows_item("raw_water"), 15, "Carrier loads a batch onto electric belts")
	g.adjust_production(target, -1)
	t.advance_until(func():
		g.select_entity(plant)
		return g.hud.entity_details.text.contains("输出  100W"), 10, "Four water items draw 100W, not 25W")
	g.remove_power_line(Vector2i(31, 8))
	g.simulate(5)
	t.near(g.stock_at(target, "raw_water"), 0, "An outage stops the in-flight shipment")
	t.near(g.resource_inventory().raw_water, 4, "Paused freight remains in inventory without loss or duplication")
	g.add_stock(g.BASE, 2, 1)
	g.place_building(Vector2i(31, 8), "low_line")
	t.advance_until(func():
		return g.stock_at(target, "raw_water") == 4, 50, "Repairing power lets all four items reach their original warehouse")
	t.near(g.resource_inventory().raw_water, 4, "Delivery preserves the same four items")

func check_track_deliveries(t) -> void:
	var g = t.game
	# The same delivery contract must work for every ingredient, including a multi-unit load.
	for entry in t.fixtures.INPUT_ROUTES:
		t.fixtures.scenario("Track supplies local recipe: " + entry.target, 1)
		var receiver := Vector2i(33, 11) if entry.target == "farm" else OTHER
		var source: Vector2i = g.BASE if entry.source == "" else P
		if entry.source != "":
			t.fixtures.station(entry.source, source)
		t.fixtures.station(entry.target, receiver)
		g.add_stock(source, entry.item, entry.amount)
		g.world.workers[0].pos = Vector2(source)
		var corner: Vector2i = t.fixtures.receiver_track(receiver, entry.target)
		var connection: Array[Vector2i] = [corner + Vector2i.DOWN, corner]
		t.check(g.place_belt_path(connection) and g.player_blocks == (entry.amount if entry.item is int else 0), "Connecting the receiver's far footprint corner costs no extra track or building materials")
		t.check(g.belt_destination(Vector2i(29, corner.y + 1)) == receiver, "The connected track targets the commanded receiver")
		g.adjust_production(receiver, 1)
		t.advance_until(func(): return t.track_shows_item(entry.item), 10, "Worker loads the requested ingredient onto a track to its receiver")
		t.check(g.hud.inventory_icons.entries[entry.item].quantity.text == "1", "A track cell carries one requested item, never a multi-unit task")
		t.near(g.stock_at(receiver, entry.item), 0, "Track cargo is not available to the receiving recipe before arrival")
		t.near(g.resource_inventory()[entry.item], entry.amount, "Reserved track cargo appears in total inventory exactly once")
		t.near(g.resource_activity(entry.item, g.world.day).consumed, 0, "Loading a track is not material consumption")
		g.adjust_production(receiver, -1)
		t.advance_until(func(): return g.stock_at(receiver, entry.item) == entry.amount, 10, "Separately loaded items reach the stopped building's local box")
		t.near(g.stock_at(source, entry.item), 0, "Delivered goods leave their source once")
		t.near(g.resource_inventory()[entry.item], entry.amount, "Arrival preserves the physical inventory")
		g.adjust_production(receiver, 1)
		t.advance_until(func(): return g.world.benches[receiver].produced_today == g.PRODUCTS[entry.target].amount, g.HOUR_SECONDS * 12, "The receiver consumes its track-delivered batch and produces normally")
		t.near(g.resource_activity(entry.item, g.world.day).consumed, entry.amount, "Only production consumes the delivered ingredient")
		t.near(g.stock_at(receiver, entry.item), 0, "Track cargo cannot be delivered or consumed twice")
