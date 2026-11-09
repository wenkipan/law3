extends CanvasLayer

const DayClock = preload("res://scripts/day_clock.gd")
const DailyReport = preload("res://scripts/daily_report.gd")
const BuildButton = preload("res://scripts/build_button.gd")
const Art = preload("res://scripts/view/art.gd")
const InspectorIcons = preload("res://scripts/view/inspector_icons.gd")
const SaveStore = preload("res://scripts/persistence/save_store.gd")
const AlertRail = preload("res://scripts/view/alert_rail.gd")
const ResearchPanel = preload("res://scripts/view/research_panel.gd")
const RateSelector = preload("res://scripts/view/rate_selector.gd")
const BUILD_CATEGORIES := {
	"food": {"name": "农业与食品", "icon": "wheat", "kinds": ["farm", "barn", "mill", "brewery", "grow_light"]},
	"industry": {"name": "工业与装备", "icon": "tools", "kinds": ["drill", "smelter", "sawmill", "smithy", "weaver", "tailor", "bench", "workbench", "chemical_plant", "soapworks", "pharmacy"]},
	"water": {"name": "水务", "icon": "water", "kinds": ["pump", "purifier"]},
	"power": {"name": "电力", "icon": "electricity", "kinds": ["manual_generator", "power_plant", "low_line", "high_line", "transformer"]},
	"logistics": {"name": "物流", "icon": "freight", "kinds": ["storage_box", "belt", "electric_belt"]},
	"life": {"name": "生活与环境", "icon": "furniture", "kinds": ["bed", "canteen", "fountain", "spotlight", "daylight", "bathhouse", "laundry", "hospital"]},
	"society": {"name": "人口金融与科研", "icon": "population-finance", "kinds": ["research_bench", "printer", "bank"]},
}

var game: Node
var report_window: Window
var day_clock: Control
var pause_button: Button
var tool_buttons: Dictionary = {}
var build_tray: PanelContainer
var speed_buttons: Dictionary = {}
var reset_dialog: ConfirmationDialog
var font: Font
var worker_attributes: VBoxContainer
var worker_bars: Dictionary = {}
var entity_panel: PanelContainer
var entity_title: Label
var entity_details: Label
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
var move_drill: Button
var slaughter: Button
var pollution_button: Button
var save_button: Button
var load_button: Button
var save_menu: Window
var save_slots: ItemList
var save_action: Button
var backup_action: Button
var save_hint: Label
var save_status: Label
var save_directory := SaveStore.DIRECTORY
var last_save_slot := -1
var menu_saving := true
var overwrite_pending := false
var status_seconds := 0.0
var alert_rail: ScrollContainer
var alert_timer := 0.0
var research_button: Button
var research_panel: PanelContainer
var research_choice: OptionButton
var wage_controls: VBoxContainer
var wage_caption: Label
var fee_details: Label
var fee_controls: VBoxContainer
var fee_selector: HBoxContainer
var fee_brush_controls: VBoxContainer
var fee_brush_selector: HBoxContainer
var fee_filters: Dictionary = {}
var wage_selector: HBoxContainer
var brush_controls: VBoxContainer
var brush_selector: HBoxContainer
var wage_filters: Dictionary = {}
var action_panel_box: PanelContainer

func blocks_simulation() -> bool:
	return reset_dialog.visible or (is_instance_valid(save_menu) and save_menu.visible)

func show_save_menu(saving: bool) -> void:
	game.cancel_placement()
	game.interaction.dragging = false
	game.interaction.panning = false
	menu_saving = saving
	save_menu.title = "保存矿区" if saving else "读取矿区"
	save_slots.clear()
	var entries := SaveStore.slots(save_directory)
	var timezone_offset := int(Time.get_time_zone_from_system().bias) * 60
	for slot in entries.size():
		var entry := entries[slot]
		var detail := "空存档"
		if entry.exists:
			detail = Time.get_datetime_string_from_unix_time(entry.modified + timezone_offset).replace("T", "  ")
		elif entry.backup:
			detail = "仅有上一版"
		save_slots.add_item("存档 %d    ·    %s" % [slot + 1, detail])
	save_slots.select(maxi(last_save_slot, 0))
	select_save_slot()
	save_menu.popup_centered(Vector2i(560, 440))
	save_slots.grab_focus()

func select_save_slot() -> void:
	overwrite_pending = false
	save_hint.text = ""
	save_action.text = "保存" if menu_saving else "读取"
	save_action.icon = Art.texture("res://assets/icons/save.svg" if menu_saving else "res://assets/icons/load.svg")
	var selected := save_slots.get_selected_items()
	var entry: Dictionary = SaveStore.slots(save_directory)[selected[0]] if not selected.is_empty() else {}
	save_action.disabled = entry.is_empty() or (not menu_saving and not entry.exists)
	backup_action.visible = not menu_saving
	backup_action.disabled = entry.is_empty() or not entry.backup

func use_save_slot(backup := false) -> void:
	var selected := save_slots.get_selected_items()
	if selected.is_empty(): return
	var slot := selected[0]
	var path := SaveStore.slot_path(slot, save_directory)
	if menu_saving and FileAccess.file_exists(path) and not overwrite_pending:
		overwrite_pending = true
		save_hint.text = "覆盖存档 %d？" % (slot + 1)
		save_action.text = "确认覆盖"
		return
	if backup: path += ".bak"
	var result: Dictionary = game.save_game(path) if menu_saving else game.load_game(path)
	finish_save(result, menu_saving, slot, backup)
	if result.ok:
		save_menu.hide()
	else:
		overwrite_pending = false
		save_action.text = "保存" if menu_saving else "读取"
		save_hint.text = save_status.text

func save_current() -> void:
	if blocks_simulation(): return
	if last_save_slot < 0:
		show_save_menu(true)
		return
	finish_save(game.save_game(SaveStore.slot_path(last_save_slot, save_directory)), true, last_save_slot)

func load_current() -> void:
	if blocks_simulation(): return
	if last_save_slot < 0:
		show_save_menu(false)
		return
	finish_save(game.load_game(SaveStore.slot_path(last_save_slot, save_directory)), false, last_save_slot)

func finish_save(result: Dictionary, saving: bool, slot: int, backup := false) -> void:
	if result.ok:
		last_save_slot = slot
		save_status.text = ("已保存：" if saving else "已读取：") + "存档 %d" % (slot + 1) + (" · 上一版" if backup else "")
		save_status.modulate = Color("#a9d9b5")
	else:
		var reasons := {"version": "存档版本不兼容", "open": "存档不存在或暂时无法读取",
			"checksum": "存档损坏，可尝试读取上一版", "write": "无法保存，原存档未更改",
			"busy": "请在当前模拟步结束后重试", "invalid": "存档内容无效，当前矿区未更改"}
		save_status.text = ("保存失败：" if saving else "读取失败：") + reasons.get(result.get("code", "invalid"), reasons.invalid)
		save_status.modulate = Color("#ed9c89")
	save_status.tooltip_text = save_status.text
	save_status.show()
	status_seconds = 10.0 if not result.ok else 4.0

func build_save_menu(root: Control) -> void:
	save_menu = Window.new()
	save_menu.hide()
	save_menu.transient = true
	save_menu.exclusive = true
	save_menu.unresizable = true
	save_menu.min_size = Vector2i(480, 400)
	save_menu.close_requested.connect(save_menu.hide)
	save_menu.window_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			save_menu.hide()
			save_menu.set_input_as_handled())
	root.add_child(save_menu)
	var margin := MarginContainer.new()
	save_menu.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	save_slots = ItemList.new()
	save_slots.add_theme_font_override("font", font)
	save_slots.add_theme_font_size_override("font_size", 16)
	save_slots.add_theme_constant_override("v_separation", 16)
	save_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	save_slots.item_selected.connect(func(_index: int): select_save_slot())
	content.add_child(save_slots)
	save_hint = make_label("", 14)
	save_hint.custom_minimum_size.y = 44
	save_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(save_hint)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	backup_action = make_button("读取上一版", "", use_save_slot.bind(true))
	backup_action.focus_mode = Control.FOCUS_ALL
	actions.add_child(backup_action)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(spacer)
	var cancel := make_button("取消", "", save_menu.hide)
	cancel.focus_mode = Control.FOCUS_ALL
	actions.add_child(cancel)
	save_action = make_button("保存", "", use_save_slot)
	save_action.focus_mode = Control.FOCUS_ALL
	save_action.custom_minimum_size.x = 124
	save_action.expand_icon = true
	save_action.add_theme_constant_override("icon_max_width", 22)
	actions.add_child(save_action)

func _process(delta: float) -> void:
	alert_timer += delta
	if alert_timer >= 0.25 and is_instance_valid(alert_rail):
		alert_timer = 0.0
		game.alerts.refresh(game)
		sync_alerts()
	if status_seconds > 0:
		status_seconds -= delta
		if status_seconds <= 0: save_status.hide()

func reset_screen() -> void:
	if is_instance_valid(research_panel): research_panel.hide()
	if is_instance_valid(alert_rail):
		alert_rail.scroll_vertical = 0
		alert_rail.sync(game.alerts.entries)
	close_build_tray()
	sync_pause()
	if is_instance_valid(report_window):
		report_window.queue_free()
		report_window = null

func open_report() -> void:
	if not is_instance_valid(report_window):
		report_window = DailyReport.new()
		report_window.game = game
		add_child(report_window)
	report_window.refresh()
	report_window.popup_centered()

func sync_tool() -> void:
	var value: String = game.interaction.tool
	game.world_view.sync_tool_cursor(value)
	if value in game.BUILDING_KINDS and is_instance_valid(build_tray):
		show_building_category(value)
	for name_ in tool_buttons:
		tool_buttons[name_].button_pressed = name_ == value
	sync_wage_brush()
	update_entity_panel()

func sync_wage_brush() -> void:
	if not is_instance_valid(brush_controls): return
	brush_controls.visible = game.interaction.tool == "wage"
	fee_brush_controls.visible = game.interaction.tool == "fee"
	action_panel_box.offset_bottom = 380 if brush_controls.visible or fee_brush_controls.visible else 292
	brush_selector.sync(game.interaction.brush_wage, "工资刷")
	fee_brush_selector.sync(game.interaction.brush_fee, "收费刷", "面包")
	for kind in wage_filters:
		wage_filters[kind].set_pressed_no_signal(kind == game.interaction.wage_filter)
	for kind in fee_filters:
		fee_filters[kind].set_pressed_no_signal(kind == game.interaction.fee_filter)

func sync_speed() -> void:
	for n in speed_buttons:
		speed_buttons[n].set_pressed_no_signal(n == game.interaction.speed)

func sync_pause() -> void:
	pause_button.set_pressed_no_signal(game.interaction.simulation_paused)
	pause_button.tooltip_text = "继续（空格）" if game.interaction.simulation_paused else "暂停（空格）"

func update_entity_panel() -> void:
	if not is_instance_valid(entity_panel):
		return
	if game.interaction.tool in ["wage", "fee"]:
		entity_panel.hide()
		return
	var p = game.interaction.selected_entity
	fee_details.text = game.building_fee_text(game.building_kind(p), p) if game.interaction.selected_worker < 0 and game.interaction.selected_tile == null else ""
	fee_controls.visible = not fee_details.text.is_empty()
	fee_selector.visible = fee_controls.visible and not game.fee_settings(p).is_empty()
	if fee_selector.visible:
		var kind: String = game.building_kind(p)
		fee_details.text = {"bed": "床费", "service": "服务费", "goods": "肉售价" if kind == "barn" else "售价"}[game.fee_kind(kind)]
		fee_selector.sync(game.base_fee(p), "商品到店、床位到达、服务完成时按当时价格结算", game.fee_unit(kind))
		if game.fee_kind(kind) == "goods" and not is_equal_approx(game.base_fee(p), game.sale_price(p, "meat" if kind == "barn" else null)):
			for button in fee_selector.buttons.values():
				button.tooltip_text += "\n当前售价  %s 面包" % String.num(game.sale_price(p, "meat" if kind == "barn" else null), 2)
	var settings: Dictionary = game.selected_wage_settings()
	wage_controls.visible = not settings.is_empty()
	if wage_controls.visible:
		wage_caption.text = "建造时薪" if game.world.sites.has(p) else ("挖掘时薪" if game.interaction.selected_tile != null else "时薪")
		wage_selector.sync(settings.get("wage", game.WAGE_PER_HOUR), game.selected_wage_tooltip())
	update_entity_icons()
	entity_details.visible = game.interaction.selected_worker >= 0 or game.interaction.selected_tile != null or p != game.BASE
	slaughter.visible = game.interaction.selected_worker < 0 and game.world.benches.has(p) and game.building_kind(p) == "barn"
	if slaughter.visible:
		slaughter.disabled = game.world.benches[p].sheep <= 0 or game.world.benches[p].slaughter
	move_drill.visible = game.interaction.selected_worker < 0 and game.world.benches.has(p) and game.building_kind(p) == "drill"
	production_controls.visible = game.interaction.selected_worker < 0 and game.world.benches.has(p) and game.PRODUCTS.has(game.building_kind(p))
	research_choice.visible = game.interaction.selected_worker < 0 and game.world.benches.has(p) and game.building_kind(p) == "research_bench"
	if research_choice.visible: sync_research_choice(p)
	bed_assignment.visible = game.interaction.selected_worker < 0 and game.world.beds.has(p)
	if bed_assignment.visible:
		if bed_assignment.item_count != game.world.workers.size() + 1 or game.world.workers.any(func(w): return bed_assignment.get_item_index(w.id + 1) < 0):
			bed_assignment.clear()
			bed_assignment.add_item("自动安排")
			for worker in game.world.workers:
				bed_assignment.add_item(worker.name, worker.id + 1)
		if bed_assignment.get_selected_id() != game.world.beds[p].assigned + 1:
			bed_assignment.select(bed_assignment.get_item_index(game.world.beds[p].assigned + 1))
	worker_attributes.visible = not game.world.worker(game.interaction.selected_worker).is_empty()
	entity_panel.offset_top = -370 if worker_attributes.visible else -350
	if production_controls.visible:
		entity_panel.offset_top = -480
	if wage_controls.visible:
		entity_panel.offset_top -= 60
	if fee_controls.visible:
		entity_panel.offset_top -= 60 if fee_selector.visible else 32
	entity_panel.offset_top = maxf(entity_panel.offset_top, 300.0 - get_viewport().get_visible_rect().size.y)
	if game.interaction.selected_tile != null:
		var details: Dictionary = game.tile_details(game.interaction.selected_tile)
		entity_panel.visible = not details.is_empty()
		if not details.is_empty():
			entity_title.text = details.title
			entity_details.text = details.text
			entity_details.text += "\n污染  %.1f" % game.cache.pollution.at(game.interaction.selected_tile)
		return
	if worker_attributes.visible:
		var w: Dictionary = game.worker_display(game.world.worker(game.interaction.selected_worker))
		entity_panel.show()
		entity_title.text = w.name
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
			state_name = "床上睡觉" if game.world.beds.has(w.bed) else "地上睡觉"
		elif w.state == "to_work":
			state_name = "前往" + game.building_name(game.building_kind(w.station))
		elif w.state == "to_shop":
			state_name = "购买" + game.item_name(w.item)
		elif w.state == "drink":
			state_name = "饮水"
		elif w.state == "use_item":
			state_name = "使用" + game.item_name(w.item)
		elif w.state == "to_service":
			state_name = "前往" + game.building_name(w.service)
		elif w.state == "service":
			state_name = game.SERVICES[w.service].action + "中"
		elif w.state == "to_meal":
			state_name = "前往食堂"
		var stage := "儿童" if game.is_child(w) else "老年" if w.age_days >= game.OLD_DAYS else "青年"
		entity_details.text = "存活 %.1f 天 · %s\n%s" % [w.age_days, stage, state_name]
		entity_panel.offset_top = -minf(500, get_viewport().get_visible_rect().size.y - 300)
		worker_bars["饥饿值"][0].text = "饥饿值  %.1f / %.0f" % [w.hunger, game.MAX_HUNGER]
		worker_bars["饥饿值"][1].value = w.hunger / game.MAX_HUNGER * 100
		worker_bars["疲劳"][0].text = "疲劳  %.1f / %.0f" % [w.fatigue, game.MAX_FATIGUE]
		worker_bars["疲劳"][1].value = w.fatigue / game.MAX_FATIGUE * 100
		worker_bars["污染"][0].text = "污染  %.1f / 100" % w.pollution
		worker_bars["污染"][1].value = w.pollution
		var mood_bonus: float = w.buffs.mood_bonus(w)
		var mood: float = clampf(w.mood.value + mood_bonus, -game.WorkerMood.LIMIT, game.WorkerMood.LIMIT)
		worker_bars["心情"][0].text = "心情  %+.1f" % mood
		var mood_tooltip := "基础心情  %+.1f\n临时加成  %+.1f\n劳动效率  %+.1f%%" % [w.mood.value, mood_bonus, (w.mood.work_rate(mood_bonus) - 1.0) * 100]
		for control in worker_bars["心情"]:
			control.tooltip_text = mood_tooltip
		worker_bars["心情"][1].value = mood
		var progress := -1.0
		if w.state == "dig" and game.world.terrain.get(w.job, 0) != 0:
			progress = w.progress / game.mining_seconds(w.job)
		elif w.state == "build" and game.world.sites.has(w.building):
			progress = game.world.sites[w.building].progress / game.world.sites[w.building].seconds
		elif w.state == "eat":
			progress = w.progress / game.MEAL_SECONDS
		elif w.state == "drink":
			progress = w.drink_progress / (game.DRINK_HOURS * game.HOUR_SECONDS)
		elif w.state == "use_item":
			progress = w.progress / (game.item_use_hours(w.item) * game.HOUR_SECONDS)
		elif w.state == "service":
			progress = w.progress / (game.SERVICES[w.service].hours * game.HOUR_SECONDS)
		elif w.state == "work" and game.world.benches.has(w.station):
			var task: Dictionary = game.world.benches[w.station].task
			if not task.is_empty():
				progress = task.progress / task.seconds
		worker_bars["动作进度"][0].visible = progress >= 0
		worker_bars["动作进度"][1].visible = progress >= 0
		worker_bars["动作进度"][0].text = "动作进度  %.0f%%" % (progress * 100)
		worker_bars["动作进度"][1].value = progress * 100
		return
	entity_panel.visible = p == game.BASE or game.world.beds.has(p) or game.world.sites.has(p) or game.world.benches.has(p) or game.world.banks.has(p) or game.world.belts.has(p) or game.world.power_lines.has(p)
	if not entity_panel.visible:
		game.interaction.selected_entity = null
		return
	if p == game.BASE:
		entity_title.text = "基地传送门"
		entity_details.text = ""
		return
	if game.interaction.selected_line and game.world.power_lines.has(p) and not game.world.sites.has(p):
		var kind: String = game.world.power_lines[p].kind
		entity_title.text = game.building_name(kind)
		entity_details.text = game.building_effects_text(kind, p, false)
		return
	if game.world.belts.has(p) and not game.world.sites.has(p):
		var belt_kind: String = game.building_kind(p)
		entity_title.text = game.building_name(belt_kind)
		var destination = game.belt_destination(p)
		var status := "未连接传送门或建筑"
		if destination != null:
			status = "通往" + ("传送门" if destination == game.BASE else game.building_name(game.building_kind(destination)))
		entity_details.text = status + "\n\n" + game.building_effects_text(belt_kind, p, false)
		if belt_kind == "electric_belt":
			entity_details.text += "\n" + ("运行中" if game.cache.powered_devices.has(p) else "待机 / 未供电")
		return
	if game.world.banks.has(p):
		entity_title.text = game.building_name("bank")
		entity_details.text = "%s\n\n已收利息  %.2f 面包" % [game.building_effects_text("bank"), game.world.banks[p].interest_received]
		return
	if game.world.benches.has(p):
		var bench: Dictionary = game.world.benches[p]
		var kind: String = game.building_kind(p)
		if kind == "research_bench":
			entity_title.text = game.building_name(kind)
			var project: String = bench.research
			if project == "":
				entity_details.text = ""
				entity_details.hide()
			else:
				var definition: Dictionary = game.Technology.PROJECTS[project]
				var status := "已完成" if game.Technology.completed(game.world.research_progress, project) else "等待工人"
				if bench.task.is_empty() and game.has_production_order(p) and not game.recipe_ready(p, game.station_materials(p)): status = "等待材料"
				if not bench.task.is_empty(): status = "本点  %.0f%%" % (bench.task.progress / bench.task.seconds * 100)
				entity_details.text = "%s\n科研点  %s / %d\n\n%s" % [status,
					String.num(game.research_value(project), 2), definition.points, game.research_recipe_text(project, p)]
			return
		if not game.PRODUCTS.has(kind):
			entity_title.text = game.building_name(kind)
			var status := "等待值班"
			if not bench.task.is_empty() and game.slot_owner("work", p) >= 0:
				status = game.world.worker(game.slot_owner("work", p)).name
			if kind in ["grow_light", "fountain", "drill", "spotlight", "daylight"]:
				status = "运行中" if game.cache.powered_devices.has(p) else "未供电"
				if kind == "fountain" and bench.water_day != game.world.day:
					status = "等待原水"
			elif kind in ["power_plant", "manual_generator", "transformer"]:
				status += "\n输出  %.0fW" % game.cache.power_output.get(p, 0.0)
			elif kind == "canteen":
				status = "用餐中" if game.world.workers.any(func(w): return game.worker_display(w).canteen == p) else "空闲"
			elif kind == "storage_box":
				status = ""
			elif game.SERVICES.has(kind):
				var service: Dictionary = game.SERVICES[kind]
				status = "使用中" if game.slot_owner(service.slot, p) >= 0 else ("空闲" if game.recipe_ready(p, service.materials) else "等待用品")
			entity_details.text = (status + "\n\n" if status != "" else "") + game.building_effects_text(kind, p, false)
			if game.world.wastewater.get(p, 0.0) > 0:
				entity_details.text += "\n废水污染  %.1f" % game.world.wastewater[p]
			return
		var product: Dictionary = game.PRODUCTS[kind]
		entity_title.text = game.building_name(kind)
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
			status = "等待工人" if game.slot_owner("work", p) < 0 else game.world.worker(game.slot_owner("work", p)).name
			status += "  %.0f%%" % (bench.task.progress / bench.task.seconds * 100)
		if kind == "farm":
			if bench.growth > 0:
				status = "生长中  %.1fh" % (bench.growth / game.HOUR_SECONDS)
			elif not bench.task.is_empty():
				status = ("收割 · " if bench.harvest else "浇水 · ") + status
		if kind == "barn":
			if bench.growth > 0: status += "\n产毛中 %.1fh" % (bench.growth / game.HOUR_SECONDS)
			if bench.slaughter: status += "\n待屠宰" if not bench.task.get("slaughter", false) else "\n屠宰中"
		entity_details.text = status + "\n\n" + game.product_recipe_text(kind, p)
		var effects: String = game.product_effects_text(kind, p, false)
		if effects != "":
			entity_details.text += "\n\n" + effects
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
			remove_order.tooltip_text = "减少一%s%s" % [product.unit, product.name]
			add_order.tooltip_text = "制作一%s%s" % [product.unit, product.name]
		return
	var kind: String = game.world.sites[p].kind if game.world.sites.has(p) else "bed"
	entity_title.text = game.building_name(kind) + ((" · 回收中" if game.world.sites[p].get("cancelled", false) else " · 建造中") if game.world.sites.has(p) else "")
	var details := ""
	if game.world.sites.has(p):
		var task: Dictionary = game.world.sites[p]
		if not task.get("cancelled", false):
			var worker: String = game.world.worker(game.slot_owner("build", p)).name if game.slot_owner("build", p) >= 0 else ("等待工人" if game.site_supplied(p) else "等待材料送达")
			details = "%s\n工时  %s / %sh\n\n" % [
				worker, String.num(task.progress / game.HOUR_SECONDS, 2), String.num(game.building_hours(kind), 2)]
	else:
		var bed: Dictionary = game.world.beds[p]
		details = "状态  空闲\n\n"
		if game.slot_owner("bed", p) >= 0:
			var occupant: Dictionary = game.worker_display(game.world.worker(game.slot_owner("bed", p)))
			details = "使用者  %s\n%s\n疲劳  %.1f / %.0f\n\n" % [
				occupant.name,
				"前往床位中" if occupant.state == "to_bed" else "剩余时间  %.1fh" % (bed.remaining / game.HOUR_SECONDS),
				occupant.fatigue, game.MAX_FATIGUE]
	entity_details.text = details + game.building_effects_text(kind, p, false)

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
	for goods in game.worker_cargo(w):
		add_held_item(contents, notes, goods.item, goods.amount, "搬运")
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
	var p = game.interaction.selected_entity
	if game.interaction.selected_tile == null:
		if not game.world.worker(game.interaction.selected_worker).is_empty():
			var w: Dictionary = game.world.worker(game.interaction.selected_worker)
			items = worker_inventory_entries(w)
			for effect in w.buffs.display_effects(game, w):
				var texture: Texture2D = Art.item_texture(effect.item) if effect.has("item") else Art.texture("res://assets/icons/%s.svg" % effect.icon)
				effects.append({"id": effect.id, "name": effect.name, "texture": texture,
					"description": effect.name + "\n" + effect.description})
		elif p != null and (not game.interaction.selected_line or game.world.sites.has(p)):
			var contents: Dictionary = game.storage_contents(p)
			var notes: Dictionary = {}
			var cargo_id: int = game.belt_cargo_at(p) if game.world.belts.has(p) and not game.world.sites.has(p) else -1
			if cargo_id >= 0:
				var cargo: Dictionary = game.world.belt_cargo[cargo_id]
				var carrier: Dictionary = game.world.worker(cargo.worker)
				add_held_item(contents, notes, cargo.delivery.item, cargo.delivery.amount, "搬运" + (" · " + carrier.name if not carrier.is_empty() else ""))
			items = inventory_entries(contents, notes)
			if game.world.benches.has(p) and game.building_kind(p) == "barn":
				var sheep: int = game.world.benches[p].sheep
				items.append({"id": "sheep", "name": "羊", "texture": Art.texture("res://assets/icons/sheep.svg"),
					"quantity": str(sheep), "description": "羊\n数量 %d" % sheep})
	inventory_icons.sync(items)
	effect_icons.sync(effects)
	effect_separator.visible = not items.is_empty() and not effects.is_empty()

func make_label(text_: String, size := 14) -> Label:
	var node := Label.new()
	node.text = text_
	node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", Color("#d7dfd8"))
	return node

func make_button(text_: String, tooltip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text_
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(46, 36)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font)
	b.pressed.connect(action)
	return b

func make_time_button(text_: String, tooltip: String, action: Callable) -> Button:
	var button := make_button(text_, tooltip, action)
	button.custom_minimum_size = Vector2(40, 36)
	button.toggle_mode = true
	button.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for property in ["font_color", "icon_normal_color"]:
		button.add_theme_color_override(property, Color("#737b80"))
	for property in ["font_pressed_color", "font_hover_pressed_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		button.add_theme_color_override(property, Color("#f1eddc"))
	for property in ["font_hover_color", "icon_hover_color"]:
		button.add_theme_color_override(property, Color("#bdc4c7"))
	return button

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
		tool_buttons[kind].visible = kind in kinds and game.is_building_unlocked(kind)
	for index in kinds.size():
		var button: Button = tool_buttons[kinds[index]]
		button.get_parent().move_child(button, index)
	for key in category_buttons:
		category_buttons[key].set_pressed_no_signal(key == category)
	build_tray.show()

func show_building_category(kind: String) -> void:
	for category in BUILD_CATEGORIES:
		if kind in BUILD_CATEGORIES[category].kinds:
			show_build_category(category)
			return

func close_build_tray() -> void:
	build_tray.hide()
	selected_build_category = ""
	for button in category_buttons.values():
		button.set_pressed_no_signal(false)
	if game.interaction.tool in game.BUILDING_KINDS:
		game.set_tool("dig")

func toggle_build_category(category: String) -> void:
	if build_tray.visible and selected_build_category == category:
		close_build_tray()
		return
	if game.interaction.tool in game.BUILDING_KINDS and game.interaction.tool not in BUILD_CATEGORIES[category].kinds:
		game.set_tool("dig")
	show_build_category(category)

func build_ui(controller: Node) -> void:
	game = controller
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["Noto Sans CJK SC", "Microsoft YaHei", "sans-serif"])
	font = system_font
	var hud := self
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	day_clock = DayClock.new()
	day_clock.clock_font = font
	root.add_child(day_clock)
	day_clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	day_clock.offset_left = -188
	day_clock.offset_top = 16
	day_clock.offset_right = -20
	day_clock.offset_bottom = 176
	day_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var report_button := make_button("", "每日报告", game.open_report)
	report_button.icon = game.icon_texture("res://assets/icons/report.svg")
	report_button.expand_icon = true
	report_button.add_theme_constant_override("icon_max_width", 26)
	root.add_child(report_button)
	report_button.position = Vector2(20, 34)
	report_button.custom_minimum_size = Vector2(46, 42)
	pollution_button = make_button("", "污染图层\n绿：0 · 黄：30 · 红：70及以上", func():
		game.interaction.pollution_visible = not game.interaction.pollution_visible
		game.world_view.sync_dynamic())
	pollution_button.icon = Art.texture("res://assets/icons/pollution.svg")
	pollution_button.expand_icon = true
	pollution_button.add_theme_constant_override("icon_max_width", 26)
	pollution_button.toggle_mode = true
	root.add_child(pollution_button)
	pollution_button.position = Vector2(74, 34)
	pollution_button.custom_minimum_size = Vector2(46, 42)
	for saving in [true, false]:
		var button := make_button("", "保存矿区（F5 快速保存）" if saving else "读取矿区（F9 快速读取）", show_save_menu.bind(saving))
		button.icon = Art.texture("res://assets/icons/save.svg" if saving else "res://assets/icons/load.svg")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 26)
		button.position = Vector2(128 if saving else 182, 34)
		button.custom_minimum_size = Vector2(46, 42)
		root.add_child(button)
		if saving: save_button = button
		else: load_button = button
	research_button = make_button("", "科技", func():
		if research_panel.visible: research_panel.hide()
		else: research_panel.open())
	research_button.icon = Art.texture("res://assets/icons/research.svg")
	research_button.expand_icon = true
	research_button.add_theme_constant_override("icon_max_width", 26)
	research_button.position = Vector2(236, 34)
	research_button.custom_minimum_size = Vector2(46, 42)
	root.add_child(research_button)
	save_status = make_label("", 12)
	save_status.position = Vector2(20, 88)
	save_status.size = Vector2(350, 48)
	save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_status.max_lines_visible = 2
	save_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	save_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_status.hide()
	root.add_child(save_status)
	build_save_menu(root)
	var action_panel := panel(root, Rect2(-336, 220, 316, 72), true)
	action_panel_box = action_panel.get_parent()
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	action_panel.add_child(actions)
	var time_controls := HBoxContainer.new()
	root.add_child(time_controls)
	time_controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	time_controls.offset_left = -188
	time_controls.offset_top = 180
	time_controls.offset_right = -20
	time_controls.offset_bottom = 216
	time_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	time_controls.add_theme_constant_override("separation", 2)
	time_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in [["dig", "pickaxe", "挖掘（G）\n工时 ≥ 1h / 块"],
		["cancel", "cancel", "取消（C）"], ["demolish", "demolish", "拆除（X）"], ["wage", "wage", "工资刷（P）"], ["fee", "fee", "收费刷（F）"]]:
		var b := make_button("", entry[2], game.set_tool.bind(entry[0]))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(46, 40)
		b.icon = game.icon_texture("res://assets/icons/%s.svg" % entry[1])
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 28)
		actions.add_child(b)
		tool_buttons[entry[0]] = b
	brush_controls = VBoxContainer.new()
	brush_controls.add_theme_constant_override("separation", 8)
	action_panel.add_child(brush_controls)
	brush_selector = RateSelector.new()
	brush_controls.add_child(brush_selector)
	brush_selector.build(font, game.set_brush_wage)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	brush_controls.add_child(filters)
	for entry in [["all", "blocks", "全部有薪任务"], ["mine", "pickaxe", "仅挖掘"], ["build", "tools", "仅施工"], ["station", "workbench", "仅岗位劳动"]]:
		var button := make_button("", entry[2], game.set_wage_filter.bind(entry[0]))
		button.toggle_mode = true
		button.icon = Art.texture("res://assets/icons/%s.svg" % entry[1])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 24)
		filters.add_child(button)
		wage_filters[entry[0]] = button
	brush_controls.hide()
	fee_brush_controls = VBoxContainer.new()
	fee_brush_controls.add_theme_constant_override("separation", 8)
	action_panel.add_child(fee_brush_controls)
	fee_brush_selector = RateSelector.new()
	fee_brush_controls.add_child(fee_brush_selector)
	fee_brush_selector.build(font, game.set_brush_fee)
	var price_filters := HBoxContainer.new()
	price_filters.add_theme_constant_override("separation", 6)
	fee_brush_controls.add_child(price_filters)
	for entry in [["all", "blocks", "全部收费项目"], ["goods", "workbench", "仅商品售价"], ["bed", "bed", "仅床费"], ["service", "hospital", "仅服务费"]]:
		var button := make_button("", entry[2], game.set_fee_filter.bind(entry[0]))
		button.toggle_mode = true
		button.icon = Art.texture("res://assets/icons/%s.svg" % entry[1])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 24)
		price_filters.add_child(button)
		fee_filters[entry[0]] = button
	fee_brush_controls.hide()
	pause_button = make_time_button("", "暂停（空格）", game.toggle_pause)
	pause_button.icon = Art.texture("res://assets/icons/pause.svg")
	pause_button.expand_icon = true
	pause_button.add_theme_constant_override("icon_max_width", 20)
	time_controls.add_child(pause_button)
	for value in [1, 2, 4]:
		var b := make_time_button("", "%d 倍速" % value, game.set_speed.bind(value))
		b.icon = Art.texture("res://assets/icons/speed-%d.svg" % value)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 26)
		time_controls.add_child(b)
		speed_buttons[value] = b
	game.set_speed(1)
	sync_pause()
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
	build_tray = choice_panel.get_parent()
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
		tool_buttons[kind] = button
	build_tray.hide()
	var inspector := panel(root, Rect2(0, 0, 280, 330))
	entity_panel = inspector.get_parent()
	entity_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	entity_panel.offset_left = -300
	entity_panel.offset_top = -350
	entity_panel.offset_right = -20
	entity_panel.offset_bottom = -20
	var inspector_heading := HBoxContainer.new()
	entity_title = make_label("", 20)
	entity_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_heading.add_child(entity_title)
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
	wage_controls = VBoxContainer.new()
	wage_controls.add_theme_constant_override("separation", 4)
	wage_caption = make_label("时薪", 13)
	wage_controls.add_child(wage_caption)
	wage_selector = RateSelector.new()
	wage_controls.add_child(wage_selector)
	wage_selector.build(font, game.set_selected_wage)
	wage_controls.hide()
	entity_details = make_label("", 14)
	entity_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(entity_details)
	inventory_icons = InspectorIcons.new()
	inventory_icons.display_font = font
	inventory_icons.hide()
	inspector.add_child(inventory_icons)
	effect_separator = HSeparator.new()
	effect_separator.hide()
	inspector.add_child(effect_separator)
	effect_icons = InspectorIcons.new()
	effect_icons.display_font = font
	effect_icons.show_quantities = false
	effect_icons.hide()
	inspector.add_child(effect_icons)
	move_drill = make_button("", "移动矿钻", func(): game.begin_drill_move(game.interaction.selected_entity))
	move_drill.icon = game.icon_texture("res://assets/icons/move.svg")
	move_drill.expand_icon = true
	move_drill.add_theme_constant_override("icon_max_width", 24)
	inspector_frame.add_child(move_drill)
	move_drill.hide()
	slaughter = make_button("", "屠宰：完成当前产毛后执行，不自动补羊", func(): game.request_slaughter(game.interaction.selected_entity))
	slaughter.icon = game.icon_texture("res://assets/icons/slaughter.svg")
	slaughter.expand_icon = true
	slaughter.add_theme_constant_override("icon_max_width", 24)
	slaughter.hide()
	bed_assignment = OptionButton.new()
	bed_assignment.add_theme_font_override("font", font)
	bed_assignment.add_item("自动安排", -1)
	bed_assignment.tooltip_text = "指定床位；当前使用结束后生效"
	bed_assignment.item_selected.connect(func(index: int): game.assign_bed(game.interaction.selected_entity, bed_assignment.get_item_id(index) - 1))
	inspector.add_child(bed_assignment)
	bed_assignment.hide()
	research_choice = OptionButton.new()
	research_choice.add_theme_font_override("font", font)
	research_choice.fit_to_longest_item = false
	research_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	research_choice.item_selected.connect(func(index: int):
		game.assign_research(game.interaction.selected_entity, research_choice.get_item_metadata(index)))
	inspector_frame.add_child(research_choice)
	research_choice.hide()
	production_controls = HBoxContainer.new()
	production_controls.add_child(slaughter)
	remove_order = make_button("−", "", func(): game.adjust_production(game.interaction.selected_entity, -1))
	production_controls.add_child(remove_order)
	queue_count = make_label("", 14)
	queue_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	production_controls.add_child(queue_count)
	add_order = make_button("+", "", func(): game.adjust_production(game.interaction.selected_entity, 1))
	production_controls.add_child(add_order)
	inspector_frame.add_child(production_controls)
	production_controls.hide()
	fee_details = make_label("", 14)
	fee_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fee_controls = VBoxContainer.new()
	fee_controls.add_theme_constant_override("separation", 4)
	fee_controls.add_child(fee_details)
	fee_selector = RateSelector.new()
	fee_controls.add_child(fee_selector)
	fee_selector.build(font, game.set_selected_fee)
	fee_controls.hide()
	inspector_frame.add_child(fee_controls)
	inspector_frame.add_child(wage_controls)
	worker_attributes = VBoxContainer.new()
	worker_attributes.add_theme_constant_override("separation", 6)
	inspector.add_child(worker_attributes)
	for attribute in ["饥饿值", "疲劳", "污染", "心情", "动作进度"]:
		var caption := make_label(attribute, 13)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 8)
		bar.show_percentage = false
		if attribute == "心情":
			caption.mouse_filter = Control.MOUSE_FILTER_PASS
			bar.mouse_filter = Control.MOUSE_FILTER_PASS
			bar.min_value = -game.WorkerMood.LIMIT
			bar.max_value = game.WorkerMood.LIMIT
		worker_attributes.add_child(caption)
		worker_attributes.add_child(bar)
		worker_bars[attribute] = [caption, bar]
	worker_attributes.hide()
	entity_panel.hide()
	alert_rail = AlertRail.new()
	alert_rail.game = game
	root.add_child(alert_rail)
	alert_rail.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	alert_rail.offset_left = 20
	alert_rail.offset_right = 300
	alert_rail.hide()
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.dialog_text = "重新开始矿区？当前任务与交付记录将清空。"
	reset_dialog.title = "重置矿区"
	reset_dialog.confirmed.connect(game.reset_world)
	root.add_child(reset_dialog)
	research_panel = ResearchPanel.new()
	root.add_child(research_panel)
	research_panel.build(game, self)
	game.set_tool("dig")

func sync_research_choice(p: Vector2i) -> void:
	if research_choice.item_count == 0:
		research_choice.add_item("暂停")
		research_choice.set_item_metadata(0, "")
		for project in game.Technology.PROJECTS:
			research_choice.add_item(game.Technology.PROJECTS[project].name)
			research_choice.set_item_metadata(research_choice.item_count - 1, project)
	for index in research_choice.item_count:
		var project: String = research_choice.get_item_metadata(index)
		research_choice.set_item_disabled(index, project != "" and not game.Technology.available(game.world.research_progress, project))
		if project == game.world.benches[p].research and research_choice.selected != index: research_choice.select(index)

func update_ui() -> void:
	pollution_button.set_pressed_no_signal(game.interaction.pollution_visible)
	var available: Dictionary = game.building_available_materials()
	for kind in game.BUILDING_KINDS:
		tool_buttons[kind].disabled = not game.can_plan_building(kind, available)
		tool_buttons[kind].visible = selected_build_category != "" and kind in BUILD_CATEGORIES[selected_build_category].kinds and game.is_building_unlocked(kind)
	if is_instance_valid(research_panel) and research_panel.visible: research_panel.sync()
	update_entity_panel()
	game.alerts.refresh(game)
	sync_alerts()
	day_clock.set_time(game.world.day_elapsed, game.world.day, game.DAY_SECONDS)

func sync_alerts() -> void:
	alert_rail.sync(game.alerts.entries)
	var height := get_viewport().get_visible_rect().size.y
	var bottom := height - (260.0 if build_tray.visible else 108.0)
	var rail_height := minf(alert_rail.list.get_combined_minimum_size().y, maxf(0, minf(320, bottom - 140)))
	var top := clampf((height - rail_height) * 0.5, 140, maxf(140, bottom - rail_height))
	alert_rail.offset_top = top - height * 0.5
	alert_rail.offset_bottom = alert_rail.offset_top + rail_height
