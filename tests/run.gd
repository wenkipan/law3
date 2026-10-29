extends SceneTree

const SUITES := {
	"world": preload("res://tests/world_behaviors.gd"),
	"production": preload("res://tests/production_behaviors.gd"),
	"equipment": preload("res://tests/equipment_behaviors.gd"),
	"interaction": preload("res://tests/interaction_behaviors.gd"),
}
var game: Node
var scenario_name := ""
var checks := 0
var failures := 0
var native := false
var native_window_size := Vector2i.ZERO

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	native = "--native" in args
	var selected := ""
	for arg in args:
		if arg.begins_with("--suite="):
			selected = arg.trim_prefix("--suite=")
	if (selected != "" and not SUITES.has(selected)) or (native and DisplayServer.get_name() == "headless"):
		printerr("Use --suite=world|production|equipment|interaction; --native requires a window.")
		quit(2)
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	if native:
		root.grab_focus()
		await create_timer(0.25).timeout
	for suite in SUITES:
		if selected == "" or selected == suite:
			await SUITES[suite].new().run(self)
	print("%s: %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	game.free()
	quit(0 if failures == 0 else 1)

# Fixtures describe starting worlds, never in-flight tasks or decision state.
func scenario(label: String, population := 3, generated := false, seed_value := 1020) -> void:
	scenario_name = label
	print("CASE: ", label)
	game.reset_world(seed_value)
	if not generated:
		# Business scenarios use a quarry fixture, not a lucky generated starting area.
		game.water_sources.clear()
		for cell in game.terrain:
			game.terrain[cell] = 1
			game.navigation.set_point_solid(cell, true)
		clear_area(Rect2i(game.BASE - Vector2i(4, 2), Vector2i(9, 5)))
		var source := Vector2i(29, 10)
		game.water_sources[source] = true
		game.terrain[source] = 0
	game.workers.resize(population)
	game.world_view.rebuild(game)
	game.ai_trace.record(game, {}, "test", "scenario", {"name": label, "population": population})

func station(kind: String, p: Vector2i, stock := 0) -> void:
	if kind == "pump" and not game.near_water_source(p):
		var source := p + Vector2i.UP
		game.water_sources[source] = true
		game.terrain[source] = 0
		game.navigation.set_point_solid(source, true)
	game.benches[p] = game.production_station(kind)
	game.benches[p].stock = stock

func materials(amount: int, ore := 1) -> void:
	for mineral in range(1, game.ORES.size()):
		game.add_stock(game.BASE, mineral, -game.stock_at(game.BASE, mineral))
	game.add_stock(game.BASE, ore, amount)

func building_materials(kind: String, count := 1) -> void:
	materials(0)
	for ore in game.building_materials(kind):
		var amount: int = game.building_materials(kind)[ore] * count
		if is_same(ore, 0):
			game.add_stock(game.BASE, 1, maxi(0, amount - 2))
			game.add_stock(game.BASE, 2, mini(2, amount))
		else:
			game.add_stock(game.BASE, ore, amount)

func bed(p: Vector2i) -> void:
	game.beds[p] = {"remaining": 0.0, "assigned": -1}

func bank(p: Vector2i) -> void:
	game.banks[p] = {"interest_received": 0.0}
	var cash: float = minf(game.LOAN_LIMIT, game.stock_at(game.BASE, "bread"))
	game.add_stock(game.BASE, "bread", -cash)
	game.add_stock(p, "bread", cash)

func belt(p: Vector2i, direction: Vector2i) -> void:
	var inputs: Array = game.DIRS.duplicate()
	inputs.erase(direction)
	game.belts[p] = {"direction": direction, "inputs": inputs, "cargo": -1, "last_input": -1, "materials": {1: game.BELT_BLOCKS}}

func clear_area(area: Rect2i) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := Vector2i(x, y)
			game.terrain[p] = 0
			game.water_sources.erase(p)
			game.explored[p] = true
			game.navigation.set_point_solid(p, false)

func cable(p: Vector2i, kind := "low_line", axis := Vector2i.RIGHT) -> void:
	game.power_lines[p] = {"kind": kind, "axis": axis, "materials": game.building_materials(kind).duplicate()}

# A valid staffed circuit starts with facilities, fuel and people, never assigned jobs.
func power_facilities(transformers := 1, lamps := 4, offset := Vector2i.ZERO) -> Vector2i:
	clear_area(Rect2i(Vector2i(23, 6) + offset, Vector2i(25, 8 + transformers * 4)))
	var plant := Vector2i(24, 8) + offset
	station("power_plant", plant)
	game.add_stock(plant, 3, 10)
	game.add_stock(plant, "bread", 30)
	game.create_worker(plant)
	cable(plant + Vector2i(2, 0), "high_line")
	for y in range(8, 9 + (transformers - 1) * 4):
		cable(Vector2i(27, y) + offset, "high_line", Vector2i.DOWN)
	for i in transformers:
		var p := Vector2i(29, 8 + i * 4) + offset
		station("transformer", p)
		game.add_stock(p, "bread", 30)
		game.create_worker(p)
		for x in range(31, 45):
			cable(Vector2i(x + offset.x, p.y))
		for j in lamps:
			station("grow_light", Vector2i(32 + j * 3, p.y + 1) + Vector2i(offset.x, 0))
	return plant

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

func settle() -> void:
	if native and root.size != native_window_size:
		native_window_size = root.size
		root.grab_focus()
		# Let the window manager apply the resize before warping the real pointer.
		await create_timer(0.15).timeout
	game.update_ui()
	game.world_view.sync_dynamic()
	game.camera.force_update_scroll()
	await physics_frame
	await physics_frame
	await process_frame
	game.world_view.sync_dynamic()

func move_to(point: Vector2) -> void:
	if native:
		root.warp_mouse(point)
		# A warp updates the cached position before the OS finishes delivering motion.
		# Give native events a bounded settling interval before synthetic button presses.
		await create_timer(0.05).timeout
		for i in 6:
			await physics_frame
			if i >= 1 and root.get_mouse_position().distance_to(point) < 1.0:
				break
	var event := InputEventMouseMotion.new()
	event.position = point
	root.push_input(event, true)
	await settle()

func click(point: Vector2) -> void:
	await move_to(point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await settle()
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await settle()

func click_world(point: Vector2) -> void:
	await click(game.get_global_transform_with_canvas() * point)

func drag_world(cells: Array[Vector2i], release_over_ui := false, cancel_with_mouse := false, preview_file := "", offset := Vector2.ZERO) -> void:
	await move_to(game.get_global_transform_with_canvas() * (game.tile_center(cells[0]) + offset))
	var event := InputEventMouseButton.new()
	event.position = game.get_global_transform_with_canvas() * (game.tile_center(cells[0]) + offset)
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await settle()
	for cell in cells.slice(1):
		await move_to(game.get_global_transform_with_canvas() * (game.tile_center(cell) + offset))
	var endpoint: Vector2 = game.pause_button.get_global_rect().get_center() if release_over_ui else game.get_global_transform_with_canvas() * (game.tile_center(cells.back()) + offset)
	await move_to(endpoint)
	if native and preview_file != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preview_file)
	if cancel_with_mouse:
		var cancel := InputEventMouseButton.new()
		cancel.position = endpoint
		cancel.button_index = MOUSE_BUTTON_RIGHT
		cancel.pressed = true
		root.push_input(cancel, true)
		cancel = cancel.duplicate()
		cancel.pressed = false
		root.push_input(cancel, true)
		await settle()
	event = event.duplicate()
	event.position = endpoint
	event.pressed = false
	root.push_input(event, true)
	await settle()
