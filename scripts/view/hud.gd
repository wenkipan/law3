extends CanvasLayer

const DailyReport = preload("res://scripts/daily_report.gd")
const BuildButton = preload("res://scripts/build_button.gd")
const Art = preload("res://scripts/view/art.gd")
const InspectorIcons = preload("res://scripts/view/inspector_icons.gd")
const SaveStore = preload("res://scripts/persistence/save_store.gd")
const BUILD_CATEGORIES := {
	"food": {"name": "农业与食品", "icon": "wheat", "kinds": ["farm", "hunting_ground", "gathering_garden", "barn", "mill", "brewery", "grow_light"]},
	"industry": {"name": "工业与装备", "icon": "tools", "kinds": ["mine", "drill", "smelter", "sawmill", "smithy", "weaver", "tailor", "bench", "workbench", "chemical_plant", "soapworks", "pharmacy"]},
	"water": {"name": "水务", "icon": "water", "kinds": ["pump", "purifier"]},
	"power": {"name": "电力", "icon": "electricity", "kinds": ["manual_generator", "power_plant", "low_line", "high_line", "transformer"]},
	"logistics": {"name": "物流", "icon": "freight", "kinds": ["market", "storage_box", "belt", "electric_belt"]},
	"life": {"name": "生活与环境", "icon": "furniture", "kinds": ["wall", "fence", "door", "bed", "canteen", "fountain", "spotlight", "daylight", "bathhouse", "laundry", "hospital"]},
	"society": {"name": "人口金融与科研", "icon": "population-finance", "kinds": ["recruitment_board", "research_bench", "printer", "bank"]},
}

var game: Node
@onready var market_controls: VBoxContainer = %MarketControls
var market_inputs: Dictionary = {}
var market_target = null
var report_window: Window
@onready var day_clock: Control = %DayClock
@onready var pause_button: Button = %PauseButton
var tool_buttons: Dictionary = {}
var tool_group := ButtonGroup.new()
@onready var build_tray: PanelContainer = %BuildTray
var speed_buttons: Dictionary = {}
var speed_group := ButtonGroup.new()
@onready var reset_dialog: ConfirmationDialog = %ResetDialog
var font: Font
@onready var worker_attributes: VBoxContainer = %WorkerAttributes
var worker_bars: Dictionary = {}
@onready var entity_panel: PanelContainer = %EntityPanel
@onready var entity_title: Label = %EntityTitle
@onready var entity_details: Label = %EntityDetails
var category_buttons: Dictionary = {}
var category_group := ButtonGroup.new()
var selected_build_category := ""
@onready var inventory_icons: InspectorIcons = %InventoryIcons
@onready var effect_icons: InspectorIcons = %EffectIcons
@onready var effect_separator: HSeparator = %EffectSeparator
@onready var bed_assignment: OptionButton = %BedAssignment
@onready var production_controls: HBoxContainer = %ProductionControls
@onready var queue_count: Label = %QueueCount
@onready var remove_order: Button = %RemoveOrder
@onready var add_order: Button = %AddOrder
@onready var move_drill: Button = %MoveDrill
@onready var pollution_button: Button = %PollutionButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var save_menu: Window = %SaveMenu
@onready var save_slots: ItemList = %SaveSlots
@onready var save_action: Button = %SaveAction
@onready var backup_action: Button = %BackupAction
@onready var save_hint: Label = %SaveHint
@onready var save_status: Label = %SaveStatus
var save_directory := SaveStore.DIRECTORY
var last_save_slot := -1
var menu_saving := true
var overwrite_pending := false
@onready var status_timer: Timer = $SaveStatusTimeout
@onready var alert_rail: ScrollContainer = %AlertRail
@onready var research_button: Button = %ResearchButton
@onready var research_panel: PanelContainer = %ResearchPanel
@onready var research_choice: OptionButton = %ResearchChoice
@onready var wage_controls: VBoxContainer = %WageControls
@onready var wage_caption: Label = %WageCaption
@onready var fee_details: Label = %FeeDetails
@onready var fee_controls: VBoxContainer = %FeeControls
@onready var fee_selector: HBoxContainer = %FeeSelector
@onready var fee_brush_controls: VBoxContainer = %FeeBrushControls
@onready var fee_brush_selector: HBoxContainer = %FeeBrushSelector
var fee_filters: Dictionary = {}
var fee_filter_group := ButtonGroup.new()
@onready var wage_selector: HBoxContainer = %WageSelector
@onready var brush_controls: VBoxContainer = %BrushControls
@onready var brush_selector: HBoxContainer = %BrushSelector
var wage_filters: Dictionary = {}
var wage_filter_group := ButtonGroup.new()
@onready var action_panel_box: PanelContainer = %ActionPanelBox

func blocks_simulation() -> bool:
	return (is_instance_valid(reset_dialog) and reset_dialog.visible) or (is_instance_valid(save_menu) and save_menu.visible)

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
	status_timer.start(10.0 if not result.ok else 4.0)

func refresh_alerts() -> void:
	game.alerts.refresh(game)
	sync_alerts()

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
		report_window.theme = %Screen.theme
		add_child(report_window)
	report_window.refresh()
	report_window.popup_centered()

func sync_tool() -> void:
	var value: String = game.interaction.tool
	if value in game.BUILDING_KINDS and is_instance_valid(build_tray):
		show_building_category(value)
	if tool_buttons.has(value):
		tool_buttons[value].button_pressed = true
	elif tool_group.get_pressed_button() != null:
		tool_group.get_pressed_button().button_pressed = false
	sync_wage_brush()
	update_entity_panel()

func sync_wage_brush() -> void:
	if not is_instance_valid(brush_controls): return
	brush_controls.visible = game.interaction.tool == "wage"
	fee_brush_controls.visible = game.interaction.tool == "fee"
	action_panel_box.offset_bottom = 380 if brush_controls.visible or fee_brush_controls.visible else 292
	brush_selector.sync(game.interaction.brush_wage, "工资刷")
	fee_brush_selector.sync(game.interaction.brush_fee, "收费刷", "货币")
	wage_filters[game.interaction.wage_filter].button_pressed = true
	fee_filters[game.interaction.fee_filter].button_pressed = true

func sync_speed() -> void:
	speed_buttons[int(game.interaction.speed)].button_pressed = true

func sync_pause() -> void:
	pause_button.set_pressed_no_signal(game.interaction.paused_by_player)
	pause_button.tooltip_text = "继续（空格）" if game.interaction.paused_by_player else "暂停（空格）"

func update_entity_panel() -> void:
	if not is_instance_valid(entity_panel):
		return
	if game.interaction.tool in ["wage", "fee"]:
		entity_panel.hide()
		return
	var p = game.interaction.selected_entity
	market_controls.visible = game.interaction.selected_worker < 0 and game.interaction.selected_tile == null and game.building_kind(p) == "market" and game.world.has_building(p, "station")
	var next_market = p if market_controls.visible else null
	if market_target != next_market:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and market_controls.is_ancestor_of(focused): focused.release_focus()
		market_target = next_market
	if market_controls.visible:
		for item in market_inputs:
			var input: SpinBox = market_inputs[item]
			var price: float = game.market_price(p, item)
			if not input.get_line_edit().has_focus() and not is_equal_approx(input.value, price): input.set_value_no_signal(price)
	fee_details.text = game.building_fee_text(game.building_kind(p), p) if game.interaction.selected_worker < 0 and game.interaction.selected_tile == null else ""
	fee_controls.visible = not fee_details.text.is_empty()
	fee_selector.visible = fee_controls.visible and not game.fee_settings(p).is_empty()
	if fee_selector.visible:
		var kind: String = game.building_kind(p)
		fee_details.text = {"bed": "床费", "service": "服务费", "goods": "售价"}[game.fee_kind(kind)]
		fee_selector.sync(game.base_fee(p), "商品到店、床位到达、服务完成时按当时价格结算", game.fee_unit(kind))
		if game.fee_kind(kind) == "goods" and not is_equal_approx(game.base_fee(p), game.sale_price(p)):
			for button in fee_selector.buttons.values():
				button.tooltip_text += "\n当前售价  %s 货币" % String.num(game.sale_price(p), 2)
	var settings: Dictionary = game.selected_wage_settings()
	var recruitment: Dictionary = game.recruitment_settings(p) if game.interaction.selected_worker < 0 and game.interaction.selected_tile == null else {}
	wage_controls.visible = not settings.is_empty() or not recruitment.is_empty()
	if not recruitment.is_empty():
		wage_caption.text = "招募费用"
		wage_selector.sync(recruitment.recruitment_cost, "居民到达时扣除木牌库存中的金币", "金币 / 人")
		wage_selector.buttons[0].tooltip_text = "关闭招募"
	elif not settings.is_empty():
		wage_caption.text = "建造时薪" if game.world.has_building(p, "site") else ("挖掘时薪" if game.interaction.selected_tile != null else "时薪")
		wage_selector.sync(settings.get("wage", game.WAGE_PER_HOUR), game.selected_wage_tooltip())
	update_entity_icons()
	entity_details.visible = true
	move_drill.visible = game.interaction.selected_worker < 0 and game.world.has_building(p, "station") and game.building_kind(p) == "drill"
	production_controls.visible = game.interaction.selected_worker < 0 and game.world.has_building(p, "station") and game.PRODUCTS.has(game.building_kind(p))
	research_choice.visible = game.interaction.selected_worker < 0 and game.world.has_building(p, "station") and game.building_kind(p) == "research_bench"
	if research_choice.visible: sync_research_choice(p)
	bed_assignment.visible = game.interaction.selected_worker < 0 and game.world.has_building(p, "bed")
	if bed_assignment.visible:
		var people: Array = game.known_workers()
		if bed_assignment.item_count != people.size() + 1 or people.any(func(w): return bed_assignment.get_item_index(w.id + 1) < 0):
			bed_assignment.clear()
			bed_assignment.add_item("自动安排")
			for worker in people:
				bed_assignment.add_item(worker.name, worker.id + 1)
		if bed_assignment.get_selected_id() != game.world.building_state(p, "bed").assigned + 1:
			bed_assignment.select(bed_assignment.get_item_index(game.world.building_state(p, "bed").assigned + 1))
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
		elif w.state in ["gather", "hunt"]:
			state_name = "捕猎" if w.state == "hunt" else "采集" + game.item_name(w.item)
		elif w.state == "sleep":
			state_name = "床上睡觉" if game.world.has_building(w.bed, "bed") else "地上睡觉"
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
		var employer: String = game.building_name(game.world.buildings[w.employer].kind) if w.employer != null else "未受雇"
		entity_details.text = "存活 %.1f 天 · %s\n%s · %s类\n%s\n%s" % [w.age_days, stage, game.SKILLS[w.skill], {"fruit": "水果", "meat": "肉", "grain": "谷物"}[w.diet], employer, state_name]
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
		elif w.state in ["gather", "hunt"]:
			progress = w.progress / game.HOUR_SECONDS
		elif w.state == "build" and game.world.has_building(w.building, "site"):
			progress = game.world.building_state(w.building, "site").progress / game.world.building_state(w.building, "site").seconds
		elif w.state == "eat":
			progress = w.progress / game.MEAL_SECONDS
		elif w.state == "drink":
			progress = w.drink_progress / (game.DRINK_HOURS * game.HOUR_SECONDS)
		elif w.state == "use_item":
			progress = w.progress / (game.item_use_hours(w.item) * game.HOUR_SECONDS)
		elif w.state == "service":
			progress = w.progress / (game.SERVICES[w.service].hours * game.HOUR_SECONDS)
		elif w.state == "work" and game.world.has_building(w.station, "station"):
			var task: Dictionary = game.world.building_state(w.station, "station").task
			if not task.is_empty():
				progress = task.progress / task.seconds
		worker_bars["动作进度"][0].visible = progress >= 0
		worker_bars["动作进度"][1].visible = progress >= 0
		worker_bars["动作进度"][0].text = "动作进度  %.0f%%" % (progress * 100)
		worker_bars["动作进度"][1].value = progress * 100
		return
	entity_panel.visible = game.world.has_building(p, "bed") or game.world.has_building(p, "site") or game.world.has_building(p, "station") or game.world.has_building(p, "bank") or game.world.has_building(p, "belt") or game.world.has_building(p, "line")
	if not entity_panel.visible:
		game.interaction.selected_entity = null
		return
	if game.interaction.selected_line and game.world.has_building(p, "line") and not game.world.has_building(p, "site"):
		var kind: String = game.world.building_state(p, "line").kind
		entity_title.text = game.building_name(kind)
		entity_details.text = game.building_effects_text(kind, p, false)
		return
	if game.world.has_building(p, "belt") and not game.world.has_building(p, "site"):
		var belt_kind: String = game.building_kind(p)
		entity_title.text = game.building_name(belt_kind)
		var destination = game.belt_destination(p)
		var status := "未连接建筑"
		if destination != null and not game.is_built_market(destination):
			status = "通往" + game.building_name(game.building_kind(destination))
		entity_details.text = status + "\n\n" + game.building_effects_text(belt_kind, p, false)
		if belt_kind == "electric_belt":
			entity_details.text += "\n" + ("运行中" if game.cache.powered_devices.has(p) else "待机 / 未供电")
		return
	if game.world.has_building(p, "bank"):
		entity_title.text = game.building_name("bank")
		entity_details.text = "%s\n\n已收利息  %.2f 货币" % [game.building_effects_text("bank"), game.world.building_state(p, "bank").interest_received]
		return
	if game.world.has_building(p, "station"):
		var bench: Dictionary = game.world.building_state(p, "station")
		var kind: String = game.building_kind(p)
		if kind in ["market", "mine", "storage_box"]:
			entity_title.text = game.building_name(kind)
			var employee: Dictionary = game.world.worker(bench.employee)
			entity_details.text = game.operator_name("work", p, "已关闭" if bench.wage == 0 else ("招聘 · " + game.SKILLS[game.work_skill(kind)] if employee.is_empty() else employee.name))
			if kind == "mine":
				var deposit = game.mine_deposit(p)
				entity_details.text += "\n资源耗尽" if deposit == null else "\n" + game.item_name(game.world.terrain[deposit]) + " × %d" % game.world.deposits[deposit]
			return
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
			var status: String = game.operator_name("work", p, "等待值班")
			if kind in ["grow_light", "fountain", "drill", "spotlight", "daylight"]:
				status = "运行中" if game.cache.powered_devices.has(p) else "未供电"
				if kind == "fountain" and bench.water_day != game.world.day:
					status = "等待原水"
			elif kind in ["power_plant", "manual_generator", "transformer"]:
				status += "\n输出  %.0fW" % game.cache.power_output.get(p, 0.0)
			elif kind == "canteen":
				status = "用餐中" if game.world.workers.any(func(w): return game.worker_display(w).canteen == p) else "空闲"
			elif kind == "recruitment_board":
				if bench.recruitment_cost == 0:
					status = "已关闭"
				else:
					status = "金币不足" if game.stock_at(p, "money") < bench.recruitment_cost else "招工中"
			elif kind == "storage_box" or kind in game.BARRIER_KINDS:
				status = ""
			elif game.SERVICES.has(kind):
				var service: Dictionary = game.SERVICES[kind]
				status = "使用中" if game.slot_owner(service.slot, p) >= 0 else ("空闲" if game.recipe_ready(p, service.materials) else "等待用品")
			entity_details.text = (status + "\n\n" if status != "" else "") + game.building_effects_text(kind, p, false)
			if game.world.waste_at(p) > 0:
				entity_details.text += "\n废水污染  %.1f" % game.world.waste_at(p)
			return
		var product: Dictionary = game.PRODUCTS[kind]
		entity_title.text = game.building_name(kind)
		var status := "空闲"
		if game.uses_daily_output(kind) and bench.task.is_empty() and not game.has_production_order(p):
			status = "已停产" if bench.daily_output == 0 else "今日已完成"
		if game.has_production_order(p) and bench.task.is_empty() and bench.growth <= 0 and not game.recipe_ready(p, game.production_materials(kind)):
			var missing: Array[String] = []
			for item in game.production_materials(kind):
				if is_same(item, 0):
					missing.append("矿石")
				elif game.stock_at(p, item) < game.production_materials(kind)[item]:
					missing.append(game.item_name(item))
			status = "等待" + "、".join(missing)
		if not bench.task.is_empty():
			status = game.operator_name("work", p, "等待工人")
			status += "  %.0f%%" % (bench.task.progress / bench.task.seconds * 100)
		if kind == "farm":
			if bench.growth > 0:
				status = "生长中  %.1fh" % (bench.growth / game.HOUR_SECONDS)
			elif not bench.task.is_empty():
				status = ("收割 · " if bench.harvest else "浇水 · ") + status
		if kind == "barn" and bench.growth > 0:
			status = "产毛中 %.1fh" % (bench.growth / game.HOUR_SECONDS)
		if product.has("recovery_hours") and bench.growth > 0:
			status = "%s中  %.1fh" % [product.recovery_name, bench.growth / game.HOUR_SECONDS]
		entity_details.text = status + "\n\n" + game.product_recipe_text(kind, p)
		var effects: String = game.product_effects_text(kind, p, false)
		if effects != "":
			entity_details.text += "\n\n" + effects
		add_order.disabled = false
		if game.uses_daily_output(kind):
			queue_count.text = "每日产出 %d%s" % [bench.daily_output, product.unit]
			remove_order.disabled = bench.daily_output == 0
			remove_order.tooltip_text = "每日产出 −%d%s" % [product.get("amount", 1), product.unit]
			add_order.tooltip_text = "每日产出 +%d%s" % [product.get("amount", 1), product.unit]
		else:
			queue_count.text = "待制  %d" % bench.queue
			remove_order.disabled = bench.queue <= (0 if bench.task.is_empty() else 1)
			remove_order.tooltip_text = "减少一%s%s" % [product.unit, product.name]
			add_order.tooltip_text = "制作一%s%s" % [product.unit, product.name]
		return
	var kind: String = game.world.building_state(p, "site").kind if game.world.has_building(p, "site") else "bed"
	entity_title.text = game.building_name(kind) + ((" · 回收中" if game.world.building_state(p, "site").get("cancelled", false) else " · 建造中") if game.world.has_building(p, "site") else "")
	var details := ""
	if game.world.has_building(p, "site"):
		var task: Dictionary = game.world.building_state(p, "site")
		if not task.get("cancelled", false):
			var worker: String = game.operator_name("build", p, "等待工人" if game.site_supplied(p) else "等待材料送达")
			details = "%s\n工时  %s / %sh\n\n" % [
				worker, String.num(task.progress / game.HOUR_SECONDS, 2), String.num(game.building_hours(kind), 2)]
	else:
		var bed: Dictionary = game.world.building_state(p, "bed")
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
	add_held_item(contents, notes, "money", w.money, "自用")
	if w.meal_food > 0: add_held_item(contents, notes, w.meal_item, w.meal_food, "自用")
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
		elif p != null and (not game.interaction.selected_line or game.world.has_building(p, "site")):
			var contents: Dictionary = game.storage_contents(p)
			var notes: Dictionary = {}
			var cargo_id: int = game.belt_cargo_at(p) if game.world.has_building(p, "belt") and not game.world.has_building(p, "site") else -1
			if cargo_id >= 0:
				var cargo: Dictionary = game.world.belt_cargo[cargo_id]
				var carrier: Dictionary = game.world.worker(cargo.worker)
				add_held_item(contents, notes, cargo.delivery.item, cargo.delivery.amount, "搬运" + (" · " + carrier.name if not carrier.is_empty() else ""))
			items = inventory_entries(contents, notes)
	elif game.interaction.selected_tile != null:
		p = game.interaction.selected_tile
		items = inventory_entries(game.storage_contents(p), {})
	if game.interaction.selected_worker < 0 and p != null:
		for entry in items:
			if game.player_pickup_amount(p, entry.id) > 0:
				entry.take = game.begin_player_drag.bind(p, entry.id)
	inventory_icons.sync(items)
	effect_icons.sync(effects)
	effect_separator.visible = not items.is_empty() and not effects.is_empty()

func make_label(text_: String, size := 14) -> Label:
	var node := Label.new()
	node.text = text_
	node.add_theme_font_size_override("font_size", size)
	return node

func make_button(text_: String, tooltip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text_
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(46, 36)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b

func show_build_category(category: String) -> void:
	selected_build_category = category
	var kinds: Array = BUILD_CATEGORIES[category].kinds
	for kind in game.BUILDING_KINDS:
		tool_buttons[kind].visible = kind in kinds and game.is_building_unlocked(kind)
	for index in kinds.size():
		var button: Button = tool_buttons[kinds[index]]
		button.get_parent().move_child(button, index)
	category_buttons[category].button_pressed = true
	build_tray.show()

func show_building_category(kind: String) -> void:
	for category in BUILD_CATEGORIES:
		if kind in BUILD_CATEGORIES[category].kinds:
			show_build_category(category)
			return

func close_build_tray() -> void:
	build_tray.hide()
	selected_build_category = ""
	if category_group.get_pressed_button() != null:
		category_group.get_pressed_button().button_pressed = false
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
	font = %Screen.get_theme_default_font()
	category_group.allow_unpress = true
	$AlertRefresh.timeout.connect(refresh_alerts)
	status_timer.timeout.connect(save_status.hide)
	%ReportButton.pressed.connect(game.open_report)
	pollution_button.pressed.connect(func():
		game.interaction.pollution_visible = not game.interaction.pollution_visible
		game.world_view.sync_dynamic())
	save_button.pressed.connect(show_save_menu.bind(true))
	load_button.pressed.connect(show_save_menu.bind(false))
	research_button.pressed.connect(func():
		if research_panel.visible: research_panel.hide()
		else: research_panel.open())
	pause_button.pressed.connect(game.toggle_pause)
	tool_buttons = {"dig": %ToolDig, "cancel": %ToolCancel, "demolish": %ToolDemolish, "wage": %ToolWage, "fee": %ToolFee}
	for tool in tool_buttons:
		var button: Button = tool_buttons[tool]
		button.button_group = tool_group
		button.pressed.connect(game.set_tool.bind(tool))
	speed_buttons = {1: %Speed1, 2: %Speed2, 4: %Speed4}
	for value in speed_buttons:
		var button: Button = speed_buttons[value]
		button.button_group = speed_group
		button.pressed.connect(game.set_speed.bind(value))
	game.set_speed(1)
	sync_pause()
	brush_selector.build(game.set_brush_wage, true)
	fee_brush_selector.build(game.set_brush_fee)
	for entry in [["all", "blocks", "全部有薪任务"], ["mine", "pickaxe", "仅挖掘"], ["build", "tools", "仅施工"], ["station", "workbench", "仅岗位劳动"]]:
		var button := make_button("", entry[2], game.set_wage_filter.bind(entry[0]))
		button.toggle_mode = true
		button.button_group = wage_filter_group
		button.icon = Art.texture("res://assets/icons/%s.svg" % entry[1])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 24)
		%WageFilters.add_child(button)
		wage_filters[entry[0]] = button
	for entry in [["all", "blocks", "全部收费项目"], ["goods", "workbench", "仅商品售价"], ["bed", "bed", "仅床费"], ["service", "hospital", "仅服务费"]]:
		var button := make_button("", entry[2], game.set_fee_filter.bind(entry[0]))
		button.toggle_mode = true
		button.button_group = fee_filter_group
		button.icon = Art.texture("res://assets/icons/%s.svg" % entry[1])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 24)
		%FeeFilters.add_child(button)
		fee_filters[entry[0]] = button
	for category in BUILD_CATEGORIES:
		var definition: Dictionary = BUILD_CATEGORIES[category]
		var button := make_button("", definition.name, toggle_build_category.bind(category))
		button.icon = Art.texture("res://assets/icons/%s.svg" % definition.icon)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 28)
		button.toggle_mode = true
		button.button_group = category_group
		button.custom_minimum_size = Vector2(48, 36)
		%Categories.add_child(button)
		category_buttons[category] = button
	for kind in game.BUILDING_KINDS:
		var button := BuildButton.new()
		button.game = game
		button.kind = kind
		button.tooltip_text = game.building_name(kind)
		button.focus_mode = Control.FOCUS_NONE
		button.icon = Art.texture("res://assets/icons/%s.svg" % kind)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 64)
		button.add_theme_color_override("icon_disabled_color", Color(0.45, 0.45, 0.45, 0.55))
		button.toggle_mode = true
		button.button_group = tool_group
		button.custom_minimum_size = Vector2(72, 54)
		button.pressed.connect(game.set_tool.bind(kind))
		button.hide()
		%BuildingChoices.add_child(button)
		tool_buttons[kind] = button
	wage_selector.build(game.set_selected_rate, true)
	fee_selector.build(game.set_selected_fee)
	for item in game.MARKET_GOODS:
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = Art.item_texture(item)
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = game.item_name(item)
		row.add_child(icon)
		var price := SpinBox.new()
		price.min_value = 1
		price.max_value = game.MAX_WAGE
		price.step = 1
		price.custom_minimum_size.x = 88
		price.prefix = "↑"
		price.tooltip_text = "出售价"
		price.value_changed.connect(func(value: float):
			if market_target != null: game.set_market_price(market_target, item, value))
		row.add_child(price)
		market_controls.add_child(row)
		market_inputs[item] = price
	effect_icons.show_quantities = false
	%InspectorClose.pressed.connect(game.clear_entity_selection)
	move_drill.pressed.connect(func(): game.begin_drill_move(game.interaction.selected_entity))
	remove_order.pressed.connect(func(): game.adjust_production(game.interaction.selected_entity, -1))
	add_order.pressed.connect(func(): game.adjust_production(game.interaction.selected_entity, 1))
	bed_assignment.item_selected.connect(func(index: int): game.assign_bed(game.interaction.selected_entity, bed_assignment.get_item_id(index) - 1))
	research_choice.item_selected.connect(func(index: int):
		game.assign_research(game.interaction.selected_entity, research_choice.get_item_metadata(index)))
	var captions := [%Attribute0, %Attribute2, %Attribute4, %Attribute6, %Attribute8]
	var bars := [%Attribute1, %Attribute3, %Attribute5, %Attribute7, %Attribute9]
	for index in captions.size():
		worker_bars[captions[index].text] = [captions[index], bars[index]]
	worker_bars["心情"][1].min_value = -game.WorkerMood.LIMIT
	worker_bars["心情"][1].max_value = game.WorkerMood.LIMIT
	save_menu.close_requested.connect(save_menu.hide)
	save_menu.window_input.connect(func(event: InputEvent):
		if event.is_action_pressed(&"game_cancel"):
			save_menu.hide()
			save_menu.set_input_as_handled())
	save_menu.visibility_changed.connect(game.apply_time_settings)
	save_slots.item_selected.connect(func(_index: int): select_save_slot())
	backup_action.pressed.connect(use_save_slot.bind(true))
	%SaveCancel.pressed.connect(save_menu.hide)
	save_action.pressed.connect(use_save_slot)
	reset_dialog.confirmed.connect(game.reset_world)
	reset_dialog.visibility_changed.connect(game.apply_time_settings)
	alert_rail.game = game
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
		if project == game.world.building_state(p, "station").research and research_choice.selected != index: research_choice.select(index)

func update_ui() -> void:
	pollution_button.set_pressed_no_signal(game.interaction.pollution_visible)
	for kind in game.BUILDING_KINDS:
		tool_buttons[kind].disabled = not game.can_plan_building(kind)
		tool_buttons[kind].visible = selected_build_category != "" and kind in BUILD_CATEGORIES[selected_build_category].kinds and game.is_building_unlocked(kind)
	if is_instance_valid(research_panel) and research_panel.visible: research_panel.sync()
	update_entity_panel()
	day_clock.set_time(game.world.day_elapsed, game.world.day, game.DAY_SECONDS)

func sync_alerts() -> void:
	alert_rail.sync(game.alerts.entries)
	var height := get_viewport().get_visible_rect().size.y
	var bottom := height - (260.0 if build_tray.visible else 108.0)
	var rail_height := minf(alert_rail.list.get_combined_minimum_size().y, maxf(0, minf(320, bottom - 140)))
	var top := clampf((height - rail_height) * 0.5, 140, maxf(140, bottom - rail_height))
	alert_rail.offset_top = top - height * 0.5
	alert_rail.offset_bottom = alert_rail.offset_top + rail_height
