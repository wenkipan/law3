extends RefCounted

func run(t) -> void:
	check_generated_terrain(t)
	var g = t.game
	var ore := Vector2i(37, 13)
	var p := Vector2i(28, 11)
	t.scenario("Mine, deliver, reveal, cancel", 1)
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
	var earned: float = g.workers[0].bread
	g.designate(next, next, true)
	g.simulate(20)
	t.check(g.delivered == 1 and g.terrain[next] != 0, "Cancellation stops excavation and extra delivery")
	t.near(g.workers[0].bread, earned, "Cancellation keeps earned wages but pays no idle wages")

	# One shared construction contract, with all actual building kinds as inputs.
	for kind in g.BUILDING_KINDS:
		t.scenario("Build and refund: " + kind, 1)
		g.update_ui()
		t.check(g.tool_buttons[kind].disabled, "Unaffordable building button is disabled")
		g.set_tool(kind)
		t.check(g.tool != kind and not g.place_building(p, kind), "Shortcut and placement cannot bypass material cost")
		var cost: int = g.building_blocks(kind)
		if kind in ["bed", "bench", "workbench"]:
			t.materials(cost, 3)
			g.update_ui()
			g.set_tool(kind)
			t.check(g.tool_buttons[kind].disabled and g.tool != kind and not g.place_building(p, kind), "Enough blocks of the wrong mineral cannot pay a specific recipe")
		t.building_materials(kind)
		var initial_materials: Dictionary = g.materials.duplicate()
		var initial_water: float = g.total_stock("raw_water")
		g.workers[0].pos = Vector2(p)
		t.check(not g.place_building(g.BASE, kind) and g.player_blocks == cost, "Rejected placement costs nothing")
		t.check(g.place_building(p, kind) and g.player_blocks == 0, "Blueprint charges materials once")
		t.near(g.resource_inventory().get(1, 0), initial_materials.get(1, 0), "Blueprint reservation keeps physical material in inventory until construction consumes it")
		t.advance_until(func(): return g.workers[0].earned_today > 0, 60, "Materials reach the site before construction starts")
		earned = g.workers[0].bread
		t.check(earned > 0, "Construction continues with empty inventory and pays labor")
		var footprint_end: Vector2i = g.building_cells(p, kind).back()
		t.check(g.cancel_site(footprint_end), "Occupied footprint cell cancels construction")
		t.advance_until(func(): return g.player_blocks == cost and g.total_stock("raw_water") == initial_water, 60, "All delivered materials, including water, are physically recovered after cancellation")
		t.check(g.materials == initial_materials, "Cancel returns the actual mineral types, not generic replacement blocks")
		for mineral in initial_materials:
			t.near(g.resource_activity(mineral, 1).produced + g.resource_activity(mineral, 1).consumed, 0, "Canceling a blueprint creates neither production nor consumption")
		t.near(g.workers[0].bread, earned, "Refund does not reclaim earned wages")
		g.place_building(p, kind)
		g.simulate(90)
		g.select_entity(footprint_end)
		t.check(g.entity_title.text == g.building_name(kind), "Building completes and can be inspected")
		t.check(g.player_blocks == 0, "No second charge during construction or completion")
		t.near(g.resource_activity("raw_water", 1).consumed, initial_water, "Construction water is charged once, not invented as daily output")
		for mineral in initial_materials:
			t.near(g.resource_activity(mineral, 1).consumed, initial_materials[mineral], "Completion records actual construction consumption once")

	# The same contract covers every footprint: no building may finish inside ore or charge twice.
	for kind in g.BUILDING_KINDS:
		for covered in [false, true]:
			t.scenario("Excavate before building: %s / covered origin %s" % [kind, covered], 1)
			var origin := ore if covered else ore + Vector2i.LEFT
			if kind == "pump":
				var source := origin + Vector2i.UP
				g.water_sources[source] = true
				g.terrain[source] = 0
				g.navigation.set_point_solid(source, true)
			t.building_materials(kind)
			var expected: Dictionary = {}
			var blocks := 0
			for cell in g.building_cells(origin, kind):
				var mineral: int = g.terrain[cell]
				if mineral != 0:
					expected[mineral] = expected.get(mineral, 0) + 1
					blocks += 1
			t.check(g.place_building(origin, kind) and g.player_blocks == 0, "Ore-covered blueprint reserves its entire recipe immediately")
			t.check(not g.place_building(origin, kind), "Reserved footprint cannot receive a second building")
			t.advance_until(func(): return g.mined == blocks or not g.sites.has(origin), 60, "Workers clear the footprint without a separate dig command")
			for cell in g.building_cells(origin, kind):
				t.check(g.terrain[cell] == 0, "Every footprint cell is cleared before the building can complete")
			t.advance_until(func(): return not g.sites.has(origin) and g.delivered == blocks, 90, "Workers deliver the excavated ore and finish construction")
			g.select_entity(origin)
			t.check(g.entity_title.text == g.building_name(kind), "Cleared blueprint becomes the requested building")
			for mineral in range(1, g.ORES.size()):
				t.check(g.materials.get(mineral, 0) == expected.get(mineral, 0), "Excavated mineral is retained without duplicate building charges")
			t.near(g.workers[0].earned_today, blocks + g.building_hours(kind), "Excavation and construction each pay their normal labor once")
			t.check(g.report_mined(1) == blocks, "Blueprint excavation uses normal daily mining reports")

	# A blueprint does not tunnel outside its footprint or strand a carrier inside solid terrain.
	t.scenario("Buried blueprint waits for a player-opened route", 1)
	t.materials(6)
	g.workers[0].pos = Vector2(36, 13)
	g.update_fog()
	var buried := Vector2i(39, 13)
	t.check(not g.place_building(Vector2i(60, 30), "bed") and g.player_blocks == 6, "Unexplored terrain still rejects blueprints without spending materials")
	t.check(g.place_building(buried, "bed") and g.player_blocks == 0, "An explored buried blueprint can be planned and funded")
	g.simulate(20)
	t.check(g.mined == 0 and g.workers[0].earned_today == 0, "No unreachable mining, construction wages, or automatic access tunnel")
	g.designate(ore, ore + Vector2i.RIGHT)
	t.advance_until(func(): return g.beds.has(buried) and g.delivered == 4, 120, "Opening access resumes excavation, material delivery, and building")
	t.check(g.player_blocks == 4, "Waiting does not lose or duplicate reserved materials")

	# Cancel only excavation introduced by the blueprint, preserving independent player dig orders.
	for manual in ["none", "before", "after"]:
		t.scenario("Cancel ore-covered blueprint: " + manual, 1)
		t.materials(6)
		g.workers[0].pos = Vector2(36, 13)
		if manual == "before":
			g.designate(ore, ore)
		g.place_building(ore, "bed")
		if manual == "after":
			g.designate(ore, ore)
		t.advance_until(func(): return g.workers[0].earned_today > 0, 10, "Excavation has begun before cancellation")
		var paid: float = g.workers[0].bread
		t.check(g.cancel_site(ore + Vector2i.RIGHT), "Either footprint cell cancels the whole covered blueprint")
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
	t.scenario("Cancel after the first footprint block is excavated", 1)
	t.materials(6)
	g.place_building(ore, "bed")
	t.advance_until(func(): return g.mined == 1, 25, "First footprint block is excavated before cancellation")
	g.cancel_site(ore + Vector2i.RIGHT)
	t.advance_until(func(): return g.delivered == 1 and g.player_blocks == 7, 30, "Refund and already mined ore both arrive exactly once")
	g.simulate(20)
	t.check(g.terrain[ore] == 0 and g.terrain[ore + Vector2i.RIGHT] != 0 and not g.building_at(ore), "Cancel preserves the cleared cell and stops the remaining excavation")

	t.scenario("Water placement restrictions")
	t.materials(16)
	t.check(not g.place_building(Vector2i(34, 11), "pump"), "Pump needs an adjacent water source")
	t.check(not g.place_building(Vector2i(29, 10), "bed"), "Water source cannot be covered")
	t.check(g.designate(Vector2i(29, 10), Vector2i(29, 10)) == 0 and g.player_blocks == 16, "Water cannot be mined and invalid placements cost nothing")

	# Canceling while a carrier is en route must not duplicate or destroy reserved goods.
	t.scenario("Cancel a blueprint during material delivery", 1)
	t.materials(6)
	g.workers[0].pos = Vector2(g.BASE)
	g.place_building(p, "bed")
	g.simulate(0.8)
	g.cancel_site(p)
	t.advance_until(func(): return g.player_blocks == 6, 20, "Carried and uncollected materials both return exactly once")
	g.simulate(10)
	t.check(g.stock_at(g.BASE, 1) == 6 and not g.building_at(p), "Canceled delivery leaves no orphaned building or duplicate material")

	# Count completion, not delivery or partial work, and preserve the correct day/person.
	t.scenario("Daily excavation counts survive cancellation and midnight", 2)
	g.workers[0].pos = Vector2(36, 13)
	g.workers[1].pos = Vector2(28, 11)
	t.check(g.report_mined(1) == 0, "Empty report shows zero excavated blocks")
	g.designate(ore, ore)
	t.advance_until(func(): return g.mined == 1, 20, "First block is excavated")
	t.check(g.delivered == 0 and g.report_mined(1) == 1, "Excavation is counted before delivery")
	t.check(g.report_mined(1, 0) == 1 and g.report_mined(1, 1) == 0, "Only the miner who completes the block receives credit")
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

	t.scenario("Eat, rest, and resume for a new need", 1)
	var w: Dictionary = g.workers[0]
	w.bread = 10.0
	g.designate(ore, ore)
	g.simulate(8)
	t.check(w.hunger > 90 and w.bread == 0 and g.delivered == 0, "Funded food is eaten; worker rests instead of mining unnecessarily")
	t.near(g.resource_activity("bread", 1).consumed, 10, "Eaten bread counts as consumption, not wage or ownership transfers")
	t.near(g.resource_inventory().bread, g.STARTING_BREAD, "Physical inventory excludes eaten food and retains factory reserves")
	t.materials(6)
	g.place_building(p, "bed")
	g.simulate(16)
	t.check(w.bread > 0, "New building needs bring a resting worker back to paid work")

	t.scenario("Assigned bed, exclusive rent, and recovery", 2)
	t.bed(p)
	g.assign_bed(p, 1)
	for worker in g.workers:
		worker.pos = Vector2(p)
		worker.bread = 10.0
		worker.fatigue = 100.0
	g.simulate(10)
	t.near(g.stock_at(p, "bread"), 5, "Only the assigned occupant pays one rent")
	t.check(g.workers[0].bread == 10 and g.workers[1].bread == 5, "Other workers cannot rent the assigned bed")
	t.check(g.workers[1].fatigue < g.workers[0].fatigue, "Bed sleep recovers faster than ground sleep")
	g.simulate(25)
	t.near(g.stock_at(p, "bread"), 5, "Continued sleep does not repeatedly charge rent")

	t.scenario("Daily needs, report history, and pause", 1)
	g.workers[0].hunger = 180.0
	g.simulate(g.DAY_SECONDS)
	t.near(g.workers[0].hunger, 80, "Hunger declines over a day")
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

	# Prevent unnecessary borrowing, oversized advances, and loans being counted as wages.
	for balance in [0.0, 7.0, 10.0]:
		t.scenario("Bank covers only the unpaid daily shortfall: " + str(balance), 1)
		t.bank(p)
		w = g.workers[0]
		w.bread = balance
		g.simulate(8)
		t.near(g.portal.lent_bread, 10.0 - balance, "Only the food shortfall is advanced")
		t.near(w.earned_today, 0, "Borrowed bread is not earned income")
		t.near(g.player_bread, g.STARTING_BREAD - g.portal.lent_bread, "Issuing principal spends existing bread")
		t.check(w.hunger > 90, "Borrower can eat before earning wages")
		g.simulate(g.DAY_SECONDS)
		t.near(g.portal.lent_bread, 10.0 if balance == 10.0 else 10.0 - balance, "Unpaid loans survive midnight without a second advance")
		t.near(g.player_bread, g.STARTING_BREAD - g.portal.lent_bread, "Idle debt has no automatic deductions or late fees")

	# Prevent blueprints or unreachable banks from lending, while keeping mining available.
	for access in ["absent", "blueprint", "unreachable", "open"]:
		t.scenario("Bank availability and daily loan cap: " + access, 1)
		w = g.workers[0]
		w.bread = 2.0
		t.bed(Vector2i(30, 11))
		t.station("bench", Vector2i(34, 11))
		if access == "blueprint":
			t.materials(g.BANK_BLOCKS)
			g.place_building(p, "bank")
		elif access == "unreachable":
			t.bank(Vector2i(1, 1))
			g.terrain[Vector2i(1, 1)] = 0
			g.navigation.set_point_solid(Vector2i(1, 1), false)
		elif access == "open":
			t.bank(p)
			t.bank(Vector2i(34, 15))
		g.designate(ore, ore)
		g.simulate(3)
		t.near(g.portal.lent_bread, 10.0 if access == "open" else 0.0, "Only a reachable completed bank lends, capped at ten")
		g.simulate(40)
		t.check(w.earned_today > 0, "Loan availability never blocks paid work")

	# Prevent stopping on borrowed cash, missed delivery deductions, and overpaying the final installment.
	t.scenario("Loan repays from wages and deliveries, then stops charging", 1)
	t.bank(p)
	w = g.workers[0]
	w.bread = 9.03
	g.designate(Vector2i(37, 11), Vector2i(37, 15))
	t.advance_until(func(): return g.mined == 1, 30, "Worker eats and then works despite having funded daily needs")
	t.near(g.portal.lent_bread, 0.97, "Fractional shortfall determines principal")
	t.near(g.portal.repaid_principal, 0.25, "One bread of mining wages repays one quarter")
	t.advance_until(func(): return g.delivered == 1, 10, "Borrower delivers the mined block")
	t.near(g.portal.repaid_principal, 0.25, "Ore delivery creates neither bread nor extra repayment")
	t.advance_until(func(): return g.banks[p].interest_received >= 0.194 - 0.000001, 60, "One-time interest is fully paid")
	t.near(g.portal.repaid_principal, 0.97, "Principal returns to the portal exactly once")
	t.near(g.banks[p].interest_received, 0.194, "Only the twenty-percent interest reaches the player")
	t.near(g.player_bread + w.bread + w.eaten_today, g.STARTING_BREAD + 9.03, "Repayment transfers existing bread without duplicating it")
	t.near(w.bread, w.earned_today - 1.164, "Final installment is capped to the balance, with no lost income")
	earned = w.earned_today
	g.simulate(20)
	t.near(w.earned_today, earned, "Debt-free worker returns to normal daily stopping")
	t.materials(g.BED_BLOCKS)
	g.place_building(Vector2i(30, 11), "bed")
	g.simulate(8)
	t.check(w.earned_today > earned, "New daily need resumes work after repayment")
	t.near(g.portal.lent_bread, 0.97, "Repaying a loan does not permit another loan on the same day")
	t.near(g.banks[p].interest_received, 0.194, "New earnings are no longer withheld once the loan is paid")
	g.reset_world()
	t.check(g.banks.is_empty() and g.portal.lent_bread == 0 and g.portal.repaid_principal == 0, "Reset clears banks and loan accounting")

	# Prevent a loan from bypassing rent, sleep, or stock payments.
	t.scenario("Borrowed funds pay for rest and equipment normally", 1)
	t.bank(p)
	t.bed(Vector2i(30, 11))
	t.station("bench", Vector2i(34, 11), 1)
	w = g.workers[0]
	w.fatigue = 100.0
	g.designate(ore, ore)
	g.simulate(10)
	t.near(g.stock_at(Vector2i(30, 11), "bread"), g.BED_PRICE, "Exhausted borrower pays normal bed rent")
	t.check(w.fatigue < 90 and w.earned_today == 0, "Debt does not force an exhausted worker to labor")
	t.advance_until(func(): return w.gun_uses > 0, 65, "Recovered borrower can buy equipment with the remaining loan")
	t.near(g.stock_at(Vector2i(30, 11), "bread") + g.stock_at(Vector2i(34, 11), "bread"), g.BED_PRICE + g.GUN_PRICE, "Loan-funded services transfer their normal sale prices")
	t.check(g.benches[Vector2i(34, 11)].stock == 0, "Loan-funded purchase consumes stock once")
	check_tracks(t)
	check_mood(t)

func check_mood(t) -> void:
	var g = t.game
	var ore := Vector2i(37, 13)
	var p := Vector2i(28, 11)
	# The same output must cost actual paid time, including work slower than its nominal hours.
	for activity in ["mining", "building", "production"]:
		var times: Array[float] = []
		var wages: Array[float] = []
		for initial_mood in [-80.0, 0.0, 80.0]:
			t.scenario("Mood changes paid output speed: %s / %s" % [activity, initial_mood], 1)
			var w: Dictionary = g.workers[0]
			w.mood.value = initial_mood
			var complete: Callable
			if activity == "mining":
				g.designate(ore, ore)
				complete = func(): return g.mined == 1
			elif activity == "building":
				t.building_materials("bed")
				g.place_building(p, "bed")
				complete = func(): return g.beds.has(p)
			else:
				t.station("bench", p)
				g.add_stock(p, 2, 1)
				g.adjust_production(p, 1)
				complete = func(): return g.benches[p].stock == 1
			times.append(t.advance_until(complete, 60, "The ordered output completes at every mood level"))
			wages.append(w.earned_today)
			var labor: float = g.report_totals(1, 0)["挖掘" if activity == "mining" else "工作"]
			t.near(w.earned_today, labor / g.HOUR_SECONDS * g.WAGE_PER_HOUR, "Every actual labor hour is paid, even beyond nominal job cost", 0.01)
			t.near(g.player_bread + w.bread, g.STARTING_BREAD, "Mood changes neither wage ownership nor total bread")
			t.near(g.resource_activity("bread", 1).consumed, 0, "Wages are transfers rather than consumption")
		t.check(times[0] > times[1] and times[1] > times[2], "Low mood slows output and high mood accelerates it")
		t.check(wages[0] > wages[1] and wages[1] > wages[2], "Hourly pay follows time rather than a fixed per-job ceiling")

	# A real night's sleep must carry into tomorrow's work, not reward entering a bed.
	var excavation_times: Array[float] = []
	for comfort in [false, true]:
		t.scenario("Sleep experience carries into later work: " + str(comfort), 1)
		var w: Dictionary = g.workers[0]
		w.pos = Vector2(35, 13)
		w.bread = 5
		w.fatigue = 100
		if comfort:
			t.bed(Vector2i(35, 13))
		t.advance_until(func(): return w.fatigue == 0, 90, "Sleep restores physical fatigue without requiring a bed")
		t.check(w.mood.value > 25 if comfort else is_zero_approx(w.mood.value), "Only time actually asleep in bed creates positive mood")
		g.designate(ore, ore)
		excavation_times.append(t.advance_until(func(): return g.mined == 1, 20, "Rested worker returns to actual mining"))
		if comfort:
			t.near(w.bed_spent_today, g.BED_PRICE, "Mood recovery does not charge extra rent")
		t.check(w.fatigue > 0, "Good mood does not remove the need for physical rest")
	t.check(excavation_times[1] < excavation_times[0], "Good sleep leaves a useful memory after leaving the bed")

	t.scenario("Free recovery, independent newborns, and reset", 1)
	var w: Dictionary = g.workers[0]
	t.near(w.mood.value, 0, "New workers start emotionally neutral")
	w.mood.value = -60
	g.simulate(g.HOUR_SECONDS * 4)
	t.check(w.mood.value > -60 and w.mood.value < 0, "Waiting without money gradually recovers mood, not instantly")
	t.near(w.bread, 0, "Free recovery needs neither purchases nor loans")
	var newcomer: Dictionary = g.create_worker(g.BASE)
	t.near(newcomer.mood.value, 0, "A newcomer does not inherit another worker's experiences")
	g.reset_world()
	for person in g.workers:
		t.near(person.mood.value, 0, "Reset discards old emotional history")

func check_tracks(t) -> void:
	var g = t.game
	var source := Vector2i(36, 13)
	var ore := source + Vector2i.RIGHT
	var line: Array[Vector2i] = [source, Vector2i(35, 13), Vector2i(34, 13), Vector2i(33, 13), g.BASE]
	# Whole strokes either place once or leave materials and existing directions untouched.
	t.scenario("Track strokes charge only new cells", 1)
	t.materials(3)
	t.check(not g.place_belt_path(line) and g.player_blocks == 3, "An unaffordable stroke cannot partially spend materials")
	t.materials(4)
	var through_portal: Array[Vector2i] = [Vector2i(33, 13), g.BASE, Vector2i(31, 13)]
	t.check(not g.place_belt_path(through_portal) and g.player_blocks == 4, "Track cannot pass through the portal footprint")
	t.check(g.place_belt_path(line) and g.player_blocks == 0, "Portal endpoint is free; four track cells cost four blocks")
	t.check(g.place_belt_path(line) and g.player_blocks == 0, "Retracing blueprints does not charge twice")
	var invalid: Array[Vector2i] = [Vector2i(35, 13), Vector2i(35, 14), Vector2i(35, 15), Vector2i(35, 16)]
	t.check(not g.place_belt_path(invalid) and g.player_blocks == 0, "Unaffordable extension into ore leaves existing construction unchanged")
	t.check(not g.cancel_site(Vector2i(37, 13)) and g.player_blocks == 0, "A track occupies only its own cell")
	g.simulate(30)
	g.select_entity(source)
	t.check(g.entity_title.text == "矿道" and g.entity_details.text.contains("通往传送门"), "Workers complete a connected track without another material charge")
	t.check(g.remove_belt(Vector2i(35, 13)), "Empty completed track can be dismantled")
	t.advance_until(func(): return g.player_blocks == 1, 15, "Dismantled material returns by worker")
	g.select_entity(source)
	t.check(g.entity_details.text.contains("未连接传送门"), "Upstream inspector reflects a severed connection")

	# Adjacent endpoints are not a connection until the player explicitly joins their cells.
	t.scenario("Separate strokes join without rotating or spending twice", 1)
	g.workers[0].pos = Vector2(source)
	t.materials(4)
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
	t.scenario("Drag direction wins over proximity to the portal", 1)
	g.workers[0].pos = Vector2(source)
	t.materials(4)
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
	t.scenario("Direct track loading, transport fee, and report", 1)
	for cell in line.slice(0, 4):
		t.belt(cell, Vector2i.LEFT)
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
		t.scenario("Track fallback: " + route_kind, 1)
		t.belt(source, Vector2i.LEFT)
		if route_kind == "cycle":
			t.belt(Vector2i(35, 13), Vector2i.RIGHT)
		w = g.workers[0]
		w.pos = Vector2(source)
		g.designate(ore, ore)
		t.advance_until(func(): return g.delivered == 1, 30, "Worker walks the ore to the portal when the route is unusable")
		t.near(g.portal.freight_bread, 0, "Walking delivery does not charge transport")
		t.near(w.earned_today, 1, "Walking miner receives only labor wages")

	# Removing an empty downstream segment must preserve upstream cargo through midnight.
	t.scenario("Blocked cargo survives disconnection and resumes after rebuilding", 1)
	for cell in line.slice(0, 4):
		t.belt(cell, Vector2i.LEFT)
	t.belt(Vector2i(36, 14), Vector2i.ZERO)
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
	t.scenario("Two branches merge mixed ore and preserve ownership", 2)
	for x in range(33, 37):
		t.belt(Vector2i(x, 13), Vector2i.LEFT)
	t.belt(Vector2i(36, 12), Vector2i.DOWN)
	t.belt(Vector2i(36, 14), Vector2i.UP)
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
		t.scenario("Track backpack and unloading contention: " + str(shared), 2 if shared else 1)
		for cell in line.slice(0, 4):
			t.belt(cell, Vector2i.LEFT)
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
	t.scenario("Belt income repays a loan after freight", 1)
	t.bank(Vector2i(28, 11))
	for cell in line.slice(0, 4):
		t.belt(cell, Vector2i.LEFT)
	w = g.workers[0]
	w.pos = Vector2(source)
	w.bread = 9.0
	g.designate(ore, ore)
	t.advance_until(func(): return g.delivered == 1, 30, "Borrower delivers through the track")
	t.near(g.portal.repaid_principal, 0.25, "Loan takes 25 percent of labor wages, not mineral delivery")
	t.near(g.portal.freight_bread, 0.2, "Transport fee is separate from uncollected loan interest")
	g.reset_world()
	t.check(g.belts.is_empty() and g.belt_cargo.is_empty() and g.player_bread == g.STARTING_BREAD, "Reset clears tracks and restores only the finite starting supply")

func check_generated_terrain(t) -> void:
	var g = t.game
	# Prevent seeds being ignored or old water/mining edits leaking into a new world.
	t.scenario("Seeded material fields reproduce the same world", 1, true)
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
	t.scenario("Mine and inspect the generated world", 1, true)
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
	t.scenario("Distant geology is independent of exploration order", 0, true)
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
			if visited.has(start) or snapshot[start] == 1 or snapshot[start] >= 5:
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
			if snapshot[cell] >= 5:
				var isolated := true
				for direction in g.DIRS:
					var neighbor: Vector2i = cell + direction
					if area.has_point(neighbor) and snapshot[neighbor] >= 5:
						isolated = false
				t.check(isolated, "Special sources occupy isolated single cells rather than ordinary mineral fields")
	for material in range(8):
		t.check(counts.get(material, 0) > 0, "Exploration finds terrain category %d, including natural caves and scarce sources" % material)
	g.reset_world(1021)
	g.reset_world(1020)
	for i in range(areas.size() - 1, -1, -1):
		g.ensure_region(areas[i])
		t.check(map_snapshot(g, areas[i]) == snapshots[i], "Reversing discovery preserves the complete mineral, cave and water layout")

	# Negative coordinates, the former sentinel and the old right edge must all work.
	for target in [Vector2i(-33, -1), Vector2i(-1, -1), Vector2i(160, 13)]:
		t.scenario("Excavate and deliver beyond old map limits: " + str(target), 1)
		var left: int = mini(target.x, g.BASE.x) - 1
		var right: int = maxi(target.x, g.BASE.x) + 2
		var top: int = mini(target.y, g.BASE.y) - 1
		g.ensure_region(Rect2i(left, top, right - left, g.BASE.y - top + 3))
		t.clear_area(Rect2i(left, target.y + 1, right - left, 1))
		t.clear_area(Rect2i(g.BASE.x, top, 1, g.BASE.y - top + 3))
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
