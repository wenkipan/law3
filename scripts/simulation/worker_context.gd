extends RefCounted

const Slots = preload("res://scripts/simulation/smart_objects.gd")
var game
var worker: Dictionary
var origin: Vector2i
var paths: Dictionary = {}
var proposal_order := 0

func job_slots(action: int) -> Array:
	var filters := {"skill": worker.skill, "available_to": worker.id}
	if worker.employer != null:
		var building = game.world.buildings.get(worker.employer)
		if building == null: return []
		filters.instance = Slots.building_id(building.id)
	return game.world.smart_objects.query(action, filters)

func shopping_items() -> Array:
	return game.MARKET_GOODS.filter(func(item): return game.wants_item(worker, item))

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
