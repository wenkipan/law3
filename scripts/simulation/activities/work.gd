extends "res://scripts/simulation/activities/activity.gd"

var segment: Dictionary = {}
var fatigue_factor := 1.0

func exit(g, w: Dictionary, reason: String) -> void:
	g.settle_labor(w, segment, reason)
	super.exit(g, w, reason)

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
			if not g.smart_objects.occupy(handles) or not g.begin_work(option, w, segment):
				return "failure"
			fatigue_factor = segment.fatigue_factor
			phase = "use"
		return "running"
	var result: Dictionary = g.perform_work(option, w, delta, segment)
	labor_seconds = result.seconds
	return "success" if result.complete else "funding" if result.funding else "running"
