extends Control

const Art = preload("res://scripts/view/art.gd")
var clock_font: Font
var segments: Array[TextureRect] = []
var time_label := Label.new()
var day_label := Label.new()
var last_minute := -1
var last_day := -1
var last_segment := -1

func _ready() -> void:
	for i in 12:
		var segment := TextureRect.new()
		segment.texture = Art.texture("res://assets/world/clock-segment.svg")
		segment.position = Vector2(4, 0)
		segment.size = Vector2(160, 160)
		segment.pivot_offset = Vector2(80, 80)
		segment.rotation = i * TAU / 12
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(segment)
		segments.append(segment)
	for label in [time_label, day_label]:
		label.add_theme_font_override("font", clock_font)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size = Vector2(100, 28)
		add_child(label)
	time_label.position = Vector2(34, 65)
	time_label.add_theme_font_size_override("font_size", 22)
	time_label.add_theme_color_override("font_color", Color("#e5e6ce"))
	day_label.position = Vector2(34, 42)
	day_label.add_theme_font_size_override("font_size", 13)
	day_label.add_theme_color_override("font_color", Color("#a6beb1"))

func set_time(elapsed: float, day: int) -> void:
	var minute := int(elapsed / 180.0 * 1440.0)
	if minute != last_minute:
		time_label.text = "%02d:%02d" % [minute / 60, minute % 60]
		last_minute = minute
	if day != last_day:
		day_label.text = "第 %d 天" % day
		last_day = day
	var current := mini(11, int(elapsed / 15.0))
	if current != last_segment:
		for i in segments.size():
			segments[i].modulate = Color("#94bda6") if i < current else (Color("#edd18c") if i == current else Color("#354349"))
		last_segment = current
