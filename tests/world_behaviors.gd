extends RefCounted

const P := Vector2i(28, 11)

func run(t) -> void:
	check_starting_world(t)
	check_immigration(t)
	check_emigration(t)
	check_construction(t)
	check_cancellation(t)
	check_demolition(t)
	check_private_property(t)
	check_private_project_trade(t)
	check_trade_driven_investment(t)
	check_unworked_wild_food(t)
	check_barriers(t)
	check_lifecycle(t)
	check_snapshots(t)

func check_demolition(t) -> void:
	var g = t.game
	t.fixtures.scenario("Demolition is paid logistics labor and drops actual goods at the site")
	t.fixtures.station("mill", P)
	t.fixtures.stock_recipe(P, {"bread": 3, "wastewater": 2})
	g.world.storage_at(P).wastewater_load = 18.0
	t.fixtures.resident("operations", P + Vector2i.DOWN)
	t.check(g.demolish_building(P), "A completed building accepts a demolition order")
	g.simulate(1)
	t.check(g.world.has_building(P), "Residents with another ability cannot perform demolition")
	t.near(g.resource_inventory()[1], 0, "Marking demolition does not refund building materials")
	t.check(not g.place_building(P, "bed"), "Pending demolition keeps its physical footprint occupied")
	var pending: Dictionary = g.capture_snapshot()
	t.check(pending.ok and g.restore_snapshot(pending.data).ok, "Pending demolition and its original contents survive loading")
	t.check(g.cancel_site(P), "Demolition can be withdrawn before actual labor")
	t.check(g.world.has_building(P, "station"), "Withdrawing restores the original facility")
	t.near(g.stock_at(P, "bread"), 3, "Withdrawing does not duplicate or lose its goods")
	t.fixtures.scenario("Eligible residents dismantle facilities for wages and preserve local recovery")
	t.fixtures.station("mill", P)
	t.fixtures.stock_recipe(P, {"bread": 3, "wastewater": 2})
	g.world.storage_at(P).wastewater_load = 18.0
	t.fixtures.resident("building_logistics", P + Vector2i.RIGHT)
	t.check(g.demolish_building(P), "The facility accepts the demolition order")
	g.simulate(5)
	var working: Dictionary = g.capture_snapshot()
	t.check(working.ok and g.restore_snapshot(working.data).ok, "A resident's ongoing demolition and wage settlement can resume after loading")
	t.advance_until(func(): return not g.world.has_building(P), 120, "An eligible resident can take the demolition job and finish it")
	t.near(g.stock_at(P, "bread"), 3, "Finished demolition leaves contents on the local ground")
	t.near(g.stock_at(P, "wastewater"), 2, "Demolition preserves actual wastewater")
	t.near(g.world.storage_at(P).wastewater_load, 18, "Spilled wastewater retains its pollution load")
	for item in g.building_materials("mill"):
		t.near(g.stock_at(P, item), g.building_materials("mill")[item], "Recovered materials drop once at the site")
	t.near(g.stock_at(g.BASE, "bread"), 0, "Demolition does not automatically send contents to the starting point")
	var earnings := 0.0
	for person in g.world.workers: earnings += person.earned_today
	t.near(earnings, g.building_hours("mill") * 0.5 * g.WAGE_PER_HOUR, "Only completed demolition labor is paid at its locked wage")
	t.near(g.resource_inventory().money, g.STARTING_MONEY, "Demolition wages transfer existing currency without creating money")
	var dropped: Dictionary = g.capture_snapshot()
	t.check(dropped.ok and g.restore_snapshot(dropped.data).ok, "Ground recovery and completed wage settlement survive loading")

func check_lifecycle(t) -> void:
	var g = t.game
	t.fixtures.scenario("Death releases employment without giving personal property to the player")
	var elder: Dictionary = t.fixtures.resident("operations", P, "grain", {"wheat": 3})
	elder.age_days = 44.98
	elder.money = 3.0
	g.add_stock(g.BASE, "money", -3)
	t.fixtures.resident("operations", P + Vector2i.RIGHT)
	t.fixtures.station("workbench", P)
	t.advance_until(func(): return g.world.workers.size() == 1, 15, "The elderly resident reaches the existing lifespan boundary")
	t.near(g.player_inventory().wheat, 0, "Private remaining goods are not inherited by the player")
	t.near(g.resource_inventory().money, 600, "Death preserves personal money and returns only the employer purse")
	t.advance_until(func(): return g.stock_at(P, "workbench") == 1, 100, "Another eligible resident can fill the released vacancy and finish the real order")

func check_starting_world(t) -> void:
	var g = t.game
	g.reset_world(1020)
	var markets: Array = g.world.building_positions("station").filter(func(p): return g.is_built_market(p))
	t.check(g.building_kind(g.BASE) == "storage_box" and markets.size() == 1, "The opening adds an independent market beside the existing player opening")
	t.check(g.world.workers.size() == 8, "The new world contains the player camp's three residents and the five neighboring residents")
	for item in g.STARTING_GOODS:
		t.near(g.stock_at(g.BASE, item), g.STARTING_GOODS[item], "Opening goods are stored in the player's actual box")
	t.near(g.player_inventory().bread, g.STARTING_GOODS.bread, "Personal meals and the neighboring business's stock are excluded from player inventory")
	t.near(g.stock_at(g.BASE, "money"), g.STARTING_MONEY - g.STARTING_LOGISTICS_CASH, "The opening box holds the operating funds left after seeding the carrier wallet")
	t.check(not g.tile_details(g.BASE + Vector2i(18, 0)).is_empty() and g.tile_details(g.BASE + Vector2i(19, 0)).is_empty(), "Opening sight retains its physical radius")
	var starting_point: Vector2i = g.BASE
	var currency: float = g.resource_inventory().money
	if markets.size() == 1:
		t.check(not g.route(g.BASE, markets[0]).is_empty(), "The neighboring market is connected to the player camp by real land")
		t.check(not g.set_market_price(markets[0], "bread", 0), "The player cannot close a neighbor's bread listing")
	var opening: Dictionary = g.capture_snapshot()
	g.reset_world(0, false)
	t.check(opening.ok and g.restore_snapshot(opening.data).ok, "The opening residents and stocked box can be saved and restored")
	t.check(g.BASE == starting_point and g.world.workers.size() == 8, "Restoring does not duplicate initial residents or move their opening")
	t.near(g.resource_inventory().money, currency, "Restoring cannot duplicate the neighboring residents' cash")
	t.near(g.player_money, g.STARTING_MONEY - g.STARTING_LOGISTICS_CASH, "Restoring preserves the opening treasury separately from the carrier wallet")
	# The usual supplied opening must be able to draw visitors on its own.
	t.advance_until(func(): return g.world.migration_goods.get("bread", {}).get("arrived", 0.0) > 0.0,
		g.DAY_SECONDS * 4, "The generated opening attracts a resident through its actual living conditions")
	# Isolate the original camp's first vacancy from the neighboring jobs and skills.
	g.reset_world(1020, false)
	var skills: Array = g.world.workers.map(func(w): return w.skill)
	for skill in [g.WorkTypes.LOGISTICS, g.WorkTypes.FARMING, g.WorkTypes.MINING]:
		t.check(skills.count(skill) == 1, "The player camp supplies one resident with skill " + skill)
	g.ensure_region(Rect2i(Vector2i(128, 128), Vector2i(64, 64)))
	g.simulate(100)
	t.check(g.world.workers.size() == 3, "Loading terrain does not generate new residents")
	t.check(g.designate(g.BASE, g.BASE + Vector2i(6, 0)) == 0, "The old excavation command cannot create free mining labor")
	# A real market creates a durable operations vacancy after the opening builder finishes it.
	var target = null
	for cell in g.cache.visible_tiles:
		if g.building_space_valid(cell, "market") and (target == null or cell.distance_to(g.BASE) < target.distance_to(g.BASE)): target = cell
	t.check(target != null and g.place_building(target, "market"), "The player can plan the first market from the actual opening")
	if target == null: return
	t.advance_until(func(): return g.world.has_building(target, "station"), 240, "The opening builder supplies and builds the first market from the player box")
	t.near(g.player_inventory()[7], g.STARTING_GOODS[7] - g.building_materials("market")[7], "First construction consumes its wood exactly once")
	t.advance_until(func(): return g.world.workers.size() == 4, 360, "The new operations vacancy attracts the missing skill without a recruitment building")
	t.check(g.world.workers.any(func(w): return w.skill == g.WorkTypes.OPERATIONS), "The opening gains the skill needed to run its new market")
	t.near(g.resource_inventory().money, g.STARTING_MONEY, "Immigration does not charge or create local currency")

# These cases prevent blueprint spam, skill-blind arrivals, duplicate local recruitment,
# blocked-entry teleportation, and save/load replay of a regional arrival.
func check_immigration(t) -> void:
	var g = t.game
	t.fixtures.scenario("Only funded long-term jobs contribute to immigration", 0, false, 1021)
	t.fixtures.station("market", P)
	t.fixtures.station("mine", P + Vector2i(0, 4)) # No remaining deposit.
	g.set_wage(P, 0)
	g.place_building(P + Vector2i(0, 7), "bed") # Temporary and unfunded.
	g.simulate(g.DAY_SECONDS)
	t.check(g.world.workers.is_empty(), "Closed buildings, exhausted mines and temporary blueprints cannot create migration demand")
	g.set_wage(P, 2)
	g.simulate(g.HOUR_SECONDS)
	var pending: Dictionary = g.capture_snapshot()
	t.check(pending.ok, "A checkpoint can save the next migration draw")
	if not pending.ok: return
	g.simulate(g.HOUR_SECONDS * 2)
	t.check(g.world.workers.size() == 1, "A market vacancy can draw a resident within its first three hours")
	t.check(g.world.workers.any(func(w): return w.skill == g.WorkTypes.OPERATIONS), "The arriving resident matches the actual vacant job type")
	t.check(g.world.workers.any(func(w): return w.items.get("bread", 0) > 0), "An arrival brings private travel food")
	t.near(g.player_inventory().bread, 0, "Travel food is not donated to the player's building or market inventory")
	t.near(g.resource_inventory().money, g.STARTING_MONEY, "Arrival does not mint or consume coins")
	g.simulate(15)
	var observed: Dictionary = t.world_observations()
	t.check(g.restore_snapshot(pending.data).ok, "The migration checkpoint can be restored")
	g.simulate(g.HOUR_SECONDS * 2)
	t.check(g.world.workers.size() == 1, "Restoring replays the arrival without a duplicate")
	g.simulate(15)
	t.check(t.world_observations() == observed, "Arrival choice, life and accounting replay from the saved random state")
	g.simulate(g.DAY_SECONDS * 0.5)
	t.check(g.world.workers.size() == 1, "Once the vacancy is covered, the prior labor shortage does not keep drawing workers")

	t.fixtures.scenario("A posted wage without money creates no job-driven immigration")
	t.fixtures.station("market", P)
	g.add_stock(g.BASE, "money", -g.STARTING_MONEY)
	t.check(g.set_wage(P, 2), "The player can open a wage listing with an empty treasury")
	g.simulate(g.DAY_SECONDS * 2)
	t.check(g.world.workers.is_empty(), "An unfunded wage listing does not draw an outside worker into an empty region")

	t.fixtures.scenario("Good living conditions can attract a resident with zero vacancies")
	t.fixtures.resident("mining", g.BASE, "grain", {"bread": 12})
	t.advance_until(func(): return g.world.workers.size() > 1, g.DAY_SECONDS * 2, "An ordinarily comfortable resident can draw an adult without an open job")
	t.check(g.world.migration_goods.get("bread", {}).get("arrived", 0.0) > 0.0, "The additional resident entered with travel food through migration")

	t.fixtures.scenario("Local available skills are considered before bringing another resident")
	t.fixtures.station("market", P)
	t.fixtures.resident("operations", g.BASE)
	g.simulate(g.DAY_SECONDS)
	t.check(g.world.workers.size() == 1, "An existing eligible local covers the vacancy even before choosing to apply")

	t.fixtures.scenario("A resident with another skill does not cover an agricultural vacancy")
	t.fixtures.station("farm", P)
	t.fixtures.resident("mining", g.BASE)
	t.advance_until(func(): return g.world.workers.size() == 2, g.DAY_SECONDS * 2, "A farm can attract its missing farmer while waiting for real water")
	t.check(g.world.workers.filter(func(w): return w.skill == g.WorkTypes.FARMING).size() == 1, "Migration supplies the missing skill instead of another random specialization")

	t.fixtures.scenario("Blocked migration routes cannot teleport residents or store a population wave")
	t.fixtures.station("market", P)
	t.fixtures.resident("building_logistics", g.world.migration_entry + Vector2i(-2, 0), "grain", {"bread": 12})
	for direction in g.DIRS: t.fixtures.station("wall", g.world.migration_entry + direction)
	g.simulate(g.DAY_SECONDS)
	t.check(g.world.workers.size() == 1, "A disconnected entry prevents a resident from appearing at the workplace")
	var wall: Vector2i = g.world.migration_entry + Vector2i.LEFT
	t.check(g.demolish_building(wall), "The player can reopen the route through actual demolition")
	t.advance_until(func(): return not g.world.has_building(wall), 90, "The local builder dismantles the obstructing wall")
	t.advance_until(func(): return g.world.workers.size() == 2, g.DAY_SECONDS * 2, "Reopening the route allows a single matching arrival")
	g.simulate(1)
	t.check(g.world.workers.size() == 2, "A formerly blocked entry cannot release an accumulated wave")

# Sustained illness must eventually allow departure, without confiscating private
# belongings, consuming equipment, or taking unused employer money across the border.
func check_emigration(t) -> void:
	var g = t.game
	t.fixtures.scenario("Sustained poor life can lead to departure with private property and real wage settlement")
	t.fixtures.station("workbench", P)
	var resident: Dictionary = t.fixtures.resident("operations", P, "grain", {"bread": 24, "cloth": 3})
	resident.money = 7.0
	resident.pollution = 100.0
	resident.gun_uses = 10
	t.advance_until(func(): return resident.earned_today > 0, 120, "Actual work is paid before any departure is considered")
	g.simulate(g.DAY_SECONDS)
	t.check(g.world.workers.size() == 1, "A difficult start does not cause immediate departure")
	var saved: Dictionary = g.capture_snapshot()
	t.check(saved.ok and g.restore_snapshot(saved.data).ok, "Residence history and gradual dissatisfaction survive saving")
	var elapsed := 0.0
	var player_funds: float = g.player_money
	var total_funds: float = g.resource_inventory().money
	var private_funds := 0.0
	while not g.world.workers.is_empty() and elapsed < g.DAY_SECONDS * 4:
		player_funds = g.player_money
		total_funds = g.resource_inventory().money
		private_funds = g.world.workers[0].money
		g.simulate(0.1)
		elapsed += 0.1
	t.check(g.world.workers.is_empty(), "A resident can choose to walk out after persistent unresolved hardship")
	t.near(g.player_money, player_funds, "Departure returns the employer purse without taking or refunding earned wages")
	t.near(g.resource_inventory().money, total_funds - private_funds, "Only the departing resident's actual personal coins leave the region")
	t.near(g.player_inventory().cloth, 0, "Departing personal goods never become player recovery stock")
	t.near(g.resource_inventory().cloth, 0, "The resident takes their private goods instead of leaving an estate")
	t.near(g.resource_activity("bench", g.world.day).consumed, 0, "Departing equipment is not reported as locally consumed")
	var empty: Dictionary = g.capture_snapshot()
	t.check(empty.ok and g.restore_snapshot(empty.data).ok, "The completed departure and its released workplace survive loading")

	t.fixtures.scenario("A shortage of jobs cannot evict well-fed residents")
	var resident_ids: Array[int] = []
	for offset in [Vector2i.ZERO, Vector2i.DOWN]:
		var independent: Dictionary = t.fixtures.resident("mining", P + offset, "grain", {"bread": 24})
		resident_ids.append(independent.id)
	g.simulate(g.DAY_SECONDS * 6)
	t.check(resident_ids.all(func(id): return not g.world.worker(id).is_empty()), "Two well-fed residents who compete for the same jobs can both stay when their skill has no vacancies")

func check_construction(t) -> void:
	var g = t.game
	t.fixtures.scenario("Blueprint planning may exceed stock without changing physical delivery or consumption", 1)
	t.fixtures.fund_carrier(g.world.workers[0])
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
	t.fixtures.fund_carrier(g.world.workers[0])
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
	t.near(g.stock_at(g.BASE, 1), 0, "Cancelling an order leaves already purchased goods with the carrier")
	var replacement := P + Vector2i(0, 6)
	t.check(g.place_building(replacement, "bed"), "The player can publish a new order for the stranded cargo")
	t.advance_until(func(): return g.stock_at(replacement, 1) == 1, 90, "The carrier resells the purchased material to the new project")
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

func check_private_project_trade(t) -> void:
	var g = t.game
	var supplier := P + Vector2i(0, -3)
	for own_supply in [false, true]:
		var source := P + Vector2i(3, 0) if own_supply else supplier
		var owner: Dictionary = t.fixtures.private_building_trade(supplier, P, source if own_supply else null)
		var cash: float = g.resource_inventory().money
		var seller_cash: float = owner.money if own_supply else g.stock_at(source, "money")
		t.check(g.start_investment(P, "bed", owner.id, 4.0), "An accepted private investment places a normal blueprint")
		var stock: float = g.stock_at(source, 1)
		t.check(not g.cancel_site(P), "The player's zoning tool cannot cancel a resident's own project")
		t.advance_until(func(): return g.stock_at(source, 1) < stock, 60, "A trader pays for and collects actual warehouse stock")
		var seller_paid: float = owner.money if own_supply else g.stock_at(source, "money")
		t.check(seller_paid > seller_cash, "The supplying warehouse is paid at pickup for either ownership")
		t.near(g.stock_at(P, 1), 0.0, "Pickup does not yet transfer materials to the project")
		t.advance_until(func(): return g.world.has_building(P, "bed"), 180, "The second sale and paid construction complete the resident's facility")
		t.near(g.stock_at(source, 1), stock - 3.0, "The warehouse supplies exactly the actual shortage")
		t.near(g.resource_inventory().money, cash, "Private supplies and payroll conserve currency")
		t.check(not g.set_fee(P, 1.0) and not g.demolish_building(P), "Player commands cannot set private fees or demolish the private asset")

func check_trade_driven_investment(t) -> void:
	var g = t.game
	var farm := Vector2i(23, 14)
	var owner: int = t.fixtures.water_trade_investment(farm, Vector2i(32, 18))
	# Other positive-return projects may be selected before the pump.
	t.advance_until(func(): return g.world.buildings.values().any(func(b):
		return b.kind == "pump" and b.phase == g.Building.Phase.BUILT and is_same(b.state.get("owner"), owner)
	), g.DAY_SECONDS * 4, "An owner without a market can eventually build a pump for a real farm order")
	t.advance_until(func(): return g.resource_inventory().wheat > 0.0, g.DAY_SECONDS * 2,
		"The new workplace is staffed, produces water and sells a real farm input")

func check_barriers(t) -> void:
	var g = t.game
	for kind in ["wall", "door"]:
		t.fixtures.scenario("Specialized construction preserves physical passage: " + kind, 1)
		t.fixtures.fund_carrier(g.world.workers[0])
		t.fixtures.building_materials(kind)
		g.place_building(P, kind)
		t.advance_until(func(): return g.world.has_building(P, "station"), 90, "The enclosure blueprint completes using actual goods")
		t.check(g.world.walkable(P) == (kind == "door"), "Only a completed wall closes its footprint")
		t.check(g.demolish_building(P), "The player can demolish the completed enclosure")
		t.check(g.world.walkable(P) == (kind == "door"), "A demolition order keeps the existing physical passage rules")
		t.advance_until(func(): return not g.world.has_building(P), 90, "The enclosure disappears only after actual dismantling")
		t.check(g.world.walkable(P), "Completed demolition restores physical passage")
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
