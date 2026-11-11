extends RefCounted

const P = preload("res://scripts/simulation/activity_parameters.gd")
var context

func _init(facts) -> void:
	context = facts

func initial() -> Dictionary:
	var w: Dictionary = context.worker
	return {"hunger": w.hunger, "fatigue": w.fatigue, "pollution": w.pollution,
		"clothes_pollution": w.clothes_pollution,
		"clothes_hours": w.equipment.get("clothes", 0.0) / context.game.HOUR_SECONDS,
		"mood": clampf(w.mood.value + w.buffs.mood_bonus(w), -w.mood.LIMIT, w.mood.LIMIT)}

func external_at(p: Vector2i) -> float:
	var g = context.game
	var own_source := 0.0
	if context.worker.pollution >= g.Pollution.DISEASE:
		var offset: Vector2i = p - context.origin
		var distance: int = maxi(absi(offset.x), absi(offset.y))
		if distance <= 2: own_source = 20.0 * (1.0 - float(distance) / 3.0)
	return maxf(0, g.cache.pollution.at(p) - own_source)

func exposure_rate(p: Vector2i) -> float:
	return external_at(p) * context.game.Pollution.EXPOSURE_PER_HOUR

func estimate(op: Dictionary, hours: float) -> Dictionary:
	# Travel affects only distance/time cost; needs and effects use present facts.
	var travel_hours := walk_hours(op.path)
	return {"hours": travel_hours + hours, "travel_hours": travel_hours}

func walk_hours(path: Array) -> float:
	return maxf(0, path.size() - 1) / P.WALK_SPEED / context.game.HOUR_SECONDS
