extends RefCounted

const Labor = preload("res://scripts/simulation/evaluation/labor.gd")

static func purchase(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var item: String = op.data.item
	var f: Dictionary = e.environment.estimate(op, g.item_use_hours(item))
	var price: float = g.sale_price(op.target, item)
	var best := {"score": -INF, "hours": f.hours, "parts": {}}
	var bonus: float = e.context.worker.activity.inertia_bonus(op)
	for amount in range(1, op.data.limit + 1):
		var parts: Dictionary = e.item_effects(item, e.state, amount)
		var result: Dictionary = e.result(f, parts, price * amount, [e.item_group(item)])
		if result.score + bonus > best.score + bonus and not is_equal_approx(result.score + bonus, best.score + bonus):
			best = result
			best.data = {"amount": amount}
	return best

static func payroll(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var best := {"score": -INF, "hours": 0.0, "parts": {}}
	var bonus: float = e.context.worker.activity.inertia_bonus(op)
	for option in op.get("work_options", []):
		var employer: int = option.data.get("building_id", g.delivery_receiver_id(option.target))
		var amount: float = g.payroll_cash(op.target, employer)
		if amount <= 0.0: continue
		var path: Array[Vector2i] = op.path.duplicate()
		var onward: Array[Vector2i] = g.route(op.target, option.position)
		if onward.is_empty(): continue
		path.append_array(onward.slice(1))
		var work := {"kind": option.kind, "target": option.target, "position": option.position,
			"path": path, "data": option.data, "funding": amount}
		var result: Dictionary = Labor.evaluate(e, work)
		if result.score + bonus > best.score + bonus and not is_equal_approx(result.score + bonus, best.score + bonus):
			best = result
			best.data = {"employer": option.target, "building_id": employer}
	return best

static func borrow(e, op: Dictionary) -> Dictionary:
	var f: Dictionary = e.environment.estimate(op, 0)
	var amount: float = minf(op.data.amount, e.context.game.stock_at(op.target, "money"))
	return e.result(f, {"food_opportunity": e.resources.income(amount)})
