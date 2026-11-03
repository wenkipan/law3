extends RefCounted

const P = preload("res://scripts/simulation/activity_parameters.gd")

static func meal(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var f: Dictionary = e.environment.forecast(op, g.MEAL_SECONDS / g.HOUR_SECONDS)
	var parts := {"food": e.needs.food_gain(f.after.hunger, op.data.amount * g.HUNGER_PER_BREAD)}
	if op.data.has("canteen"):
		parts.fatigue = e.needs.fatigue_gain(f.after.fatigue, g.CANTEEN_RECOVERY)
	if g.has_powered_effect(Vector2(op.position), "fountain"):
		parts.mood = e.needs.mood_gain(f.after.mood, e.context.worker.mood.COMFORTABLE_MEAL_GAIN, P.FORECAST_HOURS)
	return e.result(f, parts, op.data.amount, ["food"])

static func sleep(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var arrival: Dictionary = e.environment.forecast(op, 0).arrival
	var passive: float = g.FOUNTAIN_RECOVERY_PER_HOUR if g.has_powered_effect(Vector2(op.position), "fountain") else 0.0
	var bed_hours := 0.0
	if op.data.bed:
		bed_hours = minf(g.BED_LEASE_HOURS, arrival.fatigue / (g.BED_RECOVERY_PER_HOUR + passive))
	var ground_hours: float = maxf(0, arrival.fatigue - bed_hours * (g.BED_RECOVERY_PER_HOUR + passive)) / (g.SLEEP_RECOVERY_PER_HOUR + passive)
	var f: Dictionary = e.environment.forecast(op, bed_hours + ground_hours)
	var parts := {"fatigue": e.needs.fatigue_gain(f.after.fatigue, arrival.fatigue)}
	if bed_hours > 0:
		parts.mood = e.needs.mood_gain(f.after.mood, e.context.worker.mood.BED_GAIN_PER_HOUR * bed_hours, P.FORECAST_HOURS)
	return e.result(f, parts, g.BED_PRICE if op.data.bed else 0, ["fatigue"])

static func treatment(e, op: Dictionary) -> Dictionary:
	var rule: Dictionary = e.context.game.SERVICES[op.data.kind]
	var f: Dictionary = e.environment.forecast(op, rule.hours)
	return e.result(f, treatment_effects(e, f.after, rule), rule.price, ["pollution"])

static func treatment_effects(e, state: Dictionary, rule: Dictionary) -> Dictionary:
	return {"pollution": e.needs.pollution_gain(state.pollution, rule.recovery)}

static func bath(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var rule: Dictionary = g.SERVICES[op.data.kind]
	var f: Dictionary = e.environment.forecast(op, rule.hours)
	return e.result(f, bath_effects(e, f.after, rule), rule.price, ["pollution", "mood"])

static func bath_effects(e, state: Dictionary, rule: Dictionary) -> Dictionary:
	var g = e.context.game
	var remaining: float = maxf(0, e.context.worker.buffs.remaining("bathed") / g.HOUR_SECONDS - state.elapsed)
	var added_hours: float = maxf(0, minf(P.FORECAST_HOURS, g.WorkerBuffs.BATH_EFFECT_HOURS) - minf(P.FORECAST_HOURS, remaining))
	return {"pollution": e.needs.pollution_gain(state.pollution, rule.recovery),
		"mood": e.needs.mood_gain(state.mood - (g.WorkerBuffs.BATH_MOOD if remaining > 0 else 0), g.WorkerBuffs.BATH_MOOD, added_hours)}

static func laundry(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var rule: Dictionary = g.SERVICES[op.data.kind]
	var f: Dictionary = e.environment.forecast(op, rule.hours)
	return e.result(f, laundry_effects(e, f.after, rule), rule.price, ["clothing", "mood"])

static func laundry_effects(e, state: Dictionary, rule: Dictionary) -> Dictionary:
	var g = e.context.game
	var removed: float = minf(state.clothes_pollution, rule.recovery) if state.clothes_hours > 0 else 0.0
	var horizon: float = minf(P.FORECAST_HOURS, state.clothes_hours)
	var capacity: float = g.Pollution.CLOTHES_CAPACITY
	return {"clothing": P.CLOTHING_WEIGHT * (pow(state.clothes_pollution / capacity, 2) - pow((state.clothes_pollution - removed) / capacity, 2)) * horizon / P.FORECAST_HOURS,
		"mood": e.needs.mood_gain(state.mood, g.WorkerBuffs.CLOTHES_MOOD * removed / capacity, horizon)}

static func rest(e, op: Dictionary) -> Dictionary:
	# The random wander destination is not known at selection time; it has no promised recovery.
	return e.result(e.environment.forecast(op, 1.0 / e.context.game.HOUR_SECONDS), {})
