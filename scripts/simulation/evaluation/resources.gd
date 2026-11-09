extends RefCounted

var _evaluation: WeakRef
var evaluation:
	get: return _evaluation.get_ref()
var offers: Array[Dictionary] = []
var children: Array[Dictionary] = []

func _init(e) -> void:
	_evaluation = weakref(e)

func prepare() -> void:
	var e = evaluation
	var g = e.context.game
	var w: Dictionary = e.context.worker
	var state: Dictionary = e.environment.initial()
	for child in g.children_of(w):
		if not e.context.path_to(Vector2i(child.pos.round())).is_empty(): children.append(child)
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
			offers.append({"group": "clothing" if kind == "laundry" else "pollution", "price": g.base_fee(p), "value": total(parts)})
	if w.fatigue >= g.MAX_FATIGUE * e.Parameters.SLEEP_START:
		for p in g.world.smart_objects.query("bed"):
			if g.world.beds[p].assigned not in [-1, w.id] or e.context.path_to(p).is_empty(): continue
			var hours: float = minf(g.BED_LEASE_HOURS, w.fatigue / g.BED_RECOVERY_PER_HOUR)
			var saved: float = hours * (g.BED_RECOVERY_PER_HOUR / g.SLEEP_RECOVERY_PER_HOUR - 1.0)
			offers.append({"group": "fatigue", "price": g.base_fee(p),
				"value": e.Parameters.TIME_VALUE * saved + e.needs.mood_gain(state.mood, w.mood.BED_GAIN_PER_HOUR * hours, e.Parameters.FORECAST_HOURS)})

static func total(parts: Dictionary) -> float:
	var value := 0.0
	for part in parts.values(): value += part
	return value

func food_potential(cash: float, excluded_child := -1) -> float:
	var e = evaluation
	var g = e.context.game
	var w: Dictionary = e.context.worker
	var levels: Array[float] = [minf(g.MAX_HUNGER, w.hunger + w.items.get("meat", 0) * g.MEAT_HUNGER)]
	for child in children:
		if child.id == excluded_child: continue
		levels.append(minf(g.MAX_HUNGER, child.hunger + (child.bread + child.meal_bread) * g.HUNGER_PER_BREAD + child.items.get("meat", 0) * g.MEAT_HUNGER))
	levels.sort()
	levels.append(g.MAX_HUNGER)
	var food: float = maxf(0, cash) * g.HUNGER_PER_BREAD
	var value := 0.0
	var level: float = levels[0]
	# Allocate the same finite food opportunity to the strongest marginal needs.
	for i in range(1, levels.size()):
		var next: float = minf(levels[i], level + food / i)
		value += i * (e.needs.food_loss(level) - e.needs.food_loss(next))
		food -= (next - level) * i
		level = next
		if food <= 0: break
	return value

func potential(cash: float, excluded: Array = [], excluded_child := -1) -> float:
	var e = evaluation
	var result := 0.0
	if not excluded.has("food"):
		result = food_potential(cash, excluded_child)
	# Alternative uses share the same cash. Never add every shop/service price or benefit.
	for offer in offers:
		if excluded.has(offer.group) or offer.price <= 0: continue
		result = maxf(result, offer.value * clampf(cash / offer.price, 0, 1))
	return result

func cost(amount: float, excluded: Array = [], excluded_child := -1) -> float:
	var cash: float = evaluation.context.worker.bread
	return maxf(0, potential(cash, excluded, excluded_child) - potential(maxf(0, cash - amount), excluded, excluded_child))

func income(amount: float) -> float:
	var g = evaluation.context.game
	var w: Dictionary = evaluation.context.worker
	var net := amount - minf(amount * g.LOAN_REPAYMENT_RATE, w.loan_principal + w.loan_interest)
	return maxf(0, potential(w.bread + net) - potential(w.bread))
