extends RefCounted

const P = preload("res://scripts/simulation/activity_parameters.gd")

static func task(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	match op.kind:
		"mine": return g.world.mining_contracts[op.target]
		"build": return g.world.sites[op.target]
		"operate":
			if op.data.get("job") != null: return g.world.mining_contracts[op.data.job]
	return g.world.benches[op.target].task

static func profile(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var w: Dictionary = e.context.worker
	var contract: Dictionary = task(e, op)
	var kind: String = g.building_kind(op.target) if op.kind in ["produce", "operate"] else ""
	var seconds: float = contract.get("seconds", 0.0)
	if seconds <= 0:
		seconds = g.HOUR_SECONDS if op.kind == "operate" or kind in ["farm", "barn"] else g.PRODUCTS[kind].hours * g.HOUR_SECONDS
	var remaining: float = maxf(0, seconds - contract.get("progress", 0.0))
	var rate: float = w.buffs.work_rate(g, w, op.kind, kind)
	var reward: float = contract.get("reward", seconds / g.HOUR_SECONDS * g.station_wage(op.target if kind != "" else null))
	var due: float = maxf(0, reward - contract.get("paid", 0.0))
	var funding: float = op.get("funding", w.payroll if w.payroll > 0.000001 else g.PAYROLL_COLLECTION)
	var payable: float = minf(due, funding)
	if due > 0: remaining *= payable / due
	return {"hours": remaining / maxf(0.001, rate) / g.HOUR_SECONDS, "wage": payable,
		"fraction": remaining / maxf(0.001, seconds), "station": kind,
		"fatigue_factor": w.buffs.fatigue_factor(g, w)}

static func evaluate(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var w: Dictionary = e.context.worker
	var work := profile(e, op)
	var f: Dictionary = e.environment.forecast(op, work.hours)
	var parts := {"income": e.resources.income(work.wage),
		"task_progress": P.TASK_PROGRESS_VALUE * work.fraction,
		"fatigue": e.needs.fatigue_gain(f.after.fatigue, -work.hours * g.FATIGUE_PER_HOUR * work.fatigue_factor)}
	var stress: float = w.mood.WORK_STRESS.get(work.station, 0.0) * work.hours
	parts.mood = e.needs.mood_gain(f.after.mood, -stress, P.FORECAST_HOURS)
	if op.kind == "mine":
		var shortest: Array = []
		for p in g.world.smart_objects.query("store"):
			var leg: Dictionary = g.delivery_route(op.position, p)
			if not leg.path.is_empty() and (shortest.is_empty() or leg.path.size() < shortest.size()): shortest = leg.path
		f.hours += e.environment.walk_hours(shortest) / g.carry_capacity(w)
	var result: Dictionary = e.result(f, parts)
	result.work = work
	return result

static func mining(e, op: Dictionary) -> Dictionary:
	return evaluate(e, op)

static func construction(e, op: Dictionary) -> Dictionary:
	return evaluate(e, op)

static func production(e, op: Dictionary) -> Dictionary:
	return evaluate(e, op)

static func operation(e, op: Dictionary) -> Dictionary:
	return evaluate(e, op)
