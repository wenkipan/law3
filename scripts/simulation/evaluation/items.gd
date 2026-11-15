extends RefCounted

const P = preload("res://scripts/simulation/activity_parameters.gd")
const Slots = preload("res://scripts/simulation/smart_objects.gd")

static func food(e, state: Dictionary, amount := 1) -> Dictionary:
	return {"food": e.needs.food_gain(state.hunger, e.context.game.MEAT_HUNGER * amount)}

static func ale(e, state: Dictionary, _amount := 1) -> Dictionary:
	var g = e.context.game
	var w: Dictionary = e.context.worker
	if w.buffs.remaining("tipsy") > 0: return {}
	var labor := 0.0
	for work in e.work_facts():
		if work.station not in g.GENERATOR_KINDS and work.station != "transformer": labor += work.hours
	labor = minf(labor, g.WorkerBuffs.ALE_HOURS)
	var slowdown: float = labor * (1.0 / g.WorkerBuffs.ALE_RATE - 1.0)
	return {"fatigue": e.needs.fatigue_gain(state.fatigue, g.WorkerBuffs.ALE_RECOVERY),
		"mood": e.needs.mood_gain(state.mood, g.WorkerBuffs.ALE_MOOD, g.WorkerBuffs.ALE_HOURS),
		"labor_time": -P.TIME_VALUE * slowdown}

static func clothing(e, state: Dictionary, _amount := 1) -> Dictionary:
	var g = e.context.game
	if state.clothes_hours > 0: return {}
	var hours: float = minf(P.FORECAST_HOURS, g.ITEM_USES.clothes.uses / g.HOUR_SECONDS)
	var absorbed: float = minf(g.Pollution.CLOTHES_CAPACITY, e.environment.exposure_rate(e.context.origin) * hours)
	return {"mood": e.needs.mood_gain(state.mood, g.WorkerBuffs.CLOTHES_MOOD * (1.0 - absorbed / g.Pollution.CLOTHES_CAPACITY), hours),
		"protection": e.needs.pollution_gain(state.pollution + absorbed, absorbed)}

static func mining_equipment(e, state: Dictionary, _amount := 1) -> Dictionary:
	var g = e.context.game
	var w: Dictionary = e.context.worker
	if w.gun_uses > 0: return {}
	var hours := 0.0
	var count := 0
	for work in e.work_facts():
		if work.method != "mine": continue
		hours += work.hours
		count += 1
		if count >= g.GUN_USES: break
	hours = minf(P.FORECAST_HOURS, hours)
	return saved_labor(e, state, hours, hours / g.GUN_MINING_RATE)

static func production_equipment(e, state: Dictionary, _amount := 1) -> Dictionary:
	var g = e.context.game
	if g.equipped_amount(e.context.worker, "tools") > 0: return {}
	var hours := 0.0
	var count := 0
	for work in e.work_facts():
		if work.method != "produce" or not g.tool_work(g.building_kind(work.target)): continue
		hours += work.hours
		count += 1
		if count >= g.ITEM_USES.tools.uses: break
	hours = minf(P.FORECAST_HOURS, hours)
	return saved_labor(e, state, hours, hours / g.WorkerBuffs.TOOL_RATE)

static func cargo_equipment(e, _state: Dictionary, _amount := 1) -> Dictionary:
	var g = e.context.game
	if e.context.worker.backpack_uses > 0: return {}
	var trips := 0
	var saved := 0.0
	for work in e.work_facts():
		if work.method != "mine": continue
		trips += 1
		if (trips + g.cargo_count(e.context.worker)) % 2 != 0: continue
		var best: Array = []
		for p in g.world.smart_objects.positions(Slots.Action.STORE):
			var path: Array = g.route(work.position, p)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()): best = path
		saved += 2.0 * e.environment.walk_hours(best)
		if trips / 2 >= g.BACKPACK_USES: break
	return {"transport_time": P.TIME_VALUE * minf(P.FORECAST_HOURS, saved)}

static func hydration(e, state: Dictionary, amount := 1) -> Dictionary:
	var g = e.context.game
	var w: Dictionary = e.context.worker
	var labor: float = e.work_hours()
	var available: float = w.buffs.remaining("hydrated") / g.HOUR_SECONDS + w.water * g.WATER_EFFECT_HOURS
	var covered: float = minf(labor, available + amount * g.WATER_EFFECT_HOURS) - minf(labor, available)
	var before: float = state.fatigue + minf(P.FORECAST_HOURS, labor) * g.FATIGUE_PER_HOUR
	return {"avoided_fatigue": e.needs.fatigue_gain(before, covered * g.FATIGUE_PER_HOUR * g.WATER_FATIGUE_REDUCTION)}

static func saved_labor(e, state: Dictionary, before: float, after: float) -> Dictionary:
	var g = e.context.game
	return {"labor_time": P.TIME_VALUE * (before - after),
		"avoided_fatigue": e.needs.fatigue_gain(state.fatigue + before * g.FATIGUE_PER_HOUR, (before - after) * g.FATIGUE_PER_HOUR)}

static func use(e, op: Dictionary) -> Dictionary:
	var f: Dictionary = e.environment.estimate(op, e.context.game.item_use_hours(op.data.item))
	var parts: Dictionary = {"food": e.needs.food_gain(e.state.hunger, e.context.game.FOOD_RECOVERY[op.data.item])} if e.context.game.FOOD_RECOVERY.has(op.data.item) else e.item_effects(op.data.item, e.state)
	# A preparation competes with starting the same funded work, not just with its savings.
	if e.Resources.total(parts) > 0:
		parts.work_opportunity = prepared_work(e, op.data.item, e.state)
	return e.result(f, parts)

static func prepared_work(e, item: String, state: Dictionary) -> float:
	var g = e.context.game
	var w: Dictionary = e.context.worker
	var best := 0.0
	if w.payroll <= 0: return best
	for work in e.work_facts():
		if item == "meat": continue
		if item in ["bench", "workbench"] and work.method != "mine": continue
		if item == "tools" and work.method != "produce": continue
		var rate: float = maxf(0.001, w.buffs.work_rate(g, w, work.method, work.station))
		var wage: float = g.labor_wage(work.method, work.target, work.contract)
		var hours: float = minf(P.LABOR_EVALUATION_HOURS, minf(work.hours, w.payroll / wage) / rate)
		var amount: float = hours * rate * wage
		var income: float = e.resources.income(amount)
		var cost: float = -e.needs.fatigue_gain(state.fatigue, -hours * g.FATIGUE_PER_HOUR * w.buffs.fatigue_factor(g, w))
		best = maxf(best, (income - cost) / (1.0 + P.TIME_COST * hours))
	return best
