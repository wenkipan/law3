extends "res://scripts/simulation/activities/activity.gd"

func valid(g, w: Dictionary) -> bool:
	if not super.valid(g, w):
		return false
	match record.kind:
		"purchase":
			return g.world.has_building(record.target, "station") and is_same(g.world.building_state(record.target, "station"), source_identity) and record.data.item in g.shop_goods(record.target)
		"borrow":
			return g.world.has_building(record.target, "bank")
		"payroll":
			var employer: int = record.data.get("building_id", g.delivery_receiver_id(record.data.employer))
			return g.can_take_job(w, record.data.employer, employer) and g.payroll_cash(record.target, employer) > 0.0
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
		"payroll":
			if not g.employ(w, record.data.employer, record.data.get("building_id", -1)): return "failure"
			g.collect_payroll(w, record.target)
	return "success"
