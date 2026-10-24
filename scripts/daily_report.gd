extends Window

var game: Node
var days := OptionButton.new()
var people := OptionButton.new()
var summary := Label.new()
var rows: Dictionary = {}
var refresh_timer := 0.0

func _ready() -> void:
	title = "每日报告"
	size = Vector2i(680, 600)
	min_size = Vector2i(560, 550)
	transient = true
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)
	var title_label: Label = game.make_label("每日报告", 24)
	content.add_child(title_label)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 14)
	content.add_child(filters)
	days.custom_minimum_size.x = 180
	people.custom_minimum_size.x = 180
	filters.add_child(days)
	filters.add_child(people)
	people.add_item("全体")
	for w in game.workers:
		people.add_item(w.name)
	days.item_selected.connect(func(_i): refresh())
	people.item_selected.connect(func(_i): refresh())
	summary.add_theme_font_override("font", game.font)
	content.add_child(summary)
	content.add_child(HSeparator.new())
	for action in game.ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		content.add_child(row)
		var label: Label = game.make_label(action, 14)
		label.custom_minimum_size.x = 48
		row.add_child(label)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(160, 24)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.show_percentage = false
		row.add_child(bar)
		var duration: Label = game.make_label("", 13)
		duration.custom_minimum_size.x = 100
		row.add_child(duration)
		var percent: Label = game.make_label("", 13)
		percent.custom_minimum_size.x = 65
		percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(percent)
		rows[action] = [bar, duration, percent]
	refresh()

func _process(delta: float) -> void:
	if not visible:
		return
	refresh_timer += delta
	if refresh_timer >= 0.25:
		refresh_timer = 0.0
		refresh()

func refresh() -> void:
	if people.item_count != game.workers.size() + 1:
		var selected_person := people.selected
		people.clear()
		people.add_item("全体")
		for w in game.workers:
			people.add_item(w.name)
		people.select(clampi(selected_person, 0, game.workers.size()))
	var selected_day: int = days.get_selected_id() if days.item_count else game.day
	if days.item_count != game.day:
		days.clear()
		for d in range(1, game.day + 1):
			days.add_item("第 %d 天" % d, d)
		days.select(clampi(selected_day - 1, 0, game.day - 1))
	var d := days.get_selected_id()
	var totals: Dictionary = game.report_totals(d, people.selected - 1)
	var total := 0.0
	for value in totals.values():
		total += value
	summary.text = "%s · %s · %s" % ["进行中" if d == game.day else "已结算", "总人时" if people.selected == 0 else "已记录时间", format_time(total)]
	summary.text += "\n挖掘方块  %d 块" % game.report_mined(d, people.selected - 1)
	for action in game.ACTIONS:
		var ratio: float = totals[action] / total * 100.0 if total > 0 else 0.0
		rows[action][0].value = ratio
		rows[action][1].text = format_time(totals[action])
		rows[action][2].text = "%.1f%%" % ratio

func format_time(seconds: float) -> String:
	var minutes := int(round(seconds / game.DAY_SECONDS * 1440.0))
	return "%dh %02dm" % [minutes / 60, minutes % 60]
