extends RefCounted

const P := Vector2i(28, 11)
const OTHER := Vector2i(31, 11)
const INPUT_ROUTES := [
	{"source": "pump", "target": "purifier", "item": "raw_water", "amount": 4},
]

func run(t) -> void:
	var g = t.game
	for kind in ["bench", "workbench", "pump", "purifier"]:
		t.scenario("Recurring output: " + kind, 1)
		t.station(kind, P)
		if kind == "bench":
			t.materials(2, 2)
		g.workers[0].water = 4
		if kind == "purifier":
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
		if kind == "purifier":
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

func track_shows_item(g, item) -> bool:
	for p in g.belts:
		g.select_entity(p)
		if g.entity_details.text.contains(g.item_name(item) + " ×"):
			return true
	return false
