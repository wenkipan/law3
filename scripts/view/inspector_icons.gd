extends HFlowContainer

var display_font: Font
var show_quantities := true
var entries: Dictionary = {}

class IconEntry extends Control:
	var image: TextureRect
	var quantity: Label
	var description := ""
	var tooltip_label: Label
	var display_font: Font

	func configure(font: Font, with_quantity: bool) -> void:
		display_font = font
		custom_minimum_size = Vector2(72, 54) if with_quantity else Vector2(32, 32)
		mouse_filter = Control.MOUSE_FILTER_STOP
		image = TextureRect.new()
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.position = Vector2(20, 0) if with_quantity else Vector2.ZERO
		image.size = Vector2(32, 32)
		add_child(image)
		quantity = Label.new()
		quantity.position = Vector2(0, 34)
		quantity.size = Vector2(72, 20)
		quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quantity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		quantity.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quantity.add_theme_font_override("font", font)
		quantity.add_theme_font_size_override("font_size", 14)
		quantity.add_theme_color_override("font_color", Color("#d7dfd8"))
		quantity.visible = with_quantity
		add_child(quantity)

	func sync(data: Dictionary) -> void:
		image.texture = data.texture
		quantity.text = data.get("quantity", "")
		tooltip_text = data.name
		description = data.description
		if is_instance_valid(tooltip_label):
			tooltip_label.text = description

	func _make_custom_tooltip(_for_text: String) -> Object:
		var popup := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#202a2e")
		style.border_color = Color("#71887b")
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(12)
		popup.add_theme_stylebox_override("panel", style)
		tooltip_label = Label.new()
		tooltip_label.custom_minimum_size.x = 224
		tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tooltip_label.add_theme_font_override("font", display_font)
		tooltip_label.add_theme_font_size_override("font_size", 14)
		tooltip_label.add_theme_color_override("font_color", Color("#d7dfd8"))
		tooltip_label.text = description
		popup.add_child(tooltip_label)
		return popup

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 8)

func sync(data: Array[Dictionary]) -> void:
	var visible_keys: Dictionary = {}
	for index in data.size():
		var entry: Dictionary = data[index]
		var key = entry.id
		visible_keys[key] = true
		if not entries.has(key):
			var node := IconEntry.new()
			node.configure(display_font, show_quantities)
			add_child(node)
			entries[key] = node
		var node: IconEntry = entries[key]
		node.sync(entry)
		node.show()
		if node.get_index() != index:
			move_child(node, index)
	for key in entries:
		if not visible_keys.has(key):
			entries[key].hide()
	visible = not data.is_empty()

static func quantity_text(amount: float) -> String:
	if amount >= 1000000:
		return String.num(amount / 1000000, 1).trim_suffix(".0") + "M"
	if amount >= 10000:
		return String.num(amount / 1000, 1).trim_suffix(".0") + "K"
	if amount > 0 and amount < 0.01:
		return "<0.01"
	return String.num(amount, 2).trim_suffix(".00").trim_suffix(".0")
