extends "res://scripts/simulation/activities/activity.gd"

func valid(g, w: Dictionary) -> bool:
	if not super.valid(g, w):
		return false
	match record.kind:
		"give_bread", "receive_bread":
			var producer: Dictionary = g.world.worker(record.data.producer)
			var child: Dictionary = g.world.worker(record.data.child)
			return g.support_amount(producer, child) > 0
		"purchase":
			return g.world.benches.has(record.target) and is_same(g.world.benches[record.target], source_identity)
		"borrow":
			return g.world.banks.has(record.target)
		"payroll":
			return record.target in g.stock_locations()
	return false

func tick(g, w: Dictionary, delta: float) -> String:
	if record.kind in ["give_bread", "receive_bread"]:
		var other: Dictionary = g.world.worker(record.data.child if record.kind == "give_bread" else record.data.producer)
		if other.is_empty(): return "failure"
		var position := Vector2i(other.pos.round())
		if position != destination and not route_to(g, w, position): return "failure"
	var reached := navigate(g, w, delta)
	if reached < 0:
		return "failure"
	if reached == 0:
		return "running"
	match record.kind:
		"give_bread", "receive_bread":
			var producer: Dictionary = g.world.worker(record.data.producer)
			var child: Dictionary = g.world.worker(record.data.child)
			if producer.is_empty() or child.is_empty() or producer.pos.distance_to(child.pos) > 1.0: return "running"
			return "success" if g.transfer_support(producer, child, record.data.amount) > 0 else "failure"
		"purchase": g.purchase(w, record.target, record.data.amount, record.data.item)
		"borrow": g.borrow(w, record.target, record.data.amount)
		"payroll": g.collect_payroll(w, record.target)
	return "success"
