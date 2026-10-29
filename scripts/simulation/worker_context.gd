extends RefCounted

var game
var worker: Dictionary
var origin: Vector2i
var food_need := 0.0
var income_need := 0.0
var desired_cash := 0.0
var paths: Dictionary = {}

func _init(world, person: Dictionary) -> void:
	game = world
	worker = person
	origin = Vector2i(person.pos.round())
	food_need = clampf((100.0 - person.hunger) / 100.0, 0.0, 1.0)
	# A rolling reserve, not a daily work quota or a gate on eating and resting.
	desired_cash = maxf(0.0, (120.0 - person.hunger) / game.HUNGER_PER_BREAD)
	for p in game.beds:
		if game.beds[p].assigned in [-1, person.id] and not path_to(p).is_empty():
			desired_cash += game.BED_PRICE * clampf(person.fatigue / 60.0, 0.0, 1.0)
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

func travel_factor(path: Array[Vector2i]) -> float:
	var hours: float = maxf(0, path.size() - 1) / 3.0 / game.HOUR_SECONDS
	return 1.0 / (1.0 + hours * 0.4)

func labor_score(p = null) -> float:
	var rate: float = game.station_wage(p) / game.WAGE_PER_HOUR
	var comfort := 1.0
	if p != null:
		var kind: String = game.building_kind(p)
		if not worker.mood.accepts_work(kind):
			comfort = 0.35
	var stamina := 1.0 - 0.65 * pow(worker.fatigue / 100.0, 2)
	return 0.9 * income_need * rate * stamina * comfort
