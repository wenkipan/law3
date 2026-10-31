extends "res://scripts/simulation/activities/activity.gd"

func valid(g, w: Dictionary) -> bool:
	if not super.valid(g, w):
		return false
	match option.kind:
		"purchase":
			return g.benches.has(option.target) and is_same(g.benches[option.target], option.data.identity)
		"borrow":
			return g.banks.has(option.target)
		"payroll":
			return option.target in g.stock_locations()
	return false

func tick(g, w: Dictionary, delta: float) -> String:
	var reached := navigate(g, w, delta)
	if reached < 0:
		return "failure"
	if reached == 0:
		return "running"
	match option.kind:
		"purchase": g.purchase(w, option.target, option.data.amount, option.data.item)
		"borrow": g.borrow(w, option.target, option.data.amount)
		"payroll": g.collect_payroll(w, option.target)
	return "success"
