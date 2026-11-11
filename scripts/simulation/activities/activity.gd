extends RefCounted

const ActivityRecord = preload("res://scripts/simulation/activity_record.gd")

var record: ActivityRecord
# Runtime binding preserves replacement checks without copying an order into the record.
var source_identity: Dictionary = {}
var handles: Array[Dictionary] = []
var path: Array[Vector2i] = []
var destination: Vector2i
var phase := "approach"
var elapsed := 0.0
var age := 0.0
var labor_seconds := 0.0
var experience: Dictionary = {}

func enter(g, w: Dictionary, proposal) -> bool:
	record = ActivityRecord.new(proposal.kind, proposal.target, proposal.data)
	var identity = proposal.data.get("identity")
	if identity is Dictionary:
		source_identity = identity
	destination = proposal.approach_position
	path = proposal.approach_path.duplicate()
	handles = g.world.smart_objects.acquire(proposal.slots, w.id)
	return handles.size() == proposal.slots.size()

func valid(g, _w: Dictionary) -> bool:
	for handle in handles:
		if not g.world.smart_objects.valid(handle):
			return false
	return true

func matches_option(proposal) -> bool:
	return proposal != null and record.kind == proposal.kind and record.target == proposal.target and record.data.get("job") == proposal.data.get("job")

func exit(g, _w: Dictionary, _reason: String) -> void:
	g.world.smart_objects.release(handles)
	handles.clear()
	path.clear()

func tick(_g, _w: Dictionary, _delta: float) -> String:
	return "success"

func navigate(g, w: Dictionary, delta: float, pace := 3.0) -> int:
	if path.any(func(cell): return not g.world.walkable(cell)):
		path = g.route(Vector2i(w.pos.round()), destination)
		g.ai_trace.record(g, w, "navigation", "replanned", {"destination": g.WorkerTrace.cell(destination), "steps": path.size()})
	if path.is_empty():
		if w.pos.distance_to(Vector2(destination)) >= 0.01:
			g.ai_trace.record(g, w, "navigation", "unreachable", {"destination": g.WorkerTrace.cell(destination)})
		return 1 if w.pos.distance_to(Vector2(destination)) < 0.01 else -1
	var distance := delta * pace
	while not path.is_empty() and distance > 0:
		var next := Vector2(path[0])
		if absf(next.x - w.pos.x) > 0.01:
			w.facing = signf(next.x - w.pos.x)
		var remaining: float = w.pos.distance_to(next)
		if remaining <= distance:
			w.pos = next
			path.pop_front()
			distance -= remaining
		else:
			w.pos = w.pos.move_toward(next, distance)
			distance = 0
	return 1 if path.is_empty() and w.pos.distance_to(Vector2(destination)) < 0.01 else 0

func route_to(g, w: Dictionary, p: Vector2i) -> bool:
	destination = p
	path = g.route(Vector2i(w.pos.round()), p)
	return not path.is_empty()
