extends VBoxContainer

const Art = preload("res://scripts/view/art.gd")
const AMOUNT_WIDTH := 92.0
const CHART_WIDTH := 160.0
const HISTORY_DAYS := 5
var game: Node
var scroll: ScrollContainer
var list: VBoxContainer
var rows: Dictionary = {}
var details: VBoxContainer
var yesterday: Label
var charts: Dictionary = {}
var series: Dictionary = {}
var selected_item = null
var day_axis: Control
var day_labels: Array[Label] = []

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var header_margin := MarginContainer.new()
	add_child(header_margin)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	add_child(scroll)
	header_margin.add_theme_constant_override("margin_left", 8)
	header_margin.add_theme_constant_override("margin_right", 8 + int(scroll.get_v_scroll_bar().get_combined_minimum_size().x))
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header_margin.add_child(header)
	var name_label: Label = game.make_label("物资", 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	header.add_child(name_label)
	var amount_label: Label = game.make_label("总数", 14)
	amount_label.custom_minimum_size.x = AMOUNT_WIDTH
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	header.add_child(amount_label)
	var chart_header := VBoxContainer.new()
	chart_header.custom_minimum_size.x = CHART_WIDTH
	chart_header.add_theme_constant_override("separation", 2)
	header.add_child(chart_header)
	chart_header.add_child(game.make_label("库存曲线（天）", 14))
	day_axis = Control.new()
	day_axis.custom_minimum_size.y = 20
	day_axis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chart_header.add_child(day_axis)
	for i in HISTORY_DAYS:
		var label: Label = game.make_label("", 11)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		day_axis.add_child(label)
		day_labels.append(label)
		day_axis.custom_minimum_size.y = maxf(day_axis.custom_minimum_size.y, label.get_combined_minimum_size().y)
	day_axis.resized.connect(update_day_axis)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for item in game.RESOURCE_ITEMS:
		var button: Button = game.make_button("", "", select_item.bind(item))
		button.custom_minimum_size.y = 44
		button.toggle_mode = true
		button.flat = true
		list.add_child(button)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 12)
		button.add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 8
		row.offset_right = -8
		row.offset_top = 4
		row.offset_bottom = -4
		var identity := HBoxContainer.new()
		identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
		identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		identity.add_theme_constant_override("separation", 10)
		row.add_child(identity)
		var icon := TextureRect.new()
		icon.texture = Art.item_texture(item)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		identity.add_child(icon)
		var label: Label = game.make_label(game.item_name(item), 14)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		identity.add_child(label)
		var amount: Label = game.make_label("", 16)
		amount.custom_minimum_size.x = AMOUNT_WIDTH
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(amount)
		var graph := Control.new()
		graph.custom_minimum_size = Vector2(CHART_WIDTH, 36)
		graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(graph)
		var background := ColorRect.new()
		background.color = Color("#182322")
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		graph.add_child(background)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var guides: Array[ColorRect] = []
		for i in HISTORY_DAYS + 2:
			var guide := ColorRect.new()
			guide.color = Color("#384a44")
			guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
			graph.add_child(guide)
			guides.append(guide)
		var curve := Line2D.new()
		curve.width = 1.5
		curve.default_color = Color("#87cdb8")
		curve.antialiased = true
		graph.add_child(curve)
		charts[item] = [graph, curve, guides]
		rows[item] = [button, button, amount, graph]
		graph.resized.connect(plot.bind(item))
	details = VBoxContainer.new()
	details.add_theme_constant_override("separation", 10)
	list.add_child(details)
	details.hide()
	yesterday = game.make_label("", 14)
	yesterday.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(yesterday)
	details.add_child(HSeparator.new())
	refresh()

func select_item(item) -> void:
	selected_item = null if is_same(selected_item, item) else item
	details.visible = selected_item != null
	if selected_item != null:
		list.move_child(details, rows[selected_item][0].get_index() + (0 if details.get_index() < rows[selected_item][0].get_index() else 1))
	refresh()
	if selected_item != null:
		scroll.ensure_control_visible.call_deferred(details)

func refresh() -> void:
	update_day_axis()
	var inventory: Dictionary = game.resource_inventory()
	for item in rows:
		rows[item][1].set_pressed_no_signal(is_same(selected_item, item))
		rows[item][2].text = format_amount(inventory[item])
		var points: Array[Vector2] = []
		for sample in game.inventory_history:
			points.append(Vector2(sample.time, sample.stock[item]))
		var now: float = (game.day - 1) * game.DAY_SECONDS + game.day_elapsed
		points.append(Vector2(now, inventory[item]))
		series[item] = points
		plot(item)
	if selected_item == null:
		return
	if game.day == 1:
		yesterday.text = "昨日暂无记录"
	else:
		var activity: Dictionary = game.resource_activity(selected_item, game.day - 1)
		yesterday.text = "昨日产出  %s    昨日消耗  %s" % [format_amount(activity.produced), format_amount(activity.consumed)]

func update_day_axis() -> void:
	var days := mini(HISTORY_DAYS, game.day)
	var first_day := maxi(1, game.day - HISTORY_DAYS + 1)
	var width := maxf(1, day_axis.size.x - 8) / days
	for i in day_labels.size():
		day_labels[i].visible = i < days
		day_labels[i].text = str(first_day + i)
		day_labels[i].position = Vector2(4 + i * width, 0)
		day_labels[i].size = Vector2(width, day_axis.size.y)

func plot(item) -> void:
	if not series.has(item):
		return
	var points: Array[Vector2] = series[item]
	var graph: Control = charts[item][0]
	var curve: Line2D = charts[item][1]
	var guides: Array[ColorRect] = charts[item][2]
	var days := mini(HISTORY_DAYS, game.day)
	var start: float = maxi(0, game.day - HISTORY_DAYS) * game.DAY_SECONDS
	var duration: float = days * game.DAY_SECONDS
	var maximum := 1.0
	for point in points:
		if point.x >= start:
			maximum = maxf(maximum, point.y)
	maximum = ceilf(maximum)
	var area := Rect2(4, 4, maxf(1, graph.size.x - 8), maxf(1, graph.size.y - 8))
	for i in HISTORY_DAYS + 1:
		guides[i].visible = i <= days
		guides[i].position = area.position + Vector2(area.size.x * i / days, 0)
		guides[i].size = Vector2(1, area.size.y)
	guides[HISTORY_DAYS + 1].position = Vector2(area.position.x, area.end.y)
	guides[HISTORY_DAYS + 1].size = Vector2(area.size.x, 1)
	var line := PackedVector2Array()
	for point in points:
		if point.x >= start:
			line.append(area.position + Vector2((point.x - start) / duration * area.size.x, (1.0 - point.y / maximum) * area.size.y))
	curve.points = line

func format_amount(value: float) -> String:
	return String.num(value, 1).trim_suffix(".0")
