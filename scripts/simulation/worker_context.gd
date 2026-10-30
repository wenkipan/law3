extends RefCounted

var game
var worker: Dictionary
var origin: Vector2i
var food_need := 0.0
var income_need := 0.0
var desired_cash := 0.0
var paths: Dictionary = {}
var tracing := false
var rejected: Array[Dictionary] = []
var proposals: Array[Dictionary] = []

func _init(world, person: Dictionary) -> void:
	game = world
	worker = person
	tracing = game.ai_trace.watches(person.id)
	origin = Vector2i(person.pos.round())
	food_need = clampf((game.MAX_HUNGER - person.hunger) / game.MAX_HUNGER, 0.0, 1.0)
	# A rolling reserve, not a daily work quota or a gate on eating and resting.
	desired_cash = maxf(0.0, (game.MAX_HUNGER - person.hunger) / game.HUNGER_PER_BREAD)
	for p in game.beds:
		if game.beds[p].assigned in [-1, person.id] and not path_to(p).is_empty():
			desired_cash += game.BED_PRICE * clampf(person.fatigue / (game.MAX_FATIGUE * 0.6), 0.0, 1.0)
			break
	var products: Dictionary = {}
	for p in game.benches:
		var kind: String = game.building_kind(p)
		var product: Dictionary = game.PRODUCTS.get(kind, {})
		if not product.has("price") or game.benches[p].stock <= 0 or path_to(p).is_empty():
			continue
		if product.has("durability") and person[product.durability] == 0:
			products[kind] = minf(products.get(kind, INF), game.sale_price(p))
		elif kind == "purifier" and person.mood.shopping > 0 and not game.has_debt(person) and person.water == 0 and person.water_effect <= 0:
			products[kind] = minf(products.get(kind, INF), game.sale_price(p) * mini(4, game.benches[p].stock))
	for price in products.values():
		desired_cash += price
	desired_cash += minf(4.0, person.loan_principal + person.loan_interest)
	income_need = clampf((desired_cash - person.bread) / maxf(4.0, desired_cash), 0.0, 1.0)

func path_to(p: Vector2i) -> Array[Vector2i]:
	if not paths.has(p):
		paths[p] = game.route(origin, p)
	return paths[p]

func travel_factor(path: Array[Vector2i], onward: Array[Vector2i] = []) -> float:
	var distance := maxf(0, path.size() - 1) + maxf(0, onward.size() - 1)
	var hours: float = distance / 3.0 / game.HOUR_SECONDS
	return 1.0 / (1.0 + hours * 0.4)

func labor_score(p = null, task: Dictionary = {}) -> float:
	var wage: float = task.reward / (task.seconds / game.HOUR_SECONDS) if task.has("reward") else game.station_wage(p)
	var rate: float = wage / game.WAGE_PER_HOUR
	var comfort := 1.0
	if p != null:
		var kind: String = game.building_kind(p)
		if not worker.mood.accepts_work(kind):
			comfort = 0.35
	var stamina := 1.0 - 0.65 * pow(worker.fatigue / game.MAX_FATIGUE, 2)
	return 0.9 * income_need * rate * stamina * comfort

func reject(kind: String, p, reason: String, details: Dictionary = {}) -> void:
	if tracing:
		var entry := {"kind": kind, "target": game.WorkerTrace.cell(p), "reason": reason}
		entry.merge(details)
		rejected.append(entry)

func trace_selection(choices: Array, reason: String) -> void:
	if not tracing:
		return
	var ranked: Array[Dictionary] = []
	for option in choices:
		ranked.append(game.WorkerTrace.proposal(option))
	var evaluated: Array[Dictionary] = []
	for entry in proposals:
		var row: Dictionary = game.WorkerTrace.proposal(entry.option)
		row.merge({"base_score": entry.base_score, "travel_factor": entry.travel_factor,
			"steps": entry.steps, "eligible": choices.has(entry.option)})
		if not row.eligible:
			row.reason = "needs_employer_cash"
		evaluated.append(row)
	var sites := 0
	for site in game.sites.values():
		if not site.get("cancelled", false):
			sites += 1
	var production_orders := 0
	for p in game.benches:
		if game.PRODUCTS.has(game.building_kind(p)) and game.has_production_order(p):
			production_orders += 1
	game.ai_trace.selection(game, worker, {"trigger": reason,
		"food_need": food_need, "desired_cash": desired_cash, "income_need": income_need,
		"ranked": ranked, "candidates": evaluated, "rejected": rejected,
		"opportunities": {"mines": game.mining_contracts.size(), "sites": sites,
			"production_orders": production_orders, "facilities": game.benches.size(),
			"shipments": game.shipments.size()}})
