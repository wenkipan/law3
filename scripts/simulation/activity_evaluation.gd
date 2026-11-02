extends RefCounted

const Parameters = preload("res://scripts/simulation/activity_parameters.gd")

var context
var food_need := 0.0
var income_need := 0.0
var desired_cash := 0.0
var tracing := false
var rejected: Array[Dictionary] = []
var proposals: Array[Dictionary] = []

func _init(facts) -> void:
	context = facts
	var g = context.game
	var w: Dictionary = context.worker
	tracing = g.ai_trace.watches(w.id)
	food_need = clampf((g.MAX_HUNGER - w.hunger) / g.MAX_HUNGER, 0.0, 1.0)
	desired_cash = income_target()
	income_need = clampf((desired_cash - w.bread) / maxf(Parameters.INCOME_REFERENCE, desired_cash), 0.0, 1.0)

func income_target() -> float:
	var g = context.game
	var w: Dictionary = context.worker
	var target := maxf(0.0, (g.MAX_HUNGER - w.hunger) / g.HUNGER_PER_BREAD)
	for p in g.beds:
		if g.beds[p].assigned in [-1, w.id] and not context.path_to(p).is_empty():
			target += g.BED_PRICE * clampf(w.fatigue / (g.MAX_FATIGUE * Parameters.BED_RESERVE_FATIGUE), 0.0, 1.0)
			break
	var products: Dictionary = {}
	for p in g.benches:
		if context.path_to(p).is_empty(): continue
		for item in g.shop_goods(p):
			if g.stock_at(p, item) <= 0 or not g.wants_item(w, item): continue
			if item == "clean_water" and w.mood.shopping <= 0: continue
			var quantity: int = mini(Parameters.WATER_RESERVE, g.stock_at(p, item)) if item == "clean_water" else 1
			products[item] = minf(products.get(item, INF), g.sale_price(p, item) * quantity)
	for price in products.values():
		target += price
	for kind in g.SERVICES:
		if not g.wants_service(w, kind): continue
		var service: Dictionary = g.SERVICES[kind]
		for p in g.smart_objects.query(service.slot):
			if g.recipe_ready(p, service.materials) and not context.path_to(p).is_empty():
				target += service.price
				break
	return target + minf(Parameters.DEBT_RESERVE, w.loan_principal + w.loan_interest)

func travel_factor(path: Array, onward: Array = []) -> float:
	var distance := maxf(0, path.size() - 1) + maxf(0, onward.size() - 1)
	var hours: float = distance / Parameters.WALK_SPEED / context.game.HOUR_SECONDS
	return 1.0 / (1.0 + hours * Parameters.TRAVEL_COST)

func labor_score(p = null, task: Dictionary = {}) -> float:
	var g = context.game
	var w: Dictionary = context.worker
	var wage: float = task.reward / (task.seconds / g.HOUR_SECONDS) if task.has("reward") else g.station_wage(p)
	var rate: float = wage / g.WAGE_PER_HOUR
	var comfort := 1.0
	if p != null and not w.mood.accepts_work(g.building_kind(p)):
		comfort = Parameters.AVOIDED_WORK
	var stamina := 1.0 - Parameters.LABOR_FATIGUE * pow(w.fatigue / g.MAX_FATIGUE, 2)
	return Parameters.LABOR * income_need * rate * stamina * comfort

func item_score(item: String) -> float:
	if item == "ale":
		return Parameters.ALE_USE + Parameters.ALE_FATIGUE * context.worker.fatigue / context.game.MAX_FATIGUE
	if item == "meat": return Parameters.FOOD * pow(food_need, Parameters.FOOD_EXPONENT)
	return Parameters.EQUIP

func service_score(kind: String) -> float:
	var g = context.game
	var w: Dictionary = context.worker
	if kind == "hospital": return Parameters.HOSPITAL + w.pollution / Parameters.POLLUTION_REFERENCE
	if kind == "laundry": return Parameters.LAUNDRY + w.clothes_pollution / Parameters.POLLUTION_REFERENCE
	if w.pollution > g.Pollution.DISCOMFORT: return Parameters.DIRTY_BATH + w.pollution / Parameters.POLLUTION_REFERENCE
	return Parameters.SERVICE_MOOD if w.mood.shopping > 0 else Parameters.SERVICE

func meal_amount() -> float:
	var g = context.game
	var w: Dictionary = context.worker
	return minf(maxf(0, w.bread), maxf(0, g.MAX_HUNGER - w.hunger) / g.HUNGER_PER_BREAD)

func meal_score(amount: float, canteen := false) -> float:
	var score := pow(food_need, Parameters.FOOD_EXPONENT) * minf(1.0, amount / Parameters.MEAL_REFERENCE)
	if canteen: score = score + Parameters.CANTEEN + Parameters.CANTEEN_FATIGUE * context.worker.fatigue / context.game.MAX_FATIGUE
	return score

func meal_environment_bonus(p: Vector2i) -> float:
	return Parameters.CANTEEN_FOUNTAIN if context.game.has_powered_effect(Vector2(p), "fountain") else 0.0

func sleep_score(bed := false) -> float:
	var fatigue: float = context.worker.fatigue / context.game.MAX_FATIGUE
	var score := Parameters.EXHAUSTED_SLEEP if fatigue >= 1.0 else Parameters.SLEEP * pow(fatigue, Parameters.SLEEP_EXPONENT)
	return score * Parameters.BED if bed else score

func food_shortfall() -> float:
	return maxf(0, Parameters.BORROW_FOOD_RESERVE - context.worker.hunger / context.game.HUNGER_PER_BREAD - context.worker.bread)

func borrow_score() -> float:
	return Parameters.BORROW * food_need

func shopping_score(item: String, product: Dictionary, price: float) -> float:
	var optional := Parameters.OPTIONAL_SHOP_MOOD if context.worker.mood.shopping > 0 else Parameters.OPTIONAL_SHOP
	if item == "clean_water": return optional / price
	if item == "ale": return optional * product.price / price
	if item == "meat": return item_score(item)
	return Parameters.SHOP * float(product.price) / price

func shopping_amount(p: Vector2i, item: String, price: float) -> int:
	if item != "clean_water": return 1
	var g = context.game
	var w: Dictionary = context.worker
	return mini(w.mood.water_limit(g.WATER_CAPACITY), mini(g.stock_at(p, item), floori(w.bread / price)))

func freight_score() -> float:
	return Parameters.FREIGHT + Parameters.FREIGHT_INCOME * income_need

func mined_delivery_score(full: bool) -> float:
	return Parameters.COMMITTED_DELIVERY if full else Parameters.PARTIAL_DELIVERY

func reject(kind: String, p, reason: String, details: Dictionary = {}) -> void:
	if tracing:
		var entry := {"kind": kind, "target": context.game.WorkerTrace.cell(p), "reason": reason}
		entry.merge(details)
		rejected.append(entry)

func trace_selection(choices: Array, reason: String) -> void:
	if not tracing: return
	var g = context.game
	var ranked: Array[Dictionary] = []
	for option in choices:
		ranked.append(g.WorkerTrace.proposal(option))
	var evaluated: Array[Dictionary] = []
	for entry in proposals:
		var row: Dictionary = g.WorkerTrace.proposal(entry.option)
		row.merge({"base_score": entry.base_score, "travel_factor": entry.travel_factor,
			"steps": entry.steps, "eligible": choices.has(entry.option)})
		if not row.eligible: row.reason = "needs_employer_cash"
		evaluated.append(row)
	var sites := 0
	for site in g.sites.values():
		if not site.get("cancelled", false): sites += 1
	var production_orders := 0
	for p in g.benches:
		if g.PRODUCTS.has(g.building_kind(p)) and g.has_production_order(p): production_orders += 1
	g.ai_trace.selection(g, context.worker, {"trigger": reason,
		"food_need": food_need, "desired_cash": desired_cash, "income_need": income_need,
		"ranked": ranked, "candidates": evaluated, "rejected": rejected,
		"opportunities": {"mines": g.mining_contracts.size(), "sites": sites,
			"production_orders": production_orders, "facilities": g.benches.size(),
			"shipments": g.shipments.size()}})
