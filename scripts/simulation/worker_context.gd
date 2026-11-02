extends RefCounted

var game
var worker: Dictionary
var origin: Vector2i
var paths: Dictionary = {}

func _init(world, person: Dictionary) -> void:
	game = world
	worker = person
	origin = Vector2i(person.pos.round())

func path_to(p: Vector2i) -> Array[Vector2i]:
	if not paths.has(p):
		var path: Array[Vector2i] = game.route(origin, p)
		path.make_read_only()
		paths[p] = path
	return paths[p]
