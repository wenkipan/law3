extends "res://scripts/simulation/activities/activity.gd"

func enter(g, w: Dictionary, proposal) -> bool:
	if not super.enter(g, w, proposal):
		return false
	if record.kind == "eat":
		if not g.FOOD_RECOVERY.has(record.data.item) or w.items.get(record.data.item, 0) < record.data.amount:
			return false
		w.meal_food = record.data.amount
		w.meal_item = record.data.item
		w.items[record.data.item] -= w.meal_food
	if record.kind in ["rest", "use_item"] or (record.kind == "sleep" and not record.data.bed):
		phase = "use"
		path.clear()
	return true

func valid(g, w: Dictionary) -> bool:
	return super.valid(g, w) and (record.kind != "emigrate" or g.wants_emigrate(w))

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
		"emigrate":
			g.world.emigrants.append(w.id)
			return "success"
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
			if bed != null and g.world.building_state(bed, "bed").remaining <= 0:
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
					if route_to(g, w, p) and path.size() <= 9:
						break
					path.clear()
			return "success" if age >= 1.0 else "running"
	return "failure"

func exit(g, w: Dictionary, reason: String) -> void:
	if record.kind == "eat":
		w.items[record.data.item] = w.items.get(record.data.item, 0) + w.meal_food
		w.meal_food = 0.0
		w.meal_item = ""
	if record.kind == "sleep" and record.data.bed and g.world.has_building(record.target, "bed") and not handles.is_empty() and g.world.smart_objects.valid(handles[0]):
		g.world.building_state(record.target, "bed").remaining = 0.0
	super.exit(g, w, reason)
