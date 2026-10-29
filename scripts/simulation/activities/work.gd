extends "res://scripts/simulation/activities/activity.gd"

func valid(g, w: Dictionary) -> bool:
	if not super.valid(g, w):
		return false
	return g.work_available(option, w)

func tick(g, w: Dictionary, delta: float) -> String:
	if phase == "approach":
		var reached := navigate(g, w, delta)
		if reached < 0:
			return "failure"
		if reached == 1:
			if not g.smart_objects.occupy(handles) or not g.begin_work(option, w):
				return "failure"
			phase = "use"
		return "running"
	if w.payroll <= 0.000001:
		return "failure"
	var result: Dictionary = g.perform_work(option, w, delta)
	labor_seconds = result.seconds
	return "success" if result.complete else "running"
