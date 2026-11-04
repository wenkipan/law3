extends RefCounted

const P = preload("res://scripts/simulation/activity_parameters.gd")

static func evaluate(e, op: Dictionary) -> Dictionary:
	var g = e.context.game
	var w: Dictionary = e.context.worker
	var shipment: Dictionary = op.data.get("shipment", {})
	var mined: bool = op.data.get("mined", false)
	var target: Vector2i = shipment.get("target", op.data.get("target", op.target))
	var item = shipment.get("item", op.data.get("item", w.carry))
	var amount: float = shipment.get("amount", 1.0)
	var items: Array = []
	if mined:
		if shipment.is_empty():
			items = op.data.get("items", [item])
		else:
			for part in g.ore_delivery_batch(shipment): items.append(part.item)
	if shipment.is_empty() and not mined:
		amount = minf(g.FREIGHT_CAPACITY, minf(g.available_at(op.data.source, item), g.delivery_need(target, item)))
	var route: Array = op.path.duplicate()
	var onward: Array = op.get("onward", [])
	if not onward.is_empty(): route.append_array(onward.slice(1))
	var travel := op.duplicate()
	travel.path = route
	travel.position = route.back() if not route.is_empty() else op.position
	var f: Dictionary = e.environment.forecast(travel, 0.6 * items.size() / g.HOUR_SECONDS if mined else 0.0)
	var required: Dictionary = g.delivery_requirements(target)
	var demand: float = required.get(item, required.get(0, 0.0) if item is int else 0.0)
	var coverage: float = minf(1.0, amount / maxf(amount, demand)) if demand > 0 else 0.0
	if mined:
		var quantities: Dictionary = {}
		for ore in items:
			var key = 0 if ore is int and required.has(0) else ore
			quantities[key] = quantities.get(key, 0) + 1
		coverage = 0.0
		for key in quantities:
			var required_amount: float = required.get(key, 0)
			if required_amount > 0:
				coverage += float(quantities[key]) / maxf(quantities[key], required_amount)
		coverage = minf(1.0, coverage)
	var parts := {"supply": P.SUPPLY_VALUE * coverage}
	if not mined and not shipment.is_empty():
		parts.custody = P.CAPACITY_VALUE * minf(1, amount / g.FREIGHT_CAPACITY)
	if mined:
		var fullness: float = float(g.cargo_count(w)) / g.carry_capacity(w)
		var remaining: float = float(maxi(0, g.cargo_count(w) - items.size())) / g.carry_capacity(w)
		parts.capacity = P.CAPACITY_VALUE * (fullness * fullness - remaining * remaining)
		if op.position != target:
			parts.freight_fee = -e.resources.cost(minf(w.bread, g.BELT_FEE * items.size()))
	return e.result(f, parts)
