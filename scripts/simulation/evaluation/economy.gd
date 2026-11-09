extends RefCounted

const Labor = preload("res://scripts/simulation/evaluation/labor.gd")

static func purchase(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var item: String = op.data.item
	var f: Dictionary = e.environment.forecast(op, g.item_use_hours(item))
	var parts: Dictionary = e.item_effects(item, f.after, op.data.amount)
	return e.result(f, parts, g.sale_price(op.target, item) * op.data.amount, [e.item_group(item)])

static func payroll(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var amount: float = minf(g.PAYROLL_COLLECTION, g.stock_at(op.target, "bread"))
	var best := {"score": -INF, "hours": 0.0, "parts": {}}
	for option in op.get("work_options", []):
		var path: Array[Vector2i] = op.path.duplicate()
		var onward: Array[Vector2i] = g.route(op.target, option.approach_position)
		if onward.is_empty(): continue
		path.append_array(onward.slice(1))
		var work := {"kind": option.kind, "target": option.target, "position": option.approach_position,
			"path": path, "data": option.data, "funding": amount}
		var result: Dictionary = Labor.evaluate(e, work)
		if result.score > best.score: best = result
	return best

static func borrow(e, op: Dictionary) -> Dictionary:
	var f: Dictionary = e.environment.forecast(op, 0)
	var amount: float = minf(op.data.amount, e.context.game.stock_at(op.target, "bread"))
	return e.result(f, {"food_opportunity": e.resources.income(amount)})

static func support(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var producer: Dictionary = g.world.worker(op.data.producer)
	var child: Dictionary = g.world.worker(op.data.child)
	var amount: float = minf(op.data.amount, g.support_amount(producer, child))
	var f: Dictionary = e.environment.forecast(op, 0)
	if op.kind == "receive_bread":
		var cash: float = child.bread
		return e.result(f, {"food_opportunity": e.resources.potential(cash + amount) - e.resources.potential(cash)})
	var food: float = (child.bread + child.meal_bread) * g.HUNGER_PER_BREAD + child.items.get("meat", 0) * g.MEAT_HUNGER
	return e.result(f, {"child_food": e.needs.food_gain(child.hunger + food, amount * g.HUNGER_PER_BREAD),
		"giving": -e.resources.cost(amount, [], child.id)})
