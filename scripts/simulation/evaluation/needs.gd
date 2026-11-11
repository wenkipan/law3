extends RefCounted

const P = preload("res://scripts/simulation/activity_parameters.gd")
var context

func _init(facts) -> void:
	context = facts

func food_loss(value: float) -> float:
	return P.FOOD_WEIGHT * pow(clampf(1.0 - value / context.game.MAX_HUNGER, 0, 1), 2)

func fatigue_loss(value: float) -> float:
	return P.FATIGUE_WEIGHT * pow(clampf(value / context.game.MAX_FATIGUE, 0, 1), 3)

func mood_loss(value: float) -> float:
	var limit: float = context.worker.mood.LIMIT
	return P.MOOD_WEIGHT * pow((limit - clampf(value, -limit, limit)) / (2.0 * limit), 2)

func pollution_loss(value: float) -> float:
	var rules = context.game.Pollution
	var dirt := clampf(value / rules.BODY_CAPACITY, 0, 1)
	var discomfort: float = maxf(0, value - rules.DISCOMFORT) / (rules.BODY_CAPACITY - rules.DISCOMFORT)
	var illness: float = maxf(0, value - rules.DISEASE) / (rules.BODY_CAPACITY - rules.DISEASE)
	return P.POLLUTION_WEIGHT * (dirt * dirt + discomfort * discomfort + illness * illness)

func food_gain(value: float, amount: float) -> float:
	return food_loss(value) - food_loss(value + maxf(0, amount))

func fatigue_gain(value: float, amount: float) -> float:
	return fatigue_loss(value) - fatigue_loss(value - amount)

func mood_gain(value: float, amount: float, hours: float) -> float:
	return (mood_loss(value) - mood_loss(value + amount)) * clampf(hours / P.FORECAST_HOURS, 0, 1)

func pollution_gain(value: float, amount: float) -> float:
	return pollution_loss(value) - pollution_loss(maxf(0, value - amount))
