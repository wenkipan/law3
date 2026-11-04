extends RefCounted

var _evaluation: WeakRef
var evaluation:
	get: return _evaluation.get_ref()
var offers: Array[Dictionary] = []

func _init(e) -> void:
	_evaluation = weakref(e)

func prepare() -> void:
	var e = evaluation
	var g = e.context.game
	var w: Dictionary = e.context.worker
	var state: Dictionary = e.environment.initial()
	for p in g.world.smart_objects.query("shop"):
		if e.context.path_to(p).is_empty(): continue
		for item in g.shop_goods(p):
			if g.stock_at(p, item) <= 0 or not g.wants_item(w, item): continue
			var parts: Dictionary = e.item_effects(item, state)
			offers.append({"group": e.item_group(item), "price": g.sale_price(p, item), "value": total(parts)})
	for kind in g.SERVICES:
		if not g.wants_service(w, kind): continue
		var rule: Dictionary = g.SERVICES[kind]
		for p in g.world.smart_objects.query(rule.slot):
			if not g.recipe_ready(p, rule.materials) or e.context.path_to(p).is_empty(): continue
			var parts: Dictionary = e.service_effects(kind, state)
			offers.append({"group": "clothing" if kind == "laundry" else "pollution", "price": rule.price, "value": total(parts)})
			break
	if w.fatigue >= g.MAX_FATIGUE * e.Parameters.SLEEP_START:
		for p in g.world.smart_objects.query("bed"):
			if g.world.beds[p].assigned not in [-1, w.id] or e.context.path_to(p).is_empty(): continue
			var hours: float = minf(g.BED_LEASE_HOURS, w.fatigue / g.BED_RECOVERY_PER_HOUR)
			var saved: float = hours * (g.BED_RECOVERY_PER_HOUR / g.SLEEP_RECOVERY_PER_HOUR - 1.0)
			offers.append({"group": "fatigue", "price": g.BED_PRICE,
				"value": e.Parameters.TIME_VALUE * saved + e.needs.mood_gain(state.mood, w.mood.BED_GAIN_PER_HOUR * hours, e.Parameters.FORECAST_HOURS)})
			break

static func total(parts: Dictionary) -> float:
	var value := 0.0
	for part in parts.values(): value += part
	return value

func potential(cash: float, excluded: Array = []) -> float:
	var e = evaluation
	var w: Dictionary = e.context.worker
	var result := 0.0
	if not excluded.has("food"):
		var food: float = w.items.get("meat", 0) * e.context.game.MEAT_HUNGER
		result = e.needs.food_gain(w.hunger + food, cash * e.context.game.HUNGER_PER_BREAD)
	# Alternative uses share the same cash. Never add every shop/service price or benefit.
	for offer in offers:
		if excluded.has(offer.group) or offer.price <= 0: continue
		result = maxf(result, offer.value * clampf(cash / offer.price, 0, 1))
	return result

func cost(amount: float, excluded: Array = []) -> float:
	var cash: float = evaluation.context.worker.bread
	return maxf(0, potential(cash, excluded) - potential(maxf(0, cash - amount), excluded))

func income(amount: float) -> float:
	var g = evaluation.context.game
	var w: Dictionary = evaluation.context.worker
	var net := amount - minf(amount * g.LOAN_REPAYMENT_RATE, w.loan_principal + w.loan_interest)
	return maxf(0, potential(w.bread + net) - potential(w.bread))
