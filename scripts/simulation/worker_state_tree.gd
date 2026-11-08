extends RefCounted

const Selection = preload("res://scripts/simulation/activity_selection.gd")
const Parameters = preload("res://scripts/simulation/activity_parameters.gd")
const Work = preload("res://scripts/simulation/activities/work.gd")
const Life = preload("res://scripts/simulation/activities/life.gd")
const Economy = preload("res://scripts/simulation/activities/economy.gd")
const Delivery = preload("res://scripts/simulation/activities/delivery.gd")

const STARVATION := 1
const EXHAUSTION := 2
const SEVERE_ILLNESS := 4

var active = null
var drink_elapsed := -1.0
var decision_wait := 0.0
var previous_limits := 0
var inertia_group := ""
var inertia_hours := 0.0

func tick(g, w: Dictionary, delta: float) -> Dictionary:
	var experience: Dictionary = {}
	inertia_hours += delta / g.HOUR_SECONDS
	if active != null and not active.valid(g, w):
		exit(g, w, "invalidated")
	check_hard_interrupt(g, w)
	decision_wait -= delta
	if active == null and decision_wait <= 0:
		select(g, w)
	if active == null:
		g.record_worker_time(w, "等待", delta)
		return experience
	# One bounded overlay; the enclosing activity keeps its claims while drinking.
	if drink_elapsed < 0 and active is Work and active.phase == "use" and w.water > 0 and w.buffs.remaining("hydrated") <= 0:
		drink_elapsed = 0.0
	if drink_elapsed >= 0:
		drink_elapsed += delta
		g.record_worker_time(w, "吃饭", delta)
		if drink_elapsed >= g.DRINK_HOURS * g.HOUR_SECONDS:
			g.drink(w)
			drink_elapsed = -1.0
		return experience
	var action: String = report_action(g)
	active.labor_seconds = 0.0
	active.experience = {}
	var previous_phase: String = active.phase
	var result: String = active.tick(g, w, delta)
	if active.phase != previous_phase:
		g.ai_trace.record(g, w, "state_tree", "phase", {"from": previous_phase, "to": active.phase})
	active.age += delta
	experience = active.experience.duplicate()
	if active is Work and action in ["挖掘", "工作"]:
		var labor: float = active.labor_seconds
		g.record_worker_time(w, action, labor)
		g.record_worker_time(w, "等待", delta - labor)
		w.fatigue = minf(g.MAX_FATIGUE, w.fatigue + g.FATIGUE_PER_HOUR * labor * active.fatigue_factor / g.HOUR_SECONDS)
	else:
		g.record_worker_time(w, action, delta)
	if result != "running":
		# A completed duty segment is a choice point, not a mandatory power outage.
		if result == "success" and active.record.kind == "operate":
			var choices: Array = Selection.options(g, w, "period_completed")
			if not choices.is_empty() and active.matches_option(choices[0]) and g.begin_work(active.record, w, active.segment, active.source_identity):
				active.fatigue_factor = active.segment.fatigue_factor
				active.age = 0.0
				return experience
		exit(g, w, result)
	return experience

func limit_flags(g, w: Dictionary) -> int:
	return ((STARVATION if w.hunger <= Parameters.STARVATION_INTERRUPT else 0)
		| (EXHAUSTION if w.fatigue >= g.MAX_FATIGUE else 0)
		| (SEVERE_ILLNESS if w.pollution >= Parameters.ILLNESS_INTERRUPT else 0))

func response_reason(g, w: Dictionary, kind: String, data: Dictionary) -> String:
	if w.hunger <= Parameters.STARVATION_INTERRUPT:
		if kind in ["eat", "borrow"] or (kind in ["use_item", "purchase"] and data.get("item") == "meat"):
			return "starvation"
	if w.pollution >= Parameters.ILLNESS_INTERRUPT and kind == "service" and data.get("kind") == "hospital":
		return "severe_illness"
	if w.fatigue >= g.MAX_FATIGUE and kind == "sleep":
		return "exhaustion"
	return ""

func check_hard_interrupt(g, w: Dictionary) -> void:
	var limits := limit_flags(g, w)
	var entered := limits & ~previous_limits
	previous_limits = limits
	if active == null or limits == 0:
		return
	var record = active.record
	# Finish a started bite/treatment; simultaneous crises must not cancel each other.
	if active.phase == "use" and (record.kind == "eat" or (record.kind == "use_item" and record.data.item == "meat") or (record.kind == "service" and record.data.kind == "hospital")):
		return
	if response_reason(g, w, record.kind, record.data) != "":
		return
	if entered != 0:
		# Crossing settles real earned wages, which may make the remedy affordable.
		exit(g, w, "starvation" if entered & STARVATION else "exhaustion" if entered & EXHAUSTION else "severe_illness")
	elif response_available(g, w):
		var choices: Array = Selection.options(g, w, "hard_limit_response", true)
		if not choices.is_empty():
			exit(g, w, response_reason(g, w, choices[0].kind, choices[0].data))

func response_available(g, w: Dictionary) -> bool:
	if w.fatigue >= g.MAX_FATIGUE:
		return true
	if w.hunger <= Parameters.STARVATION_INTERRUPT:
		if w.bread > 0 or w.items.get("meat", 0) > 0:
			return true
		if not g.has_debt(w) and w.loan_day != g.world.day:
			for p in g.world.smart_objects.query("bank"):
				if g.stock_at(p, "bread") > 0 and not g.route(Vector2i(w.pos.round()), p).is_empty():
					return true
	if w.pollution >= Parameters.ILLNESS_INTERRUPT:
		var slot: String = g.SERVICES.hospital.slot
		for p in g.world.smart_objects.query(slot):
			if g.can_use_service(w, p) and g.world.smart_objects.available(g.SmartObjects.key(slot, p), w.id) and not g.route(Vector2i(w.pos.round()), p).is_empty():
				return true
	return false

func activity_group(kind: String, data: Dictionary) -> String:
	match kind:
		"mine", "build", "produce", "operate", "payroll": return "labor"
		"deliver":
			# Unloading mined goods is a labor interlude, not a new preference.
			return "labor" if data.get("mined", false) and inertia_group == "labor" else "delivery"
		"use_item":
			if data.item in ["bench", "workbench", "tools", "clothes"] and inertia_group == "labor":
				return "labor"
		"rest": return "rest"
	return ""

func inertia_bonus(proposal) -> float:
	if active != null:
		return Parameters.INERTIA_BONUS if active.matches_option(proposal) else 0.0
	if inertia_group == "" or activity_group(proposal.kind, proposal.data) != inertia_group:
		return 0.0
	return Parameters.INERTIA_BONUS * clampf(1.0 - inertia_hours / Parameters.INERTIA_HOURS, 0.0, 1.0)

func remember_choice(option) -> void:
	var group := activity_group(option.kind, option.data)
	# Repeated short tasks must not refresh the same preference indefinitely.
	if group != inertia_group:
		inertia_group = group
		inertia_hours = 0.0

func select(g, w: Dictionary) -> void:
	for option in Selection.options(g, w):
		var activity
		match option.kind:
			"mine", "build", "produce", "operate": activity = Work.new()
			"eat", "sleep", "rest", "use_item", "service": activity = Life.new()
			"purchase", "borrow", "payroll": activity = Economy.new()
			"deliver": activity = Delivery.new()
		if activity.enter(g, w, option):
			active = activity
			remember_choice(option)
			g.ai_trace.entered(g, w, option)
			return
		activity.exit(g, w, "rejected")
		g.ai_trace.record(g, w, "state_tree", "entry_rejected", g.WorkerTrace.proposal(option))
	decision_wait = 0.2

func exit(g, w: Dictionary, reason: String) -> void:
	if active != null:
		g.ai_trace.record(g, w, "state_tree", "exiting", {"reason": reason})
		active.exit(g, w, reason)
	if reason in ["cancelled", "invalidated", "failure", "starvation", "exhaustion", "severe_illness"]:
		inertia_group = ""
		inertia_hours = 0.0
	active = null
	drink_elapsed = -1.0
	decision_wait = 0.0

func report_action(g) -> String:
	if active == null:
		return "空闲"
	if drink_elapsed >= 0:
		return "吃饭"
	match active.record.kind:
		"use_item": return "吃饭" if active.record.data.item in ["ale", "meat"] else "空闲"
		"service": return "通勤" if active.phase == "approach" else "空闲"
		"mine": return "通勤" if active.phase == "approach" else "挖掘"
		"build": return "通勤" if active.phase == "approach" else "工作"
		"produce", "operate":
			if active.phase == "approach": return "通勤"
			return "等待" if active.record.kind == "operate" and g.building_kind(active.record.target) == "drill" and not g.cache.powered_devices.has(active.record.target) else "工作"
		"deliver": return "搬运"
		"eat": return "吃饭"
		"sleep": return "通勤" if active.phase == "approach" else "睡觉"
		"rest": return "空闲"
	return "通勤"

func presentation(g) -> Dictionary:
	# A one-way adapter for existing animation/inspector vocabulary, never AI input.
	var result := {"state": "idle", "path": [], "job": null, "station": null,
		"building": null, "bed": null, "canteen": null, "meal_seat": null,
		"progress": 0.0, "drink_progress": maxf(0, drink_elapsed)}
	if active == null:
		return result
	var a = active
	var p = a.record.target
	result.path = a.path
	result.progress = a.elapsed
	match a.record.kind:
		"use_item":
			result.state = "use_item"
			result.item = a.record.data.item
		"service":
			result.state = "to_service" if a.phase == "approach" else "service"
			result.service = a.record.data.kind
			result.station = p
		"mine":
			result.state = "walk" if a.phase == "approach" else "dig"
			result.job = p
			result.progress = g.world.mining_contracts.get(p, {}).get("progress", 0.0)
		"build":
			result.state = "to_build" if a.phase == "approach" else "build"
			result.building = p
		"produce", "operate":
			result.state = "to_work" if a.phase == "approach" else "work"
			result.station = p
		"purchase":
			result.state = "to_shop"
			result.station = p
			result.item = a.record.data.item
		"payroll": result.state = "to_payroll"
		"borrow": result.state = "to_bank"
		"eat":
			result.state = "to_meal" if a.phase == "approach" else "eat"
			result.canteen = a.record.data.get("canteen")
			result.meal_seat = p if result.canteen != null else null
		"sleep":
			result.state = "to_bed" if a.phase == "approach" else "sleep"
			result.bed = p if a.record.data.bed and not a.handles.is_empty() else null
		"rest": result.state = "rest"
		"deliver":
			result.state = ("deposit" if a.phase == "handoff" else "haul") if a.mined else ("freight_pickup" if a.phase == "pickup" else "freight_dropoff")
	if drink_elapsed >= 0:
		result.state = "drink"
	return result
