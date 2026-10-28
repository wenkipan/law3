extends RefCounted

const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var graph := AStar2D.new()
var points: Dictionary = {}
var cells: Dictionary = {}
var next_id := 0

func clear() -> void:
	graph.clear()
	points.clear()
	cells.clear()
	next_id = 0

func set_point_solid(cell: Vector2i, solid: bool) -> void:
	if solid:
		if points.has(cell):
			graph.remove_point(points[cell])
			cells.erase(points[cell])
			points.erase(cell)
		return
	if points.has(cell):
		return
	var id := next_id
	next_id += 1
	points[cell] = id
	cells[id] = cell
	graph.add_point(id, Vector2(cell))
	for direction in DIRS:
		if points.has(cell + direction):
			graph.connect_points(id, points[cell + direction])

func get_id_path(start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not points.has(start) or not points.has(target):
		return result
	for id in graph.get_id_path(points[start], points[target]):
		result.append(cells[id])
	return result
