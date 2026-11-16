extends RefCounted

const P := Vector2i(28, 11)

func run(t) -> void:
	check_starting_world(t)
	check_recruitment(t)
	check_construction(t)
	check_cancellation(t)
	check_private_property(t)
	check_unworked_wild_food(t)
	check_barriers(t)
	check_lifecycle(t)
	check_snapshots(t)

func check_lifecycle(t) -> void:
	var g = t.game
	t.fixtures.scenario("Death releases employment without giving personal property to the player")
	var elder: Dictionary = t.fixtures.resident("operations", P, "grain", {"wheat": 3})
	elder.age_days = 44.98
	elder.money = 3.0
	g.add_stock(g.BASE, "money", -3)
	t.fixtures.resident("operations", P + Vector2i.RIGHT)
	t.fixtures.station("workbench", P)
	g.adjust_production(P, 1)
	t.advance_until(func(): return g.world.workers.size() == 1, 15, "The elderly resident reaches the existing lifespan boundary")
	t.near(g.player_inventory().wheat, 0, "Private remaining goods are not inherited by the player")
	t.near(g.resource_inventory().money, 600, "Death preserves personal money and returns only the employer purse")
	t.advance_until(func(): return g.stock_at(P, "workbench") == 1, 100, "Another eligible resident can fill the released vacancy and finish the real order")

func check_starting_world(t) -> void:
	var g = t.game
	g.reset_world(1020)
	t.check(g.world.buildings.is_empty(), "Starting a new world does not grant a market or any other building")
	t.check(g.stock_at(g.BASE, "money") > 0 and g.player_inventory()[1] == 0 and g.player_inventory().berries == 0 and g.player_inventory().wheat == 0 and g.player_inventory().meat == 0, "The starting point keeps finite funds but no opening food or construction materials")
	t.check(g.world.workers.is_empty(), "A new world has no initial residents")
	t.near(g.stock_at(g.BASE, "money"), g.STARTING_MONEY, "Opening preserves actual funds without a prebuilt market")
	t.check(not g.tile_details(g.BASE + Vector2i(18, 0)).is_empty() and g.tile_details(g.BASE + Vector2i(19, 0)).is_empty(), "Starting sight reaches twice the former radius without requiring a building")
	var starting_point: Vector2i = g.BASE
	var opening: Dictionary = g.capture_snapshot()
	g.reset_world(0)
	t.check(opening.ok and g.restore_snapshot(opening.data).ok, "An unbuilt opening with loose funds can be saved and restored")
	t.near(g.player_money, g.STARTING_MONEY, "Restoring an unbuilt opening does not duplicate or lose the starting funds")
	t.check(g.BASE == starting_point and g.stock_at(starting_point, "money") == g.STARTING_MONEY, "Loading another world then restoring returns sight and loose funds to the saved random starting point")
	g.ensure_region(Rect2i(Vector2i(128, 128), Vector2i(64, 64)))
	g.simulate(100)
	t.check(g.world.workers.is_empty(), "Loading terrain or waiting without a recruitment board cannot generate residents")
	t.check(g.designate(g.BASE, g.BASE + Vector2i(6, 0)) == 0, "The old global excavation command cannot create free mining labor")

func check_recruitment(t) -> void:
	var g = t.game
	t.fixtures.scenario("Recruitment spends the configured fee from the board once per actual arrival", 0, false, 1020, false)
	t.check(g.place_building(P, "recruitment_board"), "Recruitment is available before research, without a free starting board")
	g.simulate(100)
	t.check(g.world.workers.is_empty(), "An unfunded or unfinished board cannot recruit residents")
	t.check(g.cancel_site(P), "The player can cancel the unfinished recruitment blueprint")
	t.fixtures.station("recruitment_board", P)
	t.fixtures.stock_recipe(P, {"money": 5})
	t.check(g.set_recruitment_cost(P, 3), "The player can set the completed board's recruitment fee")
	g.simulate(40)
	t.check(g.world.workers.is_empty(), "Recruitment is not instantaneous when construction finishes")
	t.near(g.stock_at(P, "money"), 5, "Waiting for a resident does not reserve or consume coins")
	var pending: Dictionary = g.capture_snapshot()
	t.check(pending.ok and g.restore_snapshot(pending.data).ok, "An unfinished recruitment interval can be saved and restored")
	g.simulate(51)
	t.check(g.world.workers.size() == 1, "A restored board attracts one resident after the remaining time, not a restarted interval")
	if not g.world.workers.is_empty():
		var newcomer: Dictionary = g.world.workers[0]
		t.check(not g.is_child(newcomer) and newcomer.skill in g.SKILLS and not newcomer.has("diet") and newcomer.employer == null, "New arrivals use ordinary independent adults without dietary restrictions")
	t.near(g.stock_at(P, "money"), 2, "The restored recruitment fee is charged exactly once from local stock")
	t.near(g.resource_inventory().money, g.STARTING_MONEY + 2, "Recruitment consumes coins instead of minting or transferring them")
	t.near(g.resource_activity("money", g.world.day).consumed, 3, "The resource report records the actual recruitment expense")
	var arrived: Dictionary = g.capture_snapshot()
	t.check(arrived.ok and g.restore_snapshot(arrived.data).ok, "An arrival can be saved without replaying recruitment")
	g.simulate(100)
	t.check(g.world.workers.size() == 1, "A restored board cannot recruit again without enough local coins")
	t.near(g.stock_at(g.BASE, "money"), g.STARTING_MONEY, "Recruitment never charges remote funds")
	t.check(g.set_recruitment_cost(P, 0), "Zero disables recruitment")
	g.simulate(100)
	t.check(g.world.workers.size() == 1 and g.stock_at(P, "money") == 2, "A disabled board cannot admit a waiting resident for free")
	t.check(g.set_recruitment_cost(P, 2), "A positive affordable fee reopens recruitment")
	g.simulate(0.1)
	t.check(g.world.workers.size() == 2 and g.stock_at(P, "money") == 0, "A waiting arrival uses the new fee and accepts exact funds")
	t.check(g.demolish_building(P), "Demolishing the board stops its recruitment")
	g.simulate(100)
	t.check(g.world.workers.size() == 2, "A removed board cannot continue attracting residents")

	t.fixtures.scenario("An enclosed recruitment entrance waits for a physically clear arrival cell")
	t.fixtures.station("recruitment_board", P)
	t.fixtures.stock_recipe(P, {"money": 1})
	for direction in g.DIRS: t.fixtures.station("wall", P + direction)
	g.simulate(180)
	t.check(g.world.workers.is_empty(), "Recruitment cannot place residents inside blocked cells")
	t.near(g.stock_at(P, "money"), 1, "Blocked arrivals never consume a recruitment fee")
	t.check(g.demolish_building(P + Vector2i.LEFT), "Opening a blocked arrival route uses normal demolition")
	g.simulate(0.1)
	t.check(g.world.workers.size() == 1, "A cleared entrance admits one waiting resident without a backlog burst")

func check_construction(t) -> void:
	var g = t.game
	t.fixtures.scenario("Blueprint planning may exceed stock without changing physical delivery or consumption", 1)
	t.fixtures.building_materials("bed", 2)
	t.check(g.place_building(P, "bed"), "A funded blueprint accepts the player command")
	t.near(g.stock_at(g.BASE, 1), 6, "Planning does not charge remote physical inventory")
	t.check(g.place_building(P + Vector2i(0, 3), "bed"), "A second blueprint accepts the player command")
	var extra := P + Vector2i(0, 6)
	t.check(g.place_building(extra, "bed"), "Outstanding recipes do not block planning beyond physical stock")
	t.check(g.cancel_site(extra), "An unsupplied excess blueprint can be cancelled")
	t.near(g.resource_inventory()[1], 6, "Cancelling an empty blueprint cannot refund its unfilled recipe")
	t.advance_until(func(): return g.world.building_positions("bed").size() == 2, 180, "A builder delivers actual materials and completes both projects")
	t.near(g.resource_inventory()[1], 0, "Completed construction consumes each recipe exactly once")
	t.near(g.world.workers[0].earned_today, 8, "Only the actual eight construction hours earn wages")
	t.near(g.resource_inventory().money, 600, "Wages transfer money without creating or consuming it")

func check_cancellation(t) -> void:
	var g = t.game
	t.fixtures.scenario("Cancelling a project recovers goods, not its unfilled recipe", 1)
	t.fixtures.stock_recipe(g.BASE, {1: 1})
	t.fixtures.station("storage_box", Vector2i(35, 11))
	t.fixtures.resident("building_logistics", Vector2i(35, 12))
	t.check(g.place_building(P, "bed"), "Partial stock does not prevent blueprint placement")
	t.advance_until(func(): return g.storage_contents(g.BASE).get(1, 0) < 1, 30, "The goods actually leave storage before cancellation, not just its available stock")
	t.near(g.stock_at(P, 1), 0, "The goods are still in transit when the player cancels")
	t.check(g.cancel_site(P), "The player can cancel a supplied or in-transit project")
	t.near(g.resource_inventory()[1], 1, "Cancellation cannot mint the undelivered part of the recipe")
	var redirected: Dictionary = g.capture_snapshot()
	t.check(redirected.ok and g.restore_snapshot(redirected.data).ok, "Redirecting picked goods preserves the shipment across saving")
	t.advance_until(func(): return g.stock_at(g.BASE, 1) == 1, 90, "Actual cancelled goods can be transported back")
	t.near(g.resource_inventory()[1], 1, "Recovery preserves the same physical material total")

func check_private_property(t) -> void:
	var g = t.game
	t.fixtures.scenario("Personal inventory is not player construction stock")
	var resident: Dictionary = t.fixtures.resident("building_logistics", g.BASE, "fruit", {1: 100})
	resident.money = 10.0
	var private_cash: float = resident.money
	t.check(g.place_building(P, "bed"), "A blueprint may be placed with no player construction stock")
	t.near(g.player_inventory()[1], 0, "Player inventory excludes private belongings")
	g.simulate(2)
	t.check(g.world.has_building(P, "site") and not g.world.has_building(P, "bed"), "Private material cannot supply or complete the player blueprint")
	t.near(resident.items.get(1, 0), 100, "Blueprint planning and supply cannot take private building materials")
	t.near(resident.money, private_cash, "An unsupplied project cannot draw wages or receive private funds")
	t.near(g.resource_inventory().money, 600 + private_cash, "Employment and waiting preserve actual currency")

func check_unworked_wild_food(t) -> void:
	var g = t.game
	var p := Vector2i(70, 30)
	t.fixtures.scenario("Residents do not produce food directly from reachable wild patches")
	for entry in [["berries", "farming", "fruit", P], ["wheat", "farming", "grain", P + Vector2i(2, 0)], ["meat", "farming", "meat", p]]:
		t.fixtures.wild(entry[3], entry[0])
		t.fixtures.resident(entry[1], entry[3], entry[2])
	g.update_fog()
	t.check(g.tile_details(p).is_empty(), "An unseen resource cannot be inspected")
	g.simulate(120)
	for item in ["berries", "wheat", "meat"]:
		t.near(g.resource_activity(item, 1).produced, 0, "A resident cannot directly harvest " + item)
	t.check(g.tile_details(p).is_empty(), "An independent resident does not reveal player fog")
	var before: int = g.world.workers.size()
	var new_region := p + Vector2i(64, 64)
	g.ensure_region(Rect2i(new_region, Vector2i.ONE))
	var count: int = g.world.workers.size()
	t.check(count == before, "New terrain cannot silently add residents independently of recruitment")
	g.ensure_region(Rect2i(new_region, Vector2i.ONE))
	t.check(g.world.workers.size() == count, "Revisiting an activated region does not regenerate residents")

func check_barriers(t) -> void:
	var g = t.game
	for kind in ["wall", "door"]:
		t.fixtures.scenario("Specialized construction preserves physical passage: " + kind, 1)
		t.fixtures.building_materials(kind)
		g.place_building(P, kind)
		t.advance_until(func(): return g.world.has_building(P, "station"), 90, "The enclosure blueprint completes using actual goods")
		t.check(g.world.walkable(P) == (kind == "door"), "Only a completed wall closes its footprint")
		t.check(g.demolish_building(P), "The player can demolish the completed enclosure")
		t.check(g.world.walkable(P), "Demolition restores physical passage")
		for item in g.building_materials(kind):
			t.near(g.resource_inventory()[item], g.building_materials(kind)[item], "Demolition recovers actual construction materials")

func check_snapshots(t) -> void:
	var g = t.game
	t.fixtures.scenario("Save and restore specialized production without duplicating goods")
	t.fixtures.resident("mining", P)
	t.fixtures.station("mine", P)
	t.fixtures.deposit(P, 2, 4)
	t.advance_until(func(): return g.stock_at(P, 2) >= 1, 70, "A mine produces before the checkpoint")
	var saved: Dictionary = g.capture_snapshot()
	t.check(saved.ok, "A running specialized world can be saved")
	if not saved.ok: return
	var observed: Dictionary = t.world_observations()
	g.simulate(5)
	var restored: Dictionary = g.restore_snapshot(saved.data)
	t.check(restored.ok, "The checkpoint restores ownership, finite resources and activities")
	if not restored.ok: return
	t.check(t.world_observations() == observed, "Restoring does not replay production, wages or needs")
	g.simulate(2)
	var nearby: Dictionary = t.world_observations()
	t.check(g.restore_snapshot(saved.data).ok, "The same checkpoint can be used from another camera position")
	g.world_view.camera.position = g.tile_center(g.BASE + Vector2i(128, -128))
	g.world_view.camera.zoom = Vector2.ONE * 2.2
	g.world_view.sync_dynamic()
	g.simulate(2)
	t.check(t.world_observations() == nearby, "Offscreen residents advance the same work, goods and payments")
	t.advance_until(func(): return g.stock_at(P, 2) == 4, 180, "Restored mining continues to its finite end")
	var path := "/tmp/law3-refactor-save.dat"
	t.check(g.save_game(path).ok, "The same checkpoint codec supports file saves")
	var before: Dictionary = t.world_observations()
	var damaged: PackedByteArray = saved.data.duplicate()
	damaged[damaged.size() - 1] ^= 1
	t.check(not g.restore_snapshot(damaged).ok, "A corrupt snapshot is rejected")
	t.check(t.world_observations() == before, "Rejected data cannot replace the live world")
	t.check(g.load_game(path).ok, "The persisted checkpoint remains readable")
