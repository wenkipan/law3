extends RefCounted

var option
var handles: Array[Dictionary] = []
var path: Array[Vector2i] = []
var destination: Vector2i
var phase := "approach"
var elapsed := 0.0
var age := 0.0
var labor_seconds := 0.0
var experience: Dictionary = {}

func enter(g, w: Dictionary, proposal) -> bool:
	option = proposal
	destination = option.destination
	path = option.path.duplicate()
	handles = g.smart_objects.acquire(option.slots, w.id)
	return handles.size() == option.slots.size()

func valid(g, _w: Dictionary) -> bool:
	for handle in handles:
		if not g.smart_objects.valid(handle):
			return false
	return true

func exit(g, _w: Dictionary, _reason: String) -> void:
	g.smart_objects.release(handles)
	handles.clear()
	path.clear()

func tick(_g, _w: Dictionary, _delta: float) -> String:
	return "success"

func navigate(g, w: Dictionary, delta: float, pace := 3.0) -> int:
	if path.any(func(cell): return g.terrain.get(cell, 1) != 0 or g.water_sources.has(cell)):
		path = g.route(Vector2i(w.pos.round()), destination)
	if path.is_empty():
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
