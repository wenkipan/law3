extends RefCounted

const Selection = preload("res://scripts/simulation/activity_selection.gd")
const Work = preload("res://scripts/simulation/activities/work.gd")
const Life = preload("res://scripts/simulation/activities/life.gd")
const Economy = preload("res://scripts/simulation/activities/economy.gd")
const Delivery = preload("res://scripts/simulation/activities/delivery.gd")

var active = null
var drink_elapsed := -1.0
var decision_wait := 0.0
var review_elapsed := 0.0

func tick(g, w: Dictionary, delta: float) -> Dictionary:
	var experience: Dictionary = {}
	if active != null and (not active.valid(g, w) or (w.fatigue >= 100 and active.option.kind != "sleep")):
		exit(g, w, "invalidated")
	decision_wait -= delta
	if active == null and decision_wait <= 0:
		select(g, w)
	if active == null:
		g.record_worker_time(w, "等待", delta)
		return experience
	# One bounded overlay; the enclosing activity keeps its claims while drinking.
	if drink_elapsed < 0 and active is Work and active.phase == "use" and w.water > 0 and w.water_effect <= 0:
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
		w.fatigue = minf(100, w.fatigue + g.FATIGUE_PER_HOUR * labor * active.fatigue_factor / g.HOUR_SECONDS)
	else:
		g.record_worker_time(w, action, delta)
	if result != "running":
		# A completed duty segment is a choice point, not a mandatory power outage.
		if result == "success" and active.option.kind == "operate":
			var choices: Array = Selection.options(g, w, "period_completed")
			if not choices.is_empty() and choices[0].same_activity(active.option) and g.begin_work(active.option, w, active.segment):
				active.fatigue_factor = active.segment.fatigue_factor
				active.age = 0.0
				return experience
		exit(g, w, result)
	else:
		review_elapsed += delta
		if review_elapsed >= g.HOUR_SECONDS and active is Work and (w.fatigue >= 75 or (w.hunger < 20 and w.bread >= 4)):
			review_elapsed = 0.0
			var choices: Array = Selection.options(g, w, "needs_review")
			var continuation := 0.0
			for option in choices:
				if option.same_activity(active.option):
					continuation = option.score
			if not choices.is_empty() and not choices[0].same_activity(active.option) and choices[0].score > continuation + 0.15:
				exit(g, w, "reconsidered")
	return experience

func select(g, w: Dictionary) -> void:
	for option in Selection.options(g, w):
		var activity
		match option.kind:
			"mine", "build", "produce", "operate": activity = Work.new()
			"eat", "sleep", "rest": activity = Life.new()
			"purchase", "borrow", "payroll": activity = Economy.new()
			"deliver": activity = Delivery.new()
		if activity.enter(g, w, option):
			active = activity
			review_elapsed = 0.0
			g.ai_trace.entered(g, w)
			return
		activity.exit(g, w, "rejected")
		g.ai_trace.record(g, w, "state_tree", "entry_rejected", g.WorkerTrace.proposal(option))
	decision_wait = 0.2

func exit(g, w: Dictionary, reason: String) -> void:
	if active != null:
		g.ai_trace.record(g, w, "state_tree", "exiting", {"reason": reason})
		active.exit(g, w, reason)
	active = null
	drink_elapsed = -1.0
	decision_wait = 0.0

func report_action(g) -> String:
	if active == null:
		return "空闲"
	if drink_elapsed >= 0:
		return "吃饭"
	match active.option.kind:
		"mine": return "通勤" if active.phase == "approach" else "挖掘"
		"build": return "通勤" if active.phase == "approach" else "工作"
		"produce", "operate":
			if active.phase == "approach": return "通勤"
			return "等待" if active.option.kind == "operate" and g.building_kind(active.option.target) == "drill" and not g.powered_devices.has(active.option.target) else "工作"
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
	var p = a.option.target
	result.path = a.path
	result.progress = a.elapsed
	match a.option.kind:
		"mine":
			result.state = "walk" if a.phase == "approach" else "dig"
			result.job = p
			result.progress = g.mining_contracts.get(p, {}).get("progress", 0.0)
		"build":
			result.state = "to_build" if a.phase == "approach" else "build"
			result.building = p
		"produce", "operate":
			result.state = "to_work" if a.phase == "approach" else "work"
			result.station = p
		"purchase":
			result.state = "to_shop"
			result.station = p
		"payroll": result.state = "to_payroll"
		"borrow": result.state = "to_bank"
		"eat":
			result.state = "to_meal" if a.phase == "approach" else "eat"
			result.canteen = a.option.data.get("canteen")
			result.meal_seat = p if result.canteen != null else null
		"sleep":
			result.state = "to_bed" if a.phase == "approach" else "sleep"
			result.bed = p if a.option.data.bed and not a.handles.is_empty() else null
		"rest": result.state = "rest"
		"deliver":
			result.state = ("deposit" if a.phase == "handoff" else "haul") if a.mined else ("freight_pickup" if a.phase == "pickup" else "freight_dropoff")
	if drink_elapsed >= 0:
		result.state = "drink"
	return result
