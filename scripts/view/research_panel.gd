extends PanelContainer

const Technology = preload("res://scripts/technology.gd")
const Art = preload("res://scripts/view/art.gd")
const NODE_SIZE := Vector2(68, 64)
const STEP := Vector2(220, 96)
const ORIGIN := Vector2(32, 32)

var game: Node
var hud: CanvasLayer
var selected := "tools"
var close_button: Button
var detail_title: Label
var detail_status: Label
var detail_cost: Label
var prerequisites: Label
var progress: ProgressBar
var unlocks: VBoxContainer
var tree_scroll: ScrollContainer
var graph: Control
var buttons: Dictionary = {}
var connections: Array[Dictionary] = []
var styles: Dictionary = {}

func build(controller: Node, layout: CanvasLayer) -> void:
	game = controller
	hud = layout
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 20
	offset_top = 108
	offset_right = -20
	offset_bottom = -20
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#202a2e")
	frame.border_color = Color("#71887b")
	frame.set_border_width_all(1)
	frame.set_content_margin_all(16)
	frame.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", frame)
	for state in ["locked", "available", "active", "done"]:
		for chosen in [false, true]:
			var style := StyleBoxFlat.new()
			style.bg_color = {"locked": Color("#30383b"), "available": Color("#354c52"),
				"active": Color("#365e60"), "done": Color("#385442")}[state]
			style.border_color = Color("#e4c67c") if chosen else {"locked": Color("#535b5c"),
				"available": Color("#7caaa5"), "active": Color("#8ae1d0"), "done": Color("#8abe8d")}[state]
			style.set_border_width_all(2 if chosen else 1)
			style.set_corner_radius_all(4)
			styles[state + str(chosen)] = style
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	add_child(content)
	var heading := HBoxContainer.new()
	content.add_child(heading)
	var title: Label = hud.make_label("科技", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	close_button = hud.make_button("×", "关闭科技（Esc）", hide)
	heading.add_child(close_button)
	content.add_child(HSeparator.new())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_stretch_ratio = 0.3
	columns.add_child(detail_scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	detail_scroll.add_child(details)
	detail_title = label(details, "", 20)
	detail_status = label(details, "")
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 10
	progress.show_percentage = false
	details.add_child(progress)
	detail_cost = label(details, "")
	prerequisites = label(details, "", 13)
	details.add_child(HSeparator.new())
	label(details, "解锁建筑", 16)
	unlocks = VBoxContainer.new()
	unlocks.add_theme_constant_override("separation", 8)
	details.add_child(unlocks)
	columns.add_child(VSeparator.new())
	tree_scroll = ScrollContainer.new()
	tree_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_scroll.size_flags_stretch_ratio = 0.7
	columns.add_child(tree_scroll)
	graph = Control.new()
	graph.custom_minimum_size = ORIGIN * 2 + Vector2(3, 8) * STEP + NODE_SIZE
	tree_scroll.add_child(graph)
	graph.gui_input.connect(pan_tree)
	build_graph()
	select_project(selected)
	hide()

func label(parent: Node, text: String, size := 14) -> Label:
	var result: Label = hud.make_label(text, size)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func project_position(project: String) -> Vector2:
	return ORIGIN + Vector2(Technology.PROJECTS[project].position) * STEP

func build_graph() -> void:
	for project in Technology.PROJECTS:
		for required in Technology.PROJECTS[project].requires:
			var start := project_position(required) + Vector2(NODE_SIZE.x, NODE_SIZE.y * 0.5)
			var end := project_position(project) + Vector2(0, NODE_SIZE.y * 0.5)
			var points := PackedVector2Array()
			if end.x - start.x < STEP.x:
				var middle := (start.x + end.x) * 0.5
				points = PackedVector2Array([start, Vector2(middle, start.y), Vector2(middle, end.y), end])
			else:
				var lane := project_position(project).y - 16
				points = PackedVector2Array([start, start + Vector2(28, 0), Vector2(start.x + 28, lane),
					Vector2(end.x - 28, lane), end - Vector2(28, 0), end])
			var line := Line2D.new()
			line.points = points
			line.width = 2
			line.default_color = Color("#566563")
			graph.add_child(line)
			var arrow := Polygon2D.new()
			arrow.polygon = PackedVector2Array([end, end + Vector2(-7, -4), end + Vector2(-7, 4)])
			graph.add_child(arrow)
			connections.append({"from": required, "to": project, "line": line, "arrow": arrow})
	for project in Technology.PROJECTS:
		var definition: Dictionary = Technology.PROJECTS[project]
		var button: Button = hud.make_button("", definition.name, toggle_project.bind(project))
		button.icon = Art.texture("res://assets/icons/%s.svg" % definition.unlocks[0])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 54)
		button.custom_minimum_size = NODE_SIZE
		button.size = NODE_SIZE
		button.position = project_position(project)
		graph.add_child(button)
		buttons[project] = button

func pan_tree(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		tree_scroll.scroll_horizontal -= roundi(event.relative.x)
		tree_scroll.scroll_vertical -= roundi(event.relative.y)
		accept_event()

func open(project := "") -> void:
	game.cancel_placement()
	game.interaction.dragging = false
	game.interaction.panning = false
	if project != "" and Technology.PROJECTS.has(project): select_project(project)
	show()
	sync()
	tree_scroll.ensure_control_visible.call_deferred(buttons[selected])

func select_project(project: String) -> void:
	selected = project
	for child in unlocks.get_children():
		unlocks.remove_child(child)
		child.queue_free()
	for kind in Technology.PROJECTS[project].unlocks:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.tooltip_text = "%s\n工时 %sh\n%s" % [game.material_requirements_text(game.building_materials(kind)),
			String.num(game.building_hours(kind), 2), game.building_effects_text(kind)]
		unlocks.add_child(row)
		var icon := TextureRect.new()
		icon.texture = Art.texture("res://assets/icons/%s.svg" % kind)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(48, 36)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var title := label(row, game.building_name(kind))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sync()

func toggle_project(project: String) -> void:
	select_project(project)
	game.toggle_research(project)

func state_for(project: String) -> String:
	if Technology.completed(game.world.research_progress, project): return "done"
	if not Technology.available(game.world.research_progress, project): return "locked"
	for p in game.research_stations():
		if game.world.benches[p].research == project: return "active"
	return "available"

func sync() -> void:
	if not is_instance_valid(detail_title): return
	for project in buttons:
		var state := state_for(project)
		var chosen: bool = project == selected
		var button: Button = buttons[project]
		button.add_theme_stylebox_override("normal", styles[state + str(chosen)])
		button.add_theme_stylebox_override("hover", styles[state + "true"])
		button.add_theme_stylebox_override("pressed", styles[state + "true"])
		button.modulate = Color("#898f90") if state == "locked" else Color.WHITE
		button.tooltip_text = Technology.PROJECTS[project].name + "\n" + status_text(project)
	for connection in connections:
		var color := Color("#8abe8d") if Technology.completed(game.world.research_progress, connection.from) else Color("#566563")
		connection.line.default_color = color
		connection.arrow.color = color
	var definition: Dictionary = Technology.PROJECTS[selected]
	detail_title.text = definition.name
	detail_status.text = "%s\n科研点  %s / %d" % [status_text(selected), String.num(game.research_value(selected), 2), definition.points]
	progress.value = game.research_value(selected) / definition.points * 100
	detail_cost.text = game.research_recipe_text(selected)
	var required_names: Array[String] = []
	for required in definition.requires: required_names.append(Technology.PROJECTS[required].name)
	prerequisites.text = "前置  " + "、".join(required_names) if not required_names.is_empty() else ""
	prerequisites.visible = not required_names.is_empty()

func status_text(project: String) -> String:
	match state_for(project):
		"done": return "已完成"
		"locked": return "前置未完成"
		"active": return "研究中"
	return "已暂停" if game.research_value(project) > 0 else "可研究"

