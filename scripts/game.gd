extends Node2D

const CELL := 40.0
const BASE := Vector2i(32, 13)
const VISION_RADIUS := 7
const DAY_SECONDS := 180.0
# 面包兼作食物和支付物。饱食度全天衰减，最低为零；出生时满饱食，不增加实物面包。
const MEAL_SECONDS := 2.0
const HUNGER_PER_BREAD := 10.0
const MAX_HUNGER := 180.0
const STARTING_HUNGER := MAX_HUNGER
const HUNGER_DECAY_PER_DAY := 80.0
# 挖掘、建造与生产增加疲劳，通勤和搬运不增加；疲劳提高睡眠意愿，满后强制休息。
const MAX_FATIGUE := 120.0
const FATIGUE_PER_HOUR := 10.0
const SLEEP_RECOVERY_PER_HOUR := 15.0
const HOUR_SECONDS := DAY_SECONDS / 24.0
const MIN_MINING_HOURS := 1.0
const BED_BLOCKS := 6
const BED_BUILD_HOURS := 4.0
const WAGE_PER_HOUR := 1.0
# 床到达后收费，独占一个租期并加快疲劳恢复；提前醒来不退费，租期结束后按地面速度恢复。
const BED_PRICE := 4.0
const BED_LEASE_HOURS := 8.0
const BED_RECOVERY_PER_HOUR := 25.0
const BENCH_BLOCKS := 6
const BENCH_BUILD_HOURS := 4.0
# 矿枪缩短挖掘时间但不降低单件报酬；每完成一格消耗一次耐久，疲劳按实际工时计算。
const GUN_WORK_HOURS := 2.0
const GUN_PRICE := 5.0
const GUN_USES := 10
const GUN_MINING_RATE := 2.0
const WORKBENCH_BLOCKS := 6
const WORKBENCH_BUILD_HOURS := 4.0
# 背包在工作桌购买，每趟多携带一块矿石；完整交付双块才消耗一次使用次数。
const BACKPACK_WORK_HOURS := 2.0
const BACKPACK_PRICE := 4.0
const BACKPACK_USES := 10
# 原水由抽水机生产，运入农田用于灌溉，运入净水器用于净化。水源格不可通行或覆盖。
const WATER_BUILD_BLOCKS := 8
const WATER_BUILD_HOURS := 4.0
const WATER_WORK_HOURS := 1.0
const WATER_BATCH := 4
# 清水在净水器购买、随身携带；饮用暂停劳动，完成后减缓疲劳增长，效果不叠加。
const WATER_PRICE := 1.0
const WATER_CAPACITY := 4
const DRINK_HOURS := 0.1
const WATER_EFFECT_HOURS := 4.0
const WATER_FATIGUE_REDUCTION := 0.3
const PRINTER_BLOCKS := 12
const PRINTER_BUILD_HOURS := 6.0
# 打印仓按有限订单消耗矿石与劳动，完成后在右侧生成工人，出生后参与模拟与日报。
const PRINT_WORKER_BLOCKS := 10
const PRINT_WORKER_HOURS := 4.0
const BANK_BLOCKS := 12
const BANK_BUILD_HOURS := 6.0
# 银行用本地面包缓解紧急食物短缺，每人每天最多一笔；未还清不能追加，借款不计为收入。
const LOAN_LIMIT := 10.0
# 借款一次计息；劳动收入按比例先还本金、再还利息，末笔以未偿余额为限。
const LOAN_INTEREST_RATE := 0.2
const LOAN_REPAYMENT_RATE := 0.25
const BELT_BLOCKS := 1
const BELT_BUILD_HOURS := 0.25
# 矿道单格单向运矿，拥堵时排队、汇流轮流放行；运费随货携带，到传送门时结算。
const BELT_SPEED := 2.0
const BELT_FEE := 0.2
const WORKER_NAMES := ["阿麦", "米粒", "石头", "小满", "青禾", "阿砾", "谷雨", "小川"]
const WORKER_COLORS := [Color("#d6ba72"), Color("#a4cbb5"), Color("#d99987")]
# 开局面包存于传送门。工厂库存与个人面包分别归属，支付转移所有权，进食消耗实物。
const STARTING_BREAD := 300.0
const RESOURCE_ITEMS := [1, 2, 3, 4, "bread", "wheat", "raw_water", "clean_water", "bench", "workbench"]
const FARM_GROWTH_HOURS := 6.0
const EFFECT_RADIUS := 3
const FOUNTAIN_WATER := 10
const LIGHT_BONUS := 0.2
const CANTEEN_RECOVERY := 10.0
const CANTEEN_WALK_LIMIT := 12
const DRILL_HOURS := 2.0
const DRILL_RADIUS := 3
const BELT_KINDS := ["belt", "electric_belt"]
const LINE_KINDS := ["high_line", "low_line"]
const GENERATOR_KINDS := ["power_plant", "manual_generator"]
const OPERATED_KINDS := ["power_plant", "manual_generator", "transformer", "drill"]
const NEW_BUILDINGS := {
	"farm": {"name": "农田", "materials": {1: 4}, "hours": 4.0},
	"power_plant": {"name": "燃煤发电站", "materials": {4: 12, 2: 6}, "hours": 8.0},
	"high_line": {"name": "粗电线", "materials": {2: 2}, "hours": 0.5},
	"low_line": {"name": "普通电线", "materials": {2: 1}, "hours": 0.25},
	"transformer": {"name": "变压站", "materials": {1: 8, 2: 4}, "hours": 4.0},
	"grow_light": {"name": "培育灯", "materials": {1: 4, 2: 2}, "hours": 2.0},
	"fountain": {"name": "喷泉", "materials": {1: 6, 4: 2, 2: 2, "raw_water": 10}, "hours": 4.0},
	"electric_belt": {"name": "电力传送带", "materials": {1: 1}, "hours": 0.25},
	"drill": {"name": "矿钻", "materials": {4: 6, 2: 4}, "hours": 6.0},
	"manual_generator": {"name": "人力发电机", "materials": {1: 6, 2: 2}, "hours": 4.0},
	"spotlight": {"name": "聚光灯", "materials": {1: 4, 2: 2}, "hours": 2.0},
	"daylight": {"name": "日光灯", "materials": {1: 4, 2: 2}, "hours": 2.0},
	"canteen": {"name": "食堂", "materials": {1: 8, 4: 2}, "hours": 4.0},
}
const FREIGHT_CAPACITY := 4
const BUILDING_KINDS := ["bed", "bench", "workbench", "pump", "purifier", "printer", "bank", "belt", "farm", "power_plant", "high_line", "low_line", "transformer", "grow_light", "fountain", "electric_belt", "drill", "manual_generator", "spotlight", "daylight", "canteen"]
# 生产批次的产物、工时与售价；原料见 production_materials，建材见 building_materials。
const PRODUCTS := {
	"farm": {"name": "小麦", "unit": "份", "hours": 2.0, "amount": 8, "item": "wheat"},
	"bench": {"name": "矿枪", "unit": "把", "hours": GUN_WORK_HOURS, "price": GUN_PRICE, "uses": GUN_USES, "durability": "gun_uses"},
	"workbench": {"name": "背包", "unit": "个", "hours": BACKPACK_WORK_HOURS, "price": BACKPACK_PRICE, "uses": BACKPACK_USES, "durability": "backpack_uses"},
	"pump": {"name": "原水", "unit": "份", "hours": WATER_WORK_HOURS, "amount": WATER_BATCH},
	"purifier": {"name": "清水", "unit": "份", "hours": WATER_WORK_HOURS, "amount": WATER_BATCH, "price": WATER_PRICE},
	"printer": {"name": "工人", "unit": "名", "hours": PRINT_WORKER_HOURS},
}
const Portal = preload("res://scripts/portal.gd")
const DailyReport = preload("res://scripts/daily_report.gd")
const MapGenerator = preload("res://scripts/map_generator.gd")
const WorldNavigation = preload("res://scripts/world_navigation.gd")
const WorkerMood = preload("res://scripts/worker_mood.gd")
const WorkerStateTree = preload("res://scripts/simulation/worker_state_tree.gd")
const SmartObjects = preload("res://scripts/simulation/smart_objects.gd")
const WorkerTrace = preload("res://scripts/simulation/worker_trace.gd")
const Art = preload("res://scripts/view/art.gd")
const ACTIONS := ["挖掘", "工作", "搬运", "等待", "空闲", "通勤", "吃饭", "睡觉"]
const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const ORES := [
	{"name": "空地", "color": Color("#263337"), "time": 0.0},
	{"name": "砂岩", "color": Color("#797c68"), "time": 2.4},
	{"name": "铜矿", "color": Color("#9b7860"), "time": 3.8},
	{"name": "煤矿", "color": Color("#484e59"), "time": 3.0},
	{"name": "花岗岩", "color": Color("#777187"), "time": 4.2},
	{"name": "致密铜矿", "color": Color("#b27457"), "time": 15.0, "item": 2},
	{"name": "致密煤矿", "color": Color("#313a43"), "time": 15.0, "item": 3},
]

var world_seed := 0
var generator: RefCounted
var generated_chunks: Dictionary = {}
var view_origin := Vector2i.ZERO
var terrain: Dictionary = {}
var water_sources: Dictionary = {}
var explored: Dictionary = {}
var visible_tiles: Dictionary = {}
var jobs: Dictionary = {}
var mining_contracts: Dictionary = {}
var sites: Dictionary = {}
var beds: Dictionary = {}
var benches: Dictionary = {}
var banks: Dictionary = {}
var belts: Dictionary = {}
var power_lines: Dictionary = {}
var powered_devices: Dictionary = {}
var ready_drills: Dictionary = {}
var power_output: Dictionary = {}
var machine_noise: Dictionary = {}
var power_graph: Dictionary = {}
var power_nodes: Dictionary = {}
var power_signature := 0
var selected_line := false
var moving_drill_from = null
var belt_cargo: Dictionary = {}
var next_cargo_id := 0
var belt_drawing := false
var belt_path: Array[Vector2i] = []
var belt_pointer := Vector2.ZERO
var building_drawing := false
var building_start := Vector2i.ZERO
var building_end := Vector2i.ZERO
var building_axis := Vector2i.ZERO
var building_pick = null
# Available stock is not a location. Reserved freight remains at its source until pickup.
var stores: Dictionary = {}
var shipments: Array[Dictionary] = []
var player_bread: float:
	get:
		var total := total_stock("bread")
		for shipment in shipments:
			if is_same(shipment.item, "bread"):
				total += shipment.amount
		for w in workers:
			total += w.payroll
		return total
var materials: Dictionary:
	get:
		var result: Dictionary = {}
		for ore in range(1, ORES.size()):
			result[ore] = int(total_stock(ore))
		return result
var player_blocks: int:
	get:
		var total := 0
		for amount in materials.values():
			total += int(amount)
		return total
var workers: Array[Dictionary] = []
var smart_objects := SmartObjects.new()
var ai_trace := WorkerTrace.new()
var newborns: Array[Vector2i] = []
var navigation := WorldNavigation.new()
var camera := Camera2D.new()
var delivered := 0
var mined := 0
var day := 1
var day_elapsed := 0.0
var portal := Portal.new()
var wander_rng := RandomNumberGenerator.new()
var daily_records: Dictionary = {}
var daily_mined: Dictionary = {}
var resource_flows: Dictionary = {}
var inventory_history: Array[Dictionary] = []
var inventory_sample_time := 0.0
var report_window: Window
var speed := 1.0
var simulation_paused := false
var tool := "dig"
var dragging := false
var panning := false
var selection_start := Vector2i.ZERO
var selection_end := Vector2i.ZERO
var fog_timer := 0.0
var recovery_timer := 0.0
var animation_time := 0.0
var day_clock: Control
var pause_button: Button
var tool_buttons: Dictionary = {}
var build_tray: PanelContainer
var furniture_button: Button
var speed_buttons: Dictionary = {}
var reset_dialog: ConfirmationDialog
var font: Font
@onready var world_view: Node2D = $World
var selected_entity = null
var selected_tile = null
var selected_worker := -1
var worker_attributes: VBoxContainer
var worker_bars: Dictionary = {}
var entity_panel: PanelContainer
var entity_title: Label
var entity_details: Label
var bed_texture: Texture2D
var bed_blueprint_texture: Texture2D

func _ready() -> void:
	ai_trace.configure(OS.get_cmdline_user_args())
	smart_objects.tracing = ai_trace.enabled
	smart_objects.traced.connect(trace_smart_object)
	get_viewport().physics_object_picking = true
	get_viewport().physics_object_picking_sort = true
	get_viewport().physics_object_picking_first_only = true
	font = ThemeDB.fallback_font
	# Prefer a local CJK font, while retaining Godot's system fallback.
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["Noto Sans CJK SC", "Microsoft YaHei", "sans-serif"])
	font = system_font
	add_child(camera)
	camera.zoom = Vector2.ONE
	build_ui()
	reset_world()

func reset_world(new_seed: int = -1) -> void:
	world_view.initialized = false
	world_seed = randi() if new_seed == -1 else new_seed
	view_origin = Vector2i.ZERO
	generated_chunks.clear()
	navigation.clear()
	terrain.clear()
	water_sources.clear()
	explored.clear()
	visible_tiles.clear()
	jobs.clear()
	mining_contracts.clear()
	sites.clear()
	beds.clear()
	benches.clear()
	banks.clear()
	belts.clear()
	power_lines.clear()
	powered_devices.clear()
	ready_drills.clear()
	power_output.clear()
	machine_noise.clear()
	power_graph.clear()
	power_signature = 0
	selected_line = false
	moving_drill_from = null
	belt_cargo.clear()
	next_cargo_id = 0
	belt_drawing = false
	belt_path.clear()
	building_drawing = false
	building_axis = Vector2i.ZERO
	building_pick = null
	stores.clear()
	stores[BASE] = {"bread": STARTING_BREAD}
	shipments.clear()
	smart_objects.clear()
	newborns.clear()
	workers.clear()
	selected_entity = null
	selected_tile = null
	selected_worker = -1
	daily_records.clear()
	daily_mined.clear()
	resource_flows.clear()
	inventory_history.clear()
	inventory_sample_time = 0.0
	delivered = 0
	mined = 0
	day = 1
	day_elapsed = 0.0
	ai_trace.reset(self)
	portal = Portal.new()
	wander_rng.seed = 1020
	recovery_timer = 0.0
	fog_timer = 0.0
	dragging = false
	simulation_paused = false
	pause_button.text = "Ⅱ"
	set_tool("dig")
	build_tray.hide()
	furniture_button.button_pressed = false
	generate_terrain()
	for i in 3:
		create_worker(BASE + Vector2i(i - 1, 1))
	sample_inventory()
	camera.position = tile_center(BASE)
	update_fog()
	update_ui()
	if is_instance_valid(report_window):
		report_window.queue_free()
		report_window = null
	world_view.rebuild(self)

func generate_terrain() -> void:
	generator = MapGenerator.new(world_seed, Rect2i(BASE - Vector2i(4, 2), Vector2i(9, 5)))
	ensure_region(Rect2i(BASE - Vector2i(16, 12), Vector2i(48, 32)))

func ensure_region(area: Rect2i) -> void:
	var first := MapGenerator.chunk_at(area.position)
	var last := MapGenerator.chunk_at(area.end - Vector2i.ONE)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var index := Vector2i(x, y)
			if generated_chunks.has(index):
				continue
			var data: PackedByteArray = generator.generate_chunk(index)
			generated_chunks[index] = true
			for dy in MapGenerator.CHUNK_SIZE:
				for dx in MapGenerator.CHUNK_SIZE:
					var cell := index * MapGenerator.CHUNK_SIZE + Vector2i(dx, dy)
					# Existing edits and fixtures are never overwritten by lazy generation.
					if terrain.has(cell):
						continue
					var material := int(data[dy * MapGenerator.CHUNK_SIZE + dx])
					terrain[cell] = 0 if material == MapGenerator.WATER else material
					if material == MapGenerator.WATER:
						water_sources[cell] = true
					if material == 0:
						navigation.set_point_solid(cell, false)
			world_view.refresh_chunk(index)

func create_worker(p: Vector2i) -> Dictionary:
	var id := workers.size()
	var worker := {"id": id, "name": WORKER_NAMES[id] if id < WORKER_NAMES.size() else "矿工%d" % (id + 1),
		"color": WORKER_COLORS[id % WORKER_COLORS.size()], "pos": Vector2(p), "facing": 1.0,
		"activity": WorkerStateTree.new(), "carry": 0, "extra_cargo": [], "freight": {}, "ore_delivery": {},
		"bread": 0.0, "earned_today": 0.0, "eaten_today": 0.0, "hunger": STARTING_HUNGER, "meal_bread": 0.0,
		"bed_spent_today": 0.0, "shop_spent_today": 0.0, "fatigue": 0.0,
		"gun_uses": 0, "backpack_uses": 0, "water": 0, "water_effect": 0.0,
		"mood": WorkerMood.new(), "loan_principal": 0.0, "loan_interest": 0.0, "loan_day": 0, "loan_bank": null,
		"unloaded_this_trip": 0, "payroll": 0.0}
	workers.append(worker)
	ai_trace.record(self, worker, "simulation", "spawn")
	return worker

func trace_smart_object(worker_id: int, event: String, data: Dictionary) -> void:
	if worker_id >= 0 and worker_id < workers.size():
		ai_trace.record(self, workers[worker_id], "smart_objects", event, data)

func tile_center(p: Vector2) -> Vector2:
	return (p - Vector2(view_origin) + Vector2(0.5, 0.5)) * CELL

func tile_corner(p: Vector2i) -> Vector2:
	return Vector2(p - view_origin) * CELL

func world_cell(point: Vector2) -> Vector2i:
	return Vector2i((point / CELL).floor()) + view_origin

func rebase_view() -> void:
	if camera.position.length_squared() < pow(CELL * 256, 2):
		return
	var shift := MapGenerator.chunk_at(Vector2i((camera.position / CELL).floor())) * MapGenerator.CHUNK_SIZE
	view_origin += shift
	var offset := Vector2(shift) * CELL
	camera.position -= offset
	belt_pointer -= offset
	world_view.reposition()

func in_bounds(p) -> bool:
	return p != null and terrain.has(p)

func route(start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	if not in_bounds(start) or not in_bounds(target) or terrain[target] != 0 or water_sources.has(target):
		return []
	return navigation.get_id_path(start, target)

func has_debt(w: Dictionary) -> bool:
	return w.loan_principal + w.loan_interest > 0.000001

func receive_income(w: Dictionary, amount: float) -> void:
	# Repayment stays in the carried employer purse; the bank records interest only.
	var repayment := minf(amount * LOAN_REPAYMENT_RATE, w.loan_principal + w.loan_interest)
	var principal := minf(repayment, w.loan_principal)
	var interest := repayment - principal
	w.loan_principal = maxf(0.0, w.loan_principal - principal)
	w.loan_interest = maxf(0.0, w.loan_interest - interest)
	portal.repaid_principal += principal
	w.payroll += repayment
	if banks.has(w.loan_bank):
		banks[w.loan_bank].interest_received += interest
	w.bread += amount - repayment
	w.earned_today += amount

func cargo_count(w: Dictionary) -> int:
	return (1 if w.carry > 0 else 0) + w.extra_cargo.size()

func carry_capacity(w: Dictionary) -> int:
	return 2 if w.backpack_uses > 0 else 1

# A delivery names its receiver first; walking and tracks are interchangeable transport legs.
func delivery_route(start: Vector2i, target: Vector2i, use_belts := true) -> Dictionary:
	var result := {"stop": target, "path": route(start, target)}
	if use_belts:
		for p in belts:
			if belts[p].cargo >= 0 or belt_destination(p) != target:
				continue
			var path := route(start, p)
			if not path.is_empty() and (result.path.is_empty() or path.size() < result.path.size()):
				result = {"stop": p, "path": path}
	return result

func take_carried_ore(w: Dictionary) -> int:
	var ore: int = w.carry
	w.carry = w.extra_cargo.pop_front() if not w.extra_cargo.is_empty() else 0
	w.unloaded_this_trip += 1
	if w.carry == 0:
		if w.unloaded_this_trip >= 2:
			if w.backpack_uses == 1:
				record_resource_use("workbench", 1)
			w.backpack_uses = maxi(0, w.backpack_uses - 1)
		w.unloaded_this_trip = 0
	return ore

func delivery_building_at(cell: Vector2i):
	if cell == BASE:
		return BASE
	for collection in [sites, benches, banks, beds]:
		for origin in collection:
			if is_same(collection, sites):
				if collection[origin].get("cancelled", false) or building_kind(origin) in BELT_KINDS or building_kind(origin) in LINE_KINDS:
					continue
			if cell in building_cells(origin, building_kind(origin)):
				return origin
	return null

func belt_destination(p: Vector2i):
	var visited: Dictionary = {}
	while belts.has(p) and not visited.has(p):
		visited[p] = true
		var direction: Vector2i = belts[p].direction
		if direction == Vector2i.ZERO:
			break
		p += direction
		var receiver = delivery_building_at(p)
		if receiver != null:
			return receiver
		if not belts.has(p) or -direction not in belts[p].inputs:
			break
	return null

func can_edit_belt(p: Vector2i) -> bool:
	if not belts.has(p) or belts[p].cargo >= 0:
		return false
	for cargo in belt_cargo.values():
		if cargo.from == p and cargo.progress < 1.0:
			return false
	return true

func remove_belt(p: Vector2i) -> bool:
	if not can_edit_belt(p):
		return false
	return_materials(belts[p].materials, p)
	sites[p] = contract(BELT_BUILD_HOURS)
	var kind: String = belts[p].get("kind", "belt")
	sites[p].merge({"kind": kind, "materials": belts[p].materials, "cancelled": true, "direction": belts[p].direction, "inputs": belts[p].inputs})
	belts.erase(p)
	recover_cancelled_sites()
	return true

func belt_direction_at(p: Vector2i) -> Vector2i:
	return belt_data(p).get("direction", Vector2i.ZERO)

func belt_data(p: Vector2i, overrides: Dictionary = {}) -> Dictionary:
	if overrides.has(p):
		return overrides[p]
	if sites.has(p) and building_kind(p) in BELT_KINDS:
		return sites[p]
	return belts.get(p, {})

func belt_connections(p: Vector2i, overrides: Dictionary = {}) -> int:
	var data := belt_data(p, overrides)
	if data.is_empty():
		return 0
	var mask := 0
	for i in DIRS.size():
		var direction: Vector2i = DIRS[i]
		var neighbor := belt_data(p + direction, overrides)
		if data.direction == direction:
			mask |= 1 << i
		elif direction in data.inputs and not neighbor.is_empty() and neighbor.direction == -direction:
			mask |= 1 << i
	return mask

func belt_path_plan(path: Array[Vector2i]) -> Dictionary:
	var plan: Dictionary = {}
	for i in path.size():
		var p := path[i]
		if delivery_building_at(p) != null:
			continue
		var data := belt_data(p)
		var direction: Vector2i = data.get("direction", Vector2i.ZERO)
		var inputs: Array = data.get("inputs", []).duplicate()
		if i + 1 < path.size():
			direction = path[i + 1] - p
		elif i > 0 and direction == path[i - 1] - p:
			# Reversing a stroke ends the old opposite-facing edge, not a two-way loop.
			direction = Vector2i.ZERO
		if i > 0 and path[i - 1] - p not in inputs:
			inputs.append(path[i - 1] - p)
		inputs.erase(direction)
		plan[p] = {"direction": direction, "inputs": inputs}
	return plan

func belt_plan_valid(path: Array[Vector2i]) -> bool:
	if path.is_empty() or delivery_building_at(path[0]) != null:
		return false
	var plan := belt_path_plan(path)
	var line_kind := "electric_belt" if tool == "electric_belt" else "belt"
	var visited: Dictionary = {}
	for i in path.size():
		var p := path[i]
		if visited.has(p) or (i > 0 and p - path[i - 1] not in DIRS):
			return false
		visited[p] = true
		if delivery_building_at(p) != null:
			if i != path.size() - 1:
				return false
			continue
		if belts.has(p) or (sites.has(p) and building_kind(p) in BELT_KINDS):
			if belts.has(p) and plan[p].direction != belts[p].direction and not can_edit_belt(p):
				return false
			continue
		if not building_space_valid(p, line_kind):
			return false
	return true

func place_belt_path(path: Array[Vector2i]) -> bool:
	if not belt_plan_valid(path):
		return false
	var line_kind := "electric_belt" if tool == "electric_belt" else "belt"
	var placed: Array[Vector2i] = []
	for p in path:
		if delivery_building_at(p) == null and not belts.has(p) and not sites.has(p):
			if not place_building(p, line_kind):
				break
		placed.append(p)
	if placed.is_empty():
		return false
	var plan := belt_path_plan(placed)
	for p in plan:
		var data := belt_data(p)
		data.direction = plan[p].direction
		data.inputs = plan[p].inputs
	return true

func extend_belt_path(world_position: Vector2) -> void:
	# Traverse crossed cell boundaries, including fast mouse motions, instead of an X-first route.
	var start := belt_pointer / CELL + Vector2(view_origin)
	var end := world_position / CELL + Vector2(view_origin)
	var delta := end - start
	var cell := Vector2i(start.floor())
	var target := Vector2i(end.floor())
	var step := Vector2i(signf(delta.x), signf(delta.y))
	var stride := Vector2(INF if step.x == 0 else absf(1.0 / delta.x), INF if step.y == 0 else absf(1.0 / delta.y))
	var crossing := Vector2(INF, INF)
	if step.x != 0:
		crossing.x = (cell.x + (1 if step.x > 0 else 0) - start.x) / delta.x
	if step.y != 0:
		crossing.y = (cell.y + (1 if step.y > 0 else 0) - start.y) / delta.y
	while cell != target:
		if cell.y == target.y or (cell.x != target.x and crossing.x <= crossing.y):
			cell.x += step.x
			crossing.x += stride.x
		else:
			cell.y += step.y
			crossing.y += stride.y
		if belt_path.size() > 1 and cell == belt_path[-2]:
			belt_path.pop_back()
		else:
			belt_path.append(cell)
	belt_pointer = world_position

func finish_belt_drag(screen_position: Vector2) -> void:
	belt_drawing = false
	if get_viewport().gui_get_hovered_control() == null:
		var world_position := get_global_transform_with_canvas().affine_inverse() * screen_position
		extend_belt_path(world_position)
		if belt_path.size() == 1 and building_at(belt_path[0]):
			select_entity(belt_path[0])
		else:
			place_belt_path(belt_path.duplicate())
	belt_path.clear()

func complete_delivery(delivery: Dictionary, fee := 0.0) -> void:
	if not shipments.has(delivery):
		return
	add_stock(delivery.target, delivery.item, delivery.amount)
	if delivery.get("mined", false):
		delivered += int(delivery.amount)
		if delivery.target == BASE:
			portal.input_blocks[delivery.item] = portal.input_blocks.get(delivery.item, 0) + int(delivery.amount)
	add_stock(BASE, "bread", fee)
	portal.freight_bread += fee
	shipments.erase(delivery)
	recover_cancelled_sites()

func load_belt(w: Dictionary, delivery: Dictionary, p: Vector2i) -> bool:
	if not belts.has(p) or belts[p].cargo >= 0 or belt_destination(p) != delivery.target:
		return false
	var fee := 0.0
	if delivery.get("mined", false):
		fee = minf(w.bread, BELT_FEE)
		w.bread -= fee
		take_carried_ore(w)
		w.ore_delivery = {}
		delivery.carried_ore = false
	delivery.on_belt = true
	delivery.owner = -1
	belt_cargo[next_cargo_id] = {"delivery": delivery, "worker": w.id,
		"from": p, "to": p, "progress": 0.0, "fee": fee}
	belts[p].cargo = next_cargo_id
	next_cargo_id += 1
	return true

func simulate_belts(delta: float) -> void:
	for id in belt_cargo.keys():
		var cargo: Dictionary = belt_cargo[id]
		var carrier: Vector2i = cargo.to if belts.has(cargo.to) else cargo.from
		var electric: bool = belts.get(carrier, {}).get("kind", "belt") == "electric_belt"
		if electric and not powered_devices.has(carrier):
			continue
		if electric and cargo.from != cargo.to:
			var moving_seconds := minf(delta, maxf(0.0, 1.0 - cargo.progress) / (BELT_SPEED * 1.2))
			record_machine_noise(carrier, "electric_belt", moving_seconds / delta)
		cargo.progress += delta * BELT_SPEED * (1.2 if electric else 1.0)
		if delivery_building_at(cargo.to) == cargo.delivery.target and cargo.progress >= 1.0:
			complete_delivery(cargo.delivery, cargo.fee)
			belt_cargo.erase(id)
	# Resolve against a snapshot so dictionary order cannot move cargo several cells at once.
	var requests: Dictionary = {}
	for p in belts:
		var id: int = belts[p].cargo
		if id < 0 or belt_cargo[id].progress < 1.0:
			continue
		# Keep the intended receiver across edits; do not enter a broken or redirected branch.
		if belt_destination(p) != belt_cargo[id].delivery.target:
			belt_cargo[id].progress = 1.0
			continue
		var target: Vector2i = p + belts[p].direction
		var receiving: bool = delivery_building_at(target) == belt_cargo[id].delivery.target
		if belts[p].direction != Vector2i.ZERO and (receiving or (belts.has(target) and -belts[p].direction in belts[target].inputs and belts[target].cargo < 0)):
			if not requests.has(target):
				requests[target] = []
			requests[target].append(p)
		else:
			belt_cargo[id].progress = 1.0
	for target in requests:
		var sources: Array = requests[target]
		var chosen: Vector2i = sources[0]
		if belts.has(target):
			var last: int = belts[target].last_input
			for offset in range(1, 5):
				var index := (last + offset) % DIRS.size()
				var candidate: Vector2i = target + DIRS[index]
				if candidate in sources:
					chosen = candidate
					belts[target].last_input = index
					break
		for source in sources:
			if source != chosen:
				belt_cargo[belts[source].cargo].progress = 1.0
		var id: int = belts[chosen].cargo
		var cargo: Dictionary = belt_cargo[id]
		belts[chosen].cargo = -1
		if belts.has(target):
			belts[target].cargo = id
		cargo.from = chosen
		cargo.to = target
		cargo.progress = minf(cargo.progress - 1.0, delta * BELT_SPEED)

func contract(hours: float) -> Dictionary:
	return {"progress": 0.0, "seconds": hours * HOUR_SECONDS}

func advance_labor(segment: Dictionary, delta: float) -> float:
	var task: Dictionary = segment.task
	var work := minf(delta * segment.rate, maxf(0, segment.goal - task.progress))
	task.progress += work
	var seconds: float = work / segment.rate
	segment.labor += seconds
	return seconds

func settle_labor(w: Dictionary, segment: Dictionary, reason: String) -> void:
	if segment.is_empty():
		return
	var task: Dictionary = segment.task
	# Cumulative entitlement makes the final payment the exact unpaid task balance.
	var entitled: float = task.reward if task.progress >= task.seconds else task.reward * task.progress / task.seconds
	var wage := minf(w.payroll, maxf(0.0, entitled - task.paid))
	w.payroll = maxf(0.0, w.payroll - wage)
	task.paid += wage
	if wage > 0:
		receive_income(w, wage)
	w.mood.worked(segment.kind, segment.labor / HOUR_SECONDS)
	ai_trace.record(self, w, "labor", "settled", {"reason": reason, "paid": wage,
		"task_reward": task.reward, "task_paid": task.paid,
		"progress": task.progress, "total_work": task.seconds, "labor_seconds": segment.labor})
	segment.clear()

func mining_seconds(p: Vector2i) -> float:
	if terrain[p] >= 5:
		return DRILL_HOURS * HOUR_SECONDS
	return maxf(MIN_MINING_HOURS * HOUR_SECONDS, ORES[terrain[p]].time)

func building_at(p: Vector2i) -> bool:
	for origin in power_lines:
		if p in building_cells(origin, power_lines[origin].kind):
			return true
	for collection in [sites, beds, benches, banks, belts]:
		for origin in collection:
			if p in building_cells(origin, building_kind(origin)):
				return true
	return false

# 矿种在开采、运输和仓储中保持身份。建材指定矿种，只有生产配方用键 0 接受任意矿石。
func building_materials(kind: String) -> Dictionary:
	if NEW_BUILDINGS.has(kind):
		return NEW_BUILDINGS[kind].materials
	match kind:
		"bed": return {1: BED_BLOCKS}
		"bench": return {1: BENCH_BLOCKS - 2, 2: 2}
		"workbench": return {1: WORKBENCH_BLOCKS - 2, 4: 2}
	return {1: building_blocks(kind)}

# Planning commits quantities only; deliveries do not change physical totals.
func building_available_materials() -> Dictionary:
	var available := resource_inventory()
	for site in sites.values():
		if site.get("cancelled", false):
			continue
		for item in site.materials:
			available[item] = available.get(item, 0.0) - site.materials[item]
	return available

func can_plan_building(kind: String, available: Dictionary = {}) -> bool:
	if kind not in BUILDING_KINDS:
		return false
	if available.is_empty():
		available = building_available_materials()
	var recipe := building_materials(kind)
	for item in recipe:
		if available.get(item, 0.0) + 0.000001 < recipe[item]:
			return false
	return true

# 开工消耗接收建筑内的原料；配方为空表示只需劳动。农田的水用于整批播种与生长。
func production_materials(kind: String) -> Dictionary:
	match kind:
		"bench": return {2: 1}
		"purifier", "farm": return {"raw_water": 4}
		"printer": return {0: PRINT_WORKER_BLOCKS}
	return {}

func return_materials(payment: Dictionary, location := BASE) -> void:
	for item in payment:
		add_stock(location, item, payment[item])
		record_resource_output(item, payment[item])

func material_requirements_text(recipe: Dictionary, show_stock := false, colored := false) -> String:
	var lines: Array[String] = []
	var available := building_available_materials() if show_stock else {}
	for ore in recipe:
		var amount: int = recipe[ore]
		var stock := int(maxf(0.0, available.get(ore, 0.0)))
		var label: String = "方块" if is_same(ore, 0) else item_name(ore)
		var line := "%s  %d / %d" % [label, stock, amount] if show_stock else "%s × %d" % [label, amount]
		if colored:
			line = "[color=%s]%s[/color]" % ["#A9D9B5" if stock >= amount else "#ED9C89", line]
		lines.append(line)
	return "\n".join(lines)

func building_blocks(kind: String) -> int:
	if NEW_BUILDINGS.has(kind):
		var count := 0
		for item in NEW_BUILDINGS[kind].materials:
			if item is int:
				count += NEW_BUILDINGS[kind].materials[item]
		return count
	if kind == "belt":
		return BELT_BLOCKS
	if kind == "bank":
		return BANK_BLOCKS
	if kind == "printer":
		return PRINTER_BLOCKS
	if kind in ["pump", "purifier"]:
		return WATER_BUILD_BLOCKS
	if kind == "workbench":
		return WORKBENCH_BLOCKS
	return BENCH_BLOCKS if kind == "bench" else BED_BLOCKS

func building_hours(kind: String) -> float:
	if NEW_BUILDINGS.has(kind):
		return NEW_BUILDINGS[kind].hours
	if kind == "belt":
		return BELT_BUILD_HOURS
	if kind == "bank":
		return BANK_BUILD_HOURS
	if kind == "printer":
		return PRINTER_BUILD_HOURS
	if kind in ["pump", "purifier"]:
		return WATER_BUILD_HOURS
	if kind == "workbench":
		return WORKBENCH_BUILD_HOURS
	return BENCH_BUILD_HOURS if kind == "bench" else BED_BUILD_HOURS

func building_name(kind: String) -> String:
	if NEW_BUILDINGS.has(kind):
		return NEW_BUILDINGS[kind].name
	return {"bed": "床", "bench": "武器桌", "workbench": "工作桌", "pump": "抽水机", "purifier": "净水器", "printer": "打印仓", "bank": "银行", "belt": "矿道"}[kind]

func building_cells(p: Vector2i, kind: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [p]
	if kind == "high_line":
		var data: Dictionary = sites[p] if sites.get(p, {}).get("kind", "") == kind else power_lines.get(p, {})
		var axis: Vector2i = data.get("axis", building_axis)
		cells.append(p + (Vector2i.RIGHT if axis == Vector2i.DOWN else Vector2i.DOWN))
	elif kind not in BELT_KINDS and kind != "low_line":
		cells.append(p + Vector2i.RIGHT)
	return cells

func building_size(p: Vector2i, kind: String) -> Vector2:
	var extent := Vector2i.ONE
	for cell in building_cells(p, kind):
		extent = extent.max(cell - p + Vector2i.ONE)
	return Vector2(extent) * CELL

func near_water_source(p: Vector2i) -> bool:
	for cell in [p, p + Vector2i.RIGHT]:
		for direction in DIRS:
			if water_sources.has(cell + direction):
				return true
	return false

func building_kind(p) -> String:
	if sites.has(p):
		return sites[p].kind
	if banks.has(p):
		return "bank"
	if belts.has(p):
		return belts[p].get("kind", "belt")
	if benches.has(p):
		return benches[p].kind
	if beds.has(p):
		return "bed"
	return power_lines.get(p, {}).get("kind", "")

func building_kind_at(p: Vector2i) -> String:
	for collection in [sites, beds, benches, banks, belts]:
		for origin in collection:
			if p in building_cells(origin, building_kind(origin)):
				return building_kind(origin)
	for origin in power_lines:
		if p in building_cells(origin, power_lines[origin].kind):
			return power_lines[origin].kind
	return ""

func building_space_valid(p: Vector2i, kind: String) -> bool:
	if kind not in BUILDING_KINDS:
		return false
	if kind == "pump" and not near_water_source(p):
		return false
	for cell in building_cells(p, kind):
		if not in_bounds(cell) or not explored.has(cell) or water_sources.has(cell) or cell == BASE or terrain[cell] >= 5:
			return false
		for collection in [sites, beds, benches, banks, belts, power_lines]:
			for origin in collection:
				var other: String = collection[origin].kind if is_same(collection, power_lines) else (collection[origin].get("kind", "belt") if is_same(collection, belts) else building_kind(origin))
				if cell not in building_cells(origin, other):
					continue
				# Completed cables and tracks can cross, but two blueprints cannot share a store.
				if not is_same(collection, sites) and ((kind in BELT_KINDS and other in LINE_KINDS) or (kind in LINE_KINDS and other in BELT_KINDS)):
					continue
				if kind in LINE_KINDS and kind == other and origin != p:
					continue
				return false
	return true

func site_cleared(p: Vector2i) -> bool:
	for cell in building_cells(p, building_kind(p)):
		if terrain[cell] != 0:
			return false
	return true

# 蓝图按数量占用可规划建材，不扣实物或绑定货源；实物到齐、占地清空后才施工。
func place_building(p: Vector2i, kind: String) -> bool:
	if not building_space_valid(p, kind) or not can_plan_building(kind):
		return false
	sites[p] = contract(building_hours(kind))
	sites[p].kind = kind
	sites[p].materials = building_materials(kind).duplicate()
	if kind in BELT_KINDS:
		sites[p].direction = Vector2i.ZERO
		sites[p].inputs = []
	if kind in LINE_KINDS:
		sites[p].axis = Vector2i.DOWN if building_axis == Vector2i.DOWN else Vector2i.RIGHT
	for cell in building_cells(p, kind):
		if add_mining_order(cell):
			mining_contracts[cell].site = p
	world_view.sync_orders()
	update_ui()
	return true

func update_building_drag(cell: Vector2i) -> void:
	building_end = cell
	var delta := cell - building_start
	if building_axis == Vector2i.ZERO and delta != Vector2i.ZERO:
		building_axis = Vector2i.RIGHT if absi(delta.x) >= absi(delta.y) else Vector2i.DOWN

func building_row() -> Array[Vector2i]:
	var result: Array[Vector2i] = [building_start]
	if building_axis == Vector2i.ZERO:
		return result
	var footprint := building_cells(Vector2i.ZERO, tool)
	var span: Vector2i = footprint.back() + Vector2i.ONE
	var delta := building_end - building_start
	var distance := delta.x if building_axis.x else delta.y
	var stride: int = span.x if building_axis.x else span.y
	for i in range(1, absi(distance) / stride + 1):
		result.append(building_start + building_axis * signi(distance) * stride * i)
	return result

func building_batch_valid(positions: Array[Vector2i], kind: String) -> bool:
	if positions.is_empty():
		return false
	var occupied: Dictionary = {}
	for p in positions:
		if existing_line(p, kind):
			continue
		if not building_space_valid(p, kind):
			return false
		for cell in building_cells(p, kind):
			if occupied.has(cell):
				return false
			occupied[cell] = true
	return true

func place_building_batch(positions: Array[Vector2i], kind: String) -> bool:
	if not building_batch_valid(positions, kind):
		return false
	var placed := false
	for p in positions:
		if not existing_line(p, kind) and not place_building(p, kind):
			break
		placed = true
	return placed

func existing_line(p: Vector2i, kind: String) -> bool:
	return kind in LINE_KINDS and (power_lines.get(p, {}).get("kind", "") == kind or sites.get(p, {}).get("kind", "") == kind)

func finish_building_drag(screen_position: Vector2) -> void:
	building_drawing = false
	if get_viewport().gui_get_hovered_control() == null:
		var world_position := get_global_transform_with_canvas().affine_inverse() * screen_position
		update_building_drag(world_cell(world_position))
		if building_start == building_end and building_pick != null and existing_line(building_pick, tool):
			selected_entity = building_pick
			selected_line = true
			update_entity_panel()
		else:
			place_building_batch(building_row(), tool)
	building_axis = Vector2i.ZERO
	building_pick = null

func cancel_placement() -> void:
	belt_drawing = false
	belt_path.clear()
	building_drawing = false
	building_axis = Vector2i.ZERO
	building_pick = null
	moving_drill_from = null
	if tool == "move_drill":
		tool = "dig"

func begin_drill_move(p: Vector2i) -> void:
	if building_kind(p) == "drill" and benches.has(p):
		set_tool("move_drill")
		moving_drill_from = p

func move_drill_to(target: Vector2i) -> bool:
	var origin = moving_drill_from
	if not benches.has(origin) or not building_space_valid(target, "drill"):
		return false
	for cell in building_cells(target, "drill"):
		if terrain[cell] != 0:
			return false
	if route(origin, target).is_empty():
		return false
	# Keep the warehouse at its old location until existing freight is delivered.
	for shipment in shipments:
		if shipment.source == origin or shipment.target == origin:
			return false
	var owner := slot_owner("work", origin)
	if owner >= 0:
		workers[owner].activity.exit(self, workers[owner], "moved")
	smart_objects.invalidate(SmartObjects.key("work", origin))
	benches[target] = benches[origin]
	benches.erase(origin)
	if stores.has(origin):
		for item in stores[origin]:
			add_stock(target, item, stores[origin][item])
		stores.erase(origin)
	powered_devices.erase(origin)
	ready_drills.erase(origin)
	set_tool("dig")
	select_entity(target)
	world_view.sync_dynamic()
	return true

func remove_power_line(p: Vector2i) -> bool:
	if not power_lines.has(p):
		return false
	return_materials(power_lines[p].materials)
	power_lines.erase(p)
	powered_devices.clear()
	ready_drills.clear()
	update_ui()
	return true

# 取消时原地解锁未取走的货物，携带中的货物返回来源，已到工地的材料搬回传送门。
func cancel_site(p: Vector2i) -> bool:
	var origin = null
	for candidate in sites:
		if p in building_cells(candidate, building_kind(candidate)):
			origin = candidate
			break
	if origin == null:
		return false
	var task: Dictionary = sites[origin]
	if task.get("cancelled", false):
		return false
	var owner := slot_owner("build", origin)
	if owner >= 0:
		workers[owner].activity.exit(self, workers[owner], "cancelled")
	smart_objects.invalidate(SmartObjects.key("build", origin))
	task.cancelled = true
	for cell in building_cells(origin, task.kind):
		if mining_contracts.get(cell, {}).get("site", null) == origin:
			cancel_mining_order(cell)
	world_view.sync_orders()
	for shipment in shipments.duplicate():
		if shipment.target != origin:
			continue
		if shipment.picked:
			shipment.target = shipment.source
			# Carriers and belts replan against the shipment's current receiver.
		else:
			if shipment.owner >= 0:
				var carrier: Dictionary = workers[shipment.owner]
				carrier.activity.exit(self, carrier, "cancelled")
				carrier.freight = {}
			release_shipment(shipment)
	recover_cancelled_sites()
	update_ui()
	return true

func uses_daily_output(kind: String) -> bool:
	return kind in ["bench", "workbench", "pump", "purifier", "farm"]

func production_station(kind: String) -> Dictionary:
	return {"kind": kind, "queue": 0, "daily_output": 0, "produced_today": 0, "stock": 0, "task": {}, "growth": 0.0, "harvest": false, "water_day": 0}

# 日产量跨天保留，完成量按完成当天计入；缺产不累积，销售库存不增加配额。
# 已开工或正在生长的批次完成后才检查新配额；打印仓使用有限待制数量。
func has_production_order(p: Vector2i) -> bool:
	var bench: Dictionary = benches[p]
	if not bench.task.is_empty() or bench.growth > 0:
		return true
	var kind := building_kind(p)
	if not uses_daily_output(kind):
		return bench.queue > 0
	var amount: int = PRODUCTS[kind].get("amount", 1)
	return bench.produced_today + amount <= bench.daily_output

func adjust_production(p: Vector2i, change: int) -> void:
	if not benches.has(p):
		return
	var bench: Dictionary = benches[p]
	var kind := building_kind(p)
	if uses_daily_output(kind):
		var amount: int = PRODUCTS[kind].get("amount", 1)
		bench.daily_output = maxi(0, bench.daily_output + change * amount)
	else:
		bench.queue = maxi(0 if bench.task.is_empty() else 1, bench.queue + change)

func product_item(kind: String):
	return PRODUCTS.get(kind, {}).get("item", {"pump": "raw_water", "purifier": "clean_water"}.get(kind, kind))

func sale_price(p: Vector2i) -> float:
	return PRODUCTS[building_kind(p)].price * (1.0 + LIGHT_BONUS if has_powered_effect(Vector2(p), "spotlight") else 1.0)

func station_wage(p) -> float:
	return WAGE_PER_HOUR * (1.0 + LIGHT_BONUS if p != null and benches.has(p) and has_powered_effect(Vector2(p), "daylight") else 1.0)

func simulate(delta: float) -> void:
	# Split at midnight so deliveries are credited to the correct day.
	var remaining := delta
	while remaining > 0.0000001:
		var step := minf(0.05, minf(remaining, DAY_SECONDS - day_elapsed))
		recovery_timer += step
		if recovery_timer >= 0.2:
			recover_cancelled_sites()
			recovery_timer = 0.0
		smart_objects.sync(self)
		machine_noise.clear()
		simulate_power(step)
		simulate_growth(step)
		simulate_belts(step)
		simulate_workers(step)
		day_elapsed += step
		remaining -= step
		if (day - 1) * DAY_SECONDS + day_elapsed >= inventory_sample_time + HOUR_SECONDS - 0.000001:
			sample_inventory()
		if day_elapsed >= DAY_SECONDS - 0.0000001:
			day_elapsed = 0.0
			day += 1
			resource_flows.erase(day - 2)
			for p in benches:
				if uses_daily_output(building_kind(p)):
					benches[p].produced_today = 0
			for w in workers:
				w.earned_today = 0
				w.eaten_today = 0
				w.bed_spent_today = 0.0
				w.shop_spent_today = 0.0

func simulate_workers(delta: float) -> void:
	var experiences: Array[Dictionary] = []
	for w in workers:
		w.mood.advance(delta / HOUR_SECONDS)
		w.hunger = maxf(0.0, w.hunger - HUNGER_DECAY_PER_DAY * delta / DAY_SECONDS)
		var experience: Dictionary = w.activity.tick(self, w, delta)
		w.water_effect = maxf(0, w.water_effect - delta)
		if not experience.is_empty():
			experience.worker = w
			experience.pos = w.pos
			experiences.append(experience)
		if has_powered_effect(w.pos, "fountain"):
			w.fatigue = maxf(0, w.fatigue - 5.0 * delta / HOUR_SECONDS)
		ai_trace.observe(self, w)
	for experience in experiences:
		var noise := machine_noise_at(experience.pos)
		if experience.has("hours"):
			experience.worker.mood.slept(experience.hours, experience.bed_hours, noise)
		else:
			experience.worker.mood.ate_meal(experience.meal_fraction, experience.comfortable, noise)
	for p in newborns:
		create_worker(p)
	if not newborns.is_empty():
		update_fog()
	newborns.clear()
	fog_timer += delta
	if fog_timer >= 0.15:
		fog_timer = 0.0
		update_fog()

func assign_bed(p: Vector2i, worker_id: int) -> void:
	if not beds.has(p) or worker_id < -1 or worker_id >= workers.size():
		return
	for other in beds:
		if worker_id >= 0 and beds[other].assigned == worker_id:
			beds[other].assigned = -1
	beds[p].assigned = worker_id

func action_for(w: Dictionary) -> String:
	return w.activity.report_action(self)

func worker_display(w: Dictionary) -> Dictionary:
	var display := w.duplicate()
	display.merge(w.activity.presentation(self), true)
	return display

func slot_owner(kind: String, p: Vector2i) -> int:
	return smart_objects.owner(SmartObjects.key(kind, p))

func record_worker_time(w: Dictionary, action: String, delta: float) -> void:
	if not daily_records.has(day):
		daily_records[day] = {}
	if not daily_records[day].has(w.id):
		daily_records[day][w.id] = empty_totals()
	daily_records[day][w.id][action] += maxf(0, delta)

func empty_totals() -> Dictionary:
	var result := {}
	for action in ACTIONS:
		result[action] = 0.0
	return result

func report_totals(report_day: int, worker_id := -1) -> Dictionary:
	var result := empty_totals()
	for id in daily_records.get(report_day, {}):
		if worker_id >= 0 and id != worker_id:
			continue
		for action in ACTIONS:
			result[action] += daily_records[report_day][id][action]
	return result

func report_mined(report_day: int, worker_id := -1) -> int:
	var counts: Dictionary = daily_mined.get(report_day, {})
	if worker_id >= 0:
		return counts.get(worker_id, 0)
	var total := 0
	for count in counts.values():
		total += count
	return total

func open_report() -> void:
	if not is_instance_valid(report_window):
		report_window = DailyReport.new()
		report_window.game = self
		add_child(report_window)
	report_window.refresh()
	report_window.popup_centered()

func _process(delta: float) -> void:
	var movement := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if not reset_dialog.visible:
		camera.position += movement.normalized() * delta * 550.0 / camera.zoom.x
	rebase_view()
	if not simulation_paused and not reset_dialog.visible:
		animation_time += delta * speed
		simulate(minf(delta, 0.1) * speed)
	update_ui()
	world_view.sync_dynamic()

# Workers reveal a circular radius through terrain; exploration persists.
func update_fog() -> void:
	var changed := visible_tiles.duplicate()
	visible_tiles.clear()
	for w in workers:
		var origin := Vector2i(w.pos.round())
		ensure_region(Rect2i(origin - Vector2i.ONE * (VISION_RADIUS + 1), Vector2i.ONE * (VISION_RADIUS * 2 + 3)))
		for y in range(-VISION_RADIUS, VISION_RADIUS + 1):
			for x in range(-VISION_RADIUS, VISION_RADIUS + 1):
				var target := origin + Vector2i(x, y)
				if not in_bounds(target) or x * x + y * y > VISION_RADIUS * VISION_RADIUS:
					continue
				visible_tiles[target] = true
				explored[target] = true
	changed.merge(visible_tiles, true)
	world_view.sync_fog(changed)

func add_mining_order(p: Vector2i) -> bool:
	if not explored.has(p) or terrain.get(p, 0) == 0 or jobs.has(p):
		return false
	mining_contracts[p] = contract(mining_seconds(p) / HOUR_SECONDS)
	jobs[p] = true
	return true

func cancel_mining_order(p: Vector2i) -> void:
	var owner := slot_owner("mine", p)
	if owner >= 0:
		workers[owner].activity.exit(self, workers[owner], "cancelled")
	smart_objects.invalidate(SmartObjects.key("mine", p))
	jobs.erase(p)
	mining_contracts.erase(p)

func designate(a: Vector2i, b: Vector2i, cancel := false) -> int:
	var count := 0
	var area := Rect2i(a.min(b), (a - b).abs() + Vector2i.ONE)
	# Iterate known cells rather than an arbitrarily large rectangle across the world.
	for p in explored:
		if not area.has_point(p):
			continue
		if cancel and cancel_site(p):
			count += 1
		elif cancel and remove_belt(p):
			count += 1
		if cancel and jobs.has(p):
			cancel_mining_order(p)
			count += 1
		elif not cancel:
			if add_mining_order(p):
				count += 1
			if mining_contracts.has(p):
				mining_contracts[p].erase("site")
	world_view.sync_orders()
	return count

func mouse_tile() -> Vector2i:
	return world_cell(get_global_mouse_position())

func select_entity(p: Vector2i) -> bool:
	selected_line = false
	selected_worker = -1
	selected_tile = null
	selected_entity = null
	if p == BASE:
		selected_entity = BASE
	else:
		for collection in [beds, sites, benches, banks, belts]:
			for origin in collection:
				if p in building_cells(origin, building_kind(origin)):
					selected_entity = origin
					selected_line = building_kind(origin) in LINE_KINDS
					break
		if selected_entity == null:
			for origin in power_lines:
				if p in building_cells(origin, power_lines[origin].kind):
					selected_entity = origin
					selected_line = true
					break
	update_entity_panel()
	return selected_entity != null

func clear_entity_selection() -> void:
	selected_line = false
	selected_worker = -1
	selected_entity = null
	selected_tile = null
	update_entity_panel()

func select_tile(p: Vector2i) -> void:
	clear_entity_selection()
	if in_bounds(p) and explored.has(p):
		selected_tile = p
		update_entity_panel()

func tile_details(p: Vector2i) -> Dictionary:
	if not in_bounds(p) or not explored.has(p):
		return {}
	if water_sources.has(p):
		return {"title": "水源", "text": "不可通行\n可供抽水与灌溉"}
	var ore: int = terrain[p]
	if ore >= 5:
		return {"title": ORES[ore].name, "text": "%s\n矿钻开采  %.0fh / 块\n产物  %s × 1\n矿脉可反复开采" % ["已标记开采" if jobs.has(p) else "需要矿钻", DRILL_HOURS, item_name(ORES[ore].item)]}
	if ore == 0:
		return {"title": "空地", "text": "可通行"}
	var status := "未标记挖掘"
	if mining_contracts.has(p):
		var task: Dictionary = mining_contracts[p]
		var worker_id := slot_owner("mine", p)
		status = "挖掘中" if worker_id >= 0 and action_for(workers[worker_id]) == "挖掘" else "等待挖掘"
		if task.progress > 0:
			status += "  %.0f%%" % (task.progress / task.seconds * 100)
	return {"title": ORES[ore].name,
		"text": "%s\n开采工时  %.1fh\n产物  %s × 1" % [status, mining_seconds(p) / HOUR_SECONDS, ORES[ore].name]}

func select_worker(worker_id: int) -> bool:
	if worker_id < 0 or worker_id >= workers.size():
		return false
	selected_worker = worker_id
	selected_entity = null
	selected_tile = null
	update_entity_panel()
	return true

func update_entity_panel() -> void:
	$UI.update_entity_panel()

func bed_effects_text() -> String:
	return "使用费  %s 面包 / %.0fh\n疲劳恢复  −%s / h" % [
		String.num(BED_PRICE, 1), BED_LEASE_HOURS, String.num(BED_RECOVERY_PER_HOUR, 1)]

func product_recipe_text(kind: String, p = null) -> String:
	var product: Dictionary = PRODUCTS[kind]
	var recipe := "%s  %d %s / %.0fh\n工资  %s 面包" % [product.name, product.get("amount", 1), product.unit, product.hours, String.num(product.hours * station_wage(p), 1)]
	if kind == "printer":
		recipe += "\n原料  %d 矿石方块" % PRINT_WORKER_BLOCKS
	elif not production_materials(kind).is_empty():
		recipe += "\n原料  " + material_requirements_text(production_materials(kind))
	if kind == "farm":
		recipe += "\n浇水 1h · 生长 6h · 收割 1h"
	return recipe

func building_effects_text(kind: String, p = null) -> String:
	match kind:
		"power_plant": return "一人操作 · 最高 3200W\n满负荷耗煤 2 / h\n按实际输出耗煤"
		"manual_generator": return "一人操作 · 最高 400W\n无需燃料"
		"high_line": return "输电容量 3200W\n可横穿传送带"
		"low_line": return "输电容量 800W"
		"transformer": return "一人值班 · 最高 800W\n左侧输入 · 右侧输出"
		"grow_light": return "耗电 200W\n三格内农田生长速度 ×2\n多灯不叠加"
		"spotlight": return "耗电 200W\n%d 格内商品售价 +%.0f%%\n多灯不叠加" % [EFFECT_RADIUS, LIGHT_BONUS * 100]
		"daylight": return "耗电 200W\n%d 格内建筑工资 +%.0f%%\n多灯不叠加" % [EFFECT_RADIUS, LIGHT_BONUS * 100]
		"canteen": return "座位 2\n每餐疲劳恢复 %.0f" % CANTEEN_RECOVERY
		"fountain": return "耗电 200W · 每日原水 ×10\n三格内疲劳恢复 5 / h\n多喷泉不叠加"
		"electric_belt": return "每件货物耗电 25W\n速度 +20% · 断电暂停"
		"drill": return "一人操作 · 耗电 400W\n三格内致密矿 1 块 / 2h\n可移动 · 需重新接电"
	if kind == "belt":
		return "采矿运费  %.1f 面包 / 块\n单格容量  1 批" % BELT_FEE
	if kind == "bank":
		return "借款上限  %.0f 面包\n一次性利息  %.0f%%\n收入还款  %.0f%%\n每日最多一笔 · 还清后再借" % [LOAN_LIMIT, LOAN_INTEREST_RATE * 100, LOAN_REPAYMENT_RATE * 100]
	var effects := product_recipe_text(kind, p) if PRODUCTS.has(kind) else bed_effects_text()
	if kind == "pump":
		effects += "\n建于水源旁"
	return effects

func product_effects_text(kind: String, p = null) -> String:
	if kind == "farm":
		return ""
	if kind == "printer":
		return "完成后加入矿区"
	if kind == "pump":
		return "原水用于净化与灌溉"
	if kind == "purifier":
		return "售价  %s 面包 / 份\n饮用  %.1fh · 持续 %.0fh\n劳动疲劳增长  −%.0f%%" % [String.num(sale_price(p) if p != null else WATER_PRICE, 1), DRINK_HOURS, WATER_EFFECT_HOURS, WATER_FATIGUE_REDUCTION * 100]
	if kind == "workbench":
		return "售价  %s 面包\n使用次数  %d 次（每次交付两块）\n携带方块  +1" % [String.num(sale_price(p) if p != null else BACKPACK_PRICE, 1), BACKPACK_USES]
	return "售价  %s 面包\n耐久  %d 格\n挖掘速度  +%.0f%%" % [String.num(sale_price(p) if p != null else GUN_PRICE, 1), GUN_USES, (GUN_MINING_RATE - 1.0) * 100.0]

func icon_texture(path: String) -> Texture2D:
	return Art.texture(path)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: toggle_pause()
			KEY_G: set_tool("dig")
			KEY_X: set_tool("cancel")
			KEY_HOME: camera.position = tile_center(BASE)
			KEY_ESCAPE:
				dragging = false
				cancel_placement()
				clear_entity_selection()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera.zoom = Vector2.ONE * minf(2.2, camera.zoom.x * 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera.zoom = Vector2.ONE * maxf(0.45, camera.zoom.x / 1.12)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if tool in BUILDING_KINDS:
				if belt_drawing or building_drawing:
					cancel_placement()
				else:
					set_tool("dig")
			else:
				set_tool("cancel")
	if event is InputEventMouseMotion:
		if panning:
			camera.position -= event.relative / camera.zoom
		if dragging:
			selection_end = mouse_tile()
		if belt_drawing and get_viewport().gui_get_hovered_control() == null:
			var world_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			extend_belt_path(world_position)
		if building_drawing and get_viewport().gui_get_hovered_control() == null:
			var world_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			update_building_drag(world_cell(world_position))

func finish_ground_drag(screen_position: Vector2) -> void:
	dragging = false
	if get_viewport().gui_get_hovered_control() != null:
		return
	var world_position := get_global_transform_with_canvas().affine_inverse() * screen_position
	selection_end = world_cell(world_position)
	designate(selection_start, selection_end, tool == "cancel")
	if selection_start == selection_end:
		select_tile(selection_end)

func handle_world_input(event: InputEvent, worker_id: int, entity, line := false) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		if belt_drawing:
			finish_belt_drag(event.position)
		if building_drawing:
			finish_building_drag(event.position)
		if dragging:
			finish_ground_drag(event.position)
		return
	if line and tool == "cancel" and power_lines.has(entity):
		remove_power_line(entity)
		get_viewport().set_input_as_handled()
		return
	var belt_entity := entity != null and building_kind(entity) in BELT_KINDS
	var crossing := (line and (tool in BELT_KINDS or tool in LINE_KINDS)) or (belt_entity and tool in LINE_KINDS)
	if tool != "move_drill" and not crossing and (worker_id >= 0 or (entity != null and not (tool == "cancel" and (sites.has(entity) or belts.has(entity))) and not (tool in BELT_KINDS and belt_entity))):
		selected_worker = worker_id
		selected_entity = entity
		selected_line = line
		selected_tile = null
		update_entity_panel()
		dragging = false
	else:
		var world_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var cell := world_cell(world_position)
		clear_entity_selection()
		if tool == "move_drill":
			move_drill_to(cell)
		elif tool in BELT_KINDS:
			belt_drawing = true
			belt_path = [cell]
			belt_pointer = world_position
		elif tool in BUILDING_KINDS:
			building_drawing = true
			building_pick = entity if line else null
			building_start = cell
			building_end = cell
			building_axis = Vector2i.ZERO
		else:
			dragging = true
			selection_start = cell
			selection_end = cell
	get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and (belt_drawing or building_drawing):
		cancel_placement()
		get_viewport().set_input_as_handled()
	# Release even over a HUD panel, so pointer capture cannot leave a stuck drag.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and belt_drawing:
			finish_belt_drag(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT and building_drawing:
			finish_building_drag(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT and dragging:
			finish_ground_drag(event.position)
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = false
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_SPACE:
		if event.echo:
			return
		if not reset_dialog.visible:
			toggle_pause()
			get_viewport().set_input_as_handled()

func make_label(text_: String, size := 14) -> Label:
	return $UI.make_label(text_, size)

func make_button(text_: String, tooltip: String, action: Callable) -> Button:
	return $UI.make_button(text_, tooltip, action)

func build_ui() -> void:
	$UI.build_ui(self)

func set_tool(value: String) -> void:
	if value in BUILDING_KINDS and not can_plan_building(value):
		return
	if value != tool:
		cancel_placement()
	tool = value
	if value in BUILDING_KINDS and is_instance_valid(build_tray):
		build_tray.show()
		furniture_button.button_pressed = true
	for name_ in tool_buttons:
		tool_buttons[name_].button_pressed = name_ == value

func toggle_build_tray() -> void:
	build_tray.visible = furniture_button.button_pressed
	if not build_tray.visible and tool in BUILDING_KINDS:
		set_tool("dig")

func set_speed(value: int) -> void:
	speed = float(value)
	for n in speed_buttons:
		speed_buttons[n].button_pressed = n == value

func toggle_pause() -> void:
	simulation_paused = not simulation_paused
	pause_button.text = "▶" if simulation_paused else "Ⅱ"

func update_ui() -> void:
	$UI.update_ui()

# 每座建筑及传送门有无限容量的仓储，产物留在生产地点；stock 是生产建筑的产物格。
# 预留货物在取货前仍位于来源建筑，取走后由工人携带，送达后才进入目标仓储。
func stock_at(p: Vector2i, item) -> float:
	if benches.has(p) and is_same(product_item(building_kind(p)), item):
		return benches[p].stock
	return stores.get(p, {}).get(item, 0.0)

func add_stock(p: Vector2i, item, amount: float) -> void:
	if benches.has(p) and is_same(product_item(building_kind(p)), item):
		benches[p].stock = maxf(0.0, benches[p].stock + amount)
	else:
		if not stores.has(p):
			stores[p] = {}
		stores[p][item] = maxf(0.0, stock_at(p, item) + amount)

func stock_locations() -> Array:
	var locations: Array = [BASE]
	for collection in [stores, benches, beds, banks]:
		for p in collection:
			if p not in locations and not sites.has(p):
				locations.append(p)
	return locations

func total_stock(item) -> float:
	var total := 0.0
	for p in stock_locations():
		total += available_at(p, item)
	return total

func available_at(p: Vector2i, item) -> float:
	if benches.has(p):
		if benches[p].kind == "power_plant" and is_same(item, 3):
			return maxf(0.0, stock_at(p, item) - 2.0)
		if benches[p].kind == "fountain" and is_same(item, "raw_water"):
			return maxf(0.0, stock_at(p, item) - FOUNTAIN_WATER)
	if benches.has(p) and has_production_order(p):
		var recipe := production_materials(building_kind(p))
		if recipe.has(item) or (item is int and recipe.has(0)):
			return 0.0
	return stock_at(p, item)

func item_name(item) -> String:
	if item is int:
		return ORES[item].name
	return {"bread": "面包", "wheat": "小麦", "raw_water": "原水",
		"clean_water": "清水", "bench": "矿枪", "workbench": "背包"}.get(item, str(item))

func storage_text(p: Vector2i) -> String:
	var contents: Dictionary = stores.get(p, {}).duplicate()
	if benches.has(p) and PRODUCTS.has(building_kind(p)) and building_kind(p) != "printer":
		var item = product_item(building_kind(p))
		contents[item] = stock_at(p, item)
	for shipment in shipments:
		if not shipment.picked and shipment.source == p:
			contents[shipment.item] = contents.get(shipment.item, 0.0) + shipment.amount
	var lines: Array[String] = []
	for item in contents:
		if contents[item] > 0.000001:
			lines.append("%s  %s" % [item_name(item), String.num(contents[item], 1)])
	return "\n".join(lines) if not lines.is_empty() else "空"

func incoming(p: Vector2i, item) -> float:
	var amount := 0.0
	for shipment in shipments:
		if shipment.target == p and is_same(shipment.item, item):
			amount += shipment.amount
	return amount

func reserve_shipment(source: Vector2i, target: Vector2i, item, amount: float) -> void:
	add_stock(source, item, -amount)
	shipments.append({"source": source, "target": target, "item": item,
		"amount": amount, "owner": -1, "picked": false})

func release_shipment(shipment: Dictionary) -> void:
	if shipments.has(shipment) and not shipment.picked:
		add_stock(shipment.source, shipment.item, shipment.amount)
		shipments.erase(shipment)

# Shared supply endpoints publish demand; only entering a delivery commits physical goods.
func delivery_requirements(p: Vector2i) -> Dictionary:
	if sites.has(p):
		return {} if sites[p].get("cancelled", false) else sites[p].materials
	if banks.has(p):
		return {"bread": LOAN_LIMIT}
	if not benches.has(p):
		return {}
	var b: Dictionary = benches[p]
	if PRODUCTS.has(b.kind) and has_production_order(p) and b.task.is_empty() and b.growth <= 0:
		return production_materials(b.kind)
	if b.kind == "power_plant":
		var fuel := stock_at(p, 3) + incoming(p, 3)
		return {3: fuel + 2.0} if fuel <= 1.0 else {}
	if b.kind == "fountain" and b.water_day != day:
		return {"raw_water": FOUNTAIN_WATER}
	return {}

func delivery_need(p: Vector2i, item) -> float:
	var recipe := delivery_requirements(p)
	var amount := float(recipe.get(item, 0))
	if item is int and recipe.has(0):
		amount = recipe[0]
		for ore in range(1, ORES.size()):
			amount -= stock_at(p, ore) + incoming(p, ore)
	else:
		amount -= stock_at(p, item) + incoming(p, item)
	return maxf(0.0, amount)

func claim_delivery(w: Dictionary, plan: Dictionary) -> Dictionary:
	var target: Vector2i = plan.target
	var mined_cargo: bool = plan.get("mined", false)
	var origin := Vector2i(w.pos.round())
	if not w.freight.is_empty() or not w.ore_delivery.is_empty():
		return {}
	if mined_cargo:
		if w.carry != plan.item or delivery_route(origin, target).path.is_empty():
			return {}
	elif w.carry > 0 or route(origin, plan.source).is_empty() or delivery_route(plan.source, target).path.is_empty():
		return {}
	var amount := 1.0 if mined_cargo else minf(FREIGHT_CAPACITY, available_at(plan.source, plan.item))
	if plan.has("identity"):
		if smart_objects.identity(SmartObjects.key("supply", target)) != plan.identity:
			return {}
		amount = minf(amount, delivery_need(target, plan.item))
	elif not mined_cargo or sites.has(target) or delivery_building_at(target) != target:
		return {}
	if amount <= 0.000001 or (mined_cargo and amount < 1.0):
		return {}
	var shipment := {"source": plan.source, "target": target, "item": plan.item,
		"amount": amount, "owner": w.id, "picked": mined_cargo,
		"mined": mined_cargo, "carried_ore": mined_cargo}
	if mined_cargo:
		w.ore_delivery = shipment
	else:
		add_stock(shipment.source, shipment.item, -amount)
	shipments.append(shipment)
	return shipment

func site_supplied(p: Vector2i) -> bool:
	for item in sites[p].materials:
		if stock_at(p, item) + 0.000001 < sites[p].materials[item]:
			return false
	return true

func local_payment(p: Vector2i, recipe: Dictionary) -> Dictionary:
	var payment: Dictionary = {}
	for item in recipe:
		if is_same(item, 0):
			continue
		if stock_at(p, item) + 0.000001 < recipe[item]:
			return {}
		payment[item] = recipe[item]
	var remaining: int = recipe.get(0, 0)
	for ore in [1, 4, 3, 2]:
		var taken := mini(remaining, int(stock_at(p, ore)) - payment.get(ore, 0))
		if taken > 0:
			payment[ore] = payment.get(ore, 0) + taken
			remaining -= taken
	return payment if remaining == 0 else {}

func recipe_ready(p: Vector2i, recipe: Dictionary) -> bool:
	return recipe.is_empty() or not local_payment(p, recipe).is_empty()

func consume_recipe(p: Vector2i, recipe: Dictionary) -> void:
	var payment := local_payment(p, recipe)
	for item in payment:
		add_stock(p, item, -payment[item])
		record_resource_use(item, payment[item])

func recover_cancelled_sites() -> void:
	for p in sites.keys():
		if not sites[p].get("cancelled", false):
			continue
		for item in stores.get(p, {}).keys():
			while stock_at(p, item) > 0.000001:
				reserve_shipment(p, BASE, item, minf(FREIGHT_CAPACITY, stock_at(p, item)))
		var recovering := false
		for shipment in shipments:
			if shipment.source == p or shipment.target == p:
				recovering = true
				break
		if not recovering:
			sites.erase(p)
			stores.erase(p)

func simulate_growth(delta: float) -> void:
	for p in benches:
		var bench: Dictionary = benches[p]
		if bench.growth <= 0:
			continue
		bench.growth = maxf(0.0, bench.growth - delta * (2.0 if has_powered_effect(Vector2(p), "grow_light") else 1.0))
		if bench.growth == 0:
			bench.harvest = true
			bench.task = contract(1.0)

func in_effect_range(source: Vector2i, target: Vector2, radius := EFFECT_RADIUS) -> bool:
	return absf(source.x - target.x) <= radius and absf(source.y - target.y) <= radius

func has_powered_effect(p: Vector2, kind: String) -> bool:
	for source in powered_devices:
		if building_kind(source) == kind and in_effect_range(source, p):
			return true
	return false

func record_machine_noise(p: Vector2i, kind: String, active_fraction: float) -> void:
	if active_fraction <= 0.0:
		return
	var profile: Dictionary = WorkerMood.MACHINE_NOISE[kind]
	var strength: float = profile.strength * clampf(active_fraction, 0.0, 1.0)
	machine_noise[p] = {"radius": profile.radius, "strength": maxf(strength, machine_noise.get(p, {}).get("strength", 0.0))}

func machine_noise_at(p: Vector2) -> float:
	var strongest := 0.0
	for source in machine_noise:
		var noise: Dictionary = machine_noise[source]
		if in_effect_range(source, p, noise.radius):
			strongest = maxf(strongest, noise.strength)
	return strongest

func drill_target(p: Vector2i, worker_id := -1):
	for target in jobs:
		if terrain[target] >= 5 and smart_objects.available(SmartObjects.key("mine", target), worker_id) and in_effect_range(p, Vector2(target), DRILL_RADIUS):
			return target
	return null

func station_staffed(p: Vector2i) -> bool:
	var owner := slot_owner("work", p)
	if owner < 0 or owner >= workers.size():
		return false
	var w: Dictionary = workers[owner]
	var active = w.activity.active
	return active != null and active.option.target == p and active.phase == "use" and w.activity.drink_elapsed < 0 and w.payroll > 0.000001 and w.fatigue < MAX_FATIGUE

func power_demand(p: Vector2i) -> float:
	match building_kind(p):
		"grow_light", "spotlight", "daylight": return 200.0
		"fountain": return 200.0 if benches[p].water_day == day else 0.0
		"drill":
			var owner := slot_owner("work", p)
			return 400.0 if drill_target(p, owner) != null else 0.0
		"electric_belt":
			var amount := 0.0
			for cargo in belt_cargo.values():
				var carrier: Vector2i = cargo.to if belts.has(cargo.to) else cargo.from
				if carrier == p:
					amount += cargo.delivery.amount
			return amount * 25.0
	return 0.0

func power_key(p: Vector2i, line := false) -> String:
	return ("line:" if line else "device:") + str(p)

func power_edge(graph: Dictionary, a: String, b: String, capacity: float) -> void:
	if not graph.has(a): graph[a] = {}
	if not graph.has(b): graph[b] = {}
	graph[a][b] = capacity
	if not graph[b].has(a): graph[b][a] = 0.0

# Each segment and transformer has its own capacity. Residual paths share bottlenecks,
# including intersecting low-voltage branches fed by several transformers.
func rebuild_power_graph() -> void:
	var signature_data: Array = []
	for p in power_lines:
		signature_data.append([p, power_lines[p].kind, power_lines[p].get("axis", Vector2i.RIGHT)])
	for p in benches:
		signature_data.append([p, benches[p].kind])
	for p in belts:
		signature_data.append([p, belts[p].get("kind", "belt")])
	var signature := hash(signature_data)
	if signature == power_signature and not power_graph.is_empty():
		return
	power_signature = signature
	power_graph = {"source": {}}
	power_nodes.clear()
	var cells: Dictionary = {}
	for p in power_lines:
		var kind: String = power_lines[p].kind
		var key := power_key(p, true)
		power_edge(power_graph, key + ":in", key + ":out", 3200.0 if kind == "high_line" else 800.0)
		for cell in building_cells(p, kind):
			if not cells.has(cell): cells[cell] = []
			cells[cell].append(key)
	for cell in cells:
		for direction in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			for a in cells[cell]:
				for b in cells.get(cell + direction, []):
					if a != b:
						power_edge(power_graph, a + ":out", b + ":in", 1000000.0)
	for p in benches.keys() + belts.keys():
		var kind := building_kind(p)
		if kind not in OPERATED_KINDS and kind not in ["grow_light", "fountain", "electric_belt", "spotlight", "daylight"]:
			continue
		var key := power_key(p)
		power_nodes[p] = key
		if not power_graph.has(key + ":in"): power_graph[key + ":in"] = {}
		if kind in GENERATOR_KINDS:
			power_edge(power_graph, "source", key + ":out", 400.0 if kind == "manual_generator" else 3200.0)
		elif kind == "transformer":
			power_edge(power_graph, key + ":in", key + ":out", 800.0)
		if kind == "transformer":
			for cable in cells.get(p + Vector2i.LEFT, []):
				power_edge(power_graph, cable + ":out", key + ":in", 3200.0)
			for cable in cells.get(p + Vector2i.RIGHT * 2, []):
				power_edge(power_graph, key + ":out", cable + ":in", 800.0)
		else:
			for cell in building_cells(p, kind):
				for direction in DIRS:
					for cable in cells.get(cell + direction, []):
						if kind in GENERATOR_KINDS:
							power_edge(power_graph, key + ":out", cable + ":in", 3200.0)
						else:
							power_edge(power_graph, cable + ":out", key + ":in", 3200.0)

func power_route(graph: Dictionary, source: String, target: String) -> Array[String]:
	var frontier: Array[String] = [source]
	var parent := {source: ""}
	var index := 0
	while index < frontier.size():
		var a := frontier[index]
		index += 1
		if a == target:
			var path: Array[String] = [a]
			while parent[a] != "":
				a = parent[a]
				path.push_front(a)
			return path
		for b in graph.get(a, {}):
			if graph[a][b] > 0.000001 and not parent.has(b):
				parent[b] = a
				frontier.append(b)
	return []

func operation_needed(p: Vector2i) -> bool:
	if power_lines.is_empty():
		return false
	rebuild_power_graph()
	var kind := building_kind(p)
	if kind == "drill":
		return power_demand(p) > 0 and not power_route(power_graph, "source", power_key(p) + ":in").is_empty()
	if kind == "power_plant" and stock_at(p, 3) <= 0.000001:
		return false
	if kind == "transformer" and power_route(power_graph, "source", power_key(p) + ":in").is_empty():
		return false
	for target in power_nodes:
		if power_demand(target) > 0 and not power_route(power_graph, power_key(p) + ":out", power_key(target) + ":in").is_empty():
			return true
	return false

func simulate_power(delta: float) -> void:
	powered_devices.clear()
	ready_drills.clear()
	power_output.clear()
	if power_lines.is_empty():
		return
	for p in benches:
		if benches[p].kind == "fountain" and benches[p].water_day != day and stock_at(p, "raw_water") >= FOUNTAIN_WATER:
			consume_recipe(p, {"raw_water": FOUNTAIN_WATER})
			benches[p].water_day = day
	rebuild_power_graph()
	var residual: Dictionary = power_graph.duplicate(true)
	var supplies: Dictionary = {}
	for p in benches:
		var key := power_key(p)
		if benches[p].kind in GENERATOR_KINDS:
			var supply := 400.0 if benches[p].kind == "manual_generator" else minf(3200.0, stock_at(p, 3) * 1600.0 * HOUR_SECONDS / delta)
			if not station_staffed(p): supply = 0.0
			supplies[p] = supply
			residual.source[key + ":out"] = supply
		elif benches[p].kind == "transformer" and not station_staffed(p):
			residual[key + ":in"][key + ":out"] = 0.0
	for p in power_nodes:
		var load := power_demand(p)
		if load <= 0 or (building_kind(p) == "drill" and not station_staffed(p)):
			continue
		var before: Dictionary = residual.duplicate(true)
		if allocate_power(residual, p, load):
			powered_devices[p] = true
		else:
			residual = before
	# Preview idle drill capacity without spending fuel or reserving any real flow.
	for p in benches:
		if building_kind(p) != "drill": continue
		if powered_devices.has(p):
			ready_drills[p] = true
		elif not station_staffed(p) and power_demand(p) > 0:
			var preview: Dictionary = residual.duplicate(true)
			if allocate_power(preview, p, power_demand(p)):
				ready_drills[p] = true
	for p in supplies:
		var used: float = supplies[p] - residual.source[power_key(p) + ":out"]
		power_output[p] = used
		if benches[p].kind == "manual_generator":
			continue
		var coal := used / 1600.0 * delta / HOUR_SECONDS
		add_stock(p, 3, -coal)
		record_resource_use(3, coal)
		if used > 0.000001:
			record_machine_noise(p, "power_plant", 1.0)
	for p in benches:
		if benches[p].kind == "transformer":
			var key := power_key(p)
			power_output[p] = residual[key + ":out"].get(key + ":in", 0.0)

func allocate_power(residual: Dictionary, p: Vector2i, load: float) -> bool:
	var remaining := load
	while remaining > 0.000001:
		var path := power_route(residual, "source", power_key(p) + ":in")
		if path.is_empty(): return false
		var flow := remaining
		for i in range(path.size() - 1):
			flow = minf(flow, residual[path[i]][path[i + 1]])
		for i in range(path.size() - 1):
			residual[path[i]][path[i + 1]] -= flow
			residual[path[i + 1]][path[i]] += flow
		remaining -= flow
	return true

func record_resource_output(item, amount: float) -> void:
	if amount <= 0:
		return
	if not resource_flows.has(day):
		resource_flows[day] = {}
	if not resource_flows[day].has(item):
		resource_flows[day][item] = {"produced": 0.0, "consumed": 0.0}
	resource_flows[day][item].produced += amount

func record_resource_use(item, amount: float) -> void:
	if amount <= 0:
		return
	if not resource_flows.has(day):
		resource_flows[day] = {}
	if not resource_flows[day].has(item):
		resource_flows[day][item] = {"produced": 0.0, "consumed": 0.0}
	resource_flows[day][item].consumed += amount

func resource_activity(item, report_day: int) -> Dictionary:
	return resource_flows.get(report_day, {}).get(item, {"produced": 0.0, "consumed": 0.0}).duplicate()

# Count physical goods once, including reservations, cargo, personal supplies and equipped items.
# Wages, sales, loans and delivery only move goods; they do not produce or consume them.
func resource_inventory() -> Dictionary:
	var result: Dictionary = {}
	for item in RESOURCE_ITEMS:
		result[item] = 0.0
	for p in stores:
		for item in stores[p]:
			result[item] = result.get(item, 0.0) + stores[p][item]
	for p in benches:
		if PRODUCTS.has(building_kind(p)) and building_kind(p) != "printer":
			var item = product_item(building_kind(p))
			result[item] += benches[p].stock
	for shipment in shipments:
		if not shipment.get("on_belt", false) and not shipment.get("carried_ore", false):
			result[shipment.item] += shipment.amount
	for cargo in belt_cargo.values():
		result[cargo.delivery.item] += cargo.delivery.amount
	for w in workers:
		if w.carry > 0:
			result[w.carry] += 1
		for ore in w.extra_cargo:
			result[ore] += 1
		result.bread += w.bread + w.payroll + w.meal_bread
		result.clean_water += w.water
		result.bench += 1 if w.gun_uses > 0 else 0
		result.workbench += 1 if w.backpack_uses > 0 else 0
	return result

func sample_inventory() -> void:
	inventory_sample_time = (day - 1) * DAY_SECONDS + day_elapsed
	inventory_history.append({"time": inventory_sample_time, "stock": resource_inventory()})
	while inventory_history.size() > 121:
		inventory_history.pop_front()

# Domain operations own all material, production and payment writes.
func work_available(option, w: Dictionary) -> bool:
	var p = option.target
	match option.kind:
		"mine":
			return mining_contracts.has(p) and is_same(mining_contracts[p], option.data.identity) and terrain[p] in [1, 2, 3, 4] and cargo_count(w) < carry_capacity(w)
		"build":
			return sites.has(p) and is_same(sites[p], option.data.identity) and not sites[p].get("cancelled", false) and site_cleared(p) and site_supplied(p)
		"produce":
			return benches.has(p) and is_same(benches[p], option.data.identity) and has_production_order(p) and benches[p].growth <= 0
		"operate":
			return benches.has(p) and is_same(benches[p], option.data.identity) and operation_needed(p) and (option.data.job == null or (mining_contracts.has(option.data.job) and ready_drills.has(p)))
	return false

func begin_work(option, w: Dictionary, segment: Dictionary) -> bool:
	if not work_available(option, w):
		return false
	if option.kind in ["produce", "operate"]:
		var p: Vector2i = option.target
		var bench: Dictionary = benches[p]
		if bench.task.is_empty():
			if option.kind == "produce":
				var recipe := production_materials(bench.kind)
				if not recipe_ready(p, recipe):
					return false
				consume_recipe(p, recipe)
			bench.task = contract(1.0 if bench.kind in OPERATED_KINDS or bench.kind == "farm" else PRODUCTS[bench.kind].hours)
	var task: Dictionary
	var station = option.target if option.kind in ["produce", "operate"] else null
	var kind := building_kind(station) if station != null else ""
	if option.kind == "mine": task = mining_contracts[option.target]
	elif option.kind == "build": task = sites[option.target]
	elif kind == "drill": task = mining_contracts[option.data.job]
	else: task = benches[station].task
	if not task.has("reward"):
		task.reward = task.seconds / HOUR_SECONDS * station_wage(station)
		task.paid = 0.0
	var goal: float = minf(task.seconds, (task.paid + w.payroll) / task.reward * task.seconds)
	if goal <= task.progress + 0.0000001:
		return false
	var rate := GUN_MINING_RATE if option.kind == "mine" and w.gun_uses > 0 else 1.0
	if kind not in GENERATOR_KINDS and kind != "transformer":
		rate *= w.mood.work_rate()
	segment.merge({"task": task, "goal": goal, "rate": rate, "kind": kind, "labor": 0.0,
		"fatigue_factor": 1.0 - WATER_FATIGUE_REDUCTION if w.water_effect > 0 or w.water > 0 else 1.0}, true)
	ai_trace.record(self, w, "labor", "started", {"reward": task.reward, "already_paid": task.paid,
		"rate": rate, "goal": goal, "fatigue_factor": segment.fatigue_factor})
	return true

func perform_work(option, w: Dictionary, delta: float, segment: Dictionary) -> Dictionary:
	var task: Dictionary = segment.task
	var p = option.target
	if option.kind == "operate" and building_kind(p) == "drill" and not powered_devices.has(p):
		return {"seconds": 0.0, "complete": false, "funding": false}
	var seconds := advance_labor(segment, delta)
	var complete: bool = task.progress >= task.seconds - 0.0000001
	var funding: bool = not complete and task.progress >= segment.goal - 0.0000001
	if option.kind == "operate" and building_kind(p) == "drill" and seconds > 0:
		record_machine_noise(p, "drill", seconds / delta)
	if complete:
		task.progress = task.seconds
		settle_labor(w, segment, "completed")
		complete_work(option, w)
	elif funding:
		settle_labor(w, segment, "funding")
	return {"seconds": seconds, "complete": complete, "funding": funding}

func complete_work(option, w: Dictionary) -> void:
	var p: Vector2i = option.target
	match option.kind:
		"mine":
			if w.gun_uses == 1: record_resource_use("bench", 1)
			w.gun_uses = maxi(0, w.gun_uses - 1)
			record_resource_output(terrain[p], 1)
			if w.carry == 0: w.carry = terrain[p]
			else: w.extra_cargo.append(terrain[p])
			terrain[p] = 0
			world_view.block_changed(p)
			navigation.set_point_solid(p, false)
			jobs.erase(p)
			mining_contracts.erase(p)
			smart_objects.invalidate(SmartObjects.key("mine", p))
			world_view.sync_orders()
			record_excavation(w)
			update_fog()
		"build": complete_building(p)
		"produce": complete_product(p)
		"operate":
			var bench: Dictionary = benches[p]
			if bench.kind == "drill":
				var mineral: Vector2i = option.data.job
				var task: Dictionary = mining_contracts[mineral]
				var item: int = ORES[terrain[mineral]].item
				add_stock(p, item, 1)
				record_resource_output(item, 1)
				record_excavation(w)
				task.clear()
				task.merge(contract(DRILL_HOURS))
			else:
				bench.task = {}

func record_excavation(w: Dictionary) -> void:
	mined += 1
	if not daily_mined.has(day): daily_mined[day] = {}
	daily_mined[day][w.id] = daily_mined[day].get(w.id, 0) + 1

func complete_product(p: Vector2i) -> void:
	var bench: Dictionary = benches[p]
	if bench.kind == "printer":
		newborns.append(p + Vector2i.RIGHT)
		bench.queue -= 1
	elif bench.kind == "farm" and not bench.harvest:
		bench.growth = FARM_GROWTH_HOURS * HOUR_SECONDS
	else:
		var amount: int = PRODUCTS[bench.kind].get("amount", 1)
		bench.stock += amount
		bench.produced_today += amount
		record_resource_output(product_item(bench.kind), amount)
		bench.harvest = false
	bench.task = {}

func complete_building(p: Vector2i) -> void:
	var task: Dictionary = sites[p]
	if PRODUCTS.has(task.kind) or NEW_BUILDINGS.has(task.kind) and task.kind not in LINE_KINDS and task.kind not in BELT_KINDS:
		benches[p] = production_station(task.kind)
		if task.kind == "fountain": benches[p].water_day = day
	elif task.kind == "bank":
		banks[p] = {"interest_received": 0.0}
	elif task.kind in BELT_KINDS:
		belts[p] = {"kind": task.kind, "direction": task.direction, "inputs": task.inputs, "cargo": -1, "last_input": -1, "materials": task.materials}
	elif task.kind in LINE_KINDS:
		power_lines[p] = {"kind": task.kind, "axis": task.axis, "materials": task.materials.duplicate()}
	else:
		beds[p] = {"remaining": 0.0, "assigned": -1}
	for item in task.materials:
		add_stock(p, item, -task.materials[item])
		record_resource_use(item, task.materials[item])
	sites.erase(p)
	smart_objects.invalidate(SmartObjects.key("build", p))

func purchase(w: Dictionary, p: Vector2i, limit: int) -> void:
	if not benches.has(p) or w.pos.distance_to(Vector2(p)) > 0.01:
		return
	var product: Dictionary = PRODUCTS[building_kind(p)]
	var price := sale_price(p)
	var count := mini(limit, mini(benches[p].stock, floori((w.bread + 0.000001) / price)))
	if product.has("durability"):
		count = mini(1, count) if w[product.durability] == 0 else 0
	else:
		count = mini(count, WATER_CAPACITY - w.water)
	if count <= 0: return
	benches[p].stock -= count
	w.bread -= count * price
	w.shop_spent_today += count * price
	add_stock(p, "bread", count * price)
	if product.has("durability"): w[product.durability] = product.uses
	else: w.water += count

func collect_payroll(w: Dictionary, p: Vector2i) -> void:
	var cash := minf(4.0, stock_at(p, "bread"))
	add_stock(p, "bread", -cash)
	w.payroll += cash

func borrow(w: Dictionary, p: Vector2i, limit: float) -> void:
	if not banks.has(p) or has_debt(w) or w.loan_day == day:
		return
	var need := maxf(0, 10.0 - w.hunger / HUNGER_PER_BREAD - w.bread)
	var amount := minf(need, minf(limit, minf(LOAN_LIMIT, stock_at(p, "bread"))))
	if amount <= 0: return
	add_stock(p, "bread", -amount)
	w.bread += amount
	portal.lent_bread += amount
	w.loan_principal = amount
	w.loan_interest = amount * LOAN_INTEREST_RATE
	w.loan_day = day
	w.loan_bank = p

func drink(w: Dictionary) -> void:
	if w.water <= 0: return
	w.water -= 1
	record_resource_use("clean_water", 1)
	w.water_effect = WATER_EFFECT_HOURS * HOUR_SECONDS

func rent_bed(w: Dictionary, p: Vector2i) -> bool:
	if not beds.has(p) or w.bread < BED_PRICE or slot_owner("bed", p) != w.id:
		return false
	w.bread -= BED_PRICE
	w.bed_spent_today += BED_PRICE
	add_stock(p, "bread", BED_PRICE)
	beds[p].remaining = BED_LEASE_HOURS * HOUR_SECONDS
	return true

func eat_portion(w: Dictionary, option, seconds: float) -> void:
	var fraction := seconds / MEAL_SECONDS
	var eaten := minf(w.meal_bread, option.data.amount * fraction)
	w.meal_bread = maxf(0, w.meal_bread - eaten)
	w.eaten_today += eaten
	w.hunger = minf(MAX_HUNGER, w.hunger + eaten * HUNGER_PER_BREAD)
	record_resource_use("bread", eaten)
	if option.data.has("canteen"):
		w.fatigue = maxf(0, w.fatigue - CANTEEN_RECOVERY * fraction)

func sleep_seconds(w: Dictionary, bed, delta: float) -> Dictionary:
	var bed_seconds := 0.0
	if bed != null and beds.has(bed):
		bed_seconds = minf(delta, minf(beds[bed].remaining, w.fatigue / BED_RECOVERY_PER_HOUR * HOUR_SECONDS))
		beds[bed].remaining = maxf(0, beds[bed].remaining - bed_seconds)
		w.fatigue = maxf(0, w.fatigue - bed_seconds / HOUR_SECONDS * BED_RECOVERY_PER_HOUR)
	var ground_seconds := minf(delta - bed_seconds, w.fatigue / SLEEP_RECOVERY_PER_HOUR * HOUR_SECONDS)
	w.fatigue = maxf(0, w.fatigue - ground_seconds / HOUR_SECONDS * SLEEP_RECOVERY_PER_HOUR)
	if w.fatigue < 0.000001:
		w.fatigue = 0.0
	return {"hours": (bed_seconds + ground_seconds) / HOUR_SECONDS, "bed_hours": bed_seconds / HOUR_SECONDS}
