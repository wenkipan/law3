extends RefCounted

const P = preload("res://scripts/simulation/activity_parameters.gd")

static func evaluate(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var w: Dictionary = e.context.worker
	var tasks: Array = op.data.tasks
	var mined: bool = op.data.mined
	var target: Vector2i = tasks[0].target
	var items: Array = op.data.items
	var amount := 0.0
	var quantities: Dictionary = {}
	var bound := false
	for i in tasks.size():
		amount += tasks[i].amount
		bound = bound or tasks[i].bound
		var item = items[i]
		quantities[item] = quantities.get(item, 0.0) + tasks[i].amount
	var route: Array = op.path.duplicate()
	var onward: Array = op.get("onward", [])
	if not onward.is_empty(): route.append_array(onward.slice(1))
	var travel := op.duplicate()
	travel.path = route
	travel.position = route.back() if not route.is_empty() else op.position
	var f: Dictionary = e.environment.forecast(travel, 0.6 * items.size() / g.HOUR_SECONDS if mined else 0.0)
	var required: Dictionary = g.delivery_requirements(target)
	var coverage := 0.0
	var generic_amount := 0.0
	for item in quantities:
		if item is int and required.has(0):
			generic_amount += quantities[item]
		else:
			var demand: float = required.get(item, 0.0)
			if demand > 0: coverage += quantities[item] / maxf(quantities[item], demand)
	if generic_amount > 0:
		coverage += generic_amount / maxf(generic_amount, required[0])
	coverage = minf(1.0, coverage)
	var parts := {"supply": P.SUPPLY_VALUE * coverage}
	if not mined and bound:
		parts.custody = P.CAPACITY_VALUE * minf(1, amount / g.FREIGHT_CAPACITY)
	if mined:
		var fullness: float = float(g.cargo_count(w)) / g.carry_capacity(w)
		var remaining: float = float(maxi(0, g.cargo_count(w) - items.size())) / g.carry_capacity(w)
		parts.capacity = P.CAPACITY_VALUE * (fullness * fullness - remaining * remaining)
		if op.position != target:
			parts.freight_fee = -e.resources.cost(minf(w.bread, g.BELT_FEE * items.size()))
	return e.result(f, parts)
