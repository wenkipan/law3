extends RefCounted

const P = preload("res://scripts/simulation/activity_parameters.gd")
var context
var needs

func _init(facts, need_evaluation) -> void:
	context = facts
	needs = need_evaluation

func initial() -> Dictionary:
	var w: Dictionary = context.worker
	return {"hunger": w.hunger, "fatigue": w.fatigue, "pollution": w.pollution,
		"clothes_pollution": w.clothes_pollution,
		"clothes_hours": w.equipment.get("clothes", 0.0) / context.game.HOUR_SECONDS,
		"mood": clampf(w.mood.value + w.buffs.mood_bonus(w), -w.mood.LIMIT, w.mood.LIMIT), "elapsed": 0.0}

func external_at(p: Vector2i) -> float:
	var g = context.game
	var own_source := 0.0
	if context.worker.pollution >= g.Pollution.DISEASE:
		var offset: Vector2i = p - context.origin
		var distance: int = maxi(absi(offset.x), absi(offset.y))
		if distance <= 2: own_source = 20.0 * (1.0 - float(distance) / 3.0)
	return maxf(0, g.cache.pollution.at(p) - own_source)

func exposure_rate(p: Vector2i) -> float:
	return context.game.Pollution.BASE_PER_HOUR + external_at(p) * context.game.Pollution.EXPOSURE_PER_HOUR

func advance(state: Dictionary, p: Vector2i, hours: float) -> void:
	var g = context.game
	var w: Dictionary = context.worker
	var rate := exposure_rate(p)
	var covered := minf(hours, state.clothes_hours)
	if covered > 0:
		var absorbed := minf(rate * covered, maxf(0, g.Pollution.CLOTHES_CAPACITY - state.clothes_pollution))
		state.clothes_pollution += absorbed
		state.pollution += rate * covered - absorbed
	state.clothes_hours = maxf(0, state.clothes_hours - hours)
	if state.clothes_hours <= 0: state.clothes_pollution = 0.0
	state.pollution = minf(g.Pollution.BODY_CAPACITY, state.pollution + rate * (hours - covered))
	state.hunger = maxf(0, state.hunger - g.HUNGER_DECAY_PER_DAY / 24.0 * hours)
	if g.has_powered_effect(Vector2(p), "fountain"):
		state.fatigue = maxf(0, state.fatigue - g.FOUNTAIN_RECOVERY_PER_HOUR * hours)
	state.elapsed += hours
	var bonus := 0.0
	if w.buffs.remaining("tipsy") / g.HOUR_SECONDS > state.elapsed: bonus += g.WorkerBuffs.ALE_MOOD
	if w.buffs.remaining("bathed") / g.HOUR_SECONDS > state.elapsed: bonus += g.WorkerBuffs.BATH_MOOD
	if state.clothes_hours > 0:
		bonus += g.WorkerBuffs.CLOTHES_MOOD * (1.0 - state.clothes_pollution / g.Pollution.CLOTHES_CAPACITY)
	state.mood = clampf(move_toward(w.mood.value, 0, w.mood.RECOVERY_PER_HOUR * state.elapsed) + bonus, -w.mood.LIMIT, w.mood.LIMIT)

func forecast(op: Dictionary, hours: float) -> Dictionary:
	var state := initial()
	var path: Array = op.path
	var step_hours: float = 1.0 / P.WALK_SPEED / context.game.HOUR_SECONDS
	for i in range(1, path.size()):
		advance(state, path[i], step_hours)
	var arrival := state.duplicate()
	advance(state, op.position, hours)
	var baseline := initial()
	advance(baseline, context.origin, state.elapsed)
	return {"arrival": arrival, "after": state, "hours": state.elapsed,
		"use_hours": hours, "environment": needs.difference(baseline, state)}

func walk_hours(path: Array) -> float:
	return maxf(0, path.size() - 1) / P.WALK_SPEED / context.game.HOUR_SECONDS
