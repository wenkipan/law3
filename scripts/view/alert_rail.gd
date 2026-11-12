extends ScrollContainer

var game: Node
var list := VBoxContainer.new()
var buttons: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	add_child(list)

func sync(entries: Array[Dictionary]) -> void:
	var active: Dictionary = {}
	for i in entries.size():
		var entry: Dictionary = entries[i]
		active[entry.id] = true
		if not buttons.has(entry.id):
			var button := Button.new()
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.clip_text = true
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.theme_type_variation = "AlertButton"
			button.pressed.connect(game.activate_alert.bind(entry.id))
			button.gui_input.connect(scroll_text)
			list.add_child(button)
			buttons[entry.id] = button
		var button: Button = buttons[entry.id]
		button.text = entry.text
		var text_width: float = game.hud.font.get_string_size(entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 8
		button.tooltip_text = entry.text if text_width > 280 else ""
		button.custom_minimum_size = Vector2(minf(280, text_width), 27)
		var color: Color = {0: Color("#8abe8d"), 1: Color("#edcf81"), 2: Color("#ee9989")}[entry.severity]
		button.add_theme_color_override("font_color", color)
		button.add_theme_color_override("font_hover_color", color.lightened(0.3))
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
		button.show()
		list.move_child(button, i)
	for id in buttons.keys():
		if not active.has(id):
			list.remove_child(buttons[id])
			buttons[id].queue_free()
			buttons.erase(id)
	visible = not entries.is_empty()

func scroll_text(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			scroll_vertical += -32 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 32
			accept_event()
