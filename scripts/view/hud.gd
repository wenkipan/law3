extends CanvasLayer

const DayClock = preload("res://scripts/day_clock.gd")
const BuildButton = preload("res://scripts/build_button.gd")
const Art = preload("res://scripts/view/art.gd")
const InspectorIcons = preload("res://scripts/view/inspector_icons.gd")
const BUILD_CATEGORIES := {
	"food": {"name": "农业与食品", "icon": "wheat", "kinds": ["farm", "barn", "mill", "brewery", "grow_light"]},
	"industry": {"name": "工业与装备", "icon": "tools", "kinds": ["drill", "smelter", "sawmill", "smithy", "weaver", "tailor", "bench", "workbench"]},
	"water": {"name": "水务", "icon": "water", "kinds": ["pump", "purifier"]},
	"power": {"name": "电力", "icon": "electricity", "kinds": ["manual_generator", "power_plant", "low_line", "high_line", "transformer"]},
	"logistics": {"name": "物流", "icon": "freight", "kinds": ["belt", "electric_belt"]},
	"life": {"name": "生活与环境", "icon": "furniture", "kinds": ["bed", "canteen", "fountain", "spotlight", "daylight"]},
	"society": {"name": "人口与金融", "icon": "population-finance", "kinds": ["printer", "bank"]},
}

var game: Node
var category_buttons: Dictionary = {}
var selected_build_category := ""
var inventory_icons: InspectorIcons
var effect_icons: InspectorIcons
var effect_separator: HSeparator
var bed_assignment: OptionButton
var production_controls: HBoxContainer
var queue_count: Label
var remove_order: Button
var add_order: Button
var belt_controls: HBoxContainer
var remove_track: Button
var move_drill: Button
var slaughter: Button

func update_entity_panel() -> void:
	if not is_instance_valid(game.entity_panel):
		return
	var p = game.selected_entity
	update_entity_icons()
	game.entity_details.visible = game.selected_worker >= 0 or game.selected_tile != null or p != game.BASE
	slaughter.visible = game.selected_worker < 0 and game.benches.has(p) and game.building_kind(p) == "barn"
	if slaughter.visible:
		slaughter.disabled = game.benches[p].sheep <= 0 or game.benches[p].slaughter
	move_drill.visible = game.selected_worker < 0 and game.benches.has(p) and game.building_kind(p) == "drill"
	belt_controls.visible = game.selected_worker < 0 and (game.selected_line or game.building_kind(p) in game.BELT_KINDS)
	if belt_controls.visible:
		remove_track.disabled = not game.selected_line and game.belts.has(p) and not game.can_edit_belt(p)
		remove_track.tooltip_text = "拆除线路" if game.selected_line else "拆除传送带"
	production_controls.visible = game.selected_worker < 0 and game.benches.has(p) and game.PRODUCTS.has(game.building_kind(p))
	bed_assignment.visible = game.selected_worker < 0 and game.beds.has(p)
	if bed_assignment.visible:
		if bed_assignment.item_count != game.workers.size() + 1:
			bed_assignment.clear()
			bed_assignment.add_item("自动安排")
			for worker in game.workers:
				bed_assignment.add_item(worker.name)
		bed_assignment.select(game.beds[p].assigned + 1)
	game.worker_attributes.visible = game.selected_worker >= 0 and game.selected_worker < game.workers.size()
	game.entity_panel.offset_top = -370 if game.worker_attributes.visible else -350
	if production_controls.visible:
		game.entity_panel.offset_top = -480
	if game.selected_tile != null:
		var details: Dictionary = game.tile_details(game.selected_tile)
		game.entity_panel.visible = not details.is_empty()
		if not details.is_empty():
			game.entity_title.text = details.title
			game.entity_details.text = details.text
		return
	if game.worker_attributes.visible:
		var w: Dictionary = game.worker_display(game.workers[game.selected_worker])
		game.entity_panel.show()
		game.entity_title.text = w.name
		var state_name: String = game.action_for(w)
		if w.state == "rest":
			state_name = "闲逛"
		elif w.state == "to_bed":
			state_name = "前往床位"
		elif w.state == "to_build":
			state_name = "前往工地"
		elif w.state == "build":
			state_name = "建造"
		elif w.state == "sleep":
			state_name = "床上睡觉" if game.beds.has(w.bed) else "地上睡觉"
		elif w.state == "to_work":
			state_name = "前往" + game.building_name(game.building_kind(w.station))
		elif w.state == "to_shop":
			state_name = "购买" + game.item_name(w.item)
		elif w.state == "drink":
			state_name = "饮水"
		elif w.state == "use_item":
			state_name = "使用" + game.item_name(w.item)
		elif w.state == "to_meal":
			state_name = "前往食堂"
		game.entity_details.text = state_name
		game.entity_panel.offset_top = -minf(500, get_viewport().get_visible_rect().size.y - 110)
		game.worker_bars["饥饿值"][0].text = "饥饿值  %.1f / %.0f" % [w.hunger, game.MAX_HUNGER]
		game.worker_bars["饥饿值"][1].value = w.hunger / game.MAX_HUNGER * 100
		game.worker_bars["疲劳"][0].text = "疲劳  %.1f / %.0f" % [w.fatigue, game.MAX_FATIGUE]
		game.worker_bars["疲劳"][1].value = w.fatigue / game.MAX_FATIGUE * 100
		var progress := -1.0
		if w.state == "dig" and game.terrain.get(w.job, 0) != 0:
			progress = w.progress / game.mining_seconds(w.job)
		elif w.state == "build" and game.sites.has(w.building):
			progress = game.sites[w.building].progress / game.sites[w.building].seconds
		elif w.state == "eat":
			progress = w.progress / game.MEAL_SECONDS
		elif w.state == "drink":
			progress = w.drink_progress / (game.DRINK_HOURS * game.HOUR_SECONDS)
		elif w.state == "work" and game.benches.has(w.station):
			var task: Dictionary = game.benches[w.station].task
			if not task.is_empty():
				progress = task.progress / task.seconds
		game.worker_bars["动作进度"][0].visible = progress >= 0
		game.worker_bars["动作进度"][1].visible = progress >= 0
		game.worker_bars["动作进度"][0].text = "动作进度  %.0f%%" % (progress * 100)
		game.worker_bars["动作进度"][1].value = progress * 100
		return
	game.entity_panel.visible = p == game.BASE or game.beds.has(p) or game.sites.has(p) or game.benches.has(p) or game.banks.has(p) or game.belts.has(p) or game.power_lines.has(p)
	if not game.entity_panel.visible:
		game.selected_entity = null
		return
	if p == game.BASE:
		game.entity_title.text = "基地传送门"
		game.entity_details.text = ""
		return
	if game.selected_line and game.power_lines.has(p) and not game.sites.has(p):
		var kind: String = game.power_lines[p].kind
		game.entity_title.text = game.building_name(kind)
		game.entity_details.text = game.building_effects_text(kind)
		return
	if game.belts.has(p) and not game.sites.has(p):
		var belt_kind: String = game.building_kind(p)
		game.entity_title.text = game.building_name(belt_kind)
		var destination = game.belt_destination(p)
		var status := "未连接传送门或建筑"
		if destination != null:
			status = "通往" + ("传送门" if destination == game.BASE else game.building_name(game.building_kind(destination)))
		game.entity_details.text = status + "\n\n" + game.building_effects_text(belt_kind)
		if belt_kind == "electric_belt":
			game.entity_details.text += "\n" + ("运行中" if game.powered_devices.has(p) else "待机 / 未供电")
		return
	if game.banks.has(p):
		game.entity_title.text = game.building_name("bank")
		game.entity_details.text = "%s\n\n已收利息  %.2f 面包" % [game.building_effects_text("bank"), game.banks[p].interest_received]
		return
	if game.benches.has(p):
		var bench: Dictionary = game.benches[p]
		var kind: String = game.building_kind(p)
		if not game.PRODUCTS.has(kind):
			game.entity_title.text = game.building_name(kind)
			var status := "等待值班"
			if not bench.task.is_empty() and game.slot_owner("work", p) >= 0:
				status = game.workers[game.slot_owner("work", p)].name
			if kind in ["grow_light", "fountain", "drill", "spotlight", "daylight"]:
				status = "运行中" if game.powered_devices.has(p) else "未供电"
				if kind == "fountain" and bench.water_day != game.day:
					status = "等待原水"
			elif kind in ["power_plant", "manual_generator", "transformer"]:
				status += "\n输出  %.0fW" % game.power_output.get(p, 0.0)
			elif kind == "canteen":
				status = "用餐中" if game.workers.any(func(w): return game.worker_display(w).canteen == p) else "空闲"
			game.entity_details.text = status + "\n\n" + game.building_effects_text(kind, p)
			return
		var product: Dictionary = game.PRODUCTS[kind]
		game.entity_title.text = game.building_name(kind)
		var status := "空闲"
		if game.uses_daily_output(kind) and bench.task.is_empty() and not game.has_production_order(p):
			status = "已停产" if bench.daily_output == 0 else "今日已完成"
		if game.has_production_order(p) and bench.task.is_empty() and not (kind == "barn" and bench.slaughter) and not game.recipe_ready(p, game.production_materials(kind)):
			var missing: Array[String] = []
			for item in game.production_materials(kind):
				if is_same(item, 0):
					missing.append("矿石")
				elif game.stock_at(p, item) < game.production_materials(kind)[item]:
					missing.append(game.item_name(item))
			status = "等待" + "、".join(missing)
		if not bench.task.is_empty():
			status = "等待工人" if game.slot_owner("work", p) < 0 else game.workers[game.slot_owner("work", p)].name
			status += "  %.0f%%" % (bench.task.progress / bench.task.seconds * 100)
		if kind == "farm":
			if bench.growth > 0:
				status = "生长中  %.1fh" % (bench.growth / game.HOUR_SECONDS)
			elif not bench.task.is_empty():
				status = ("收割 · " if bench.harvest else "浇水 · ") + status
		if kind == "barn":
			if bench.growth > 0: status += "\n产毛中 %.1fh" % (bench.growth / game.HOUR_SECONDS)
			if bench.slaughter: status += "\n待屠宰" if not bench.task.get("slaughter", false) else "\n屠宰中"
		game.entity_details.text = status + "\n\n" + game.product_recipe_text(kind, p)
		var effects: String = game.product_effects_text(kind, p)
		if effects != "":
			game.entity_details.text += "\n\n" + effects
		if game.uses_daily_output(kind):
			add_order.disabled = kind == "barn" and (bench.sheep <= 0 or bench.slaughter)
			queue_count.text = "每日产出 %d%s" % [bench.daily_output, product.unit]
			remove_order.disabled = bench.daily_output == 0
			remove_order.tooltip_text = "每日产出 −%d%s" % [product.get("amount", 1), product.unit]
			add_order.tooltip_text = "每日产出 +%d%s" % [product.get("amount", 1), product.unit]
		else:
			add_order.disabled = false
			queue_count.text = "待制  %d" % bench.queue
			remove_order.disabled = bench.queue <= (0 if bench.task.is_empty() else 1)
			remove_order.tooltip_text = "减少一%s（保留正在制作的%s）" % [product.unit, product.name]
			add_order.tooltip_text = "制作一%s%s" % [product.unit, product.name]
		return
	var kind: String = game.sites[p].kind if game.sites.has(p) else "bed"
	game.entity_title.text = game.building_name(kind) + (" · 建造中" if game.sites.has(p) else "")
	var details := ""
	if game.sites.has(p):
		var task: Dictionary = game.sites[p]
		var worker: String = game.workers[game.slot_owner("build", p)].name if game.slot_owner("build", p) >= 0 else ("等待工人" if game.site_supplied(p) else "等待材料送达")
		if task.get("cancelled", false):
			worker = "回收材料"
		details = "%s\n工时  %s / %sh\n\n" % [
			worker, String.num(task.progress / game.HOUR_SECONDS, 2), String.num(game.building_hours(kind), 2)]
	else:
		var bed: Dictionary = game.beds[p]
		details = "状态  空闲\n\n"
		if game.slot_owner("bed", p) >= 0:
			var occupant: Dictionary = game.worker_display(game.workers[game.slot_owner("bed", p)])
			details = "使用者  %s\n%s\n疲劳  %.1f / %.0f\n\n" % [
				occupant.name,
				"前往床位中" if occupant.state == "to_bed" else "剩余时间  %.1fh" % (bed.remaining / game.HOUR_SECONDS),
				occupant.fatigue, game.MAX_FATIGUE]
	game.entity_details.text = details + game.building_effects_text(kind)

func inventory_entries(contents: Dictionary, notes: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in game.RESOURCE_ITEMS:
		var amount: float = contents.get(item, 0.0)
		if amount <= 0.000001:
			continue
		var title: String = game.item_name(item)
		var description := title + "\n"
		if notes.has(item):
			var lines: Array[String] = []
			for role in notes[item]:
				lines.append(role + " " + String.num(notes[item][role], 4))
			description += "\n".join(lines)
		else:
			description += "数量 " + String.num(amount, 4)
		result.append({"id": item, "texture": Art.item_texture(item), "name": title,
			"quantity": InspectorIcons.quantity_text(amount), "description": description})
	return result

func add_held_item(contents: Dictionary, notes: Dictionary, item, amount: float, role: String) -> void:
	if amount <= 0.000001:
		return
	contents[item] = contents.get(item, 0.0) + amount
	if not notes.has(item):
		notes[item] = {}
	notes[item][role] = notes[item].get(role, 0.0) + amount

func worker_inventory_entries(w: Dictionary) -> Array[Dictionary]:
	var contents: Dictionary = {}
	var notes: Dictionary = {}
	add_held_item(contents, notes, "bread", w.bread + w.meal_bread, "自用")
	add_held_item(contents, notes, "clean_water", w.water, "自用")
	for item in w.items:
		add_held_item(contents, notes, item, w.items[item], "未使用")
	if w.carry > 0:
		add_held_item(contents, notes, w.carry, 1, "搬运")
	for ore in w.extra_cargo:
		add_held_item(contents, notes, ore, 1, "搬运")
	var freight: Dictionary = w.freight
	if freight.get("picked", false) and not freight.get("on_belt", false) and not freight.get("carried_ore", false):
		add_held_item(contents, notes, freight.item, freight.amount, "搬运")
	var result := inventory_entries(contents, notes)
	var special_items: Dictionary = game.worker_special_items(w)
	for item in special_items:
		var title: String = game.item_name(item)
		result.append({"id": item, "texture": Art.item_texture(item), "name": title,
			"quantity": str(special_items[item]), "description": title + "\n凭证 %d 笔" % special_items[item]})
	return result

func update_entity_icons() -> void:
	var items: Array[Dictionary] = []
	var effects: Array[Dictionary] = []
	var p = game.selected_entity
	if game.selected_tile == null:
		if game.selected_worker >= 0 and game.selected_worker < game.workers.size():
			var w: Dictionary = game.workers[game.selected_worker]
			items = worker_inventory_entries(w)
			for effect in w.buffs.display_effects(game, w):
				var texture: Texture2D = Art.item_texture(effect.item) if effect.has("item") else Art.texture("res://assets/icons/%s.svg" % effect.icon)
				effects.append({"id": effect.id, "name": effect.name, "texture": texture,
					"description": effect.name + "\n" + effect.description})
		elif p != null and (not game.selected_line or game.sites.has(p)):
			var contents: Dictionary = game.storage_contents(p)
			var notes: Dictionary = {}
			if game.belts.has(p) and not game.sites.has(p) and game.belts[p].cargo >= 0:
				var cargo: Dictionary = game.belt_cargo[game.belts[p].cargo]
				add_held_item(contents, notes, cargo.delivery.item, cargo.delivery.amount, "搬运 · " + game.workers[cargo.worker].name)
			items = inventory_entries(contents, notes)
			if game.benches.has(p) and game.building_kind(p) == "barn":
				var sheep: int = game.benches[p].sheep
				items.append({"id": "sheep", "name": "羊", "texture": Art.texture("res://assets/icons/sheep.svg"),
					"quantity": str(sheep), "description": "羊\n数量 %d" % sheep})
	inventory_icons.sync(items)
	effect_icons.sync(effects)
	effect_separator.visible = not items.is_empty() and not effects.is_empty()

func make_label(text_: String, size := 14) -> Label:
	var node := Label.new()
	node.text = text_
	node.add_theme_font_override("font", game.font)
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", Color("#d7dfd8"))
	return node

func make_button(text_: String, tooltip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text_
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(46, 36)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", game.font)
	b.pressed.connect(action)
	return b

func panel(parent: Node, rect: Rect2, anchor_right := false, anchor_bottom := false) -> VBoxContainer:
	var box := PanelContainer.new()
	parent.add_child(box)
	if anchor_right:
		box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	if anchor_bottom:
		box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = rect.position.x
	box.offset_top = rect.position.y
	box.offset_right = rect.end.x
	box.offset_bottom = rect.end.y
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#202a2eee")
	style.border_color = Color("#50605b")
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(3)
	box.add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	box.add_child(content)
	return content

func show_build_category(category: String) -> void:
	selected_build_category = category
	var kinds: Array = BUILD_CATEGORIES[category].kinds
	for kind in game.BUILDING_KINDS:
		game.tool_buttons[kind].visible = kind in kinds
	for index in kinds.size():
		var button: Button = game.tool_buttons[kinds[index]]
		button.get_parent().move_child(button, index)
	for key in category_buttons:
		category_buttons[key].set_pressed_no_signal(key == category)
	game.build_tray.show()

func show_building_category(kind: String) -> void:
	for category in BUILD_CATEGORIES:
		if kind in BUILD_CATEGORIES[category].kinds:
			show_build_category(category)
			return

func close_build_tray() -> void:
	game.build_tray.hide()
	selected_build_category = ""
	for button in category_buttons.values():
		button.set_pressed_no_signal(false)
	if game.tool in game.BUILDING_KINDS:
		game.set_tool("dig")

func toggle_build_category(category: String) -> void:
	if game.build_tray.visible and selected_build_category == category:
		close_build_tray()
		return
	if game.tool in game.BUILDING_KINDS and game.tool not in BUILD_CATEGORIES[category].kinds:
		game.set_tool("dig")
	show_build_category(category)

func build_ui(controller: Node) -> void:
	game = controller
	var hud := self
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.day_clock = DayClock.new()
	game.day_clock.clock_font = game.font
	root.add_child(game.day_clock)
	game.day_clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	game.day_clock.offset_left = -188
	game.day_clock.offset_top = 16
	game.day_clock.offset_right = -20
	game.day_clock.offset_bottom = 176
	game.day_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var report_button := make_button("", "每日报告", game.open_report)
	report_button.icon = game.icon_texture("res://assets/icons/report.svg")
	report_button.expand_icon = true
	report_button.add_theme_constant_override("icon_max_width", 26)
	root.add_child(report_button)
	report_button.position = Vector2(284, 34)
	report_button.custom_minimum_size = Vector2(46, 42)
	var actions := panel(root, Rect2(-98, 220, 78, 120), true)
	var time_controls := panel(root, Rect2(20, 20, 248, 68))
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	time_controls.add_child(tools)
	for entry in [["dig", "", "挖掘（G）\n工时 ≥ 1h / 块\n工资 1 面包 / h"],
		["cancel", "×", "取消（X）"]]:
		var b := make_button(entry[1], entry[2], game.set_tool.bind(entry[0]))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(46, 40)
		if entry[0] == "dig":
			b.icon = game.icon_texture("res://assets/icons/pickaxe.svg")
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 28)
		actions.add_child(b)
		game.tool_buttons[entry[0]] = b
	game.pause_button = make_button("Ⅱ", "暂停 / 继续（空格）", game.toggle_pause)
	tools.add_child(game.pause_button)
	for value in [1, 2, 4]:
		var b := make_button("%d×" % value, "时间倍率", game.set_speed.bind(value))
		b.toggle_mode = true
		tools.add_child(b)
		game.speed_buttons[value] = b
	game.set_speed(1)
	var construction := panel(root, Rect2(20, -88, 416, 68), false, true)
	var categories := HBoxContainer.new()
	categories.add_theme_constant_override("separation", 8)
	construction.add_child(categories)
	for category in BUILD_CATEGORIES:
		var definition: Dictionary = BUILD_CATEGORIES[category]
		var button := make_button("", definition.name, toggle_build_category.bind(category))
		button.icon = game.icon_texture("res://assets/icons/%s.svg" % definition.icon)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 28)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(48, 36)
		categories.add_child(button)
		category_buttons[category] = button
	var choice_panel := panel(root, Rect2(20, -248, 344, 148), false, true)
	game.build_tray = choice_panel.get_parent()
	var choice_scroll := ScrollContainer.new()
	choice_scroll.custom_minimum_size = Vector2(312, 116)
	choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choice_panel.add_child(choice_scroll)
	var choices := GridContainer.new()
	choices.columns = 4
	choices.add_theme_constant_override("h_separation", 8)
	choices.add_theme_constant_override("v_separation", 8)
	choice_scroll.add_child(choices)
	for kind in game.BUILDING_KINDS:
		var button := BuildButton.new()
		button.game = game
		button.kind = kind
		button.tooltip_text = game.building_name(kind)
		button.focus_mode = Control.FOCUS_NONE
		button.icon = game.icon_texture("res://assets/icons/%s.svg" % kind)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 64)
		button.add_theme_color_override("icon_disabled_color", Color(0.45, 0.45, 0.45, 0.55))
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(72, 54)
		button.pressed.connect(game.set_tool.bind(kind))
		button.hide()
		choices.add_child(button)
		game.tool_buttons[kind] = button
	game.build_tray.hide()
	var inspector := panel(root, Rect2(0, 0, 280, 330))
	game.entity_panel = inspector.get_parent()
	game.entity_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	game.entity_panel.offset_left = -300
	game.entity_panel.offset_top = -350
	game.entity_panel.offset_right = -20
	game.entity_panel.offset_bottom = -20
	var inspector_heading := HBoxContainer.new()
	game.entity_title = make_label("", 20)
	game.entity_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_heading.add_child(game.entity_title)
	inspector_heading.add_child(make_button("×", "关闭属性（Esc）", game.clear_entity_selection))
	inspector.add_child(inspector_heading)
	inspector.add_child(HSeparator.new())
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector.add_child(detail_scroll)
	var detail_content := VBoxContainer.new()
	detail_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_content.add_theme_constant_override("separation", 10)
	detail_scroll.add_child(detail_content)
	var inspector_frame := inspector
	inspector = detail_content
	game.entity_details = make_label("", 14)
	game.entity_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(game.entity_details)
	inventory_icons = InspectorIcons.new()
	inventory_icons.display_font = game.font
	inventory_icons.hide()
	inspector.add_child(inventory_icons)
	effect_separator = HSeparator.new()
	effect_separator.hide()
	inspector.add_child(effect_separator)
	effect_icons = InspectorIcons.new()
	effect_icons.display_font = game.font
	effect_icons.show_quantities = false
	effect_icons.hide()
	inspector.add_child(effect_icons)
	belt_controls = HBoxContainer.new()
	remove_track = make_button("×", "拆除矿道", func():
		if game.sites.has(game.selected_entity):
			game.cancel_site(game.selected_entity)
		elif game.selected_line:
			game.remove_power_line(game.selected_entity)
		else:
			game.remove_belt(game.selected_entity))
	belt_controls.add_child(remove_track)
	inspector.add_child(belt_controls)
	belt_controls.hide()
	move_drill = make_button("", "移动矿钻", func(): game.begin_drill_move(game.selected_entity))
	move_drill.icon = game.icon_texture("res://assets/icons/move.svg")
	move_drill.expand_icon = true
	move_drill.add_theme_constant_override("icon_max_width", 24)
	inspector.add_child(move_drill)
	move_drill.hide()
	slaughter = make_button("", "屠宰：完成当前产毛后执行，不自动补羊", func(): game.request_slaughter(game.selected_entity))
	slaughter.icon = game.icon_texture("res://assets/icons/slaughter.svg")
	slaughter.expand_icon = true
	slaughter.add_theme_constant_override("icon_max_width", 24)
	slaughter.hide()
	bed_assignment = OptionButton.new()
	bed_assignment.add_theme_font_override("font", game.font)
	bed_assignment.add_item("自动安排", -1)
	bed_assignment.tooltip_text = "指定床位；当前使用结束后生效"
	bed_assignment.item_selected.connect(func(index: int): game.assign_bed(game.selected_entity, index - 1))
	inspector.add_child(bed_assignment)
	bed_assignment.hide()
	production_controls = HBoxContainer.new()
	production_controls.add_child(slaughter)
	remove_order = make_button("−", "", func(): game.adjust_production(game.selected_entity, -1))
	production_controls.add_child(remove_order)
	queue_count = make_label("", 14)
	queue_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	production_controls.add_child(queue_count)
	add_order = make_button("+", "", func(): game.adjust_production(game.selected_entity, 1))
	production_controls.add_child(add_order)
	inspector_frame.add_child(production_controls)
	production_controls.hide()
	game.worker_attributes = VBoxContainer.new()
	game.worker_attributes.add_theme_constant_override("separation", 6)
	inspector.add_child(game.worker_attributes)
	for attribute in ["饥饿值", "疲劳", "动作进度"]:
		var caption := make_label(attribute, 13)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 8)
		bar.show_percentage = false
		game.worker_attributes.add_child(caption)
		game.worker_attributes.add_child(bar)
		game.worker_bars[attribute] = [caption, bar]
	game.worker_attributes.hide()
	game.entity_panel.hide()
	game.reset_dialog = ConfirmationDialog.new()
	game.reset_dialog.dialog_text = "重新开始矿区？当前任务与交付记录将清空。"
	game.reset_dialog.title = "重置矿区"
	game.reset_dialog.confirmed.connect(game.reset_world)
	root.add_child(game.reset_dialog)
	game.set_tool("dig")

func update_ui() -> void:
	var available: Dictionary = game.building_available_materials()
	for kind in game.BUILDING_KINDS:
		game.tool_buttons[kind].disabled = not game.can_plan_building(kind, available)
	update_entity_panel()
	game.day_clock.set_time(game.day_elapsed, game.day)
