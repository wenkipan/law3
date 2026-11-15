extends "res://scripts/simulation/activities/activity.gd"

var segment: Dictionary = {}
var fatigue_factor := 1.0

func enter(g, w: Dictionary, proposal) -> bool:
	if w.skill != proposal.kind: return false
	if not super.enter(g, w, proposal): return false
	return g.employ(w, record.target)

func exit(g, w: Dictionary, reason: String) -> void:
	g.settle_labor(w, segment, reason)
	super.exit(g, w, reason)

func valid(g, w: Dictionary) -> bool:
	if not super.valid(g, w):
		return false
	return g.work_available(record, w, source_identity)

func tick(g, w: Dictionary, delta: float) -> String:
	if phase == "approach":
		var reached := navigate(g, w, delta)
		if reached < 0:
			return "failure"
		if reached == 1:
			if not g.world.smart_objects.occupy(handles) or not g.begin_work(record, w, segment, source_identity):
				return "failure"
			fatigue_factor = segment.fatigue_factor
			phase = "use"
		return "running"
	var result: Dictionary = g.perform_work(record, w, delta, segment)
	labor_seconds = result.seconds
	return "success" if result.complete else "funding" if result.funding else "running"
