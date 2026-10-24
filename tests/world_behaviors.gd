extends RefCounted

func run(t) -> void:
	var g = t.game
	var ore := Vector2i(37, 13)
	var p := Vector2i(28, 11)
	t.scenario("Mine, deliver, reveal, cancel", 1)
	t.check(g.designate(Vector2i(60, 30), Vector2i(60, 30)) == 0, "Unexplored ore cannot be ordered")
	g.designate(ore, ore)
	t.advance_until(func(): return g.delivered == 1, 30, "Mining delivers a block to the portal")
	t.check(g.terrain[ore] == 0 and g.player_blocks == 1, "Delivered ore becomes open ground and building material")
	t.check(g.workers[0].bread > 0 and g.player_bread == 0, "Worker receives wages without inventing treasury income")
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
		g.player_blocks = cost
		g.workers[0].pos = Vector2(p)
		t.check(not g.place_building(g.BASE, kind) and g.player_blocks == cost, "Rejected placement costs nothing")
		t.check(g.place_building(p, kind) and g.player_blocks == 0, "Blueprint charges materials once")
		g.simulate(minf(8, g.building_hours(kind) * g.HOUR_SECONDS / 2))
		earned = g.workers[0].bread
		t.check(earned > 0, "Construction continues with empty inventory and pays labor")
		var footprint_end: Vector2i = g.building_cells(p, kind).back()
		t.check(g.cancel_site(footprint_end) and g.player_blocks == cost, "Occupied footprint cell can cancel and refund")
		t.near(g.workers[0].bread, earned, "Refund does not reclaim earned wages")
		g.place_building(p, kind)
		g.simulate(60)
		g.select_entity(footprint_end)
		t.check(g.entity_title.text == g.building_name(kind), "Building completes and can be inspected")
		t.check(g.player_blocks == 0, "No second charge during construction or completion")

	t.scenario("Water placement restrictions")
	g.player_blocks = 16
	t.check(not g.place_building(Vector2i(34, 11), "pump"), "Pump needs an adjacent water source")
	t.check(not g.place_building(Vector2i(29, 10), "bed"), "Water source cannot be covered")
	t.check(g.designate(Vector2i(29, 10), Vector2i(29, 10)) == 0 and g.player_blocks == 16, "Water cannot be mined and invalid placements cost nothing")

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
	g.player_blocks = 6
	g.place_bed(p)
	g.simulate(8)
	t.check(w.bread > 0, "New building needs bring a resting worker back to paid work")

	t.scenario("Assigned bed, exclusive rent, and recovery", 2)
	t.bed(p)
	g.assign_bed(p, 1)
	for worker in g.workers:
		worker.pos = Vector2(p)
		worker.bread = 10.0
		worker.fatigue = 100.0
	g.simulate(10)
	t.near(g.player_bread, 5, "Only the assigned occupant pays one rent")
	t.check(g.workers[0].bread == 10 and g.workers[1].bread == 5, "Other workers cannot rent the assigned bed")
	t.check(g.workers[1].fatigue < g.workers[0].fatigue, "Bed sleep recovers faster than ground sleep")
	g.simulate(25)
	t.near(g.player_bread, 5, "Continued sleep does not repeatedly charge rent")

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

	# Prevent unnecessary borrowing, oversized advances, and loans being counted as wages.
	for balance in [0.0, 7.0, 10.0]:
		t.scenario("Bank covers only the unpaid daily shortfall: " + str(balance), 1)
		t.bank(p)
		w = g.workers[0]
		w.bread = balance
		g.simulate(4)
		t.near(g.portal.lent_bread, 10.0 - balance, "Only the food shortfall is advanced")
		t.near(w.earned_today, 0, "Borrowed bread is not earned income")
		t.near(g.player_bread, 0, "Issuing principal does not create player revenue")
		t.check(w.hunger > 90, "Borrower can eat before earning wages")
		g.simulate(g.DAY_SECONDS)
		t.near(g.portal.lent_bread, 10.0 if balance == 10.0 else 10.0 - balance, "Unpaid loans survive midnight without a second advance")
		t.near(g.player_bread, 0, "Idle debt has no automatic deductions or late fees")

	# Prevent blueprints or unreachable banks from lending, while keeping mining available.
	for access in ["absent", "blueprint", "unreachable", "open"]:
		t.scenario("Bank availability and daily loan cap: " + access, 1)
		w = g.workers[0]
		w.bread = 2.0
		t.bed(Vector2i(30, 11))
		t.station("bench", Vector2i(34, 11))
		if access == "blueprint":
			g.player_blocks = g.BANK_BLOCKS
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
		g.simulate(5)
		t.check(w.earned_today > 0, "Loan availability never blocks paid work")

	# Prevent stopping on borrowed cash, missed delivery deductions, and overpaying the final installment.
	t.scenario("Loan repays from wages and deliveries, then stops charging", 1)
	t.bank(p)
	w = g.workers[0]
	w.bread = 9.03
	g.designate(ore, Vector2i(39, 13))
	t.advance_until(func(): return g.mined == 1, 30, "Worker eats and then works despite having funded daily needs")
	t.near(g.portal.lent_bread, 0.97, "Fractional shortfall determines principal")
	t.near(g.portal.repaid_principal, 0.25, "One bread of mining wages repays one quarter")
	t.advance_until(func(): return g.delivered == 1, 10, "Borrower delivers the mined block")
	t.near(g.portal.repaid_principal, 0.5, "Delivery income also repays one quarter")
	t.advance_until(func(): return g.player_bread >= 0.194 - 0.000001, 60, "One-time interest is fully paid")
	t.near(g.portal.repaid_principal, 0.97, "Principal returns to the portal exactly once")
	t.near(g.player_bread, 0.194, "Only the twenty-percent interest reaches the player")
	t.near(g.banks[p].interest_received, g.player_bread, "Bank receipts match actual interest income")
	t.near(w.bread, w.earned_today - 1.164, "Final installment is capped to the balance, with no lost income")
	earned = w.earned_today
	g.simulate(20)
	t.near(w.earned_today, earned, "Debt-free worker returns to normal daily stopping")
	g.player_blocks = g.BED_BLOCKS
	g.place_bed(Vector2i(30, 11))
	g.simulate(8)
	t.check(w.earned_today > earned, "New daily need resumes work after repayment")
	t.near(g.portal.lent_bread, 0.97, "Repaying a loan does not permit another loan on the same day")
	t.near(g.player_bread, 0.194, "New earnings are no longer withheld once the loan is paid")
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
	t.near(g.player_bread, g.BED_PRICE, "Exhausted borrower pays normal bed rent")
	t.check(w.fatigue < 90 and w.earned_today == 0, "Debt does not force an exhausted worker to labor")
	t.advance_until(func(): return w.gun_uses > 0, 65, "Recovered borrower can buy equipment with the remaining loan")
	t.near(g.player_bread, g.BED_PRICE + g.GUN_PRICE, "Loan-funded services transfer their normal sale prices")
	t.check(g.benches[Vector2i(34, 11)].stock == 0, "Loan-funded purchase consumes stock once")
	check_tracks(t)

func check_tracks(t) -> void:
	var g = t.game
	var source := Vector2i(36, 13)
	var ore := source + Vector2i.RIGHT
	var line: Array[Vector2i] = [source, Vector2i(35, 13), Vector2i(34, 13), Vector2i(33, 13), g.BASE]
	# Whole strokes either place once or leave materials and existing directions untouched.
	t.scenario("Track strokes charge only new cells", 1)
	g.player_blocks = 3
	t.check(not g.place_belt_path(line) and g.player_blocks == 3, "An unaffordable stroke cannot partially spend materials")
	g.player_blocks = 4
	var through_portal: Array[Vector2i] = [Vector2i(33, 13), g.BASE, Vector2i(31, 13)]
	t.check(not g.place_belt_path(through_portal) and g.player_blocks == 4, "Track cannot pass through the portal footprint")
	t.check(g.place_belt_path(line) and g.player_blocks == 0, "Portal endpoint is free; four track cells cost four blocks")
	t.check(g.place_belt_path(line) and g.player_blocks == 0, "Retracing blueprints does not charge twice")
	var invalid: Array[Vector2i] = [Vector2i(35, 13), Vector2i(35, 14), Vector2i(35, 15), Vector2i(35, 16)]
	t.check(not g.place_belt_path(invalid) and g.player_blocks == 0, "Stroke into solid terrain leaves existing construction unchanged")
	t.check(not g.cancel_site(Vector2i(37, 13)) and g.player_blocks == 0, "A track occupies only its own cell")
	g.simulate(30)
	g.select_entity(source)
	t.check(g.entity_title.text == "矿道" and g.entity_details.text.contains("通往传送门"), "Workers complete a connected track without another material charge")
	t.check(g.remove_belt(Vector2i(35, 13)) and g.player_blocks == 1, "Empty completed track can be dismantled for its material")
	g.select_entity(source)
	t.check(g.entity_details.text.contains("未连接传送门"), "Upstream inspector reflects a severed connection")

	# Adjacent endpoints are not a connection until the player explicitly joins their cells.
	t.scenario("Separate strokes join without rotating or spending twice", 1)
	g.workers[0].pos = Vector2(source)
	g.player_blocks = 4
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
	t.near(g.player_bread, 0.2, "Connected-stroke delivery charges freight once")

	# The portal must not silently reverse the direction chosen by the player's stroke.
	t.scenario("Drag direction wins over proximity to the portal", 1)
	g.workers[0].pos = Vector2(source)
	g.player_blocks = 4
	var outward: Array[Vector2i] = [Vector2i(33, 13), Vector2i(34, 13), Vector2i(35, 13), source]
	g.place_belt_path(outward)
	g.simulate(20)
	g.designate(ore, ore)
	t.advance_until(func(): return g.delivered == 1, 30, "Outward-facing track leaves the worker to walk the ore home")
	t.near(g.player_bread, 0, "An adjacent portal does not make a backward track usable")
	t.check(g.place_belt_path(line) and g.player_blocks == 1, "A reverse stroke reconnects existing empty tracks without another charge")
	g.designate(ore + Vector2i.RIGHT, ore + Vector2i.RIGHT)
	t.advance_until(func(): return g.delivered == 2, 30, "Reversed track carries the next real excavation home")
	t.near(g.player_bread, 0.2, "Only the correctly directed trip pays freight")

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
	t.near(g.player_bread, 0, "Loading does not charge transport fees")
	t.check(g.report_mined(1, 0) == 1, "Track delivery does not replace excavation reporting")
	t.advance_until(func(): return g.delivered == 1, 5, "Conveyor delivers the ore to the portal")
	t.near(w.earned_today, 1.8, "Ore owner receives the exchange value minus one transport fee")
	t.near(g.player_bread, 0.2, "Player receives exactly one transport fee")
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
		t.near(g.player_bread, 0, "Walking delivery does not charge transport")
		t.near(w.earned_today, 2, "Walking miner keeps the full exchange income")

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
	t.near(g.player_bread, 0, "Blocked ore never earns a fee")
	var reconnect: Array[Vector2i] = [Vector2i(35, 13), Vector2i(34, 13), Vector2i(33, 13)]
	t.check(g.place_belt_path(reconnect), "Refunded material can reconnect the gap")
	t.advance_until(func(): return g.delivered == 1, 15, "Rebuilt route resumes transport without mining the block again")
	t.near(g.player_bread, 0.2, "Resumed cargo pays once")
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
	g.simulate(5)
	t.check(g.delivered == 2 and g.portal.input_blocks.get(1, 0) == 1 and g.portal.input_blocks.get(2, 0) == 1, "Merged line delivers both original ore types once")
	for worker in g.workers:
		t.near(worker.earned_today, 0.8, "Each owner receives only their own ore payment")
	t.near(g.player_bread, 0.4, "Merged deliveries charge two fees")

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
		t.near(income, g.delivered, "Walking and belt deliveries together conserve the exchange proceeds")

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
	t.near(g.portal.repaid_principal, 0.45, "Loan takes 25 percent of one wage plus 0.8 net delivery")
	t.near(g.player_bread, 0.2, "Transport fee is separate from uncollected loan interest")
	g.reset_world()
	t.check(g.belts.is_empty() and g.belt_cargo.is_empty() and g.player_bread == 0, "Reset clears tracks, cargo, and freight receipts")
