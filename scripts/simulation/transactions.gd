extends RefCounted

const Slots = preload("res://scripts/simulation/smart_objects.gd")
const MAX_RECORDS := 256

static func labor(skill: String) -> String:
	return "labor/" + skill

static func service(kind: String) -> String:
	return "service/" + kind

static func record(g, subject, seller: Vector2i, buyer: Vector2i, units: float, amount: float, seller_account = null, buyer_account = null) -> void:
	if units <= 0.0 or amount <= 0.0: return
	g.cache.trade_books.clear()
	var history: Array = g.world.transactions
	var row := {"subject": subject, "seller": seller, "buyer": buyer, "units": units, "amount": amount, "day": g.world.day}
	if seller_account != null: row.seller_account = seller_account
	if buyer_account != null: row.buyer_account = buyer_account
	history.append(row)
	if history.size() > MAX_RECORDS: history.pop_front()
	g.trace_economy("transaction", buyer, history.back())

# The settlement price is a quote between endpoints. Only an executed transfer enters history.
static func quote(g, subject, seller: Vector2i, buyer: Vector2i, demand := 0.0) -> float:
	var market := book(g, subject, seller)
	var other := market if buyer == seller else book(g, subject, buyer)
	var supply: float = (market.supply + other.supply) * 0.5
	var requests: float = maxf(demand, (market.demand + other.demand) * 0.5)
	var reference: float = (market.value + other.value) * 0.5
	return price_from_pressure(reference, supply, requests)

static func price_from_pressure(reference: float, supply: float, requests: float) -> float:
	var pressure := (requests - supply) / (1.0 + requests + supply)
	return maxf(0.05, snappedf(reference * exp(0.65 * pressure), 0.05))

static func book(g, subject, position: Vector2i) -> Dictionary:
	var key := [subject, position]
	if not g.cache.trade_books.has(key):
		g.cache.trade_books[key] = read_book(g, subject, position)
	return g.cache.trade_books[key]

static func read_book(g, subject, position: Vector2i) -> Dictionary:
	var supply := 0.0
	var demand := 0.0
	var end_demand := 0.0
	var reference := replacement(g, subject)
	var amount := 0.0
	var units := 0.0
	for row in g.world.transactions:
		if not is_same(row.subject, subject): continue
		var weight := proximity(g, position, row.seller) / (1.0 + maxf(0, g.world.day - row.day))
		amount += row.amount * weight
		units += row.units * weight
	var value := (reference * 2.0 + amount) / (2.0 + units)
	if subject is String and subject.begins_with("labor/"):
		var skill: String = subject.trim_prefix("labor/")
		for worker in g.world.workers:
			if worker.skill == skill and not g.is_child(worker):
				var capacity := 1.0 - clampf(worker.fatigue / g.MAX_FATIGUE, 0.0, 1.0)
				supply += capacity * proximity(g, position, Vector2i(worker.pos.round()))
		for endpoint in g.world.smart_objects.query(skill, {"domain": Slots.Definitions.Domain.BUILDING}):
			if not g.world.smart_objects.labor_offer(endpoint).has("reason"):
				demand += proximity(g, position, endpoint.position)
	elif subject is String and subject.begins_with("service/"):
		var kind: String = subject.trim_prefix("service/")
		for location in g.world.built_building_positions([kind]):
			supply += proximity(g, position, location)
		for worker in g.world.workers:
			var need: float = worker.fatigue / g.MAX_FATIGUE if kind == "bed" else float(g.wants_service(worker, kind))
			if kind == "market":
				need = maxf(0.0, g.hunger_decay(worker) - g.personal_food(worker)) / g.FOOD_RECOVERY.bread
			demand += minf(need, worker.money / reference) * proximity(g, position, Vector2i(worker.pos.round()))
	else:
		for source in g.world.storage_locations():
			supply += g.trade_stock(source, subject) * proximity(g, position, source)
		for task in g.world.delivery_tasks:
			if not task.bound and g.delivery_task_accepts(task, subject):
				var requested: float = minf(task.amount, g.business_cash(task.target) / reference) * proximity(g, position, task.target)
				demand += requested
				if not g.is_built_market(task.target): end_demand += requested
		if g.FOOD_RECOVERY.has(subject):
			for worker in g.world.workers:
				# Food options share one appetite and one wallet.
				var need: float = minf(g.hunger_decay(worker), maxf(0.0, g.MAX_HUNGER - worker.hunger - g.personal_food(worker)))
				var requested: float = minf(need / g.FOOD_RECOVERY[subject], worker.money / reference) * proximity(g, position, Vector2i(worker.pos.round())) / g.FOOD_ITEMS.size()
				demand += requested
				end_demand += requested
	return {"value": value, "supply": supply, "demand": demand, "end_demand": end_demand, "traded": units}

static func proximity(g, a: Vector2i, b: Vector2i) -> float:
	if a != b and not g.cache.navigation.connected(a, b): return 0.0
	return 1.0 / (1.0 + a.distance_to(b) / 4.0)

# Initial units are derived from physical work when no trade has happened yet.
static func replacement(g, subject) -> float:
	if subject is int and subject > 0 and subject < g.ORES.size(): return g.ORES[subject].hours
	if subject is String and subject.begins_with("service/"):
		if subject == service("market"): return 1.0 / g.MARKET_STOCK
		return maxf(1.0, g.default_fee(subject.trim_prefix("service/")))
	for kind in g.PRODUCTS:
		if is_same(g.product_item(kind), subject):
			var product: Dictionary = g.PRODUCTS[kind]
			return maxf(0.25, (product.hours + g.production_materials(kind).size()) / product.get("amount", 1))
	return 1.0
