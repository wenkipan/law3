extends RefCounted

const P := Vector2i(28, 11)
const OTHER := Vector2i(31, 11)
const INPUT_ROUTES := [
	{"source": "farm", "target": "mill", "item": "wheat", "amount": 4},
	{"source": "pump", "target": "farm", "item": "raw_water", "amount": 4},
	{"source": "pump", "target": "purifier", "item": "raw_water", "amount": 4},
]

func run(t) -> void:
	var g = t.game
	for kind in ["bench", "workbench", "pump", "purifier", "farm", "mill"]:
		t.scenario("Recurring output: " + kind, 1)
		t.station(kind, P)
		if kind == "bench":
			t.materials(2, 2)
		if kind == "mill":
			g.add_stock(g.BASE, "wheat", 8)
		g.workers[0].water = 4
		if kind in ["purifier", "farm"]:
			t.station("pump", OTHER, 12)
		g.adjust_production(P, 1)
		var amount: int = g.PRODUCTS[kind].get("amount", 1)
		g.simulate(70)
		t.check(g.benches[P].stock == amount, "One daily batch is produced")
		g.simulate(30)
		t.check(g.benches[P].stock == amount, "Daily target does not repeat within the day")
		g.simulate(g.DAY_SECONDS)
		t.check(g.benches[P].stock == amount * 2, "Tomorrow produces again without another order")
		g.select_entity(P)
		t.check(g.get_node("UI").queue_count.text == "每日产出 %d%s" % [amount, g.PRODUCTS[kind].unit], "Daily setting persists in the inspector")
		t.near(g.workers[0].bread, g.PRODUCTS[kind].hours * 2, "Wages cover actual production only")
		g.adjust_production(P, -1)
		g.simulate(g.DAY_SECONDS)
		t.check(g.benches[P].stock == amount * 2, "Zero output stops production across days")
		if kind in ["purifier", "farm"]:
			t.check(g.benches[OTHER].stock == 4, "Raw water is charged once per completed batch")
		elif kind == "bench":
			t.check(g.materials.get(2, 0) == 0, "Each produced gun consumes one copper ore")
			g.adjust_production(P, 1)
			var earned: float = g.workers[0].bread
			g.simulate(g.DAY_SECONDS)
			g.select_entity(P)
			t.check(g.benches[P].stock == 2 and g.entity_details.text.contains("等待铜矿"), "An unfunded daily gun order waits for copper")
			t.near(g.workers[0].bread, earned, "No copper means no idle production wages")
			g.designate(Vector2i(27, 13), Vector2i(27, 13))
			g.simulate(45)
			t.check(g.benches[P].stock == 3 and g.materials.get(2, 0) == 0, "Mining copper resumes the existing daily order")

	t.scenario("Water chain and no backlog", 1)
	t.station("pump", P)
	t.station("purifier", OTHER)
	g.adjust_production(OTHER, 1)
	g.simulate(g.DAY_SECONDS * 2)
	g.select_entity(OTHER)
	t.check(g.entity_details.text.contains("等待原水") and g.benches[OTHER].stock == 0, "Missing raw water waits instead of creating output")
	t.near(g.workers[0].bread, 0, "Waiting for materials pays no wages")
	g.adjust_production(P, 3)
	g.simulate(45)
	t.check(g.benches[OTHER].stock == 4 and g.benches[P].stock == 8, "Missed days do not accumulate catch-up batches")

	t.scenario("Paid batch survives sleep, zero target, and midnight", 1)
	t.station("pump", P, 4)
	t.station("purifier", OTHER)
	g.workers[0].fatigue = 95.0
	g.simulate(g.DAY_SECONDS - 3)
	g.adjust_production(OTHER, 1)
	t.advance_until(func(): return g.workers[0].earned_today > 0, 12, "Delivered water allows paid production to begin")
	g.adjust_production(OTHER, -1)
	g.simulate(120)
	t.check(g.day == 2 and g.benches[OTHER].stock == 4, "Already-paid batch completes after midnight despite zero target")
	t.near(g.workers[0].bread, 1, "Finished batch pays exactly one work hour")
	t.check(g.report_totals(2)["睡觉"] > 0, "Exhausted operator slept before resuming the paid batch")
	g.simulate(20)
	t.check(g.benches[OTHER].stock == 4, "Finished batch does not restart")

	t.scenario("Overnight output counts on its completion day", 1)
	t.station("bench", P)
	t.materials(2, 2)
	g.simulate(g.DAY_SECONDS - 5)
	g.adjust_production(P, 1)
	g.simulate(45)
	t.check(g.day == 2 and g.benches[P].stock == 1, "Midnight does not duplicate an unfinished daily batch")
	g.adjust_production(P, 1)
	g.simulate(25)
	t.check(g.benches[P].stock == 2, "Increasing target makes only the missing output")

	# Competing destinations must not reserve, carry, or consume the same batch twice.
	for entry in INPUT_ROUTES:
		t.scenario("Competing local recipes: " + entry.target)
		var source: Vector2i = g.BASE if entry.source == "" else P
		if entry.source != "":
			t.station(entry.source, source)
		g.add_stock(source, entry.item, entry.amount)
		t.station(entry.target, OTHER)
		var second := Vector2i(34, 11)
		t.station(entry.target, second)
		g.adjust_production(OTHER, 1)
		g.adjust_production(second, 1)
		g.simulate(90)
		var amount: int = g.PRODUCTS[entry.target].amount
		t.check(g.benches[OTHER].produced_today + g.benches[second].produced_today == amount, "One shared input batch produces only one batch across competing buildings")
		t.near(g.stock_at(source, entry.item), 0, "Delivered ingredients leave their source exactly once")

	t.scenario("Printing is finite, material-limited, and adds a working person")
	t.station("printer", P)
	t.station("printer", OTHER)
	g.adjust_production(P, 1)
	g.adjust_production(OTHER, 1)
	g.simulate(8)
	t.check(g.workers.size() == 3 and g.workers[0].bread == 0, "No ore means no new person or idle wages")
	t.materials(10)
	t.advance_until(func(): return g.workers.size() == 4, 45, "Available ore prints one worker")
	var born_at: float = g.day_elapsed
	g.simulate(10)
	t.check(g.workers.size() == 4 and g.player_blocks == 0, "Competing printer cannot reuse spent ore")
	t.near(t.report_seconds(3), g.day_elapsed - born_at, "New worker has no report time before birth", 0.11)
	# A second player order is already waiting; earned mining material supplies it.
	g.designate(Vector2i(37, 11), Vector2i(37, 15))
	g.simulate(30)
	t.check(g.delivered > 0 and g.workers[3].bread > 0, "Printed worker joins real paid mining")
	g.adjust_production(OTHER, -1)
	g.adjust_production(P, -1)
	g.simulate(g.DAY_SECONDS)
	t.check(g.workers.size() == 4, "Printing does not automatically recur tomorrow")

	t.scenario("Finite printing with enough materials for another worker", 1)
	t.station("printer", P)
	t.materials(20)
	g.adjust_production(P, 1)
	g.simulate(g.DAY_SECONDS + 40)
	t.check(g.workers.size() == 2 and g.player_blocks == 10, "One order creates only one person even with tomorrow's materials available")

	# Reservations and carried goods are not local inputs; stopped orders retain delivered material.
	for entry in INPUT_ROUTES:
		t.scenario("Actual material arrival: " + entry.target, 0)
		var source: Vector2i = g.BASE if entry.source == "" else P
		if entry.source != "":
			t.station(entry.source, source)
		t.station(entry.target, OTHER)
		g.add_stock(source, entry.item, 1024 + entry.amount)
		g.adjust_production(OTHER, 1)
		g.simulate(30)
		t.check(g.stock_at(OTHER, entry.item) == 0 and g.benches[OTHER].produced_today == 0, "Without workers, a stocked remote warehouse cannot supply a recipe")
		g.create_worker(Vector2i(36, 15))
		g.simulate(0.5)
		g.select_entity(source)
		t.check(g.entity_details.text.contains("%s  %s" % [g.item_name(entry.item), String.num(1024 + entry.amount, 1)]), "Reserved goods remain visible in their source warehouse until pickup")
		var carried := "搬运  %s × %s" % [g.item_name(entry.item), String.num(entry.amount, 1)]
		t.advance_until(func():
			g.select_worker(0)
			return g.entity_details.text.contains(carried), 10, "Worker visibly carries the actual ingredient after visiting its source")
		t.check(g.stock_at(OTHER, entry.item) == 0 and g.benches[OTHER].produced_today == 0, "Ingredients in transit cannot be consumed at the destination")
		t.near(g.resource_inventory()[entry.item], 1024 + entry.amount, "Inventory includes transported material exactly once")
		t.near(g.resource_activity(entry.item, g.day).consumed, 0, "Reservation and transport are not consumption")
		t.near(g.stock_at(source, entry.item), 1024, "Pickup preserves the source's remaining stock without a capacity limit")
		g.adjust_production(OTHER, -1)
		t.advance_until(func(): return g.stock_at(OTHER, entry.item) == entry.amount, 10, "Stopping production still lets the carried goods arrive in the local warehouse")
		t.near(g.workers[0].earned_today, 0, "No production wages are paid while inputs are traveling or the order is stopped")
		g.adjust_production(OTHER, 1)
		var amount: int = g.PRODUCTS[entry.target].amount
		t.advance_until(func(): return g.benches[OTHER].produced_today == amount, 90, "Resuming consumes the delivered local batch and produces output")
		t.near(g.stock_at(OTHER, entry.item), 0, "The local recipe consumes its ingredients once")
		t.near(g.stock_at(source, entry.item), 1024, "Resuming does not fetch or consume a second batch from elsewhere")
		t.near(g.workers[0].earned_today, g.PRODUCTS[entry.target].hours, "Only actual production earns the configured wages")
		t.near(g.resource_activity(entry.item, g.day).consumed, entry.amount, "Only the local recipe records material consumption")
		t.near(g.resource_activity(g.product_item(entry.target), g.day).produced, amount, "Completed output is recorded on the day it is produced")
		t.near(g.resource_activity("bread", g.day).consumed, 0, "Wage transfers are not food consumption")
		t.near(g.resource_inventory()[entry.item], 1024, "Consumed ingredients disappear from total physical inventory")
		var yesterday: Dictionary = g.resource_activity(entry.item, g.day)
		g.adjust_production(OTHER, -1)
		g.simulate(g.DAY_SECONDS - g.day_elapsed)
		t.check(g.resource_activity(entry.item, g.day - 1) == yesterday, "Yesterday's material use survives the midnight rollover")
		t.near(g.resource_activity(entry.item, g.day).consumed, 0, "The new day starts with no phantom material use")

	check_track_deliveries(t)

	# Harvest leaves a reusable field, and a second day repeats the complete chain.
	t.scenario("Pump, renewable field, and mill supply one another", 1)
	t.station("pump", OTHER)
	t.station("farm", P)
	var mill := Vector2i(34, 11)
	t.station("mill", mill)
	g.adjust_production(OTHER, 1)
	g.adjust_production(P, 1)
	g.adjust_production(mill, 1)
	t.advance_until(func(): return g.benches[mill].produced_today == 16, 120, "Raw water is carried to the field and harvested wheat to the mill")
	t.check(g.benches.has(P) and g.stock_at(P, "wheat") == 4, "Harvest preserves the field and remaining wheat")
	g.simulate(g.DAY_SECONDS - g.day_elapsed + 120)
	t.check(g.benches[P].produced_today == 8 and g.benches[mill].produced_today == 16, "The same field grows another harvest without rebuilding")

	# A wired light shortens only the unattended portion of a reusable farm batch.
	t.scenario("Powered grow light accelerates farm growth", 3)
	var plant := Vector2i(28, 11)
	var transformer := Vector2i(32, 11)
	var light := Vector2i(37, 11)
	var field := Vector2i(37, 15)
	t.station("power_plant", plant)
	t.station("transformer", transformer)
	t.station("grow_light", light)
	t.station("farm", field)
	for origin in [plant, transformer, light, field]:
		for cell in g.building_cells(origin, g.building_kind(origin)):
			g.terrain[cell] = 0
			g.navigation.set_point_solid(cell, false)
			g.world_view.block_changed(cell)
	g.workers[0].pos = Vector2(field)
	g.add_stock(plant, 3, 2)
	g.add_stock(field, "raw_water", 4)
	g.power_lines[Vector2i(30, 10)] = {"kind": "high_line", "materials": {2: 2}}
	for x in range(34, 37):
		g.power_lines[Vector2i(x, 11)] = {"kind": "low_line", "materials": {2: 1}}
	g.adjust_production(field, 1)
	t.advance_until(func(): return g.benches[field].stock == 8, 65, "The connected light powers while the operator works and the field grows")
	t.check(g.stock_at(plant, 3) < 2 and g.benches[field].stock == 8, "Actual crop growth is faster and coal use follows the 200W load")

	t.scenario("Powered fountains restore fatigue without stacking", 3)
	plant = Vector2i(28, 11)
	transformer = Vector2i(32, 11)
	t.station("power_plant", plant)
	t.station("transformer", transformer)
	var fountain_a := Vector2i(37, 11)
	var fountain_b := Vector2i(39, 11)
	t.station("fountain", fountain_a)
	t.station("fountain", fountain_b)
	for origin in [plant, transformer, fountain_a, fountain_b]:
		for cell in g.building_cells(origin, g.building_kind(origin)):
			g.terrain[cell] = 0
			g.navigation.set_point_solid(cell, false)
			g.world_view.block_changed(cell)
	g.workers[2].pos = Vector2(38, 12)
	g.workers[2].fatigue = 50.0
	g.add_stock(plant, 3, 2)
	g.power_lines[Vector2i(30, 10)] = {"kind": "high_line", "materials": {2: 2}}
	for x in range(34, 39):
		g.power_lines[Vector2i(x, 11)] = {"kind": "low_line", "materials": {2: 1}}
	t.advance_until(func(): return g.workers[2].fatigue < 50.0, 12, "A connected fountain begins restoring fatigue")
	var fatigue_start: float = g.workers[2].fatigue
	g.simulate(20)
	t.near(g.workers[2].fatigue, fatigue_start - 5.0 * 20.0 / g.HOUR_SECONDS, "Powered fountains restore five fatigue per hour even when their ranges overlap", 0.2)

	t.scenario("Powered drill opens dense ore to ordinary excavation orders", 3)
	plant = Vector2i(28, 11)
	transformer = Vector2i(32, 11)
	var drill := Vector2i(37, 11)
	var dense_ore := Vector2i(37, 14)
	t.station("power_plant", plant)
	t.station("transformer", transformer)
	t.station("drill", drill)
	g.create_worker(g.BASE + Vector2i(0, 2))
	for origin in [plant, transformer, drill]:
		for cell in g.building_cells(origin, g.building_kind(origin)):
			g.terrain[cell] = 0
			g.navigation.set_point_solid(cell, false)
			g.world_view.block_changed(cell)
	g.add_stock(plant, 3, 4)
	g.power_lines[Vector2i(30, 10)] = {"kind": "high_line", "materials": {2: 2}}
	for x in range(34, 37):
		g.power_lines[Vector2i(x, 11)] = {"kind": "low_line", "materials": {2: 1}}
	g.workers[0].pos = Vector2(plant)
	g.workers[1].pos = Vector2(transformer)
	g.workers[2].pos = Vector2(drill)
	g.workers[3].pos = Vector2(dense_ore + Vector2i.LEFT)
	g.terrain[dense_ore + Vector2i.LEFT] = 0
	g.navigation.set_point_solid(dense_ore + Vector2i.LEFT, false)
	g.terrain[dense_ore] = 5
	g.navigation.set_point_solid(dense_ore, true)
	g.world_view.block_changed(dense_ore)
	g.designate(dense_ore, dense_ore)
	t.advance_until(func(): return g.stock_at(g.BASE, 5) >= 1, 150, "A powered, staffed drill lets a miner recover dense copper")
	t.check(g.delivered == 1 and g.resource_inventory()[5] >= 1, "Dense ore becomes a real deliverable mineral, not decorative terrain")

	if t.native:
		t.scenario("Food buildings and growing field in the native viewport")
		t.station("farm", P)
		t.station("pump", OTHER)
		t.station("mill", mill)
		for position in [P, OTHER, mill]:
			g.adjust_production(position, 1)
		g.simulate(35)
		for size in [Vector2i(1440, 900), Vector2i(960, 640)]:
			t.root.size = size
			await t.settle()
			await t.click_world(g.tile_center(P + Vector2i.RIGHT))
			t.check(g.entity_title.text == "农田" and g.entity_details.text.contains("生长"), "The planted field opens live growth and storage details")
			t.check(t.root.get_visible_rect().encloses(g.entity_panel.get_global_rect()), "Food inspector fits the viewport")
			await RenderingServer.frame_post_draw
			t.root.get_texture().get_image().save_png("/tmp/law3-food-%d.png" % size.x)

func check_track_deliveries(t) -> void:
	var g = t.game
	# The same delivery contract must work for every ingredient, including a multi-unit load.
	for entry in INPUT_ROUTES:
		t.scenario("Track supplies local recipe: " + entry.target, 1)
		var source: Vector2i = g.BASE if entry.source == "" else P
		if entry.source != "":
			t.station(entry.source, source)
		t.station(entry.target, OTHER)
		g.add_stock(source, entry.item, entry.amount)
		g.workers[0].pos = Vector2(source)
		for x in range(29, 33):
			t.belt(Vector2i(x, 12), Vector2i.RIGHT if x < 32 else Vector2i.ZERO)
		var connection: Array[Vector2i] = [Vector2i(32, 12), OTHER + Vector2i.RIGHT]
		t.check(g.place_belt_path(connection) and g.player_blocks == (entry.amount if entry.item is int else 0), "Connecting the receiver's second footprint cell costs no extra track or building materials")
		g.select_entity(Vector2i(29, 12))
		t.check(g.entity_details.text.contains("通往" + g.building_name(entry.target)), "Upstream track identifies its receiving production building")
		g.adjust_production(OTHER, 1)
		t.advance_until(func(): return track_shows_item(g, entry.item), 10, "Worker loads the requested ingredient onto a track to its receiver")
		t.near(g.stock_at(OTHER, entry.item), 0, "Track cargo is not available to the receiving recipe before arrival")
		t.near(g.resource_inventory()[entry.item], entry.amount, "Reserved track cargo appears in total inventory exactly once")
		t.near(g.resource_activity(entry.item, g.day).consumed, 0, "Loading a track is not material consumption")
		g.adjust_production(OTHER, -1)
		t.advance_until(func(): return g.stock_at(OTHER, entry.item) == entry.amount, 5, "Track unloads the whole batch into a stopped building's local box")
		t.near(g.stock_at(source, entry.item), 0, "Delivered goods leave their source once")
		t.near(g.resource_inventory()[entry.item], entry.amount, "Arrival preserves the physical inventory")
		g.adjust_production(OTHER, 1)
		t.advance_until(func(): return g.benches[OTHER].produced_today == g.PRODUCTS[entry.target].amount, 90, "The receiver consumes its track-delivered batch and produces normally")
		t.near(g.resource_activity(entry.item, g.day).consumed, entry.amount, "Only production consumes the delivered ingredient")
		t.near(g.stock_at(OTHER, entry.item), 0, "Track cargo cannot be delivered or consumed twice")

	# A downstream rewire must never deliver an already-reserved batch to the wrong building.
	t.scenario("In-flight ingredient retains its intended receiver after rewiring", 1)
	t.station("farm", P, 8)
	var receiver := Vector2i(34, 11)
	var wrong := Vector2i(34, 13)
	t.station("mill", receiver)
	t.station("mill", wrong)
	g.workers[0].pos = Vector2(P)
	for x in range(29, 36):
		t.belt(Vector2i(x, 12), Vector2i.RIGHT if x < 35 else Vector2i.UP)
	g.adjust_production(receiver, 1)
	t.advance_until(func(): return track_shows_item(g, "wheat"), 10, "Wheat is on its original route before editing")
	var redirect: Array[Vector2i] = [Vector2i(35, 12), wrong + Vector2i.RIGHT]
	t.check(g.place_belt_path(redirect), "An empty downstream endpoint can be rewired to a different building")
	g.simulate(4)
	t.near(g.stock_at(receiver, "wheat") + g.stock_at(wrong, "wheat"), 0, "Neither wrong destination nor intended destination receives blocked cargo")
	t.near(g.resource_inventory().wheat, 8, "Blocked cargo remains visible in inventory without duplication")
	t.near(g.stock_at(P, "wheat"), 4, "An in-flight reservation prevents dispatching a duplicate batch from the source")
	t.near(g.benches[receiver].produced_today, 0, "The intended receiver cannot produce with goods stranded on a track")
	var restore: Array[Vector2i] = [Vector2i(35, 12), receiver + Vector2i.RIGHT]
	t.check(g.place_belt_path(restore), "Restoring the empty endpoint reconnects the original receiver")
	g.adjust_production(receiver, -1)
	t.advance_until(func(): return g.stock_at(receiver, "wheat") == 4, 5, "Reconnection delivers the retained batch once")
	t.near(g.stock_at(wrong, "wheat"), 0, "The wrong building never receives another building's reservation")
	t.near(g.resource_inventory().wheat, 8, "Reconnection neither destroys nor duplicates goods")
	var first_cell: Array[Vector2i] = [Vector2i(34, 12), receiver]
	t.check(g.place_belt_path(first_cell), "An empty approach can also connect to the receiver's first footprint cell")

func track_shows_item(g, item) -> bool:
	for p in g.belts:
		g.select_entity(p)
		if g.entity_details.text.contains(g.item_name(item) + " ×"):
			return true
	return false
