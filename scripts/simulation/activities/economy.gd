extends "res://scripts/simulation/activities/activity.gd"

func enter(g, w: Dictionary, proposal) -> bool:
	if not super.enter(g, w, proposal): return false
	return g.employ(w, record.data.employer) if record.kind == "payroll" else true

func valid(g, w: Dictionary) -> bool:
	if not super.valid(g, w):
		return false
	match record.kind:
		"purchase", "sell":
			return g.world.has_building(record.target, "station") and is_same(g.world.building_state(record.target, "station"), source_identity) and g.building_open(record.target)
		"borrow":
			return g.world.has_building(record.target, "bank")
		"payroll":
			return w.employer == g.delivery_receiver_id(record.data.employer) and g.can_take_job(w, record.data.employer) and record.target in g.stock_locations()
	return false

func tick(g, w: Dictionary, delta: float) -> String:
	var reached := navigate(g, w, delta)
	if reached < 0:
		return "failure"
	if reached == 0:
		return "running"
	match record.kind:
		"purchase": g.purchase(w, record.target, record.data.amount, record.data.item)
		"sell": g.market_sale(w, record.target, record.data.item, record.data.amount)
		"borrow": g.borrow(w, record.target, record.data.amount)
		"payroll": g.collect_payroll(w, record.target)
	return "success"
