extends HBoxContainer

const UITheme = preload("res://assets/ui_theme.tres")
var buttons: Dictionary = {}
var group := ButtonGroup.new()

static func color_for(value: int) -> Color:
	return UITheme.get_color("font_color", "Rate%d" % clampi(value, 0, 9))

func build(action: Callable, zero := false) -> void:
	add_theme_constant_override("separation", 2)
	for value in range(0 if zero else 1, 10):
		var button := Button.new()
		button.text = str(value)
		button.custom_minimum_size = Vector2(20 if zero else 24, 32)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = "Rate%d" % value
		button.pressed.connect(action.bind(value))
		add_child(button)
		buttons[value] = button

func sync(value: float, tooltip: String, unit := "货币 / 基准工时") -> void:
	# Commands use pressed, so model-to-view selection does not submit another command.
	if value == int(value) and buttons.has(int(value)):
		buttons[int(value)].button_pressed = true
	elif group.get_pressed_button() != null:
		group.get_pressed_button().button_pressed = false
	for amount in buttons:
		buttons[amount].tooltip_text = "%d %s\n%s" % [amount, unit, tooltip]
