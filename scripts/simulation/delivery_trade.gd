extends RefCounted

const Transactions = preload("res://scripts/simulation/transactions.gd")

static func ask(g, source: Vector2i, item) -> float:
	if g.is_built_market(source): return g.sale_price(source, item)
	return Transactions.quote(g, item, source, source)

static func bid(g, target: Vector2i, item) -> float:
	var requirements: Dictionary = g.delivery_requirements(target)
	var missing: float = g.delivery_shortfall(target, item, requirements)
	if missing <= 0.0: return Transactions.quote(g, item, target, target)
	var book := Transactions.book(g, item, target)
	var price := Transactions.price_from_pressure(book.value, g.trade_stock(target, item), missing)
	if g.is_built_market(target): return minf(price, g.sale_price(target, item))
	return price

static func lot(g, worker: Dictionary, source: Vector2i, target: Vector2i, item, requested: int, resale: bool) -> Dictionary:
	var available: int
	if resale:
		available = worker.get("trade_cargo", []).filter(func(goods): return is_same(goods.item, item)).size()
	else:
		available = floori(g.trade_stock(source, item))
	if available <= 0: return {}
	var buyer_price := bid(g, target, item)
	if buyer_price <= 0.0: return {}
	var affordable := floori((g.business_cash(target) + 0.000001) / buyer_price)
	var units := mini(available, mini(requested, mini(g.FREIGHT_CAPACITY, affordable)))
	var seller_price := 0.0
	if not resale:
		seller_price = ask(g, source, item)
		if buyer_price <= seller_price or seller_price <= 0.0: return {}
		units = mini(units, floori((worker.money + 0.000001) / seller_price))
	return {"units": units, "bid": buyer_price, "income": units * (buyer_price - seller_price)} if units > 0 else {}

static func claim(g, worker: Dictionary, plan: Dictionary) -> bool:
	var tasks: Array = plan.tasks
	var target: Vector2i = tasks[0].target
	var item = plan.items[0]
	var resale: bool = plan.get("resale", false)
	if worker.skill != g.WorkTypes.LOGISTICS or g.is_child(worker) or not is_same(worker.carry, 0): return false
	if g.route(Vector2i(worker.pos.round()), plan.source).is_empty() or g.route(plan.source, target).is_empty(): return false
	var terms := lot(g, worker, plan.source, target, item, tasks.size(), resale)
	if terms.is_empty() or terms.units != tasks.size(): return false
	var keys: Array[String] = []
	for task in tasks:
		if not g.world.delivery_tasks.has(task) or task.bound or task.target != target or task.receiver_id < 0 or task.receiver_id != g.delivery_receiver_id(target) or not g.delivery_task_accepts(task, item):
			return false
		var key: String = g.SmartObjects.delivery_key(task)
		if keys.has(key): return false
		keys.append(key)
	var handles: Array = g.world.smart_objects.acquire(keys, worker.id)
	if handles.size() != tasks.size(): return false
	for i in tasks.size():
		var task: Dictionary = tasks[i]
		task.merge({"source": plan.source, "item": item, "bound": true, "picked": resale,
			"owner": worker.id, "handle": handles[i], "resale_price": terms.bid}, true)
		if resale:
			var index: int = worker.trade_cargo.find_custom(func(goods): return is_same(goods.item, item))
			var goods: Dictionary = worker.trade_cargo.pop_at(index)
			task.pollution = goods.pollution
		g.world.register_delivery(task)
	worker.delivery_tasks = tasks.duplicate()
	g.supply_changed(target)
	return true

static func pickup(g, worker: Dictionary) -> bool:
	var tasks: Array = worker.delivery_tasks
	var first: Dictionary = tasks[0]
	var source: Vector2i = first.source
	var item = first.item
	var price := ask(g, source, item)
	var cost := price * tasks.size()
	if (worker.pos.distance_to(Vector2(source)) > 0.01 or price <= 0.0 or price >= first.resale_price
			or g.trade_stock(source, item) < tasks.size() or worker.money + 0.000001 < cost):
		return false
	var goods: Dictionary = g.take_goods(source, item, tasks.size())
	worker.money -= cost
	g.credit_proprietor(source, cost)
	for task in tasks:
		task.picked = true
		task.pollution = goods.pollution / tasks.size()
	Transactions.record(g, item, source, source, tasks.size(), cost, g.proprietor_at(source), worker.id)
	return true

static func sell(g, worker: Dictionary, tasks: Array) -> bool:
	var task: Dictionary = tasks[0]
	var target: Vector2i = task.target
	var price: float = task.resale_price * tasks.size()
	if (worker.pos.distance_to(Vector2(target)) > 0.01 or g.delivery_receiver_id(target) != task.receiver_id
			or g.business_cash(target) + 0.000001 < price):
		return false
	var recipe: Dictionary = g.delivery_requirements(target)
	var missing: float = recipe.get(task.requested_item, 0)
	if is_same(task.requested_item, 0):
		for ore in range(1, g.ORES.size()): missing -= g.stock_at(target, ore)
	else:
		missing -= g.stock_at(target, task.item)
	if missing + 0.000001 < tasks.size(): return false
	var buyer = g.proprietor_at(target)
	g.debit_business(target, price)
	g.add_private_money(worker.id, price)
	Transactions.record(g, task.item, target, target, tasks.size(), price, worker.id, buyer)
	return true

static func release(g, worker: Dictionary, task: Dictionary) -> void:
	if task.picked:
		if not worker.has("trade_cargo"): worker.trade_cargo = []
		worker.trade_cargo.append({"item": task.item, "amount": task.amount, "pollution": task.get("pollution", 0.0)})
	g.remove_delivery_task(task)
