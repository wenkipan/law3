extends "res://scripts/simulation/activities/activity.gd"

func valid(g, w: Dictionary) -> bool:
	if not super.valid(g, w):
		return false
	match record.kind:
		"purchase":
			return g.world.benches.has(record.target) and is_same(g.world.benches[record.target], source_identity)
		"borrow":
			return g.world.banks.has(record.target)
		"payroll":
			return record.target in g.stock_locations()
	return false

func tick(g, w: Dictionary, delta: float) -> String:
	var reached := navigate(g, w, delta)
	if reached < 0:
		return "failure"
	if reached == 0:
		return "running"
	match record.kind:
		"purchase": g.purchase(w, record.target, record.data.amount, record.data.item)
		"borrow": g.borrow(w, record.target, record.data.amount)
		"payroll": g.collect_payroll(w, record.target)
	return "success"
