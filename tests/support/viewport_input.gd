extends RefCounted

var tree: SceneTree
var game: Node
var root: Window
var native: bool
var native_window_size := Vector2i.ZERO
var pointer := Vector2.ZERO
var os_mouse := false

func _init(scene_tree: SceneTree, world: Node, native_input: bool) -> void:
	tree = scene_tree
	game = world
	root = tree.root
	native = native_input
	os_mouse = native and DisplayServer.get_name() == "X11" and FileAccess.file_exists("/usr/bin/xdotool")

func settle() -> void:
	if native and root.size != native_window_size:
		native_window_size = root.size
		root.grab_focus()
		# Let the window manager apply the resize before warping the real pointer.
		await tree.create_timer(0.15, true, false, true).timeout
	game.update_ui()
	game.world_view.sync_dynamic()
	game.world_view.camera.force_update_scroll()
	await tree.physics_frame
	await tree.physics_frame
	await tree.process_frame
	game.world_view.sync_dynamic()
	if native:
		await RenderingServer.frame_post_draw

func move_to(point: Vector2) -> void:
	pointer = point
	if native:
		if not root.has_focus():
			root.grab_focus()
			await tree.create_timer(0.1, true, false, true).timeout
		root.warp_mouse(point)
		# A warp updates the cached position before the OS finishes delivering motion.
		# Give native events a bounded settling interval before button presses.
		await tree.create_timer(0.05, true, false, true).timeout
		for i in 6:
			await tree.physics_frame
			if i >= 1 and root.get_mouse_position().distance_to(point) < 1.0:
				break
		if os_mouse:
			await settle()
			return
	var event := InputEventMouseMotion.new()
	event.position = point
	root.push_input(event, true)
	await settle()

func send_button(event: InputEventMouseButton) -> void:
	if os_mouse:
		OS.execute("/usr/bin/xdotool", ["mousedown" if event.pressed else "mouseup", str(event.button_index)])
	else:
		root.push_input(event, true)

func click(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	await move_to(point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	send_button(event)
	await settle()
	event = event.duplicate()
	event.pressed = false
	send_button(event)
	await settle()

func click_world(point: Vector2) -> void:
	await settle()
	await click(game.get_global_transform_with_canvas() * point)

func press_world(point: Vector2) -> void:
	await settle()
	await press(game.get_global_transform_with_canvas() * point)

func press(point: Vector2) -> void:
	await move_to(point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	send_button(event)
	await settle()

func release() -> void:
	var event := InputEventMouseButton.new()
	event.position = pointer
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	send_button(event)
	await settle()

func hold_world(point: Vector2, seconds: float) -> void:
	await begin_hold_world(point)
	game.simulate(seconds)
	await release()

func begin_hold_world(point: Vector2) -> void:
	await press_world(point)
	await tree.create_timer(0.3, true, false, true).timeout

func press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	await settle()
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await settle()

func choose_save_slot(menu: Window, list: ItemList, slot: int) -> void:
	await settle()
	await click(Vector2(menu.position) + list.global_position + list.get_item_rect(slot).get_center())

func choose_option(button: OptionButton, id: int) -> void:
	await click(button.get_global_rect().get_center())
	var popup := button.get_popup()
	var fraction: float = (button.get_item_index(id) + 0.5) / button.item_count
	await click(Vector2(popup.position) + Vector2(popup.size.x * 0.5, popup.size.y * fraction))

func drag_world(cells: Array[Vector2i], release_over_ui := false, right_click := false, offset := Vector2.ZERO) -> void:
	await settle()
	await move_to(game.get_global_transform_with_canvas() * (game.tile_center(cells[0]) + offset))
	var event := InputEventMouseButton.new()
	event.position = game.get_global_transform_with_canvas() * (game.tile_center(cells[0]) + offset)
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	send_button(event)
	await settle()
	for cell in cells.slice(1):
		await move_to(game.get_global_transform_with_canvas() * (game.tile_center(cell) + offset))
	var endpoint: Vector2 = game.hud.pause_button.get_global_rect().get_center() if release_over_ui else game.get_global_transform_with_canvas() * (game.tile_center(cells.back()) + offset)
	await move_to(endpoint)
	if right_click:
		var cancel := InputEventMouseButton.new()
		cancel.position = endpoint
		cancel.button_index = MOUSE_BUTTON_RIGHT
		cancel.pressed = true
		send_button(cancel)
		cancel = cancel.duplicate()
		cancel.pressed = false
		send_button(cancel)
		await settle()
	event = event.duplicate()
	event.position = endpoint
	event.pressed = false
	send_button(event)
	await settle()

func choose_building(kind: String) -> void:
	await settle()
	var ui = game.get_node("UI")
	for category in ui.BUILD_CATEGORIES:
		if kind in ui.BUILD_CATEGORIES[category].kinds and (not game.hud.build_tray.visible or ui.selected_build_category != category):
			await click(ui.category_buttons[category].get_global_rect().get_center())
	var scroll: ScrollContainer = game.hud.tool_buttons[kind].get_parent().get_parent()
	for attempt in 12:
		var target: Rect2 = game.hud.tool_buttons[kind].get_global_rect()
		var visible_area := scroll.get_global_rect()
		if visible_area.encloses(target): break
		await scroll_at(visible_area.get_center(), MOUSE_BUTTON_WHEEL_DOWN if target.end.y > visible_area.end.y else MOUSE_BUTTON_WHEEL_UP)
	await click(game.hud.tool_buttons[kind].get_global_rect().get_center())

func close_build_tray() -> void:
	var ui = game.get_node("UI")
	if game.hud.build_tray.visible:
		await click(ui.category_buttons[ui.selected_build_category].get_global_rect().get_center())

func choose_technology(project: String) -> void:
	var panel = game.hud.research_panel
	for attempt in 32:
		var target: Rect2 = panel.buttons[project].get_global_rect()
		var visible_area: Rect2 = panel.tree_scroll.get_global_rect().grow(-12)
		if visible_area.encloses(target): break
		var direction: MouseButton
		if target.position.x < visible_area.position.x: direction = MOUSE_BUTTON_WHEEL_LEFT
		elif target.end.x > visible_area.end.x: direction = MOUSE_BUTTON_WHEEL_RIGHT
		elif target.position.y < visible_area.position.y: direction = MOUSE_BUTTON_WHEEL_UP
		else: direction = MOUSE_BUTTON_WHEEL_DOWN
		await scroll_at(visible_area.get_center(), direction)
	await click(panel.buttons[project].get_global_rect().get_center())

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
		if game.hud.entity_title.text == title:
			return

func screenshot(path: String, viewport: Viewport = root) -> void:
	if not native:
		return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(path)
