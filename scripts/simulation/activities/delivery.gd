extends "res://scripts/simulation/activities/activity.gd"

var mined := false
var task: Dictionary = {}
var receiver: Vector2i

func enter(g, w: Dictionary, proposal) -> bool:
	if not super.enter(g, w, proposal):
		return false
	mined = record.data.get("mined", false)
	if not g.claim_delivery_tasks(w, proposal.data): return false
	task = w.delivery_tasks[0]
	if not g.world.delivery_tasks.has(task) or task.get("on_belt", false) or task.owner != w.id:
		return false
	receiver = task.target
	phase = "transport" if task.picked else "pickup"
	return true

func valid(g, w: Dictionary) -> bool:
	return w.skill == task.kind and (not mined or not is_same(w.carry, 0)) and g.world.delivery_tasks.has(task) and task.bound and not task.get("on_belt", false) and task.owner == w.id and g.world.smart_objects.valid(task.handle)

func matches_option(proposal) -> bool:
	# Pickup, transport and redirected routes still fulfill the same concrete task.
	return proposal.kind == task.kind and proposal.record.method == task.method and proposal.data.tasks.has(task)

func tick(g, w: Dictionary, delta: float) -> String:
	# Replan for receiver or connection changes, never temporary entry occupancy.
	if phase != "pickup" and (receiver != task.target
			or (destination != task.target and g.belt_destination(destination) != task.target)):
		if not transport_route(g, w):
			return "failure"
	if phase == "handoff":
		elapsed += delta
		if elapsed < (0.6 if mined else 0.0):
			return "running"
		if destination == task.target:
			g.unload_delivery(w, task)
		elif not g.load_belt(w, task, destination):
			return "running"
		if not w.delivery_tasks.is_empty():
			task = w.delivery_tasks[0]
			elapsed = 0.0
			return "running" if transport_route(g, w) else "failure"
		return "success"
	var reached := navigate(g, w, delta)
	if reached < 0:
		return "failure"
	if reached == 0:
		return "running"
	if phase == "pickup":
		for part in w.delivery_tasks: part.picked = true
		return "running" if transport_route(g, w) else "failure"
	phase = "handoff"
	elapsed = 0.0
	return "running"

func transport_route(g, w: Dictionary) -> bool:
	var target: Vector2i = task.target
	var leg: Dictionary = g.delivery_route(Vector2i(w.pos.round()), target)
	destination = leg.stop
	path = leg.path
	receiver = target
	phase = "transport"
	return not path.is_empty()

func exit(g, w: Dictionary, reason: String) -> void:
	for part in w.delivery_tasks.duplicate():
		if not part.picked and part.owner == w.id: g.release_delivery_task(part)
	# Picked cargo remains with its carrier across sleep and other interruptions.
	super.exit(g, w, reason)
