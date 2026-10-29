extends CanvasLayer

const DayClock = preload("res://scripts/day_clock.gd")
const BuildButton = preload("res://scripts/build_button.gd")
var game: Node
var bed_assignment: OptionButton
var production_controls: HBoxContainer
var queue_count: Label
var remove_order: Button
var add_order: Button
var belt_controls: HBoxContainer
var remove_track: Button
var move_drill: Button

func update_entity_panel() -> void:
	if not is_instance_valid(game.entity_panel):
		return
	var p = game.selected_entity
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
			state_name = "购买" + game.PRODUCTS[game.building_kind(w.station)].name
		elif w.state == "drink":
			state_name = "饮水"
		elif w.state == "to_meal":
			state_name = "前往食堂"
		game.entity_details.text = "%s\n面包  %.1f" % [state_name, w.bread]
		if not w.freight.is_empty() and w.freight.picked:
			game.entity_details.text += "\n搬运  %s × %s" % [game.item_name(w.freight.item), String.num(w.freight.amount, 1)]
		if w.carry:
			var cargo: Array[String] = [game.ORES[w.carry].name]
			for ore in w.extra_cargo:
				cargo.append(game.ORES[ore].name)
			game.entity_details.text += "\n携带  " + "、".join(cargo)
		if w.gun_uses > 0:
			game.entity_panel.offset_top = -420
			game.entity_details.text += "\n矿枪  剩余 %d 格" % [w.gun_uses, (game.GUN_MINING_RATE - 1.0) * 100]
		if w.backpack_uses > 0:
			game.entity_panel.offset_top = -460 if w.gun_uses > 0 else -420
			game.entity_details.text += "\n背包  剩余 %d 次" % w.backpack_uses
		if w.water > 0:
			game.entity_details.text += "\n清水  %d 份" % w.water
		if w.water_effect > 0:
			game.entity_details.text += "\n饮水效果  %.1fh" % [w.water_effect / game.HOUR_SECONDS, game.WATER_FATIGUE_REDUCTION * 100]
		if w.water > 0 or w.water_effect > 0:
			game.entity_panel.offset_top -= 70
		game.worker_bars["饥饿值"][0].text = "饥饿值  %.1f / %.0f" % [w.hunger, game.MAX_HUNGER]
		game.worker_bars["饥饿值"][1].value = w.hunger / game.MAX_HUNGER * 100
		game.worker_bars["疲劳"][0].text = "疲劳  %.1f / 100" % w.fatigue
		game.worker_bars["疲劳"][1].value = w.fatigue
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
		game.entity_details.text = "仓储\n" + game.storage_text(p)
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
		var cargo_id: int = game.belts[p].cargo
		if cargo_id >= 0:
			var cargo: Dictionary = game.belt_cargo[cargo_id]
			status += "\n%s × %s · %s" % [game.item_name(cargo.delivery.item), String.num(cargo.delivery.amount, 1), game.workers[cargo.worker].name]
		game.entity_details.text = status + "\n\n" + game.building_effects_text(belt_kind)
		if belt_kind == "electric_belt":
			game.entity_details.text += "\n" + ("运行中" if game.powered_devices.has(p) else "待机 / 未供电")
		return
	if game.banks.has(p):
		game.entity_title.text = game.building_name("bank")
		game.entity_details.text = "%s\n\n已收利息  %.2f 面包\n仓储\n%s" % [game.building_effects_text("bank"), game.banks[p].interest_received, game.storage_text(p)]
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
			game.entity_details.text = status + "\n\n" + game.building_effects_text(kind, p) + "\n\n仓储\n" + game.storage_text(p)
			return
		var product: Dictionary = game.PRODUCTS[kind]
		game.entity_title.text = game.building_name(kind)
		var status := "空闲"
		if game.uses_daily_output(kind) and bench.task.is_empty() and not game.has_production_order(p):
			status = "已停产" if bench.daily_output == 0 else "今日已完成"
		if game.has_production_order(p) and bench.task.is_empty() and not game.recipe_ready(p, game.production_materials(kind)):
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
		game.entity_details.text = "%s\n仓储\n%s\n\n%s" % [status, game.storage_text(p), game.product_recipe_text(kind, p)]
		var effects: String = game.product_effects_text(kind, p)
		if effects != "":
			game.entity_details.text += "\n\n" + effects
		if game.uses_daily_output(kind):
			queue_count.text = "每日产出 %d%s" % [bench.daily_output, product.unit]
			remove_order.disabled = bench.daily_output == 0
			remove_order.tooltip_text = "每日产出 −%d%s" % [product.get("amount", 1), product.unit]
			add_order.tooltip_text = "每日产出 +%d%s" % [product.get("amount", 1), product.unit]
		else:
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
		details = "仓储\n" + game.storage_text(p) + "\n\n"
		details += "%s\n工时  %s / %sh\n\n" % [
			worker, String.num(task.progress / game.HOUR_SECONDS, 2), String.num(game.building_hours(kind), 2)]
	else:
		var bed: Dictionary = game.beds[p]
		details = "状态  空闲\n\n"
		if game.slot_owner("bed", p) >= 0:
			var occupant: Dictionary = game.worker_display(game.workers[game.slot_owner("bed", p)])
			details = "使用者  %s\n%s\n疲劳  %.1f / 100\n\n" % [
				occupant.name,
				"前往床位中" if occupant.state == "to_bed" else "剩余时间  %.1fh" % (bed.remaining / game.HOUR_SECONDS),
				occupant.fatigue]
	game.entity_details.text = details + game.building_effects_text(kind)
	if game.beds.has(p):
		game.entity_details.text += "\n\n仓储\n" + game.storage_text(p)

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
	var construction := panel(root, Rect2(20, -88, 88, 68), false, true)
	var categories := HBoxContainer.new()
	categories.add_theme_constant_override("separation", 18)
	construction.add_child(categories)
	game.furniture_button = make_button("", "家具", game.toggle_build_tray)
	game.furniture_button.icon = game.icon_texture("res://assets/icons/furniture.svg")
	game.furniture_button.expand_icon = true
	game.furniture_button.add_theme_constant_override("icon_max_width", 28)
	game.furniture_button.toggle_mode = true
	game.furniture_button.custom_minimum_size.x = 56
	categories.add_child(game.furniture_button)
	var choice_panel := panel(root, Rect2(20, -474, 350, 404), false, true)
	game.build_tray = choice_panel.get_parent()
	var choices := GridContainer.new()
	choices.columns = 4
	choices.add_theme_constant_override("h_separation", 8)
	choices.add_theme_constant_override("v_separation", 8)
	choice_panel.add_child(choices)
	var bed_button := BuildButton.new()
	bed_button.game = game
	bed_button.tooltip_text = "床"
	bed_button.focus_mode = Control.FOCUS_NONE
	bed_button.add_theme_font_override("font", game.font)
	bed_button.add_theme_font_size_override("font_size", 18)
	bed_button.add_theme_constant_override("h_separation", 16)
	game.bed_texture = game.icon_texture("res://assets/icons/bed.svg")
	bed_button.icon = game.bed_texture
	game.bed_blueprint_texture = game.icon_texture("res://assets/icons/bed-blueprint.svg")
	bed_button.expand_icon = true
	bed_button.add_theme_constant_override("icon_max_width", 64)
	bed_button.add_theme_color_override("icon_disabled_color", Color(0.45, 0.45, 0.45, 0.55))
	bed_button.pressed.connect(game.set_tool.bind("bed"))
	bed_button.toggle_mode = true
	bed_button.custom_minimum_size = Vector2(72, 54)
	choices.add_child(bed_button)
	game.tool_buttons["bed"] = bed_button
	for kind in game.BUILDING_KINDS:
		if kind == "bed":
			continue
		var bench_button := BuildButton.new()
		bench_button.game = game
		bench_button.kind = kind
		bench_button.tooltip_text = game.building_name(kind)
		bench_button.focus_mode = Control.FOCUS_NONE
		bench_button.icon = game.icon_texture("res://assets/icons/%s.svg" % kind)
		bench_button.expand_icon = true
		bench_button.add_theme_constant_override("icon_max_width", 64)
		bench_button.add_theme_color_override("icon_disabled_color", Color(0.45, 0.45, 0.45, 0.55))
		bench_button.toggle_mode = true
		bench_button.custom_minimum_size = Vector2(72, 54)
		bench_button.pressed.connect(game.set_tool.bind(kind))
		choices.add_child(bench_button)
		game.tool_buttons[kind] = bench_button
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
	game.entity_details = make_label("", 14)
	game.entity_details.custom_minimum_size.x = 248
	game.entity_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(game.entity_details)
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
	bed_assignment = OptionButton.new()
	bed_assignment.add_theme_font_override("font", game.font)
	bed_assignment.add_item("自动安排", -1)
	bed_assignment.tooltip_text = "指定床位；当前使用结束后生效"
	bed_assignment.item_selected.connect(func(index: int): game.assign_bed(game.selected_entity, index - 1))
	inspector.add_child(bed_assignment)
	bed_assignment.hide()
	production_controls = HBoxContainer.new()
	remove_order = make_button("−", "", func(): game.adjust_production(game.selected_entity, -1))
	production_controls.add_child(remove_order)
	queue_count = make_label("", 14)
	queue_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	production_controls.add_child(queue_count)
	add_order = make_button("+", "", func(): game.adjust_production(game.selected_entity, 1))
	production_controls.add_child(add_order)
	inspector.add_child(production_controls)
	production_controls.hide()
	game.worker_attributes = VBoxContainer.new()
	game.worker_attributes.add_theme_constant_override("separation", 6)
	inspector.add_child(game.worker_attributes)
	for attribute in ["饥饿值", "疲劳", "动作进度"]:
		var caption := make_label(attribute, 13)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(240, 8)
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
	update_entity_panel()
	game.day_clock.set_time(game.day_elapsed, game.day)
