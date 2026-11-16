extends RefCounted

const Slots = preload("res://scripts/simulation/smart_objects.gd")
var _evaluation: WeakRef
var evaluation:
	get: return _evaluation.get_ref()
var offers: Array[Dictionary] = []
var children: Array[Dictionary] = []
var food_quotes: Array[Dictionary] = []
# Each evaluation owns its quotes and memoized values; nothing survives the decision.
var _food_values: Dictionary = {}
var _potential_values: Dictionary = {}

func _init(e) -> void:
	_evaluation = weakref(e)

func prepare() -> void:
	var e = evaluation
	var g = e.context.game
	var w: Dictionary = e.context.worker
	var state: Dictionary = e.state
	for p in g.world.smart_objects.positions(Slots.Action.SHOP, {"items": g.FOOD_ITEMS + e.context.shopping_items()}):
		if e.context.path_to(p).is_empty(): continue
		for item in g.FOOD_ITEMS:
			var price: float = g.sale_price(p, item)
			if price > 0: food_quotes.append({"price": price, "stock": g.stock_at(p, item), "recovery": g.FOOD_RECOVERY[item]})
		for item in g.shop_goods(p):
			if g.stock_at(p, item) <= 0 or not g.wants_item(w, item): continue
			var parts: Dictionary = e.item_effects(item, state)
			offers.append({"group": e.item_group(item), "price": g.sale_price(p, item), "value": total(parts)})
	for kind in g.SERVICES:
		if not g.wants_service(w, kind): continue
		var rule: Dictionary = g.SERVICES[kind]
		for p in g.world.smart_objects.positions(Slots.Action.SERVICE, {"type": kind}):
			if not g.recipe_ready(p, rule.materials) or e.context.path_to(p).is_empty(): continue
			var parts: Dictionary = e.service_effects(kind, state)
			offers.append({"group": "clothing" if kind == "laundry" else "pollution", "price": g.base_fee(p), "value": total(parts)})
	if w.fatigue >= g.MAX_FATIGUE * e.Parameters.SLEEP_START:
		for p in g.world.smart_objects.positions(Slots.Action.BED):
			if g.world.building_state(p, "bed").assigned not in [-1, w.id] or e.context.path_to(p).is_empty(): continue
			var hours: float = minf(g.BED_LEASE_HOURS, w.fatigue / g.BED_RECOVERY_PER_HOUR)
			var saved: float = hours * (g.BED_RECOVERY_PER_HOUR / g.SLEEP_RECOVERY_PER_HOUR - 1.0)
			offers.append({"group": "fatigue", "price": g.base_fee(p),
				"value": e.Parameters.TIME_VALUE * saved + e.needs.mood_gain(state.mood, w.mood.BED_GAIN_PER_HOUR * hours, e.Parameters.FORECAST_HOURS)})

static func total(parts: Dictionary) -> float:
	var value := 0.0
	for part in parts.values(): value += part
	return value

func food_potential(cash: float, excluded_child := -1) -> float:
	if _food_values.has(cash): return _food_values[cash]
	var e = evaluation
	var g = e.context.game
	var w: Dictionary = e.context.worker
	var value := 0.0
	for quote in food_quotes:
		var amount: float = minf(quote.stock, maxf(0, cash) / quote.price)
		value = maxf(value, e.needs.food_gain(w.hunger + g.personal_food(w), amount * quote.recovery))
	_food_values[cash] = value
	return value

func potential(cash: float, excluded: Array = [], excluded_child := -1) -> float:
	var key := [cash, excluded, excluded_child]
	if _potential_values.has(key): return _potential_values[key]
	var result := 0.0
	if not excluded.has("food"):
		result = food_potential(cash, excluded_child)
	# Alternative uses share the same cash. Never add every shop/service price or benefit.
	for offer in offers:
		if excluded.has(offer.group) or offer.price <= 0: continue
		result = maxf(result, offer.value * clampf(cash / offer.price, 0, 1))
	_potential_values[key] = result
	return result

func cost(amount: float, excluded: Array = [], excluded_child := -1) -> float:
	var cash: float = evaluation.context.worker.money
	return maxf(0, potential(cash, excluded, excluded_child) - potential(maxf(0, cash - amount), excluded, excluded_child))

func income(amount: float) -> float:
	var g = evaluation.context.game
	var w: Dictionary = evaluation.context.worker
	var net := amount - minf(amount * g.LOAN_REPAYMENT_RATE, w.loan_principal + w.loan_interest)
	return maxf(0, potential(w.money + net) - potential(w.money))
