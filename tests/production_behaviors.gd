extends RefCounted

const P := Vector2i(28, 11)
const OTHER := Vector2i(31, 11)
const INPUT_ROUTES := [
	{"source": "pump", "target": "purifier", "item": "raw_water", "amount": 4},
	{"source": "pump", "target": "farm", "item": "raw_water", "amount": 4},
]

func run(t) -> void:
	var g = t.game
	for kind in ["bench", "workbench", "pump", "purifier", "farm"]:
		t.scenario("Recurring output: " + kind, 1)
		t.station(kind, P)
		if kind == "bench":
			t.materials(2, 2)
			g.terrain[Vector2i(27, 13)] = 2
		g.workers[0].water = 4
		if kind in ["purifier", "farm"]:
			t.station("pump", OTHER, 12)
		g.adjust_production(P, 1)
		var amount: int = g.PRODUCTS[kind].get("amount", 1)
		t.advance_until(func(): return g.benches[P].produced_today == amount, 120, "One daily batch is produced despite personal breaks")
		g.simulate(30)
		t.check(g.benches[P].stock == amount, "Daily target does not repeat within the day")
		g.simulate(g.DAY_SECONDS)
		t.check(g.benches[P].stock == amount * 2, "Tomorrow produces again without another order")
		g.select_entity(P)
		t.check(g.get_node("UI").queue_count.text == "每日产出 %d%s" % [amount, g.PRODUCTS[kind].unit], "Daily setting persists in the inspector")
		t.near((g.report_totals(1, 0)["工作"] + g.report_totals(2, 0)["工作"]) / g.HOUR_SECONDS, g.PRODUCTS[kind].hours * 2, "Recorded labor covers the two actual batches only")
		g.adjust_production(P, -1)
		g.simulate(g.DAY_SECONDS)
		t.check(g.benches[P].stock == amount * 2, "Zero output stops production across days")
		if kind in ["purifier", "farm"]:
			t.check(g.benches[OTHER].stock == 4, "Raw water is charged once per completed batch")
		elif kind == "bench":
			t.check(g.materials.get(2, 0) == 0, "Each produced gun consumes one copper ore")
			g.adjust_production(P, 1)
			var earned: float = g.report_totals(g.day, 0)["工作"]
			g.simulate(g.DAY_SECONDS)
			g.select_entity(P)
			t.check(g.benches[P].stock == 2 and g.entity_details.text.contains("等待铜矿"), "An unfunded daily gun order waits for copper")
			t.near(g.report_totals(g.day - 1, 0)["工作"], earned, "No copper means no idle production labor")
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

	t.scenario("Paid batch survives sleep, zero target, and midnight", 0)
	t.station("workbench", OTHER)
	g.simulate(g.DAY_SECONDS - 4)
	var tired_worker: Dictionary = g.create_worker(OTHER)
	tired_worker.fatigue = 72
	tired_worker.hunger = 120
	tired_worker.loan_principal = 20
	tired_worker.payroll = 4
	g.adjust_production(OTHER, 1)
	t.advance_until(func(): return tired_worker.earned_today > 0, 3, "A real production batch begins before midnight")
	g.adjust_production(OTHER, -1)
	t.advance_until(func(): return g.benches[OTHER].produced_today == 1, 150, "The committed batch finishes after a voluntary sleep despite zero target")
	t.check(g.day == 2, "The unfinished batch crosses midnight")
	t.near((g.report_totals(1, 0)["工作"] + g.report_totals(2, 0)["工作"]) / g.HOUR_SECONDS, 2, "The batch pays exactly its actual labor")
	t.check(g.report_totals(2)["睡觉"] > 0, "The operator really slept before resuming")
	g.simulate(20)
	t.check(g.benches[OTHER].produced_today == 1, "A finished zero-target batch does not restart")

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
		t.near(g.resource_activity("bread", g.day).consumed, g.workers[0].eaten_today, "Only actual personal eating consumes bread; wages do not")
		t.near(g.resource_inventory()[entry.item], 1024, "Consumed ingredients disappear from total physical inventory")
		var yesterday: Dictionary = g.resource_activity(entry.item, g.day)
		g.adjust_production(OTHER, -1)
		g.simulate(g.DAY_SECONDS - g.day_elapsed)
		t.check(g.resource_activity(entry.item, g.day - 1) == yesterday, "Yesterday's material use survives the midnight rollover")
		t.near(g.resource_activity(entry.item, g.day).consumed, 0, "The new day starts with no phantom material use")

	check_track_deliveries(t)
	check_farming(t)
	check_power(t)
	check_local_services(t)
	check_drilling(t)
	check_electric_freight(t)
	check_mood_experiences(t)
	check_machine_environment(t)

func check_machine_environment(t) -> void:
	var g = t.game
	# Shared contract: only real operation disturbs nearby sleep, never an idle shell or lost supply.
	for kind in ["power_plant", "drill", "electric_belt"]:
		for condition in ["running", "idle", "unpowered", "no_fuel", "outside", "blocked"]:
			if condition == "blocked" and kind != "electric_belt": continue
			t.scenario("Machine environment: %s / %s" % [kind, condition], 1)
			var facilities := noise_facilities(t, kind, condition != "idle")
			var sleeper: Dictionary = g.workers[0]
			sleeper.pos = Vector2(facilities.near) + (Vector2(0, 4) if condition == "outside" else Vector2.ZERO)
			if condition == "blocked": sleeper.pos = Vector2(33, 10)
			sleeper.fatigue = 100
			if condition == "no_fuel":
				g.add_stock(facilities.plant, 3, -10)
			if condition == "unpowered":
				g.remove_power_line(Vector2i(31, 8))
			if condition != "idle":
				if kind == "drill": g.designate(facilities.deposit, facilities.deposit)
				if kind == "electric_belt": g.adjust_production(facilities.target, 1)
			var setup_seconds := 0.0
			if condition == "blocked":
				setup_seconds = t.advance_until(func(): return track_shows_item(g, "raw_water"), 15, "Actual goods reach the belt before the route is disconnected")
				t.check(g.remove_belt(Vector2i(34, 9)), "Removing an empty downstream segment leaves the existing shipment waiting")
			var elapsed := 25.0 + setup_seconds
			if condition == "running":
				elapsed = t.advance_until(func(): return sleeper.mood.value < -0.01, 25, "Actual machinery disturbs a sleeping non-operator")
			else:
				g.simulate(25)
				t.near(sleeper.mood.value, 0, "Idle, blocked, unpowered, unfueled or distant machinery cannot disturb sleep")
			if condition in ["running", "outside"]:
				t.check(g.resource_activity(3, 1).consumed > 0, "The source circuit has really delivered power")
			t.near(sleeper.fatigue, 100 - elapsed / g.HOUR_SECONDS * g.SLEEP_RECOVERY_PER_HOUR, "Environmental mood does not reduce physical sleep recovery", 0.02)
			t.near(sleeper.earned_today, 0, "A nearby sleeper is affected without operating or earning from the machine")
			if condition == "running":
				var before: float = sleeper.mood.value
				g.remove_power_line(Vector2i(31, 8))
				g.simulate(2)
				t.check(sleeper.mood.value > before, "Stopping real operation clears the disturbance on the next simulation step")

	# Beds still recover the same fatigue; a busy industrial location changes the experience, not rent.
	var bed_moods: Array[float] = []
	var fatigue_after_sleep: Array[float] = []
	for running in [false, true]:
		t.scenario("A bed near generation is physically useful but less pleasant: " + str(running), 1)
		var facilities := noise_facilities(t, "power_plant", running)
		var sleeper: Dictionary = g.workers[0]
		sleeper.pos = Vector2(facilities.near)
		sleeper.bread = 5
		sleeper.fatigue = 100
		t.bed(facilities.near)
		g.assign_bed(facilities.near, sleeper.id)
		g.simulate(g.HOUR_SECONDS * 2)
		bed_moods.append(sleeper.mood.value)
		fatigue_after_sleep.append(sleeper.fatigue)
		t.near(sleeper.bed_spent_today, 5, "Noise neither refunds nor repeats the bed rent")
	t.check(bed_moods[0] > 0 and bed_moods[1] < 0, "Quiet bed sleep improves mood while strong ongoing noise spoils the experience (quiet %.3f, noisy %.3f)" % [bed_moods[0], bed_moods[1]])
	t.near(fatigue_after_sleep[0], fatigue_after_sleep[1], "Quiet and noisy beds retain identical fatigue recovery")

	# A pleasant environment cannot erase industrial disturbance; both are part of the same meal.
	t.scenario("Two diners share a fountain but only one is beside generation", 0)
	t.power_facilities(1, 0)
	t.station("fountain", Vector2i(30, 10))
	g.add_stock(Vector2i(30, 10), "raw_water", 10)
	t.cable(Vector2i(31, 9))
	g.simulate(4)
	var noisy: Dictionary = g.create_worker(Vector2i(27, 10))
	var quiet: Dictionary = g.create_worker(Vector2i(33, 10))
	noisy.bread = 10
	quiet.bread = 10
	g.simulate(g.MEAL_SECONDS + 0.5)
	t.check(is_equal_approx(noisy.eaten_today, 10) and is_equal_approx(quiet.eaten_today, 10), "Both diners consume the same real meal")
	t.near(noisy.hunger, quiet.hunger, "Noise does not change the food's nutritional effect")
	t.check(quiet.mood.value > 15 and noisy.mood.value > 0, "An operating fountain still contributes comfort to both meals")
	t.near(quiet.mood.value - noisy.mood.value, 12, "Only the diner's actual noisy meal time receives the penalty", 0.03)

	# Dense machine placement must not multiply penalties or depend on the sleeper's iteration order.
	var changes: Array[float] = []
	for count in [1, 2]:
		t.scenario("Overlapping operating drills do not stack disturbance: " + str(count), 1)
		t.power_facilities(1, 0)
		var sleeper: Dictionary = g.workers[0]
		sleeper.pos = Vector2(36, 12)
		sleeper.fatigue = 100
		var drills: Array[Vector2i] = []
		var deposits: Array[Vector2i] = []
		for i in count:
			var drill := Vector2i(34 + i * 3, 9)
			var deposit := Vector2i(35 + i * 3, 11)
			t.station("drill", drill)
			g.add_stock(drill, "bread", 30)
			g.create_worker(drill)
			g.terrain[deposit] = 5
			g.navigation.set_point_solid(deposit, true)
			drills.append(drill)
			deposits.append(deposit)
		# Isolate noise from personal shopping and collection trips using starting needs/cash.
		for person in g.workers:
			if person.id != sleeper.id:
				person.hunger = 120
				person.loan_principal = 20
				person.payroll = 20
		for deposit in deposits: g.designate(deposit, deposit)
		t.advance_until(func():
			for drill in drills:
				if g.stock_at(drill, 2) < 1: return false
			return true, 35, "Every nearby drill produces actual ore before the comparison")
		var before: float = sleeper.mood.value
		g.simulate(g.HOUR_SECONDS)
		changes.append(sleeper.mood.value - before)
	# Real operators may briefly collect cash at a batch boundary during this interval.
	t.near(changes[0], -6.5, "Strong running machinery offsets natural mood recovery during sleep", 0.15)
	t.near(changes[0], changes[1], "Two noisy machines do not double one sleeper's mood penalty", 0.08)

func noise_facilities(t, kind: String, running: bool) -> Dictionary:
	var g = t.game
	var plant: Vector2i = t.power_facilities(1, 1 if kind == "power_plant" and running else 0)
	var result := {"plant": plant, "near": Vector2i(24, 10)}
	if kind == "drill":
		var drill := Vector2i(34, 9)
		result.near = Vector2i(34, 12)
		result.deposit = Vector2i(35, 11)
		t.station("drill", drill)
		g.add_stock(drill, "bread", 30)
		g.create_worker(drill)
		g.terrain[result.deposit] = 5
		g.navigation.set_point_solid(result.deposit, true)
	elif kind == "electric_belt":
		var source := Vector2i(32, 11)
		result.target = Vector2i(39, 9)
		result.near = Vector2i(35, 10)
		t.station("pump", source, 4)
		t.station("purifier", result.target)
		g.create_worker(source)
		for x in range(33, 39):
			t.belt(Vector2i(x, 9), Vector2i.RIGHT)
			g.belts[Vector2i(x, 9)].kind = "electric_belt"
	return result

func check_mood_experiences(t) -> void:
	var g = t.game
	# Ordinary proximity, empty water tanks and unpowered fountains are not pleasant meals.
	var meal_moods: Array[float] = []
	for setting in ["absent", "dry", "unpowered", "one", "two"]:
		t.scenario("Comfort comes from eating at an operating fountain: " + setting, 0)
		t.power_facilities(1, 1)
		for i in (2 if setting == "two" else 1):
			if setting == "absent": break
			var p := Vector2i(35 + i * 3, 9)
			t.station("fountain", p)
			if setting != "dry": g.add_stock(p, "raw_water", 10)
		if setting == "unpowered":
			g.power_lines.erase(Vector2i(31, 8))
		g.simulate(4)
		var person: Dictionary = g.create_worker(Vector2i(36, 10))
		person.bread = 10
		g.simulate(g.MEAL_SECONDS + 0.5)
		t.check(is_equal_approx(person.eaten_today, 10) and person.hunger > 90, "The same real meal is consumed in every environment")
		meal_moods.append(person.mood.value)
		var before: float = person.mood.value
		g.simulate(2)
		t.check(person.mood.value <= before, "Standing or wandering near a fountain cannot farm more mood")
	for i in 3:
		t.near(meal_moods[i], 0, "Only a powered, watered fountain improves the meal")
	t.check(meal_moods[3] > 15, "A pleasant meal leaves positive mood after eating ends")
	t.near(meal_moods[3], meal_moods[4], "Overlapping fountains cannot multiply one meal's emotional reward")

	# Sustained mechanical work must lead to a reversible refusal, not lost cargo or permanent unemployment.
	t.scenario("Mechanical stress, duty handoff, alternative work, and recovery", 0)
	var plant: Vector2i = t.power_facilities(1, 1)
	var person: Dictionary = g.workers[0]
	var ore := Vector2i(36, 13)
	g.terrain[ore] = 1
	g.navigation.set_point_solid(ore, true)
	t.advance_until(func(): return g.resource_activity(3, 1).consumed > 0, 15, "Neutral workers take mechanical duty normally")
	g.simulate(g.HOUR_SECONDS * 9.3)
	var earned: float = person.earned_today
	var coal: float = g.stock_at(plant, 3)
	t.check(person.mood.value < -45 and person.fatigue < 100, "Real mechanical work causes distress before physical exhaustion")
	g.simulate(g.HOUR_SECONDS * 0.5)
	t.near(person.earned_today, earned, "Distressed operator hands off duty instead of restarting it forever")
	t.near(g.stock_at(plant, 3), coal, "Unstaffed generation burns no fuel during a mood-related break")
	g.designate(ore, ore)
	t.advance_until(func(): return g.delivered == 1, 180, "A worker can choose ordinary mining after recovering from mechanical work")
	t.check(g.report_mined(1) + g.report_mined(2) == 1, "Mechanical discomfort does not make ordinary work permanently unavailable")
	t.advance_until(func(): return g.stock_at(plant, 3) < coal - 0.01, g.DAY_SECONDS * 2, "Free recovery eventually restores staffed generation without purchases")

	# A single bad moment must not instantly abandon a working circuit.
	for operator in [0, 1]:
		t.scenario("Low mood needs sustained time before refusing duty: " + str(operator), 0)
		t.power_facilities(1, 1)
		g.workers[operator].mood.value = -46
		g.simulate(g.HOUR_SECONDS)
		t.check(g.resource_activity(3, 1).consumed > 0 and g.workers[operator].earned_today > 0, "A newly distressed operator still starts paid duty")
		t.near(g.workers[operator].earned_today, g.report_totals(1, operator)["工作"] / g.HOUR_SECONDS, "Mood does not speed up or underpay attendance hours", 0.01)

	# Drilling yields at a delivered batch, not the middle of a paid extraction.
	t.scenario("Distressed drilling pays actual effort and stops on loss of power", 0)
	t.power_facilities(1, 0)
	var drill := Vector2i(34, 9)
	var deposit := Vector2i(35, 11)
	t.station("drill", drill)
	g.add_stock(drill, "bread", 30)
	g.terrain[deposit] = 5
	g.navigation.set_point_solid(deposit, true)
	var miner: Dictionary = g.create_worker(drill)
	miner.mood.value = -60
	g.designate(deposit, deposit)
	t.advance_until(func(): return g.stock_at(drill, 2) == 1, 35, "Already-started drilling finishes despite sustained distress")
	t.check(miner.earned_today > g.DRILL_HOURS, "Slow drilling pays its full actual labor cost")
	var drilling_wages: float = miner.earned_today
	g.remove_power_line(Vector2i(31, 8))
	g.simulate(g.HOUR_SECONDS)
	t.near(g.stock_at(drill, 2), 1, "An unpowered drill cannot produce another extraction")
	t.near(miner.earned_today, drilling_wages, "Loss of power leaves no phantom paid drilling")
	t.near(g.resource_activity(2, 1).produced, 2, "Reports contain one drilled ore and one physically recovered cable")

func check_farming(t) -> void:
	var g = t.game
	# No worker may be held for growth, and ripe wheat still requires harvesting labor.
	t.scenario("Unattended growth followed by paid harvest", 1)
	t.station("farm", P)
	t.station("workbench", OTHER)
	g.add_stock(P, "raw_water", 8)
	g.adjust_production(P, 2)
	t.advance_until(func():
		g.select_entity(P)
		return g.entity_details.text.contains("生长中"), 25, "One watering hour starts growth")
	t.near(g.workers[0].earned_today, 1, "Watering is one paid hour, not both labor phases")
	g.adjust_production(OTHER, 1)
	t.advance_until(func(): return g.stock_at(OTHER, "workbench") == 1, 25, "The same worker makes a backpack while crops grow")
	t.check(g.stock_at(P, "wheat") == 0, "Growing crops do not produce premature wheat")
	g.adjust_production(P, -2)
	t.advance_until(func(): return g.stock_at(P, "wheat") == 8, 65, "Stopping future batches still harvests the already-watered crop")
	t.near(g.workers[0].earned_today, 4, "Harvest pays its separate hour; growth pays no wages")
	t.near(g.stock_at(P, "raw_water"), 4, "A stopped farm uses only one batch of water")
	g.adjust_production(P, 2)
	t.advance_until(func(): return g.stock_at(P, "wheat") == 16, 85, "The same farmland can be watered and harvested again")

	var growth_rates: Array[float] = []
	var remaining_pattern := RegEx.new()
	remaining_pattern.compile("生长中\\s+([0-9.]+)h")
	for lamps in [0, 1, 2]:
		t.scenario("Powered growth rate without stacking: %d lamps" % lamps, 0)
		t.power_facilities(1, lamps)
		var farm := Vector2i(34, 10)
		t.station("farm", farm)
		g.add_stock(farm, "raw_water", 4)
		g.add_stock(farm, "bread", 8)
		g.create_worker(farm)
		g.adjust_production(farm, 1)
		t.advance_until(func():
			g.select_entity(farm)
			return g.entity_details.text.contains("生长中"), 20, "Crop is watered")
		var before_match := remaining_pattern.search(g.entity_details.text)
		t.check(before_match != null, "The farm inspector displays its remaining growth time")
		if before_match == null: return
		var before := before_match.get_string(1).to_float()
		g.simulate(g.HOUR_SECONDS)
		g.select_entity(farm)
		var after_match := remaining_pattern.search(g.entity_details.text)
		t.check(after_match != null, "The crop remains visibly growing during the measured hour")
		if after_match == null: return
		var after := after_match.get_string(1).to_float()
		growth_rates.append(before - after)
		t.near(before - after, 1 if lamps == 0 else 2, "Visible growth time advances at the actual powered rate", 0.11)
		t.advance_until(func(): return g.stock_at(farm, "wheat") == 8, 120, "Ripe crops are subsequently harvested by an available worker")
	t.near(growth_rates[1], growth_rates[2], "Overlapping lights do not accelerate growth again", 0.11)

func check_power(t) -> void:
	var g = t.game
	# Capacity applies per transformer, per shared wire and per plant, not per consumer.
	for entry in [[1, 1, 200.0], [1, 5, 800.0], [5, 4, 3200.0]]:
		t.scenario("Metered coal and circuit limits: %s" % str(entry), 0)
		var plant: Vector2i = t.power_facilities(entry[0], entry[1])
		t.advance_until(func():
			g.select_entity(plant)
			return g.entity_details.text.contains("输出  %.0fW" % entry[2]), 15, "Operators bring the circuit up to its allowed output")
		var coal: float = g.resource_activity(3, 1).consumed
		g.simulate(g.HOUR_SECONDS * 0.5)
		t.near(g.resource_activity(3, 1).consumed - coal, entry[2] / 1600.0 * 0.5, "Coal follows actual output rather than nameplate capacity", 0.003)
		g.remove_power_line(plant + Vector2i(2, 0))
		coal = g.resource_activity(3, 1).consumed
		g.simulate(g.HOUR_SECONDS)
		t.near(g.resource_activity(3, 1).consumed, coal, "Disconnecting the high-voltage supply stops fuel consumption")

	t.scenario("Independent generators keep independent output limits", 0)
	var first: Vector2i = t.power_facilities(3, 4)
	var second: Vector2i = t.power_facilities(3, 4, Vector2i(30, 0))
	t.advance_until(func():
		for p in [first, second]:
			g.select_entity(p)
			if not g.entity_details.text.contains("输出  2400W"): return false
		return true, 15, "Separate circuits can jointly exceed one generator's 3200W rating")
	var fuel_used: float = g.resource_activity(3, 1).consumed
	g.simulate(g.HOUR_SECONDS * 0.5)
	t.near(g.resource_activity(3, 1).consumed - fuel_used, 1.5, "Each generator pays only for the load it actually supplies", 0.003)

	t.scenario("Low-voltage trunk shared by two transformers", 0)
	var plant: Vector2i = t.power_facilities(2, 0)
	# Both feeds meet before one 800W trunk, so their ratings cannot be added downstream.
	for y in range(8, 13):
		t.cable(Vector2i(31, y))
	for x in range(32, 45):
		g.power_lines.erase(Vector2i(x, 12))
	t.clear_area(Rect2i(32, 8, 19, 4))
	for x in range(32, 50):
		t.cable(Vector2i(x, 8))
	for i in 5:
		t.station("grow_light", Vector2i(35 + i * 3, 9))
	t.advance_until(func():
		g.select_entity(plant)
		return g.entity_details.text.contains("输出  800W"), 15, "Shared trunk carries at most 800W even with two staffed feeders")
	var coal: float = g.resource_activity(3, 1).consumed
	g.simulate(g.HOUR_SECONDS)
	t.near(g.resource_activity(3, 1).consumed - coal, 0.5, "An extra transformer does not bypass a line bottleneck", 0.003)

	# Attendance and fuel remain necessary; neither wire type requires voltage conversion.
	for missing in ["operator", "coal", "transformer", "low_line"]:
		t.scenario("Disconnected or unavailable supply: " + missing, 0)
		plant = t.power_facilities(1, 1)
		if missing == "operator": g.workers.clear()
		if missing == "coal": g.add_stock(plant, 3, -10)
		if missing == "transformer":
			g.benches.erase(Vector2i(29, 8))
			t.cable(Vector2i(29, 8), "high_line")
			t.cable(Vector2i(30, 8), "high_line")
		if missing == "low_line":
			for x in range(31, 45):
				g.power_lines[Vector2i(x, 8)].kind = "high_line"
		g.simulate(20)
		g.select_entity(Vector2i(32, 9))
		if missing in ["operator", "coal"]:
			t.check(g.entity_details.text.contains("未供电"), "Lights still require staffed and fueled generation")
			t.near(g.resource_activity(3, 1).consumed, 0, "An unavailable circuit burns no coal")
		else:
			t.check(g.entity_details.text.contains("运行中"), "Either wire connects consumers, including mixed wires without a transformer")
			t.check(g.resource_activity(3, 1).consumed > 0, "Directly connected consumers use real fuel")

	# A shared narrow segment limits the circuit even when the rest uses thick cable.
	for generator in ["manual_generator", "power_plant"]:
		for wire in ["low_line", "high_line", "mixed"]:
			t.scenario("Direct generation and per-wire limits: " + generator + " / " + wire, 0)
			t.clear_area(Rect2i(23, 5, 25, 7))
			plant = Vector2i(24, 8)
			t.station(generator, plant)
			g.add_stock(plant, "bread", 30)
			g.add_stock(plant, 3, 10)
			var operator: Dictionary = g.create_worker(plant)
			for x in range(26, 46):
				t.cable(Vector2i(x, 8), "low_line" if wire == "low_line" or (wire == "mixed" and x == 29) else "high_line")
			for i in 5:
				t.station("grow_light", Vector2i(32 + i * 3, 7))
			var expected := 400 if generator == "manual_generator" else (1000 if wire == "high_line" else 800)
			t.advance_until(func():
				g.select_entity(plant)
				return g.entity_details.text.contains("输出  %dW" % expected), 15, "Generator powers loads directly up to the smallest shared capacity")
			var fuel: float = g.resource_activity(3, 1).consumed
			var wages: float = operator.earned_today
			g.simulate(g.HOUR_SECONDS * 0.5)
			t.near(g.resource_activity(3, 1).consumed - fuel, 0 if generator == "manual_generator" else expected / 1600.0 * 0.5, "Only coal generation consumes coal", 0.003)
			t.near(operator.earned_today - wages, 0.5, "Generation pays for actual attendance, not power capacity", 0.01)
			g.remove_power_line(Vector2i(29, 8))
			g.simulate(0.1)
			wages = operator.earned_today
			g.simulate(g.HOUR_SECONDS)
			t.near(operator.earned_today, wages, "A disconnected manual or coal generator releases its operator")
			g.select_entity(Vector2i(32, 7))
			t.check(g.entity_details.text.contains("未供电"), "Breaking either cable type disables downstream loads")

	var fatigue_results: Array[float] = []
	for fountains in [1, 2]:
		t.scenario("Fountain water, fatigue and non-stacking: %d" % fountains, 0)
		t.power_facilities(1, 0)
		for i in fountains:
			var p := Vector2i(32 + i * 3, 9)
			t.station("fountain", p)
			g.add_stock(p, "raw_water", 10)
		var person: Dictionary = g.create_worker(Vector2i(34, 10))
		person.fatigue = 100
		# Exhaustion naturally starts ground sleep, keeping the observer within range.
		t.advance_until(func():
			g.select_entity(Vector2i(32, 9))
			return g.entity_details.text.begins_with("运行中"), 15, "Delivered daily water enables the fountain")
		var before: float = person.fatigue
		g.simulate(g.HOUR_SECONDS)
		fatigue_results.append(before - person.fatigue - g.SLEEP_RECOVERY_PER_HOUR)
		t.near(g.resource_activity("raw_water", 1).consumed, fountains * 10, "Each fountain consumes one daily refill, not water every frame")
		g.simulate(g.DAY_SECONDS - g.day_elapsed + 0.1)
		g.select_entity(Vector2i(32, 9))
		t.check(g.entity_details.text.contains("等待原水"), "A new day without water disables recovery")
		t.near(g.resource_activity("raw_water", 2).produced, 0, "Fountains do not create free raw water at midnight")
	t.near(fatigue_results[0], 5, "One powered fountain restores five fatigue per hour", 0.05)
	t.near(fatigue_results[1], 5, "Overlapping fountains restore the same five fatigue", 0.05)

func check_local_services(t) -> void:
	var g = t.game
	# Equivalent labor uses the same real-money wage rule; overlapping lamps cannot mint wages.
	for setting in ["absent", "one", "two", "outside", "disconnect", "debt", "short_cash"]:
		t.scenario("Local wage light: " + setting, 0)
		t.power_facilities(1, 1 if setting == "absent" else 0)
		var station := Vector2i(34, 10) if setting != "outside" else Vector2i(40, 10)
		if setting != "absent":
			t.station("daylight", Vector2i(32, 9))
			if setting == "two": t.station("daylight", Vector2i(35, 9))
		t.advance_until(func():
			g.select_entity(Vector2i(32, 9))
			return g.entity_details.text.contains("运行中"), 15, "A real staffed supply is running before the production order")
		t.station("workbench", station)
		g.add_stock(station, "bread", 8)
		var worker: Dictionary = g.create_worker(station)
		worker.payroll = 0.1 if setting == "short_cash" else 0.0
		if setting == "debt": worker.loan_principal = 2
		var bread: float = g.resource_inventory().bread
		g.adjust_production(station, 1)
		var expected := 2.0 if setting in ["absent", "outside"] else 2.4
		if setting == "disconnect":
			t.advance_until(func(): return worker.earned_today > 0.4, 10, "The first part of the batch is paid at the lit rate")
			var paid: float = worker.earned_today
			expected = paid + 2.0 - paid / 1.2
			g.remove_power_line(Vector2i(31, 8))
		t.advance_until(func(): return g.stock_at(station, "workbench") == 1, 30, "The same paid batch finishes without losing progress")
		t.near(worker.earned_today, expected, "Actual wages follow powered coverage without stacking", 0.01)
		t.near(worker.bread + worker.meal_bread + worker.eaten_today, worker.earned_today * (0.75 if setting == "debt" else 1.0), "The actual raised wage preserves normal repayment and food ownership", 0.001)
		t.near(g.resource_inventory().bread + g.resource_activity("bread", 1).consumed, bread, "Actual meals and wage bonuses conserve existing bread")
		if setting == "debt": t.near(worker.loan_principal, 2 - worker.earned_today * 0.25, "Repayment uses the actual raised wage")

	# A real wage difference must influence choice, not merely the eventual receipt.
	for lit in [false, true]:
		t.scenario("Wage changes which nearby opportunity is chosen: " + str(lit), 0)
		t.power_facilities(1, 0)
		t.station("daylight" if lit else "grow_light", Vector2i(32, 9))
		t.advance_until(func():
			g.select_entity(Vector2i(32, 9))
			return g.entity_details.text.contains("运行中"), 15, "The staffed circuit supplies the real wage light")
		var nearer := Vector2i(37, 11)
		var better_paid := Vector2i(34, 11)
		for p in [nearer, better_paid]:
			t.station("workbench", p)
			g.adjust_production(p, 1)
		var chooser: Dictionary = g.create_worker(Vector2i(36, 11))
		chooser.payroll = 4
		t.advance_until(func(): return g.benches[nearer].produced_today + g.benches[better_paid].produced_today > 0, 25, "One competing order is actually completed")
		var chosen: Vector2i = better_paid if lit else nearer
		t.check(g.benches[chosen].produced_today == 1, "A higher local wage outweighs one extra walking cell; equal wages favor the closer job")

	# Diners must travel, reserve distinct seats, and keep a fallback when seats cannot be used.
	for setting in ["near", "full", "unreachable", "far", "none", "small_meal", "midnight"]:
		t.scenario("Canteen meals: " + setting, 0)
		t.clear_area(Rect2i(26, 10, 28, 6))
		var canteen := Vector2i(28, 11) if setting != "far" else Vector2i(50, 11)
		if setting != "none": t.station("canteen", canteen)
		if setting == "unreachable":
			for cell in [Vector2i(27, 11), Vector2i(30, 11), Vector2i(28, 10), Vector2i(29, 10), Vector2i(28, 12), Vector2i(29, 12)]:
				g.terrain[cell] = 1
				g.navigation.set_point_solid(cell, true)
		if setting == "midnight": g.simulate(g.DAY_SECONDS - 1)
		var diners: Array = []
		for i in (3 if setting == "full" else 1):
			var diner: Dictionary = g.create_worker(Vector2i(32 + i, 13))
			diner.bread = 10
			diner.fatigue = 50
			if setting == "small_meal": diner.bread = 1
			diners.append(diner)
		var bread: float = g.resource_inventory().bread
		t.advance_until(func(): return diners.all(func(w): return w.eaten_today >= (0.999 if setting == "small_meal" else 9.999)), 12, "Every diner eats, including overflow or unreachable seats")
		var restored := 0.0
		var eaten := 0.0
		for diner in diners:
			restored += 50 - diner.fatigue - g.report_totals(g.day, diner.id)["睡觉"] / g.HOUR_SECONDS * g.SLEEP_RECOVERY_PER_HOUR
			eaten += diner.eaten_today
		var expected := 0 if setting in ["none", "far", "unreachable"] else (20 if setting == "full" else 10)
		t.near(restored, expected, "Only actual seated meals restore fatigue; two seats cannot serve three concurrent diners")
		t.near(g.resource_inventory().bread, bread - eaten, "The canteen consumes personal food once and charges no fee")
		g.simulate(4)
		t.near(diners[0].fatigue, (50 if expected == 0 else 40) - g.report_totals(g.day, diners[0].id)["睡觉"] / g.HOUR_SECONDS * g.SLEEP_RECOVERY_PER_HOUR, "Post-meal recovery comes only from actual sleep, not standing near a seat", 0.1)
		if setting == "near":
			var later: Dictionary = g.create_worker(Vector2i(32, 13))
			later.bread = 10
			later.fatigue = 50
			t.advance_until(func(): return later.eaten_today >= 9.999, 12, "A later diner can use a released seat")
			t.near(later.fatigue, 40, "Completed meals release their seats")

func check_drilling(t) -> void:
	var g = t.game
	# A powered operator produces normal ore repeatedly without erasing the dense deposit.
	t.scenario("Dense mining, outage, cancellation and relocation", 0)
	t.power_facilities(1, 0)
	var drill := Vector2i(34, 9)
	var deposit := Vector2i(35, 11)
	t.station("drill", drill)
	g.add_stock(drill, "bread", 30)
	g.terrain[deposit] = 5
	g.navigation.set_point_solid(deposit, true)
	var miner: Dictionary = g.create_worker(drill)
	miner.gun_uses = 10
	g.designate(deposit, deposit)
	t.advance_until(func(): return g.stock_at(drill, 2) >= 2, 65, "A single drilling operator repeatedly extracts copper")
	t.check(g.terrain[deposit] == 5 and miner.gun_uses == 10, "Dense deposits remain and do not consume ordinary mining tools")
	g.remove_power_line(Vector2i(31, 8))
	var stock: float = g.stock_at(drill, 2)
	g.simulate(20)
	t.near(g.stock_at(drill, 2), stock, "Drilling pauses without electricity rather than mining by hand")
	g.designate(deposit, deposit, true)
	g.add_stock(g.BASE, 2, 1)
	g.place_building(Vector2i(31, 8), "low_line")
	t.advance_until(func(): return not g.sites.has(Vector2i(31, 8)), 30, "Player repairs the cut power cable")
	g.simulate(20)
	t.near(g.stock_at(drill, 2), stock, "Canceled dense mining does not resume when power returns")
	g.begin_drill_move(drill)
	var destination := Vector2i(40, 14)
	t.check(g.move_drill_to(destination), "Drill can relocate to reachable clear ground without new building materials")
	t.near(g.stock_at(destination, 2), stock, "Moving carries its extracted stock exactly once")
	var next_deposit := destination + Vector2i(1, 2)
	g.terrain[next_deposit] = 6
	g.navigation.set_point_solid(next_deposit, true)
	g.designate(next_deposit, next_deposit)
	g.simulate(20)
	t.near(g.stock_at(destination, 3), 0, "A moved drill does not retain its previous electrical connection")
	var cable_path: Array[Vector2i] = []
	for y in range(9, 14): cable_path.append(Vector2i(40, y))
	g.add_stock(g.BASE, 2, cable_path.size())
	t.check(g.place_building_batch(cable_path, "low_line"), "A new low-voltage branch can reach the moved drill")
	t.advance_until(func(): return g.stock_at(destination, 3) > 0, g.DAY_SECONDS * 3, "Reconnecting resumes extraction after workers satisfy their own needs")
	t.near(g.stock_at(destination, 2), stock, "Later reconnection still preserves moved copper exactly once")

	# A spare unpowered machine must not attract the entire crew away from generation.
	t.scenario("An unpowered drill cannot strand the available power crew", 0)
	t.power_facilities(1, 0)
	var deposits: Array[Vector2i] = [Vector2i(34, 11), Vector2i(40, 11)]
	for machine in [Vector2i(34, 9), Vector2i(40, 9)]:
		t.station("drill", machine)
		g.add_stock(machine, "bread", 30)
	for mineral in deposits:
		g.terrain[mineral] = 5
		g.navigation.set_point_solid(mineral, true)
	g.create_worker(Vector2i(37, 10))
	for person in g.workers:
		person.pos = Vector2(37, 10)
		person.payroll = 4
	for mineral in deposits:
		g.designate(mineral, mineral)
	t.advance_until(func(): return g.mined > 0, 60, "Three workers can power and operate one of two drills instead of all waiting for power")
	t.check(g.resource_activity(3, 1).consumed > 0, "Extraction is supported by actual fuel consumption")

	# Two machines sharing one deposit must not double its physical extraction rate.
	t.scenario("Competing drills share one deposit without duplicate labor", 0)
	t.power_facilities(1, 0)
	var shared := Vector2i(36, 11)
	g.terrain[shared] = 5
	g.navigation.set_point_solid(shared, true)
	for machine in [Vector2i(34, 9), Vector2i(37, 9)]:
		t.station("drill", machine)
		g.add_stock(machine, "bread", 30)
		var person: Dictionary = g.create_worker(machine)
		person.payroll = 4
	g.designate(shared, shared)
	var elapsed: float = t.advance_until(func(): return g.mined >= 2, 90, "Competing equipment still produces two real batches")
	t.check(elapsed >= g.DRILL_HOURS * 2 * g.HOUR_SECONDS - 0.1, "Two drills cannot accelerate one deposit by simultaneously working it")
	t.near(g.stock_at(Vector2i(34, 9), 2) + g.stock_at(Vector2i(37, 9), 2), 2, "Each completed extraction enters exactly one machine warehouse")
	g.designate(shared, shared, true)
	g.simulate(3)
	t.check(g.mined == 2, "Canceling the shared order stops both machines")
	g.designate(shared, shared)
	t.advance_until(func(): return g.mined > 2, g.DAY_SECONDS * 3, "A fresh shared order can use released equipment after workers meet their needs")

	t.scenario("Ordinary tools cannot excavate dense deposits", 1)
	var p := Vector2i(37, 13)
	g.terrain[p] = 5
	g.workers[0].gun_uses = 10
	g.designate(p, p)
	g.simulate(50)
	t.check(g.terrain[p] == 5 and g.mined == 0 and g.workers[0].earned_today == 0, "Hand mining and a mining gun cannot consume or get paid for dense ore")

func check_electric_freight(t) -> void:
	var g = t.game
	# Electricity is charged for all four physical items, not one shipment icon.
	t.scenario("Powered freight pauses and survives a cable repair", 0)
	var plant: Vector2i = t.power_facilities(1, 0)
	var source := Vector2i(32, 11)
	var target := Vector2i(39, 9)
	t.station("pump", source, 4)
	t.station("purifier", target)
	g.create_worker(source)
	var sleeper: Dictionary = g.create_worker(Vector2i(35, 10))
	sleeper.fatigue = 100
	for x in range(33, 39):
		t.belt(Vector2i(x, 9), Vector2i.RIGHT)
		g.belts[Vector2i(x, 9)].kind = "electric_belt"
	g.adjust_production(target, 1)
	t.advance_until(func(): return track_shows_item(g, "raw_water"), 15, "Carrier loads a batch onto electric belts")
	g.adjust_production(target, -1)
	t.advance_until(func():
		g.select_entity(plant)
		return g.entity_details.text.contains("输出  100W"), 10, "Four water items draw 100W, not 25W")
	g.remove_power_line(Vector2i(31, 8))
	var before_outage: float = sleeper.mood.value
	g.simulate(5)
	t.check(sleeper.mood.value >= before_outage, "A powered belt's outage does not keep disturbing a nearby sleeper")
	t.near(g.stock_at(target, "raw_water"), 0, "An outage stops the in-flight shipment")
	t.near(g.resource_inventory().raw_water, 4, "Paused freight remains in inventory without loss or duplication")
	g.add_stock(g.BASE, 2, 1)
	g.place_building(Vector2i(31, 8), "low_line")
	var lowest_mood := [sleeper.mood.value]
	t.advance_until(func():
		lowest_mood[0] = minf(lowest_mood[0], sleeper.mood.value)
		return g.stock_at(target, "raw_water") == 4, 50, "Repairing power lets all four items reach their original warehouse")
	t.check(lowest_mood[0] < -0.01, "Resumed automatic cargo movement disturbs sleep without a belt operator")
	t.near(g.resource_inventory().raw_water, 4, "Delivery preserves the same four items")
	g.simulate(6)
	t.near(sleeper.mood.value, 0, "An empty belt stops disturbing sleep after the shipment arrives")

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
