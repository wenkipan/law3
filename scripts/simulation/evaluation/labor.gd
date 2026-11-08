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
		seconds = g.station_work_hours(op.target) * g.HOUR_SECONDS
	var progress: float = contract.get("progress", 0.0)
	var rate: float = maxf(0.001, w.buffs.work_rate(g, w, op.kind, kind))
	var reward: float = seconds / g.HOUR_SECONDS * g.labor_wage(op.kind, op.target, contract)
	var funding: float = op.get("funding", w.payroll if w.payroll > 0.000001 else g.PAYROLL_COLLECTION)
	var goal: float = minf(seconds, (contract.get("paid", 0.0) + funding) / reward * seconds) if reward > 0 else seconds
	# Bound the estimate without imposing an execution or interruption timer.
	var remaining: float = minf(maxf(0, goal - progress), P.LABOR_EVALUATION_HOURS * g.HOUR_SECONDS * rate)
	return {"hours": remaining / rate / g.HOUR_SECONDS, "wage": reward * remaining / seconds,
		"progress_hours": remaining / g.HOUR_SECONDS,
		"fraction": remaining / maxf(0.001, seconds), "station": kind,
		"fatigue_factor": w.buffs.fatigue_factor(g, w)}

static func evaluate(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var w: Dictionary = e.context.worker
	var work := profile(e, op)
	if work.hours <= 0:
		return {"score": -INF, "hours": 0.0, "parts": {}, "work": work}
	var f: Dictionary = e.environment.forecast(op, work.hours)
	var parts := {"income": e.resources.income(work.wage),
		"task_progress": P.LABOR_PROGRESS_PER_HOUR * work.progress_hours,
		"fatigue": e.needs.fatigue_gain(f.after.fatigue, -work.hours * g.FATIGUE_PER_HOUR * work.fatigue_factor)}
	var stress: float = w.mood.WORK_STRESS.get(work.station, 0.0) * work.hours
	parts.mood = e.needs.mood_gain(f.after.mood, -stress, P.FORECAST_HOURS)
	if op.kind == "mine":
		var shortest: Array = []
		for p in g.world.smart_objects.query("store"):
			var leg: Dictionary = g.delivery_route(op.position, p)
			if not leg.path.is_empty() and (shortest.is_empty() or leg.path.size() < shortest.size()): shortest = leg.path
		var unloading_travel: float = e.environment.walk_hours(shortest) * work.fraction / g.carry_capacity(w)
		f.hours += unloading_travel
		f.travel_hours += unloading_travel
	# Compare hourly yields, including the full approach and apportioned unloading.
	# Only the comparison is scaled; forecasts and payable labor remain actual.
	for key in parts:
		parts[key] /= f.hours
	var comparison := {"hours": 1.0, "travel_hours": f.travel_hours / f.hours,
		"environment": f.environment / f.hours}
	var result: Dictionary = e.result(comparison, parts)
	result.hours = f.hours
	result.comparison_hours = comparison.hours
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
