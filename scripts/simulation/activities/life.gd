extends "res://scripts/simulation/activities/activity.gd"

func enter(g, w: Dictionary, proposal) -> bool:
	if not super.enter(g, w, proposal):
		return false
	if record.kind == "eat":
		if w.bread < record.data.amount:
			return false
		w.meal_bread = record.data.amount
		w.bread -= w.meal_bread
	if record.kind in ["rest", "use_item"] or (record.kind == "sleep" and not record.data.bed):
		phase = "use"
		path.clear()
	return true

func tick(g, w: Dictionary, delta: float) -> String:
	if phase == "approach":
		var reached := navigate(g, w, delta)
		if reached < 0:
			return "failure"
		if reached == 1:
			if not g.world.smart_objects.occupy(handles):
				return "failure"
			if record.kind == "sleep" and not g.rent_bed(w, record.target):
				return "failure"
			if record.kind == "service" and not g.can_use_service(w, record.target):
				return "failure"
			phase = "use"
		return "running"
	match record.kind:
		"use_item":
			elapsed += delta
			if elapsed < g.item_use_hours(record.data.item) * g.HOUR_SECONDS: return "running"
			return "success" if g.use_item(w, record.data.item) else "failure"
		"service":
			if not g.can_use_service(w, record.target): return "failure"
			elapsed += delta
			if elapsed < g.SERVICES[record.data.kind].hours * g.HOUR_SECONDS: return "running"
			return "success" if g.finish_service(w, record.target) else "failure"
		"eat":
			var seconds := minf(delta, g.MEAL_SECONDS - elapsed)
			g.eat_portion(w, record, seconds)
			elapsed += seconds
			experience = {"meal_fraction": seconds / g.MEAL_SECONDS,
				"comfortable": g.has_powered_effect(w.pos, "fountain")}
			return "success" if elapsed >= g.MEAL_SECONDS - 0.000001 else "running"
		"sleep":
			var bed = record.target if record.data.bed and not handles.is_empty() else null
			experience = g.sleep_seconds(w, bed, delta)
			if bed != null and g.world.beds[bed].remaining <= 0:
				g.world.smart_objects.release(handles)
				handles.clear()
			return "success" if w.fatigue <= 0.000001 else "running"
		"rest":
			if not path.is_empty():
				navigate(g, w, delta, 1.1)
			elif age < 0.1:
				var origin := Vector2i(w.pos.round())
				for attempt in 8:
					var p: Vector2i = origin + Vector2i(g.world.wander_rng.randi_range(-4, 4), g.world.wander_rng.randi_range(-3, 3))
					if g.world.explored.has(p) and route_to(g, w, p) and path.size() <= 9:
						break
					path.clear()
			return "success" if age >= 1.0 else "running"
	return "failure"

func exit(g, w: Dictionary, reason: String) -> void:
	if record.kind == "eat":
		w.bread += w.meal_bread
		w.meal_bread = 0.0
	if record.kind == "sleep" and record.data.bed and g.world.beds.has(record.target) and not handles.is_empty() and g.world.smart_objects.valid(handles[0]):
		g.world.beds[record.target].remaining = 0.0
	super.exit(g, w, reason)
