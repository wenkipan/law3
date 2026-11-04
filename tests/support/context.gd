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
	var elapsed := observe_until(outcome, seconds)
	check(outcome.call(), result)
	return elapsed

func observe_until(outcome: Callable, seconds: float) -> float:
	var elapsed := 0.0
	while not outcome.call() and elapsed < seconds:
		game.simulate(0.1)
		elapsed += 0.1
	return elapsed

func measure_power(plants: Array, seconds: float) -> Dictionary:
	var energy := 0.0
	var peak := 0.0
	var elapsed := 0.0
	while elapsed < seconds - 0.000001:
		var step := minf(0.05, seconds - elapsed)
		game.simulate(step)
		var output := 0.0
		for p in plants: output += game.cache.power_output.get(p, 0.0)
		energy += output * step / game.HOUR_SECONDS
		peak = maxf(peak, output)
		elapsed += step
	return {"energy": energy, "peak": peak}

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

func personal_feedback_text() -> String:
	var lines: Array[String] = []
	for label in game.world_view.get_node("Overlays/WorkerFeedback").find_children("*", "Label", true, false):
		if label.is_visible_in_tree(): lines.append(label.text)
	return "\n".join(lines)

func track_shows_item(item) -> bool:
	for p in game.world.belts:
		game.select_entity(p)
		if inventory_description(item).contains("搬运"):
			return true
	return false

func world_observations() -> Dictionary:
	var people: Array = []
	for w in game.world.workers:
		people.append({"name": w.name, "pos": w.pos, "bread": w.bread,
			"hunger": w.hunger, "fatigue": w.fatigue, "pollution": w.pollution,
			"clothes_pollution": w.clothes_pollution, "inventory": game.hud.worker_inventory_entries(w),
			"effects": w.buffs.display_effects(game, w)})
	var reports: Array = []
	for day in range(1, game.world.day + 1):
		reports.append({"labor": game.report_totals(day), "mined": game.report_mined(day)})
	var flows: Dictionary = {}
	for item in game.RESOURCE_ITEMS: flows[item] = game.resource_activity(item, game.world.day)
	# Inventory entry textures are presentation resources, not observable save data.
	for person in people:
		for item in person.inventory: item.erase("texture")
	return {"day": game.world.day, "time": game.world.day_elapsed,
		"inventory": game.resource_inventory(), "people": people, "reports": reports,
		"flows": flows, "mined": game.world.mined, "delivered": game.world.delivered}.duplicate(true)
