extends HBoxContainer

const COLORS := ["#8aa8c1", "#8eb5c2", "#8ebfba", "#a0c297", "#c8cb83", "#e0c37e", "#e6a574", "#e18a78", "#eb7278"]
var buttons: Dictionary = {}

func build(display_font: Font, action: Callable) -> void:
	add_theme_constant_override("separation", 2)
	for value in range(1, 10):
		var button := Button.new()
		button.text = str(value)
		button.custom_minimum_size = Vector2(24, 32)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.add_theme_font_override("font", display_font)
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_color_override("font_color", Color(COLORS[value - 1]))
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("#243338") if state == "normal" else Color("#405357")
			style.border_color = Color(COLORS[value - 1]) if state in ["pressed", "hover_pressed"] else Color("#526166")
			style.set_border_width_all(2 if state in ["pressed", "hover_pressed"] else 1)
			style.set_content_margin_all(0)
			button.add_theme_stylebox_override(state, style)
		button.pressed.connect(action.bind(value))
		add_child(button)
		buttons[value] = button

func sync(value: float, tooltip: String, unit := "面包 / 基准工时") -> void:
	for amount in buttons:
		buttons[amount].set_pressed_no_signal(amount == value)
		buttons[amount].tooltip_text = "%d %s\n%s" % [amount, unit, tooltip]
