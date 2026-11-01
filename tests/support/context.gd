extends RefCounted

var game: Node
var tree: SceneTree
var native: bool
var fixtures: RefCounted
var input: RefCounted
var checks := 0
var failures := 0
var scenario_name: String:
	get:
		return fixtures.scenario_name

func _init(scene_tree: SceneTree, world: Node, native_input: bool) -> void:
	tree = scene_tree
	game = world
	native = native_input
	fixtures = preload("res://tests/support/fixtures.gd").new(game)
	input = preload("res://tests/support/viewport_input.gd").new(tree, game, native)

func check(condition: bool, result: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL [%s]: %s" % [scenario_name, result])

func near(actual: float, expected: float, result: String, tolerance := 0.001) -> void:
	check(absf(actual - expected) <= tolerance, "%s (got %.3f, expected %.3f)" % [result, actual, expected])

func advance_until(outcome: Callable, seconds: float, result: String) -> float:
	var elapsed := 0.0
	while not outcome.call() and elapsed < seconds:
		game.simulate(0.1)
		elapsed += 0.1
	check(outcome.call(), result)
	return elapsed

func report_seconds(worker := -1, report_day := 1) -> float:
	var total := 0.0
	for value in game.report_totals(report_day, worker).values():
		total += value
	return total

func effect_description(id: String) -> String:
	var entries: Dictionary = game.get_node("UI").effect_icons.entries
	return entries[id].description if entries.has(id) and entries[id].visible else ""

func inventory_description(item) -> String:
	var entries: Dictionary = game.get_node("UI").inventory_icons.entries
	return entries[item].description if entries.has(item) and entries[item].visible else ""

func track_shows_item(item) -> bool:
	for p in game.belts:
		game.select_entity(p)
		if inventory_description(item).contains("搬运"):
			return true
	return false
