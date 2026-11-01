extends RefCounted

var tree: SceneTree
var game: Node
var root: Window
var native: bool
var native_window_size := Vector2i.ZERO

func _init(scene_tree: SceneTree, world: Node, native_input: bool) -> void:
	tree = scene_tree
	game = world
	root = tree.root
	native = native_input

func settle() -> void:
	if native and root.size != native_window_size:
		native_window_size = root.size
		root.grab_focus()
		# Let the window manager apply the resize before warping the real pointer.
		await tree.create_timer(0.15).timeout
	game.update_ui()
	game.world_view.sync_dynamic()
	game.camera.force_update_scroll()
	await tree.physics_frame
	await tree.physics_frame
	await tree.process_frame
	game.world_view.sync_dynamic()

func move_to(point: Vector2) -> void:
	if native:
		root.warp_mouse(point)
		# A warp updates the cached position before the OS finishes delivering motion.
		# Give native events a bounded settling interval before synthetic button presses.
		await tree.create_timer(0.05).timeout
		for i in 6:
			await tree.physics_frame
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

func choose_building(kind: String) -> void:
	await settle()
	var ui = game.get_node("UI")
	for category in ui.BUILD_CATEGORIES:
		if kind in ui.BUILD_CATEGORIES[category].kinds and (not game.build_tray.visible or ui.selected_build_category != category):
			await click(ui.category_buttons[category].get_global_rect().get_center())
	var scroll: ScrollContainer = game.tool_buttons[kind].get_parent().get_parent()
	for attempt in 12:
		var target: Rect2 = game.tool_buttons[kind].get_global_rect()
		var visible_area := scroll.get_global_rect()
		if visible_area.encloses(target): break
		await scroll_at(visible_area.get_center(), MOUSE_BUTTON_WHEEL_DOWN if target.end.y > visible_area.end.y else MOUSE_BUTTON_WHEEL_UP)
	await click(game.tool_buttons[kind].get_global_rect().get_center())

func close_build_tray() -> void:
	var ui = game.get_node("UI")
	if game.build_tray.visible:
		await click(ui.category_buttons[ui.selected_build_category].get_global_rect().get_center())

func scroll_at(point: Vector2, button: MouseButton) -> void:
	await move_to(point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await settle()

func click_exposed_building(cell: Vector2i, title: String) -> void:
	# Keep workers where simulation left them; click distinct exposed edges, never move them away.
	for offset in [Vector2(0, 16), Vector2(-18, 16), Vector2(18, 16), Vector2(-18, -18), Vector2(18, -18)]:
		await click_world(game.tile_center(cell) + offset)
		if game.entity_title.text == title:
			return

func choose_report_filter(report: Window, button: OptionButton, index: int) -> void:
	await click(Vector2(report.position) + button.get_global_rect().get_center())
	var popup := button.get_popup()
	if not popup.visible:
		return
	var keys := [KEY_HOME]
	for i in index + 1:
		keys.append(KEY_DOWN)
	keys.append(KEY_ENTER)
	for key in keys:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = true
		root.push_input(event, true)
		event = event.duplicate()
		event.pressed = false
		root.push_input(event, true)
		await settle()

func screenshot(path: String, viewport: Viewport = root) -> void:
	if not native:
		return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(path)
