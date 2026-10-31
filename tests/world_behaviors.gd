extends RefCounted

func run(t) -> void:
	check_generated_terrain(t)
	var g = t.game
	var ore := Vector2i(37, 13)
	var p := Vector2i(28, 11)
	t.fixtures.scenario("Mine, deliver, reveal, cancel", 1)
	var mined_item: int = g.terrain[ore]
	t.check(g.designate(Vector2i(60, 30), Vector2i(60, 30)) == 0, "Unexplored ore cannot be ordered")
	g.designate(ore, ore)
	t.advance_until(func(): return g.delivered == 1, 30, "Mining delivers a block to the portal")
	t.check(g.terrain[ore] == 0 and g.player_blocks == 1, "Delivered ore becomes open ground and building material")
	t.near(g.resource_activity(mined_item, 1).produced, 1, "Excavation counts as production once, not again on delivery")
	t.near(g.resource_inventory()[mined_item], 1, "The delivered mineral appears once in physical inventory")
	t.check(g.workers[0].bread > 0 and is_equal_approx(g.player_bread + g.workers[0].bread, g.STARTING_BREAD), "Worker receives wages without inventing treasury income")
	var next := ore + Vector2i.RIGHT
	t.check(g.designate(next, next) == 1, "Excavation exposes the next reachable block")
	g.simulate(2)
	var earned: float = g.workers[0].earned_today
	g.designate(next, next, true)
	t.check(g.workers[0].earned_today > earned, "Cancellation settles the unfinished block's actual labor once")
	earned = g.workers[0].earned_today
	g.simulate(20)
	t.check(g.delivered == 1 and g.terrain[next] != 0, "Cancellation stops excavation and extra delivery")
	t.near(g.workers[0].earned_today, earned, "Cancellation keeps earned wages but pays no idle wages")

	# New map blocks are ordinary finite resources, never drill-only deposits.
	for mineral in [7, 8]:
		t.fixtures.scenario("Extract new raw material: " + g.item_name(mineral), 1)
		g.terrain[ore] = mineral
		g.designate(ore, ore)
		t.advance_until(func(): return g.delivered == 1, 40, "An ordinary worker extracts and delivers the new raw material")
		t.near(g.stock_at(g.BASE, mineral), 1, "Delivery preserves timber and iron identities")
		t.near(g.resource_activity(mineral, 1).produced, 1, "New resource extraction is counted once")
		t.check(g.terrain[ore] == 0, "New resource blocks are depleted after excavation")

	# One shared construction contract, with all actual building kinds as inputs.
	for kind in g.BUILDING_KINDS:
		t.fixtures.scenario("Plan, supply, build and recover: " + kind, 1)
		g.workers[0].hunger = 120
		g.update_ui()
		g.set_tool(kind)
		t.check(g.tool_buttons[kind].disabled and g.tool != kind, "Empty inventory disables selecting the building tool")
		t.check(not g.place_building(p, kind), "Missing materials prevent blueprint placement")
		g.simulate(3)
		t.check(not g.building_at(p) and g.workers[0].earned_today == 0, "Rejected blueprints cannot create construction or wages")
		t.check(not g.cancel_site(p) and g.player_blocks == 0, "Rejected placement cannot invent a cancellation refund")
		var cost: int = g.building_blocks(kind)
		var wrong_mineral := 2 if kind in ["pump", "purifier", "printer", "bank", "belt"] else 3
		t.fixtures.materials(cost, wrong_mineral)
		t.check(not g.place_building(p, kind), "Other minerals cannot fund the specified recipe")
		g.simulate(3)
		t.check(g.workers[0].earned_today == 0 and g.stock_at(p, wrong_mineral) == 0, "Other minerals cannot substitute for the building's specified recipe")
		g.cancel_site(p)
		t.fixtures.building_materials(kind)
		# Every ingredient matters, including water and the secondary mineral.
		for item in g.building_materials(kind):
			g.add_stock(g.BASE, item, -1)
			g.update_ui()
			t.check(g.tool_buttons[kind].disabled and not g.place_building(p, kind), "One missing ingredient disables planning even when the others are sufficient")
			g.add_stock(g.BASE, item, 1)
		g.update_ui()
		g.set_tool(kind)
		t.check(not g.tool_buttons[kind].disabled and g.tool == kind, "Exactly enough of every ingredient enables selecting the tool")
		var initial_materials: Dictionary = g.materials.duplicate()
		var recipe: Dictionary = g.building_materials(kind)
		var initial_water: float = g.total_stock("raw_water")
		g.workers[0].pos = Vector2(p)
		t.check(not g.place_building(g.BASE, kind) and g.player_blocks == cost, "Rejected placement costs nothing")
		t.check(g.place_building(p, kind) and g.player_blocks == cost, "Placing a blueprint commits quantities without removing warehouse stock")
		t.near(g.resource_inventory().get(1, 0), initial_materials.get(1, 0), "Blueprint placement leaves physical inventory unchanged")
		t.check(g.tool_buttons[kind].disabled, "The new blueprint immediately exhausts the planning allowance")
		g.cancel_site(p)
		t.check(not g.tool_buttons[kind].disabled and g.player_blocks == cost, "Canceling before delivery immediately releases quantities without producing goods")
		g.place_building(p, kind)
		t.advance_until(func(): return g.report_totals(1, 0)["工作"] > 0, 60, "Materials reach the site before construction starts")
		g.update_ui()
		t.check(g.tool_buttons[kind].disabled, "Delivery into the site cannot release the blueprint's material commitment")
		t.near(g.workers[0].earned_today, 0, "An unfinished construction does not pay incremental wages")
		var footprint_end: Vector2i = g.building_cells(p, kind).back()
		t.check(g.cancel_site(footprint_end), "Occupied footprint cell cancels construction")
		earned = g.workers[0].bread
		t.check(earned > 0, "Cancellation pays only the actual completed construction share")
		t.advance_until(func():
			for item in recipe:
				if g.total_stock(item) != recipe[item]: return false
			return true, 60, "All delivered materials, including processed goods, are physically recovered after cancellation")
		t.check(g.materials == initial_materials, "Cancel returns the actual mineral types, not generic replacement blocks")
		for mineral in initial_materials:
			t.near(g.resource_activity(mineral, 1).produced + g.resource_activity(mineral, 1).consumed, 0, "Canceling a blueprint creates neither production nor consumption")
		t.near(g.workers[0].bread, earned, "Refund does not reclaim earned wages")
		g.place_building(p, kind)
		t.advance_until(func(): return not g.sites.has(p), 240, "Construction finishes across voluntary meals and sleep")
		g.select_entity(footprint_end)
		t.check(g.entity_title.text == g.building_name(kind), "Building completes and can be inspected")
		t.check(g.player_blocks == 0, "No second charge during construction or completion")
		g.update_ui()
		t.check(g.tool_buttons[kind].disabled, "Completion consumes the goods without making another building affordable")
		t.near(g.resource_activity("raw_water", 1).consumed, initial_water, "Construction water is charged once, not invented as daily output")
		for mineral in initial_materials:
			t.near(g.resource_activity(mineral, g.day).consumed, initial_materials[mineral], "Completion records actual construction consumption once on its completion day")

	# Exercise placement families, not every recipe again: two-cell buildings,
	# water adjacency, belts and the two cable footprints.
	for kind in ["bed", "pump", "belt", "high_line", "low_line"]:
		for covered in [false, true]:
			t.fixtures.scenario("Excavate before building: %s / covered origin %s" % [kind, covered], 1)
			var origin := ore if covered else ore + Vector2i.LEFT
			if kind == "pump":
				var source := origin + Vector2i.UP
				g.water_sources[source] = true
				g.terrain[source] = 0
				g.navigation.set_point_solid(source, true)
			t.fixtures.building_materials(kind)
			var expected: Dictionary = {}
			var blocks := 0
			for cell in g.building_cells(origin, kind):
				var mineral: int = g.terrain[cell]
				if mineral != 0:
					expected[mineral] = expected.get(mineral, 0) + 1
					blocks += 1
			t.check(g.place_building(origin, kind) and g.player_blocks == g.building_blocks(kind), "Ore-covered blueprints do not deduct their recipe at placement")
			t.check(not g.place_building(origin, kind), "Reserved footprint cannot receive a second building")
			t.advance_until(func(): return g.mined == blocks or not g.sites.has(origin), 60, "Workers clear the footprint without a separate dig command")
			for cell in g.building_cells(origin, kind):
				t.check(g.terrain[cell] == 0, "Every footprint cell is cleared before the building can complete")
			t.advance_until(func(): return not g.sites.has(origin) and g.delivered == blocks, 240, "Workers deliver the excavated ore and finish construction")
			g.select_entity(origin)
			t.check(g.entity_title.text == g.building_name(kind), "Cleared blueprint becomes the requested building")
			for mineral in range(1, g.ORES.size()):
				t.check(g.materials.get(mineral, 0) == expected.get(mineral, 0), "Excavated mineral is retained without duplicate building charges")
			t.near((g.report_totals(1, 0)["挖掘"] + g.report_totals(1, 0)["工作"] + g.report_totals(2, 0)["挖掘"] + g.report_totals(2, 0)["工作"]) / g.HOUR_SECONDS, blocks + g.building_hours(kind), "Excavation and construction each pay their normal labor once")
			t.check(g.report_mined(1) == blocks, "Blueprint excavation uses normal daily mining reports")

	# A blueprint does not tunnel outside its footprint or strand a carrier inside solid terrain.
	t.fixtures.scenario("Buried blueprint waits for a player-opened route", 1)
	t.fixtures.materials(6)
	g.workers[0].pos = Vector2(36, 13)
	g.update_fog()
	var buried := Vector2i(39, 13)
	t.check(not g.place_building(Vector2i(60, 30), "bed") and g.player_blocks == 6, "Unexplored terrain still rejects blueprints without spending materials")
	t.check(g.place_building(buried, "bed") and g.player_blocks == 6, "An explored buried blueprint does not lock remote stock")
	g.simulate(20)
	t.check(g.mined == 0 and g.workers[0].earned_today == 0, "No unreachable mining, construction wages, or automatic access tunnel")
	g.designate(ore, ore + Vector2i.RIGHT)
	t.advance_until(func(): return g.beds.has(buried) and g.delivered == 4, 120, "Opening access resumes excavation, material delivery, and building")
	t.check(g.player_blocks == 4, "Waiting does not lose or duplicate reserved materials")

	# Cancel only excavation introduced by the blueprint, preserving independent player dig orders.
	for manual in ["none", "before", "after"]:
		t.fixtures.scenario("Cancel ore-covered blueprint: " + manual, 1)
		t.fixtures.materials(6)
		g.workers[0].pos = Vector2(36, 13)
		if manual == "before":
			g.designate(ore, ore)
		g.place_building(ore, "bed")
		if manual == "after":
			g.designate(ore, ore)
		t.advance_until(func(): return g.report_totals(1, 0)["挖掘"] > 0, 10, "Excavation has begun before cancellation")
		t.check(g.cancel_site(ore + Vector2i.RIGHT), "Either footprint cell cancels the whole covered blueprint")
		var paid: float = g.workers[0].bread
		t.check(g.player_blocks == 6, "Uncollected reserved material is refunded immediately")
		g.simulate(30)
		t.check(not g.building_at(ore) and g.terrain[ore + Vector2i.RIGHT] != 0, "Cancellation removes the blueprint and its remaining automatic excavation")
		if manual == "none":
			t.check(g.mined == 0 and g.terrain[ore] != 0, "Canceling an active blueprint stops its miner")
			t.near(g.workers[0].bread, paid, "Canceled excavation retains earned wages but accrues no more")
		else:
			t.check(g.delivered == 1 and g.player_blocks == 7, "Independent dig order survives blueprint cancellation and delivers once")
			t.near(g.workers[0].earned_today, 1, "Preserved mining retains partial work without paying twice")

	# Cancellation must keep already excavated ore, without clearing the rest of the footprint.
	t.fixtures.scenario("Cancel after the first footprint block is excavated", 1)
	t.fixtures.materials(6)
	g.place_building(ore, "bed")
	t.advance_until(func(): return g.mined == 1, 25, "First footprint block is excavated before cancellation")
	g.cancel_site(ore + Vector2i.RIGHT)
	t.advance_until(func(): return g.delivered == 1 and g.player_blocks == 7, 30, "Refund and already mined ore both arrive exactly once")
	g.simulate(20)
	t.check(g.terrain[ore] == 0 and g.terrain[ore + Vector2i.RIGHT] != 0 and not g.building_at(ore), "Cancel preserves the cleared cell and stops the remaining excavation")

	t.fixtures.scenario("Water placement restrictions")
	t.fixtures.materials(16)
	t.check(not g.place_building(Vector2i(34, 11), "pump"), "Pump needs an adjacent water source")
	t.check(not g.place_building(Vector2i(29, 10), "bed"), "Water source cannot be covered")
	t.check(g.designate(Vector2i(29, 10), Vector2i(29, 10)) == 0 and g.player_blocks == 16, "Water cannot be mined and invalid placements cost nothing")

	# Canceling while a carrier is en route must not duplicate or destroy reserved goods.
	t.fixtures.scenario("Cancel a blueprint during material delivery", 1)
	t.fixtures.materials(6)
	g.workers[0].pos = Vector2(g.BASE)
	g.place_building(p, "bed")
	t.advance_until(func():
		g.select_worker(0)
		return g.entity_details.text.contains("搬运  砂岩"), 5, "The worker really picks up material before cancellation")
	g.cancel_site(p)
	t.advance_until(func(): return g.player_blocks == 6, 20, "Carried and uncollected materials both return exactly once")
	g.simulate(10)
	t.check(g.stock_at(g.BASE, 1) == 6 and not g.building_at(p), "Canceled delivery leaves no orphaned building or duplicate material")

	# Moving committed goods must neither hide free stock nor free the same commitment twice.
	t.fixtures.scenario("Uncommitted materials remain available throughout delivery and completion", 1)
	t.fixtures.materials(12)
	g.place_building(p, "bed")
	t.advance_until(func():
		g.select_worker(0)
		return g.entity_details.text.contains("搬运  砂岩"), 10, "A real delivery leaves the source warehouse")
	g.update_ui()
	t.check(not g.tool_buttons.bed.disabled and g.material_requirements_text(g.building_materials("bed"), true).contains("6 / 6"), "In-flight goods are still physical inventory, leaving exactly one free bed recipe")
	t.advance_until(func(): return g.report_totals(1, 0)["工作"] > 0, 60, "The first bed receives its full recipe and starts building")
	g.update_ui()
	t.check(not g.tool_buttons.bed.disabled and g.material_requirements_text(g.building_materials("bed"), true).contains("6 / 6"), "Materials at the site do not reduce the free allowance a second time")
	t.advance_until(func(): return g.beds.has(p), 120, "The first bed completes with six unused sandstone remaining")
	g.update_ui()
	t.check(not g.tool_buttons.bed.disabled and g.material_requirements_text(g.building_materials("bed"), true).contains("6 / 6"), "Completion removes physical goods and their commitment together")
	t.check(g.place_building(Vector2i(35, 11), "bed") and g.tool_buttons.bed.disabled, "The remaining stock funds exactly one additional blueprint")

	# A planning commitment cannot protect stock from production or create it on cancellation.
	t.fixtures.scenario("Other consumption does not turn canceled commitments into physical refunds", 1)
	t.fixtures.station("bench", p)
	g.add_stock(p, 2, 1)
	var isolated := Vector2i(50, 20)
	t.fixtures.clear_area(Rect2i(isolated, Vector2i.ONE))
	t.check(g.place_building(isolated, "low_line"), "An existing copper block funds a blueprint without binding its source")
	g.adjust_production(p, 1)
	t.advance_until(func(): return g.benches[p].stock == 1, 60, "Production consumes the copper while the inaccessible blueprint waits")
	g.update_ui()
	t.check(g.building_at(isolated) and g.tool_buttons.low_line.disabled, "A stock shortfall preserves the existing blueprint but blocks new ones")
	g.cancel_site(isolated)
	t.check(g.tool_buttons.low_line.disabled and not g.place_building(Vector2i(35, 11), "low_line"), "Releasing an unmet commitment cannot replace copper already consumed elsewhere")
	t.near(g.resource_inventory()[2], 0, "Cancellation of the unsupplied blueprint creates no copper")

	# Count completion, not delivery or partial work, and preserve the correct day/person.
	t.fixtures.scenario("Daily excavation counts survive cancellation and midnight", 2)
	g.workers[0].pos = Vector2(36, 13)
	g.workers[1].pos = Vector2(28, 11)
	t.check(g.report_mined(1) == 0, "Empty report shows zero excavated blocks")
	g.designate(ore, ore)
	t.advance_until(func(): return g.mined == 1, 20, "First block is excavated")
	t.check(g.delivered == 0 and g.report_mined(1) == 1, "Excavation is counted before delivery")
	t.check(g.report_mined(1, 0) + g.report_mined(1, 1) == 1, "A completed block is credited to one miner, not the whole workforce")
	g.designate(next, next)
	g.simulate(1)
	g.designate(next, next, true)
	g.simulate(20)
	t.check(g.report_mined(1) == 1, "Cancellation and delivery do not add excavated blocks")
	g.simulate(g.DAY_SECONDS - g.day_elapsed - 2)
	g.designate(next, next)
	t.advance_until(func(): return g.mined == 2, 25, "Excavation ordered before midnight completes the next day")
	t.check(g.report_mined(1) == 1 and g.report_mined(2) == 1, "Completion day owns the block and yesterday stays unchanged")
	t.check(g.report_mined(2) == g.report_mined(2, 0) + g.report_mined(2, 1), "All-worker total equals individual counts")
	g.reset_world()
	t.check(g.report_mined(1) == 0 and g.report_mined(2) == 0, "Reset clears daily excavation history")

	t.fixtures.scenario("Daily needs, report history, and pause", 1)
	g.workers[0].hunger = 180.0
	g.simulate(g.DAY_SECONDS)
	t.near(g.workers[0].hunger, 100, "One day consumes eighty satiety, equivalent to eight bread")
	t.near(t.report_seconds(), g.DAY_SECONDS, "Report accounts for elapsed person-time")
	var history: Dictionary = g.report_totals(1).duplicate()
	g.designate(ore, ore)
	g.simulate(30)
	t.check(g.delivered == 1, "Worker can work on the next day")
	t.near(t.report_seconds(0, 2), 30, "New day has its own report")
	t.check(g.report_totals(1) == history, "Yesterday's report stays unchanged")
	var elapsed: float = g.day_elapsed
	g.toggle_pause()
	g._process(0.1)
	t.near(g.day_elapsed, elapsed, "Pause freezes game time")
	g.toggle_pause()
	g.set_speed(3)
	g._process(0.1)
	t.near(g.day_elapsed - elapsed, 0.3, "Speed control changes elapsed game time")
	g.reset_world()
	t.check(g.workers.size() == 3 and g.player_blocks == 0 and g.day == 1, "Reset returns to the starting game")
	t.near(g.resource_activity("bread", 1).produced + g.resource_activity("bread", 1).consumed, 0, "Reset clears material flow history without treating starting bread as production")
	t.near(g.resource_inventory().bread, g.STARTING_BREAD, "Reset restores the physical starting stock")

	check_direct_supply(t)
	check_loans(t)
	check_tracks(t)
	check_mood(t)

func check_direct_supply(t) -> void:
	var g = t.game
	var ore := Vector2i(37, 13)
	# A mined block must reach demand directly, regardless of which command exposed it.
	for covered in [false, true]:
		t.fixtures.scenario("New ore supplies a blueprint directly: covered %s" % covered, 1)
		t.fixtures.isolated_warehouse({1: 6})
		var target := Vector2i(36, 13) if covered else Vector2i(35, 13)
		g.workers[0].pos = Vector2(36, 13)
		t.check(g.place_building(target, "bed"), "Physical stock funds planning without binding the blueprint to its inaccessible warehouse")
		if not covered:
			g.designate(ore, ore)
		t.advance_until(func(): return g.stock_at(target, 1) == 1, 25, "The excavated sandstone goes straight into the blueprint")
		t.check(g.portal.input_blocks.get(1, 0) == 0 and g.stock_at(g.BASE, 1) == 0, "Blueprint supply never detours through the portal")
		t.near(g.resource_inventory()[1], 7, "Direct supply counts the new block once alongside existing remote stock")
		t.near(g.resource_activity(1, 1).consumed, 0, "A partially supplied blueprint has not consumed its materials")
		g.cancel_site(target)
		t.advance_until(func(): return g.stock_at(g.BASE, 1) == 1, 25, "Cancellation physically recovers only the one delivered block")
		t.near(g.resource_inventory()[1], 7, "Cancellation does not turn an unfilled recipe into extra physical goods")

	t.fixtures.scenario("New copper supplies production without a warehouse detour", 1)
	var station := Vector2i(35, 13)
	t.fixtures.station("bench", station)
	g.terrain[ore] = 2
	g.workers[0].pos = Vector2(36, 13)
	g.adjust_production(station, 1)
	g.designate(ore, ore)
	t.advance_until(func(): return g.benches[station].produced_today == 1, 75, "Fresh copper directly enables the waiting gun order")
	t.check(g.portal.input_blocks.get(2, 0) == 0, "Production supply uses the same direct delivery rule as blueprints")
	t.near(g.resource_activity(2, 1).consumed, 1, "Production consumes the fresh copper exactly once")

	# Track transport must preserve the blueprint receiver and a cancellation's actual cargo.
	for cancelled in [false, true]:
		t.fixtures.scenario("Fresh ore supplies a blueprint by track: cancel %s" % cancelled, 1)
		t.fixtures.isolated_warehouse({1: 6})
		var target := Vector2i(28, 11)
		g.workers[0].pos = Vector2(36, 13)
		for x in range(28, 37):
			t.fixtures.belt(Vector2i(x, 12), Vector2i.UP if x == 28 else Vector2i.LEFT)
		t.fixtures.belt(Vector2i(33, 13), Vector2i.LEFT)
		g.place_building(target, "bed")
		g.designate(ore, ore)
		t.advance_until(func():
			g.select_entity(Vector2i(36, 12))
			return g.entity_details.text.contains("砂岩 ×"), 25, "The miner loads the blueprint's real sandstone onto the connected track")
		t.near(g.resource_inventory()[1], 7, "Track cargo is counted once alongside existing remote stock")
		if cancelled:
			g.cancel_site(target)
			var reconnect: Array[Vector2i] = [Vector2i(33, 12), Vector2i(33, 13), g.BASE]
			t.check(g.place_belt_path(reconnect), "The player reconnects the returning cargo to its warehouse")
			t.advance_until(func(): return g.stock_at(g.BASE, 1) == 1, 20, "Canceled in-flight ore returns without inventing a full recipe refund")
		else:
			t.advance_until(func(): return g.stock_at(target, 1) == 1, 20, "The track unloads into the blueprint rather than the portal")
			t.check(g.portal.input_blocks.is_empty(), "Track supply also skips the intermediate portal")
		t.near(g.resource_inventory()[1], 7, "Arrival or cancellation preserves remote stock and the one excavated block")

	# Two destinations and several carriers cannot promise the same warehouse stock twice.
	t.fixtures.scenario("Competing blueprints share one real material batch", 3)
	t.fixtures.materials(6)
	var first := Vector2i(35, 11)
	var second := Vector2i(35, 14)
	t.check(g.place_building(first, "bed"), "The first blueprint can commit the six sandstone")
	t.check(not g.place_building(second, "bed"), "The same physical batch cannot fund a second blueprint")
	g.simulate(100)
	t.check(g.beds.has(first) and not g.building_at(second), "Only the affordable bed is placed and completed")
	t.near(g.resource_inventory()[1], 0, "Competing deliveries neither duplicate material nor leave excess at a completed site")
	t.near(g.resource_activity(1, 1).consumed, 6, "Only the completed bed consumes materials")

	# The two backpack items may have different receivers and still form one load.
	t.fixtures.scenario("A mixed backpack supplies different nearby consumers", 1)
	t.fixtures.isolated_warehouse({1: 6, 2: 1})
	var bed := Vector2i(35, 11)
	var cable := Vector2i(35, 14)
	g.workers[0].pos = Vector2(36, 13)
	g.workers[0].backpack_uses = 1
	g.terrain[ore + Vector2i.DOWN] = 2
	g.place_building(bed, "bed")
	g.place_building(cable, "low_line")
	g.designate(ore, ore + Vector2i.DOWN)
	t.advance_until(func(): return g.stock_at(bed, 1) == 1 and g.power_lines.has(cable), 90, "Sandstone and copper reach their respective consumers")
	t.check(g.workers[0].backpack_uses == 0 and g.delivered == 2, "Completing the two-item load spends one backpack use across destinations")
	t.near(g.resource_inventory()[1], 7, "The unfinished bed retains its sandstone without changing remote stock")
	t.near(g.resource_inventory()[2], 1, "The cable consumes the fresh copper, leaving remote copper untouched")
	t.check(g.portal.input_blocks.is_empty(), "Neither item needs an intermediate portal visit")

	# In-flight goods already cover demand; newly mined goods must not overfill it.
	t.fixtures.scenario("An existing shipment covers the final material", 2)
	t.fixtures.clear_area(Rect2i(38, 12, 30, 3))
	var distant := Vector2i(65, 13)
	g.explored[distant] = true
	g.add_stock(g.BASE, 2, 1)
	g.terrain[ore] = 2
	g.workers[0].pos = Vector2(36, 13)
	g.workers[1].pos = Vector2(g.BASE)
	g.place_building(distant, "low_line")
	g.designate(ore, ore)
	t.advance_until(func(): return g.power_lines.has(distant) and g.delivered == 1, 60, "The original material builds the cable and the new copper remains available")
	t.near(g.resource_inventory()[2], 1, "Only one of the two copper blocks is consumed")
	t.near(g.stock_at(distant, 2), 0, "Already-covered demand cannot receive a duplicate delivery")

	# Canceling a destination must redirect actual carried ore, not refund its whole recipe.
	t.fixtures.scenario("Cancel a direct mined delivery and reuse the location", 1)
	t.fixtures.isolated_warehouse({1: 6, 2: 1})
	t.fixtures.clear_area(Rect2i(38, 12, 12, 3))
	distant = Vector2i(47, 13)
	for cell in g.building_cells(distant, "bed"):
		g.explored[cell] = true
	g.workers[0].pos = Vector2(36, 13)
	g.place_building(distant, "bed")
	g.designate(ore, ore)
	t.advance_until(func(): return g.mined == 1 and g.workers[0].pos.x > 39, 25, "The carrier is taking the mined block directly toward the distant blueprint")
	g.cancel_site(distant)
	t.check(g.place_building(distant, "low_line"), "The canceled blueprint does not reserve its old footprint")
	t.advance_until(func(): return g.stock_at(g.BASE, 1) == 1, 25, "The carried sandstone returns to a real warehouse after cancellation")
	t.near(g.stock_at(distant, 1), 0, "A replacement blueprint cannot receive an old delivery through a stale target")
	t.near(g.resource_inventory()[1], 7, "Cancellation preserves remote stock and the single excavated block")

func check_mood(t) -> void:
	var g = t.game
	var ore := Vector2i(37, 13)
	var p := Vector2i(28, 11)
	# Faster or slower execution must not change the price of the same finished task.
	for activity in ["mining", "building", "production"]:
		var times: Array[float] = []
		var wages: Array[float] = []
		for initial_mood in [-80.0, 0.0, 80.0]:
			t.fixtures.scenario("Mood changes paid output speed: %s / %s" % [activity, initial_mood], 1)
			var w: Dictionary = g.workers[0]
			w.mood.value = initial_mood
			var complete: Callable
			if activity == "mining":
				g.designate(ore, ore)
				complete = func(): return g.mined == 1
			elif activity == "building":
				t.fixtures.building_materials("bed")
				g.place_building(p, "bed")
				complete = func(): return g.beds.has(p)
			else:
				t.fixtures.station("bench", p)
				g.add_stock(p, 2, 1)
				g.adjust_production(p, 1)
				complete = func(): return g.benches[p].stock == 1
			t.advance_until(complete, 60, "The ordered output completes at every mood level")
			var report: Dictionary = g.report_totals(g.day, w.id)
			times.append(report["工作"] + report["挖掘"])
			wages.append(w.earned_today)
			var reward := 1.0 if activity == "mining" else 4.0 if activity == "building" else 2.0
			t.near(w.earned_today, reward, "A completed task pays its agreed reward independently of execution speed")
			t.near(g.resource_inventory().bread + g.resource_activity("bread", 1).consumed, g.STARTING_BREAD, "Actual meals and wage transfers conserve the same physical bread")
			t.near(g.resource_activity("bread", 1).consumed, w.eaten_today, "Only actual eating, not wages, consumes bread")
		t.check(times[0] > times[1] and times[1] > times[2], "Mood changes actual labor time, independent of breaks or activity choice")
		t.check(is_equal_approx(wages[0], wages[1]) and is_equal_approx(wages[1], wages[2]), "Mood changes time, not the price of the finished item")

	t.fixtures.scenario("Free recovery, independent newborns, and reset", 1)
	var w: Dictionary = g.workers[0]
	t.near(w.mood.value, 0, "New workers start emotionally neutral")
	w.mood.value = -60
	g.simulate(g.HOUR_SECONDS * 4)
	t.check(w.mood.value > -60 and w.mood.value < 0, "Waiting without money gradually recovers mood, not instantly")
	t.near(w.bread, 0, "Free recovery needs neither purchases nor loans")
	var newcomer: Dictionary = g.create_worker(g.BASE)
	t.near(newcomer.mood.value, 0, "A newcomer does not inherit another worker's experiences")
	t.near(newcomer.hunger, g.MAX_HUNGER, "New workers arrive fully fed without personal bread")
	t.near(newcomer.bread, 0, "Full starting satiety does not mint spendable food")
	g.reset_world()
	for person in g.workers:
		t.near(person.mood.value, 0, "Reset discards old emotional history")

func check_tracks(t) -> void:
	var g = t.game
	var source := Vector2i(36, 13)
	var ore := source + Vector2i.RIGHT
	var line: Array[Vector2i] = [source, Vector2i(35, 13), Vector2i(34, 13), Vector2i(33, 13), g.BASE]
	# Planning is free, but invalid strokes must not create partial construction.
	t.fixtures.scenario("Track strokes plan without prepayment", 1)
	t.fixtures.materials(4)
	var through_portal: Array[Vector2i] = [Vector2i(33, 13), g.BASE, Vector2i(31, 13)]
	t.check(not g.place_belt_path(through_portal) and g.player_blocks == 4, "Track cannot pass through the portal footprint")
	t.check(g.place_belt_path(line) and g.player_blocks == 4, "Four track blueprints leave their materials in the warehouse")
	t.check(g.place_belt_path(line) and g.player_blocks == 4, "Retracing blueprints does not create a material charge")
	var invalid: Array[Vector2i] = [Vector2i(35, 13), Vector2i(35, 15)]
	t.check(not g.place_belt_path(invalid) and g.player_blocks == 4, "A nonadjacent stroke leaves existing construction unchanged")
	t.check(not g.cancel_site(Vector2i(37, 13)) and g.player_blocks == 4, "A track occupies only its own cell")
	g.simulate(30)
	g.select_entity(source)
	t.check(g.entity_title.text == "矿道" and g.entity_details.text.contains("通往传送门"), "Workers complete a connected track without another material charge")
	t.check(g.remove_belt(Vector2i(35, 13)), "Empty completed track can be dismantled")
	t.advance_until(func(): return g.player_blocks == 1, 15, "Dismantled material returns by worker")
	g.select_entity(source)
	t.check(g.entity_details.text.contains("未连接传送门"), "Upstream inspector reflects a severed connection")

	# Adjacent endpoints are not a connection until the player explicitly joins their cells.
	t.fixtures.scenario("Separate strokes join without rotating or spending twice", 1)
	g.workers[0].pos = Vector2(source)
	t.fixtures.materials(4)
	var head: Array[Vector2i] = [source, Vector2i(35, 13)]
	var tail: Array[Vector2i] = [Vector2i(34, 13), Vector2i(33, 13), g.BASE]
	g.place_belt_path(head)
	g.place_belt_path(tail)
	g.simulate(20)
	g.select_entity(source)
	t.check(g.entity_details.text.contains("未连接传送门"), "Touching endpoints do not silently join")
	var join: Array[Vector2i] = [Vector2i(35, 13), Vector2i(34, 13)]
	t.check(g.place_belt_path(join) and g.player_blocks == 0, "Existing endpoints can be joined without paying for either tile again")
	g.select_entity(source)
	t.check(g.entity_details.text.contains("通往传送门"), "Explicit join keeps the receiving line's exit")
	g.designate(ore, ore)
	t.advance_until(func(): return g.delivered == 1, 30, "Ore traverses a line built from separate connected strokes")
	t.near(g.portal.freight_bread, 0.2, "Connected-stroke delivery charges freight once")

	# The portal must not silently reverse the direction chosen by the player's stroke.
	t.fixtures.scenario("Drag direction wins over proximity to the portal", 1)
	g.workers[0].pos = Vector2(source)
	t.fixtures.materials(4)
	var outward: Array[Vector2i] = [Vector2i(33, 13), Vector2i(34, 13), Vector2i(35, 13), source]
	g.place_belt_path(outward)
	g.simulate(20)
	g.designate(ore, ore)
	t.advance_until(func(): return g.delivered == 1, 30, "Outward-facing track leaves the worker to walk the ore home")
	t.near(g.portal.freight_bread, 0, "An adjacent portal does not make a backward track usable")
	t.check(g.place_belt_path(line) and g.player_blocks == 1, "A reverse stroke reconnects existing empty tracks without another charge")
	g.designate(ore + Vector2i.RIGHT, ore + Vector2i.RIGHT)
	t.advance_until(func(): return g.delivered == 2, 30, "Reversed track carries the next real excavation home")
	t.near(g.portal.freight_bread, 0.2, "Only the correctly directed trip pays freight")

	# Real mining must unload directly onto a track, without a station or premature settlement.
	t.fixtures.scenario("Direct track loading, transport fee, and report", 1)
	for cell in line.slice(0, 4):
		t.fixtures.belt(cell, Vector2i.LEFT)
	var w: Dictionary = g.workers[0]
	w.pos = Vector2(source)
	g.designate(ore, ore)
	t.advance_until(func(): return not g.belt_cargo.is_empty(), 20, "Miner puts the excavated block directly on a track")
	t.check(w.carry == 0 and g.delivered == 0 and g.player_blocks == 0, "Track holds the ore but does not credit an undelivered block")
	t.near(w.earned_today, 1.0, "Only mining wages are earned before arrival")
	t.near(g.portal.freight_bread, 0, "Loading does not charge transport fees")
	t.check(g.report_mined(1, 0) == 1, "Track delivery does not replace excavation reporting")
	t.advance_until(func(): return g.delivered == 1, 5, "Conveyor delivers the ore to the portal")
	t.near(w.earned_today, 1.0, "Ore delivery does not mint exchange income")
	t.near(g.portal.freight_bread, 0.2, "Player receives exactly one transport fee")
	g.simulate(5)
	t.check(g.delivered == 1 and g.player_blocks == 1, "Arrived cargo is not delivered again")

	# Invalid routes must never entice workers into leaving ore on a dead end or cycle.
	for route_kind in ["disconnected", "cycle"]:
		t.fixtures.scenario("Track fallback: " + route_kind, 1)
		t.fixtures.belt(source, Vector2i.LEFT)
		if route_kind == "cycle":
			t.fixtures.belt(Vector2i(35, 13), Vector2i.RIGHT)
		w = g.workers[0]
		w.pos = Vector2(source)
		g.designate(ore, ore)
		t.advance_until(func(): return g.delivered == 1, 30, "Worker walks the ore to the portal when the route is unusable")
		t.near(g.portal.freight_bread, 0, "Walking delivery does not charge transport")
		t.near(w.earned_today, 1, "Walking miner receives only labor wages")

	# Removing an empty downstream segment must preserve upstream cargo through midnight.
	t.fixtures.scenario("Blocked cargo survives disconnection and resumes after rebuilding", 1)
	for cell in line.slice(0, 4):
		t.fixtures.belt(cell, Vector2i.LEFT)
	t.fixtures.belt(Vector2i(36, 14), Vector2i.ZERO)
	g.workers[0].pos = Vector2(source)
	g.designate(ore, ore)
	t.advance_until(func(): return not g.belt_cargo.is_empty(), 20, "Block has been loaded before the route is changed")
	var redirect: Array[Vector2i] = [source, Vector2i(36, 14)]
	t.check(not g.place_belt_path(redirect) and not g.remove_belt(source), "Loaded track cannot redirect or delete its cargo")
	t.check(g.remove_belt(Vector2i(34, 13)), "An empty downstream segment can be removed")
	g.simulate(g.DAY_SECONDS)
	t.check(g.delivered == 0 and g.belt_cargo.size() == 1, "Disconnected ore remains on the track across midnight")
	t.near(g.portal.freight_bread, 0, "Blocked ore never earns a fee")
	var reconnect: Array[Vector2i] = [Vector2i(35, 13), Vector2i(34, 13), Vector2i(33, 13)]
	t.check(g.place_belt_path(reconnect), "Refunded material can reconnect the gap")
	t.advance_until(func(): return g.delivered == 1, 15, "Rebuilt route resumes transport without mining the block again")
	t.near(g.portal.freight_bread, 0.2, "Resumed cargo pays once")
	t.check(g.report_mined(1, 0) == 1 and g.report_mined(2, 0) == 0, "Delayed arrival does not count another excavation")

	# Simultaneous ore from two owners must merge without overwriting or mixing payouts.
	t.fixtures.scenario("Two branches merge mixed ore and preserve ownership", 2)
	for x in range(33, 37):
		t.fixtures.belt(Vector2i(x, 13), Vector2i.LEFT)
	t.fixtures.belt(Vector2i(36, 12), Vector2i.DOWN)
	t.fixtures.belt(Vector2i(36, 14), Vector2i.UP)
	for i in 2:
		g.workers[i].pos = Vector2(36, 12 + i * 2)
		g.workers[i].carry = i + 1
		g.workers[i].bread = 1.0
	g.simulate(5)
	t.check(g.delivered == 2 and g.portal.input_blocks.get(1, 0) == 1 and g.portal.input_blocks.get(2, 0) == 1, "Merged line delivers both original ore types once")
	t.check(g.materials.get(1, 0) == 1 and g.materials.get(2, 0) == 1, "Mixed freight remains separate materials in the spendable inventory")
	for worker in g.workers:
		t.near(worker.earned_today, 0, "Freight delivery creates no wages or bread")
	t.near(g.portal.freight_bread, 0.4, "Merged deliveries charge two fees")

	# Same-cell contention must fall back without losing ore, and backpack use stays per load.
	for shared in [false, true]:
		t.fixtures.scenario("Track backpack and unloading contention: " + str(shared), 2 if shared else 1)
		for cell in line.slice(0, 4):
			t.fixtures.belt(cell, Vector2i.LEFT)
		for worker in g.workers:
			worker.pos = Vector2(source)
			worker.carry = 1
			worker.extra_cargo = [2]
			worker.backpack_uses = 1
		g.simulate(8)
		t.check(g.delivered == g.workers.size() * 2 and g.belt_cargo.is_empty(), "Every block reaches the portal even when unloading competes")
		for worker in g.workers:
			t.check(worker.carry == 0 and worker.backpack_uses == 0, "Two-block load consumes one backpack use, not one per deposit")
		var income: float = g.player_bread
		for worker in g.workers:
			income += worker.earned_today
		t.near(income, g.STARTING_BREAD, "Freight without new labor or food production cannot create bread")

	# Debt deductions apply to actual net transport income, never the player's freight fee.
	t.fixtures.scenario("Belt income repays a loan after freight", 1)
	t.fixtures.bank(Vector2i(28, 11))
	for cell in line.slice(0, 4):
		t.fixtures.belt(cell, Vector2i.LEFT)
	w = g.workers[0]
	w.pos = Vector2(source)
	w.bread = 9.0
	g.workers[0].loan_principal = 1.0
	g.designate(ore, ore)
	t.advance_until(func(): return g.delivered == 1, 30, "Borrower delivers through the track")
	t.near(g.portal.repaid_principal, 0.25, "Loan takes 25 percent of labor wages, not mineral delivery")
	t.near(g.portal.freight_bread, 0.2, "Transport fee is separate from uncollected loan interest")
	g.reset_world()
	t.check(g.belts.is_empty() and g.belt_cargo.is_empty() and g.player_bread == g.STARTING_BREAD, "Reset clears tracks and restores only the finite starting supply")

func check_generated_terrain(t) -> void:
	var g = t.game
	# Prevent seeds being ignored or old water/mining edits leaking into a new world.
	t.fixtures.scenario("Seeded material fields reproduce the same world", 1, true)
	var previous: Dictionary = {}
	for seed_value in [0, 1020, 4294967295]:
		g.reset_world(seed_value)
		var blocks: Dictionary = g.terrain.duplicate()
		var water: Dictionary = g.water_sources.duplicate()
		if not previous.is_empty():
			t.check(blocks != previous, "Different seeds change the actual mineral layout")
		g.reset_world(seed_value + 1)
		g.reset_world(seed_value)
		t.check(g.terrain == blocks and g.water_sources == water, "Recreating a seed restores exactly its minerals and water, without remnants of another map")
		previous = blocks

	# Measure the delivered map, including water and the camp, not noise internals.
	for seed_value in [0, 1020, 4294967295]:
		g.reset_world(seed_value)
		var sample_area := Rect2i(-64, -64, 256, 192)
		g.ensure_region(sample_area)
		var sample := map_snapshot(g, sample_area)
		var sandstone := 0
		for material in sample.values():
			if material == 1:
				sandstone += 1
		var share := float(sandstone) / sample.size()
		print("MAP seed=%d sandstone=%.2f%% other=%.2f%% ratio=%.2f:1" % [seed_value, share * 100.0, (1.0 - share) * 100.0, share / (1.0 - share)])
		t.check(share >= 0.75 and share <= 0.8, "Representative maps keep sandstone at 75-80 percent, including all minerals and caves in the remainder")

	# Exercise actual generated resources, rather than just the hand-arranged quarry.
	t.fixtures.scenario("Mine and inspect the generated world", 1, true)
	var ore := Vector2i(-1, -1)
	var camp := Rect2i(g.BASE - Vector2i(4, 2), Vector2i(9, 5))
	for cell in g.explored:
		if g.terrain[cell] < 1 or g.terrain[cell] > 4:
			continue
		for direction in g.DIRS:
			if camp.has_point(cell + direction):
				ore = cell
				break
		if ore.x >= 0:
			break
	t.check(ore.x >= 0, "The chosen seed provides an ordinary block adjacent to the camp for this mining scenario")
	if ore.x < 0:
		return
	var mineral: int = g.terrain[ore]
	g.select_tile(ore)
	t.check(g.entity_title.text == g.ORES[mineral].name, "Generated material is shown correctly in the inspector")
	t.check(g.designate(ore, ore) == 1, "A generated ordinary block accepts a mining command")
	t.advance_until(func(): return g.delivered == 1, 30, "Generated ore is mined and delivered through normal gameplay")
	t.check(g.terrain[ore] == 0 and g.stock_at(g.BASE, mineral) == 1, "Mining clears the generated block and delivers its actual material once")
	g.reset_world(1020)
	t.check(g.terrain[ore] == mineral and g.player_blocks == 0, "Restarting the same seed restores the original deposit and clears previous inventory")
	check_unbounded_world(t)

func map_snapshot(g, area: Rect2i) -> Dictionary:
	var result: Dictionary = {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			result[cell] = g.MapGenerator.WATER if g.water_sources.has(cell) else g.terrain[cell]
	return result

func check_unbounded_world(t) -> void:
	var g = t.game
	# Exploration order must not move deposits, truncate caves, or duplicate water.
	t.fixtures.scenario("Distant geology is independent of exploration order", 0, true)
	var areas := [Rect2i(-160, -96, 64, 64), Rect2i(160, 96, 64, 64), Rect2i(-32, -32, 64, 64)]
	var snapshots: Array[Dictionary] = []
	var counts: Dictionary = {}
	for area in areas:
		g.ensure_region(area)
		var snapshot := map_snapshot(g, area)
		snapshots.append(snapshot)
		# Prevent overlapping spots from consuming the sandstone or forming giant fields.
		var sandstone := 0
		for material in snapshot.values():
			if material == 1:
				sandstone += 1
		t.check(sandstone >= snapshot.size() * 0.65, "Sandstone remains the dominant ground throughout sampled regions")
		var visited: Dictionary = {}
		var largest := 0
		for start in snapshot:
			if visited.has(start) or snapshot[start] in [1, 5, 6, g.MapGenerator.WATER]:
				continue
			var frontier: Array[Vector2i] = [start]
			visited[start] = true
			var size := 0
			while not frontier.is_empty():
				var current: Vector2i = frontier.pop_back()
				size += 1
				for direction in g.DIRS:
					var neighbor: Vector2i = current + direction
					if snapshot.get(neighbor, -1) == snapshot[start] and not visited.has(neighbor):
						visited[neighbor] = true
						frontier.append(neighbor)
			largest = maxi(largest, size)
		t.check(largest <= 512, "Varied mineral deposits and caves stay compact instead of merging into region-wide fields")
		for cell in snapshot:
			counts[snapshot[cell]] = counts.get(snapshot[cell], 0) + 1
			if snapshot[cell] in [5, 6, g.MapGenerator.WATER]:
				var isolated := true
				for direction in g.DIRS:
					var neighbor: Vector2i = cell + direction
					if area.has_point(neighbor) and snapshot[neighbor] in [5, 6, g.MapGenerator.WATER]:
						isolated = false
				t.check(isolated, "Special sources occupy isolated single cells rather than ordinary mineral fields")
	for material in range(10):
		t.check(counts.get(material, 0) > 0, "Exploration finds terrain category %d, including natural caves and scarce sources" % material)
	g.reset_world(1021)
	g.reset_world(1020)
	for i in range(areas.size() - 1, -1, -1):
		g.ensure_region(areas[i])
		t.check(map_snapshot(g, areas[i]) == snapshots[i], "Reversing discovery preserves the complete mineral, cave and water layout")

	# Negative coordinates, the former sentinel and the old right edge must all work.
	for target in [Vector2i(-33, -1), Vector2i(-1, -1), Vector2i(160, 13)]:
		t.fixtures.scenario("Excavate and deliver beyond old map limits: " + str(target), 1)
		var left: int = mini(target.x, g.BASE.x) - 1
		var right: int = maxi(target.x, g.BASE.x) + 2
		var top: int = mini(target.y, g.BASE.y) - 1
		g.ensure_region(Rect2i(left, top, right - left, g.BASE.y - top + 3))
		t.fixtures.clear_area(Rect2i(left, target.y + 1, right - left, 1))
		t.fixtures.clear_area(Rect2i(g.BASE.x, top, 1, g.BASE.y - top + 3))
		g.terrain[target] = 2
		g.water_sources.erase(target)
		g.navigation.set_point_solid(target, true)
		g.explored[target] = true
		g.select_tile(target)
		t.check(g.entity_panel.visible and g.entity_title.text == "铜矿", "Negative and distant cells retain their clicked details")
		t.check(g.designate(target, target) == 1, "Mining commands accept cells outside the old rectangle")
		t.advance_until(func(): return g.stock_at(g.BASE, 2) == 1, 600, "Workers cross region boundaries and deliver the real material to the portal")
		g.ensure_region(Rect2i(target - Vector2i.ONE * 2, Vector2i.ONE * 5))
		t.check(g.terrain[target] == 0 and g.delivered == 1, "Revisiting generated terrain never respawns an excavated deposit")

func check_loans(t) -> void:
	var g = t.game
	var bank := Vector2i(28, 11)
	for balance in [0.0, 7.0, 10.0]:
		t.fixtures.scenario("Bank funds an urgent food shortage: " + str(balance), 1)
		t.fixtures.bank(bank)
		var w: Dictionary = g.workers[0]
		w.pos = Vector2(bank)
		w.bread = balance
		w.hunger = 0
		g.simulate(15)
		var lent: float = g.portal.lent_bread
		t.check(lent >= 0 and lent <= 10 - balance + 0.05, "Borrowing covers only the live food shortage, not beds or equipment")
		t.near(w.earned_today, 0, "A bank advance is not labor income")
		t.near(g.resource_inventory().bread + g.resource_activity("bread", 1).consumed, g.STARTING_BREAD + balance, "Loan and meal conserve physical bread")
		if lent > 0:
			g.simulate(g.DAY_SECONDS)
			t.near(g.portal.lent_bread, lent, "Outstanding debt blocks a second advance across midnight")

	for access in ["absent", "blueprint", "unreachable"]:
		t.fixtures.scenario("Only accessible completed banks lend: " + access, 1)
		g.workers[0].hunger = 0
		if access == "blueprint":
			t.fixtures.building_materials("bank")
			g.place_building(bank, "bank")
		elif access == "unreachable":
			t.fixtures.bank(Vector2i(1, 1))
		g.simulate(4)
		t.near(g.portal.lent_bread, 0, "Neither an inaccessible bank nor a blueprint can issue cash")

	t.fixtures.scenario("Actual wages repay principal then interest exactly once", 1)
	t.fixtures.bank(bank)
	var w: Dictionary = g.workers[0]
	w.pos = Vector2(bank)
	w.bread = 7
	w.hunger = 0
	t.advance_until(func(): return g.portal.lent_bread > 0, 3, "A real advance creates the loan")
	var principal: float = g.portal.lent_bread
	g.designate(Vector2i(37, 11), Vector2i(40, 15))
	t.advance_until(func(): return g.banks[bank].interest_received >= principal * g.LOAN_INTEREST_RATE - 0.00001, g.DAY_SECONDS * 3, "Work eventually repays principal and the one-time interest")
	t.near(g.portal.repaid_principal, principal, "Principal is repaid once")
	t.near(g.banks[bank].interest_received, principal * g.LOAN_INTEREST_RATE, "The final installment does not overpay interest")
	var interest: float = g.banks[bank].interest_received
	g.simulate(10)
	t.near(g.banks[bank].interest_received, interest, "Paid debt stops withholding interest")
