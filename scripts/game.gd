extends Node2D

const CELL := 40.0
const BASE := Vector2i(32, 13)
const VISION_RADIUS := 7
const DAY_SECONDS := 180.0
# 面包兼作食物和支付物。进食消耗个人面包、恢复饱食度；饱食度全天衰减，最低为零。
const MEAL_SECONDS := 2.0
const HUNGER_PER_BREAD := 10.0
const MAX_HUNGER := 180.0
const HUNGER_DECAY_PER_DAY := 100.0
# 挖掘、建造与生产增加疲劳；通勤和搬运不增加。疲劳满后睡眠，恢复至零醒来。
const FATIGUE_PER_HOUR := 10.0
const SLEEP_RECOVERY_PER_HOUR := 10.0
const FATIGUING_STATES := ["dig", "work", "build"]
const HOUR_SECONDS := DAY_SECONDS / 24.0
const MIN_MINING_HOURS := 1.0
const BED_BLOCKS := 6
const BED_BUILD_HOURS := 4.0
const WAGE_PER_HOUR := 1.0
# 床到达后收费，独占一个租期并加快疲劳恢复；提前醒来不退费，租期结束后按地面速度恢复。
const BED_PRICE := 5.0
const BED_LEASE_HOURS := 8.0
const BED_RECOVERY_PER_HOUR := 15.0
const BENCH_BLOCKS := 6
const BENCH_BUILD_HOURS := 4.0
# 矿枪在武器桌购买，缩短挖掘时间；每完成一格消耗一次耐久，工资与疲劳按实际工时计算。
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
# 银行用本地面包覆盖生活费缺口，每人每天最多一笔；未还清不能追加，借款不计为收入。
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
var dispatch_timer := 0.0
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
	stores.clear()
	stores[BASE] = {"bread": STARTING_BREAD}
	shipments.clear()
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
	portal = Portal.new()
	wander_rng.seed = 1020
	dispatch_timer = 0.0
	fog_timer = 0.0
	dragging = false
	simulation_paused = false
	pause_button.text = "Ⅱ"
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
		"color": WORKER_COLORS[id % WORKER_COLORS.size()], "pos": Vector2(p), "state": "idle",
		"path": [], "job": null, "progress": 0.0, "carry": 0,
		"bread": 0, "earned_today": 0, "eaten_today": 0, "hunger": 0.0, "meal_day": 0, "meal_bread": 0,
		"meal_seat": null, "canteen": null,
		"bed_spent_today": 0.0, "shop_spent_today": 0.0,
		"wander_wait": 0.0, "facing": 1.0, "fatigue": 0.0,
		"bed": null, "used_bed_this_sleep": false, "building": null,
		"station": null, "gun_uses": 0, "backpack_uses": 0, "extra_cargo": [],
		"water": 0, "water_effect": 0.0, "drink_progress": 0.0, "drink_resume": "",
		"mood": WorkerMood.new(), "water_purchase_limit": 0, "water_purchase_optional": false,
		"loan_principal": 0.0, "loan_interest": 0.0, "loan_day": 0, "loan_bank": null,
		"haul_target": BASE, "unloaded_this_trip": 0, "freight": {}, "payroll": 0.0,
		"cash_source": BASE}
	workers.append(worker)
	return worker

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

# 生活费由食物、可用床位和待补装备组成，包含蓝图带来的需求；已消费部分抵扣当天需求。
# 达到剩余生活费后进食、休息；有债务则继续找工作。清水是可选消费，不纳入强制需求。
func daily_budget(w: Dictionary) -> Dictionary:
	var food := maxf(HUNGER_DECAY_PER_DAY / HUNGER_PER_BREAD, w.eaten_today + w.meal_bread)
	var planned_bed := false
	var planned_shops: Dictionary = {}
	for bench in benches.values():
		if PRODUCTS.has(bench.kind):
			planned_shops[bench.kind] = true
	for task in sites.values():
		if task.kind == "bed":
			planned_bed = true
		elif PRODUCTS.has(task.kind):
			planned_shops[task.kind] = true
	var bed_cost: float = w.bed_spent_today
	if bed_cost < BED_PRICE:
		for p in beds:
			var assigned: int = beds[p].assigned
			if assigned >= 0 and assigned != w.id:
				continue
			planned_bed = true
			break
	if planned_bed:
		bed_cost = maxf(bed_cost, BED_PRICE)
	var shopping: float = w.shop_spent_today
	for kind in planned_shops:
		var product: Dictionary = PRODUCTS[kind]
		if product.has("durability") and w[product.durability] == 0:
			shopping += planned_product_price(w, kind)
	var total: float = food + bed_cost + shopping
	var paid: float = w.eaten_today + w.meal_bread + w.bed_spent_today + w.shop_spent_today
	return {"food": food, "bed": bed_cost, "shopping": shopping,
		"total": total, "paid": paid, "remaining": maxf(0.0, total - paid)}

func daily_budget_ready(w: Dictionary) -> bool:
	return w.bread >= daily_budget(w).remaining - 0.000001

func has_debt(w: Dictionary) -> bool:
	return w.loan_principal + w.loan_interest > 0.000001

func can_rest(w: Dictionary) -> bool:
	return daily_budget_ready(w) and not has_debt(w) and w.bread >= daily_budget(w).remaining + optional_water_cost(w) - 0.000001

# Optional desires never enter the living-cost estimate used by meals and bank loans.
func optional_water_cost(w: Dictionary) -> float:
	if w.mood.shopping <= 0 or has_debt(w) or w.water > 0 or w.water_effect > 0:
		return 0.0
	for p in shop_locations(w, "purifier"):
		if benches[p].stock > 0:
			return mini(WATER_CAPACITY, benches[p].stock) * sale_price(p)
	return 0.0

func needs_meal(w: Dictionary) -> bool:
	return w.meal_day != day and w.hunger < MAX_HUNGER

func try_borrow(w: Dictionary) -> bool:
	if has_debt(w) or w.loan_day == day or w.bread >= daily_budget(w).remaining:
		return false
	for p in banks:
		if stock_at(p, "bread") <= 0 or route(Vector2i(w.pos.round()), p).is_empty():
			continue
		w.cash_source = p
		w.path = route(Vector2i(w.pos.round()), p)
		w.state = "to_bank"
		return true
	return false

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

func assign_job(w: Dictionary) -> void:
	if w.state in ["eat", "to_meal", "sleep", "to_bed", "drink"]:
		return
	if w.carry > 0:
		if cargo_count(w) >= carry_capacity(w) or can_rest(w) or (daily_budget_ready(w) and needs_meal(w)) or not assign_mining_job(w):
			start_haul(w)
		return
	if not w.freight.is_empty():
		resume_freight(w)
		return
	if daily_budget_ready(w):
		if try_shop_trip(w):
			return
		if needs_meal(w) or can_rest(w):
			if not needs_meal(w) and try_water_trip(w, true):
				return
			start_meal(w)
			return
	if try_borrow(w):
		return
	prepare_deliveries()
	if assign_freight(w):
		return
	var start := Vector2i(w.pos.round())
	for target in sites:
		if sites[target].owner != -1 or sites[target].get("cancelled", false) or not site_cleared(target) or not site_supplied(target):
			continue
		var path := route(start, target)
		if not path.is_empty():
			if not prepare_payroll(w):
				return
			if try_water_trip(w):
				return
			sites[target].owner = w.id
			w.building = target
			w.path = path
			w.state = "to_build"
			return
	for target in benches:
		var bench: Dictionary = benches[target]
		var kind := building_kind(target)
		if kind not in OPERATED_KINDS:
			continue
		if not w.mood.accepts_work(kind):
			continue
		if not operation_needed(target) or (not bench.task.is_empty() and bench.task.owner != -1):
			continue
		var path := route(start, target)
		if path.is_empty():
			continue
		if not prepare_payroll(w):
			return
		if bench.task.is_empty():
			bench.task = contract(1.0)
		bench.task.owner = w.id
		w.station = target
		w.path = path
		w.state = "to_work"
		return
	for target in benches:
		var bench: Dictionary = benches[target]
		if not PRODUCTS.has(bench.kind) or bench.growth > 0 or not has_production_order(target) or (not bench.task.is_empty() and bench.task.owner != -1):
			continue
		var path := route(start, target)
		if path.is_empty():
			continue
		var recipe := production_materials(building_kind(target))
		if bench.task.is_empty() and not recipe_ready(target, recipe):
			continue
		if not prepare_payroll(w):
			return
		if try_water_trip(w):
			return
		if bench.task.is_empty():
			consume_recipe(target, recipe)
			bench.task = contract(1.0 if bench.kind == "farm" else PRODUCTS[bench.kind].hours)
		bench.task.owner = w.id
		w.station = target
		w.path = path
		w.state = "to_work"
		return
	assign_mining_job(w)

func assign_mining_job(w: Dictionary) -> bool:
	var start := Vector2i(w.pos.round())
	for target in jobs:
		if jobs[target] != -1 or terrain[target] >= 5:
			continue
		for direction in DIRS:
			var stand: Vector2i = target + direction
			var path := route(start, stand)
			if not path.is_empty():
				if w.carry == 0 and try_shop_trip(w):
					return true
				if try_water_trip(w):
					return true
				if not prepare_payroll(w):
					return w.state == "to_payroll"
				jobs[target] = w.id
				w.job = target
				w.path = path
				w.state = "walk"
				w.progress = mining_contracts[target].progress
				return true
	return false

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

func mined_delivery(w: Dictionary) -> Dictionary:
	return {"target": BASE, "item": w.carry, "amount": 1, "mined": true}

func start_haul(w: Dictionary, use_belts := true) -> void:
	var delivery := mined_delivery(w)
	var leg := delivery_route(Vector2i(w.pos.round()), delivery.target, use_belts)
	w.path = leg.path
	w.haul_target = leg.stop
	w.state = "haul"

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

func deliver_ore(ore: int, freight_fee := 0.0) -> void:
	delivered += 1
	add_stock(BASE, ore, 1)
	add_stock(BASE, "bread", freight_fee)
	portal.freight_bread += freight_fee
	portal.input_blocks[ore] = portal.input_blocks.get(ore, 0) + 1

func delivery_building_at(cell: Vector2i):
	if cell == BASE:
		return BASE
	for collection in [benches, banks, beds]:
		for origin in collection:
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
	update_build_availability()
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
	var cost := 0
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
		cost += building_blocks(line_kind)
	return cost == 0 or can_afford_building(line_kind, cost)

func place_belt_path(path: Array[Vector2i]) -> bool:
	if not belt_plan_valid(path):
		return false
	var plan := belt_path_plan(path)
	var line_kind := "electric_belt" if tool == "electric_belt" else "belt"
	for p in plan:
		if not belts.has(p) and not sites.has(p):
			place_building(p, line_kind)
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
	if delivery.get("mined", false):
		deliver_ore(delivery.item, fee)
	else:
		add_stock(delivery.target, delivery.item, delivery.amount)
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
	else:
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
	return {"progress": 0.0, "seconds": hours * HOUR_SECONDS,
		"owner": -1}

# 工厂随身款按实际劳动连续转为个人面包；中断保留已完成工时，取消不追回已付工资。
func pay_labor(w: Dictionary, task: Dictionary, delta: float, rate := 1.0) -> void:
	var kind := building_kind(w.station) if w.state == "work" else ""
	# Attendance is real time, not output: a happy operator cannot speed up a duty hour.
	if kind not in GENERATOR_KINDS and kind != "transformer":
		rate *= w.mood.work_rate()
	var hourly_wage := station_wage(w.station) if w.state == "work" else WAGE_PER_HOUR
	var work := minf(delta * rate, task.seconds - task.progress)
	work = minf(work, w.payroll / hourly_wage * HOUR_SECONDS * rate)
	var hours := work / rate / HOUR_SECONDS
	var wage := hours * hourly_wage
	task.progress += work
	w.payroll = maxf(0, w.payroll - wage)
	receive_income(w, wage)
	w.mood.worked(kind, hours)
	if kind == "drill":
		record_machine_noise(w.station, kind, hours * HOUR_SECONDS / delta)

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

# 矿种在开采、运输和仓储中保持身份。配方键 0 表示任意矿石，其余键对应 ORES。
func building_materials(kind: String) -> Dictionary:
	if NEW_BUILDINGS.has(kind):
		return NEW_BUILDINGS[kind].materials
	match kind:
		"bed": return {1: BED_BLOCKS}
		"bench": return {1: BENCH_BLOCKS - 2, 2: 2}
		"workbench": return {1: WORKBENCH_BLOCKS - 2, 4: 2}
	return {0: building_blocks(kind)}

# 开工消耗接收建筑内的原料；配方为空表示只需劳动。农田的水用于整批播种与生长。
func production_materials(kind: String) -> Dictionary:
	match kind:
		"bench": return {2: 1}
		"purifier", "farm": return {"raw_water": 4}
		"printer": return {0: PRINT_WORKER_BLOCKS}
	return {}

func material_payment(recipe: Dictionary, count := 1) -> Dictionary:
	var payment: Dictionary = {}
	for ore in recipe:
		if is_same(ore, 0):
			continue
		var required: int = recipe[ore] * count
		if total_stock(ore) < required:
			return {}
		payment[ore] = required
	var remaining: int = recipe.get(0, 0) * count
	# Generic recipes spend common stone first, preserving copper for equipment.
	for ore in [1, 4, 3, 2]:
		var amount := mini(remaining, materials.get(ore, 0) - payment.get(ore, 0))
		if amount > 0:
			payment[ore] = payment.get(ore, 0) + amount
			remaining -= amount
	return payment if remaining == 0 else {}

func take_materials(recipe: Dictionary, destination: Vector2i) -> Dictionary:
	var payment := material_payment(recipe)
	# Reserve at the source even while excavation blocks access to the blueprint.
	for item in payment:
		var remaining: float = payment[item]
		for source in stock_locations():
			while remaining > 0.000001 and available_at(source, item) > 0.000001:
				var moved := minf(FREIGHT_CAPACITY, minf(remaining, available_at(source, item)))
				reserve_shipment(source, destination, item, moved)
				remaining -= moved
	return payment

func return_materials(payment: Dictionary, location := BASE) -> void:
	for item in payment:
		add_stock(location, item, payment[item])
		record_resource_output(item, payment[item])

func can_afford_building(kind: String, count := 1) -> bool:
	return not material_payment(building_materials(kind), count).is_empty()

func material_requirements_text(recipe: Dictionary, show_stock := false, colored := false) -> String:
	var lines: Array[String] = []
	for ore in recipe:
		var amount: int = recipe[ore]
		var stock: int = player_blocks if is_same(ore, 0) else int(total_stock(ore))
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

# 放置时锁定全部建材并安排占地挖掘；全部清空、材料齐备才施工，不再次收费。
func place_building(p: Vector2i, kind: String) -> bool:
	if not building_space_valid(p, kind) or not can_afford_building(kind):
		return false
	var payment := take_materials(building_materials(kind), p)
	sites[p] = contract(building_hours(kind))
	sites[p].kind = kind
	sites[p].materials = payment
	if kind in BELT_KINDS:
		sites[p].direction = Vector2i.ZERO
		sites[p].inputs = []
	if kind in LINE_KINDS:
		sites[p].axis = Vector2i.DOWN if building_axis == Vector2i.DOWN else Vector2i.RIGHT
	for cell in building_cells(p, kind):
		if add_mining_order(cell):
			mining_contracts[cell].site = p
	world_view.sync_orders()
	update_build_availability()
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
	var count := 0
	for p in positions:
		if not existing_line(p, kind): count += 1
	if positions.is_empty() or (count > 0 and not can_afford_building(kind, count)):
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
	for p in positions:
		if not existing_line(p, kind):
			place_building(p, kind)
	return true

func existing_line(p: Vector2i, kind: String) -> bool:
	return kind in LINE_KINDS and (power_lines.get(p, {}).get("kind", "") == kind or sites.get(p, {}).get("kind", "") == kind)

func finish_building_drag(screen_position: Vector2) -> void:
	building_drawing = false
	if get_viewport().gui_get_hovered_control() == null:
		var world_position := get_global_transform_with_canvas().affine_inverse() * screen_position
		update_building_drag(world_cell(world_position))
		place_building_batch(building_row(), tool)
	building_axis = Vector2i.ZERO

func cancel_placement() -> void:
	belt_drawing = false
	belt_path.clear()
	building_drawing = false
	building_axis = Vector2i.ZERO
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
	for w in workers:
		if w.station == origin:
			release_work(w)
			w.state = "idle"
	benches[target] = benches[origin]
	benches.erase(origin)
	if stores.has(origin):
		for item in stores[origin]:
			add_stock(target, item, stores[origin][item])
		stores.erase(origin)
	powered_devices.erase(origin)
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
	if task.owner >= 0:
		var w: Dictionary = workers[task.owner]
		release_work(w)
		w.state = "idle"
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
			var carrier: Dictionary = workers[shipment.owner]
			if carrier.state in ["freight_pickup", "freight_dropoff"]:
				resume_freight(carrier)
		else:
			add_stock(shipment.source, shipment.item, shipment.amount)
			if shipment.owner >= 0:
				var carrier: Dictionary = workers[shipment.owner]
				carrier.freight = {}
				if carrier.state == "freight_pickup":
					carrier.path = []
					carrier.pos = carrier.pos.round()
					carrier.state = "idle"
			shipments.erase(shipment)
	recover_cancelled_sites()
	update_build_availability()
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

func try_shop_trip(w: Dictionary) -> bool:
	if w.carry > 0:
		return false
	for p in shop_locations(w):
		var product: Dictionary = PRODUCTS[building_kind(p)]
		if not product.has("durability") or benches[p].stock <= 0 or w[product.durability] > 0 or w.bread < sale_price(p):
			continue
		var path := route(Vector2i(w.pos.round()), p)
		if path.is_empty():
			continue
		w.station = p
		w.path = path
		w.state = "to_shop"
		return true
	return false

func product_item(kind: String):
	return PRODUCTS.get(kind, {}).get("item", {"pump": "raw_water", "purifier": "clean_water"}.get(kind, kind))

func sale_price(p: Vector2i) -> float:
	return PRODUCTS[building_kind(p)].price * (1.0 + LIGHT_BONUS if has_powered_effect(Vector2(p), "spotlight") else 1.0)

func station_wage(p) -> float:
	return WAGE_PER_HOUR * (1.0 + LIGHT_BONUS if p != null and benches.has(p) and has_powered_effect(Vector2(p), "daylight") else 1.0)

# Prices are local: choose an affordable stocked shop before committing to the trip.
func shop_locations(w: Dictionary, kind := "") -> Array:
	var offers: Array = []
	for p in benches:
		if kind != "" and building_kind(p) != kind:
			continue
		if not PRODUCTS.get(building_kind(p), {}).has("price"):
			continue
		var path := route(Vector2i(w.pos.round()), p)
		if not path.is_empty():
			offers.append({"pos": p, "price": sale_price(p), "distance": path.size()})
	offers.sort_custom(func(a, b): return a.distance < b.distance if is_equal_approx(a.price, b.price) else a.price < b.price)
	return offers.map(func(offer): return offer.pos)

func planned_product_price(w: Dictionary, kind: String) -> float:
	var locations := shop_locations(w, kind)
	for p in locations:
		if benches[p].stock > 0:
			return sale_price(p)
	return sale_price(locations[0]) if not locations.is_empty() else float(PRODUCTS[kind].price)

func water_purchase_count(w: Dictionary, stock: int, limit: int, optional: bool, price := WATER_PRICE) -> int:
	var reserve: float = daily_budget(w).remaining if optional else 0.0
	return maxi(0, mini(limit, mini(WATER_CAPACITY - w.water, mini(stock, floori((w.bread - reserve + 0.000001) / price)))))

func try_water_trip(w: Dictionary, optional := false) -> bool:
	# Water is optional: never reserve wages or delay work for unavailable water.
	if w.carry > 0 or w.water > 0 or w.water_effect > 0 or w.bread < WATER_PRICE:
		return false
	if optional and optional_water_cost(w) <= 0:
		return false
	optional = optional or w.mood.shopping > 0
	if optional and has_debt(w):
		return false
	var limit: int = w.mood.water_limit(WATER_CAPACITY)
	for p in shop_locations(w, "purifier"):
		if water_purchase_count(w, benches[p].stock, limit, optional, sale_price(p)) == 0:
			continue
		var path := route(Vector2i(w.pos.round()), p)
		if path.is_empty():
			continue
		w.station = p
		w.water_purchase_limit = limit
		w.water_purchase_optional = optional
		w.path = path
		w.state = "to_shop"
		return true
	return false

func start_drink(w: Dictionary) -> bool:
	if w.state not in FATIGUING_STATES or w.water <= 0 or w.water_effect > 0 or can_rest(w):
		return false
	w.drink_resume = w.state
	w.drink_progress = 0.0
	w.state = "drink"
	return true

# 每天安排一次进食，按可支配面包与饱食度缺口取餐，保留床费及装备费；餐中跨日照常完成。
func start_meal(w: Dictionary) -> void:
	if w.state in ["eat", "to_meal"]:
		return
	if w.carry > 0:
		start_haul(w)
		return
	if w.meal_day == day:
		w.state = "rest" if can_rest(w) else "idle"
	elif w.hunger >= MAX_HUNGER:
		w.meal_day = day
		w.state = "rest" if can_rest(w) else "idle"
	elif w.bread > 0:
		var needed := ceili((MAX_HUNGER - w.hunger) / HUNGER_PER_BREAD)
		var budget := daily_budget(w)
		var reserved: float = budget.bed - w.bed_spent_today + budget.shopping - w.shop_spent_today
		w.meal_bread = mini(maxi(0, floori(w.bread - reserved)), needed)
		if w.meal_bread == 0:
			w.state = "idle"
			return
		w.bread -= w.meal_bread
		w.meal_day = day
		w.progress = 0.0
		w.state = "eat"
		choose_meal_seat(w)

func choose_meal_seat(w: Dictionary) -> void:
	var best_path: Array[Vector2i] = []
	for p in benches:
		if building_kind(p) != "canteen":
			continue
		for seat in building_cells(p, "canteen"):
			if workers.any(func(other): return other.meal_seat == seat):
				continue
			var path := route(Vector2i(w.pos.round()), seat)
			if path.is_empty() or path.size() - 1 > CANTEEN_WALK_LIMIT:
				continue
			if best_path.is_empty() or path.size() < best_path.size():
				best_path = path
				w.meal_seat = seat
				w.canteen = p
	if not best_path.is_empty():
		w.path = best_path
		w.state = "to_meal"

func release_meal_seat(w: Dictionary) -> void:
	w.meal_seat = null
	w.canteen = null

func move_worker(w: Dictionary, delta: float, pace := 3.0) -> bool:
	var distance := delta * pace
	while not w.path.is_empty() and distance > 0:
		var next := Vector2(w.path[0])
		if absf(next.x - w.pos.x) > 0.01:
			w.facing = signf(next.x - w.pos.x)
		var remaining: float = w.pos.distance_to(next)
		if remaining <= distance:
			w.pos = next
			w.path.pop_front()
			distance -= remaining
		else:
			w.pos = w.pos.move_toward(next, distance)
			distance = 0
	return w.path.is_empty()

func wander(w: Dictionary, delta: float) -> void:
	if not w.path.is_empty():
		if move_worker(w, delta, 1.1):
			w.wander_wait = wander_rng.randf_range(1.2, 3.0)
		return
	w.wander_wait -= delta
	if w.wander_wait > 0:
		return
	var origin := Vector2i(w.pos.round())
	for attempt in 16:
		var target := origin + Vector2i(wander_rng.randi_range(-4, 4), wander_rng.randi_range(-3, 3))
		if target == origin or not explored.has(target):
			continue
		var path := route(origin, target)
		if path.size() > 1 and path.size() <= 9:
			w.path = path
			return
	w.wander_wait = 1.5

func simulate(delta: float) -> void:
	# Split at midnight so deliveries are credited to the correct day.
	var remaining := delta
	while remaining > 0.0000001:
		var step := minf(0.05, minf(remaining, DAY_SECONDS - day_elapsed))
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
				if w.state == "rest":
					w.state = "idle"
					w.pos = w.pos.round()
					w.path = []
					w.wander_wait = 0.0

func simulate_workers(delta: float) -> void:
	dispatch_timer += delta
	var printed_workers: Array[Vector2i] = []
	var rest_experiences: Array[Dictionary] = []
	for w in workers:
		w.mood.advance(delta / HOUR_SECONDS)
		var refreshed_seconds := minf(delta, w.water_effect)
		w.water_effect = maxf(0.0, w.water_effect - delta)
		w.hunger = maxf(0.0, w.hunger - HUNGER_DECAY_PER_DAY * delta / DAY_SECONDS)
		if w.fatigue >= 100.0 and w.state not in ["sleep", "to_bed", "to_bank"]:
			start_sleep(w)
		if w.state == "sleep" and not beds.has(w.bed) and not w.used_bed_this_sleep and dispatch_timer >= 0.2:
			try_sleep_in_bed(w)
		if refreshed_seconds == 0:
			start_drink(w)
		record_action(w, delta)
		var was_working: bool = w.state in FATIGUING_STATES
		match w.state:
			"to_payroll":
				if move_worker(w, delta):
					var cash := minf(4.0, stock_at(w.cash_source, "bread"))
					add_stock(w.cash_source, "bread", -cash)
					w.payroll += cash
					w.state = "idle"
			"to_bank":
				if move_worker(w, delta):
					var amount := maxf(0.0, minf(stock_at(w.cash_source, "bread"), minf(LOAN_LIMIT, daily_budget(w).remaining - w.bread)))
					if amount > 0 and not has_debt(w) and w.loan_day != day:
						add_stock(w.cash_source, "bread", -amount)
						w.bread += amount
						portal.lent_bread += amount
						w.loan_principal = amount
						w.loan_interest = amount * LOAN_INTEREST_RATE
						w.loan_day = day
						w.loan_bank = w.cash_source
					w.state = "idle"
			"freight_pickup", "freight_dropoff":
				simulate_freight(w, delta)
			"drink":
				w.drink_progress += delta
				if w.drink_progress >= DRINK_HOURS * HOUR_SECONDS - 0.000001:
					w.water -= 1
					record_resource_use("clean_water", 1)
					w.water_effect = WATER_EFFECT_HOURS * HOUR_SECONDS
					w.state = w.drink_resume
					w.drink_resume = ""
					w.drink_progress = 0.0
			"sleep":
				var recovery := SLEEP_RECOVERY_PER_HOUR
				var bed_seconds := 0.0
				if beds.has(w.bed):
					var bed: Dictionary = beds[w.bed]
					recovery = BED_RECOVERY_PER_HOUR
					bed_seconds = minf(delta, minf(bed.remaining, w.fatigue / recovery * HOUR_SECONDS))
					bed.remaining = maxf(0, bed.remaining - delta)
					if bed.remaining <= 0:
						release_bed(w)
				var sleep_seconds := minf(delta, w.fatigue / recovery * HOUR_SECONDS)
				rest_experiences.append({"worker": w, "pos": w.pos,
					"hours": sleep_seconds / HOUR_SECONDS, "bed_hours": bed_seconds / HOUR_SECONDS})
				w.fatigue = maxf(0.0, w.fatigue - recovery * delta / HOUR_SECONDS)
				if w.fatigue < 0.000001:
					release_bed(w)
					w.fatigue = 0.0
					if w.carry > 0:
						start_haul(w)
					elif daily_budget_ready(w):
						w.state = "idle"
						start_meal(w)
					else:
						w.state = "idle"
			"idle":
				if dispatch_timer >= 0.2:
					assign_job(w)
			"walk":
				if move_worker(w, delta):
					w.state = "dig"
			"to_build":
				if move_worker(w, delta):
					w.state = "build"
			"to_work":
				if move_worker(w, delta):
					w.state = "work"
			"work":
				if benches.has(w.station):
					var bench: Dictionary = benches[w.station]
					if bench.kind in OPERATED_KINDS:
						was_working = operate_station(w, delta)
						# Continuous duty and drilling have their own completion rules.
					else:
						work_product(w, delta, printed_workers)
			"to_shop":
				if move_worker(w, delta):
					if benches.has(w.station):
						var product: Dictionary = PRODUCTS[building_kind(w.station)]
						var price := sale_price(w.station)
						if building_kind(w.station) == "purifier":
							var amount := water_purchase_count(w, benches[w.station].stock, w.water_purchase_limit, w.water_purchase_optional, price)
							benches[w.station].stock -= amount
							w.water += amount
							w.bread -= amount * price
							w.shop_spent_today += amount * price
							add_stock(w.station, "bread", amount * price)
						elif product.has("durability") and benches[w.station].stock > 0 and w.bread >= price and w[product.durability] == 0:
							benches[w.station].stock -= 1
							w.bread -= price
							w.shop_spent_today += price
							add_stock(w.station, "bread", price)
							w[product.durability] = product.uses
					w.station = null
					w.state = "idle"
			"build":
				if sites.has(w.building):
					var task: Dictionary = sites[w.building]
					pay_labor(w, task, delta)
					if task.progress >= task.seconds - 0.000001:
						if PRODUCTS.has(task.kind):
							benches[w.building] = production_station(task.kind)
						elif task.kind == "bank":
							banks[w.building] = {"interest_received": 0.0}
						elif task.kind in BELT_KINDS:
							belts[w.building] = {"kind": task.kind, "direction": task.direction, "inputs": task.inputs, "cargo": -1, "last_input": -1, "materials": task.materials}
						elif task.kind in LINE_KINDS:
							power_lines[w.building] = {"kind": task.kind, "axis": task.axis, "materials": task.materials.duplicate()}
						elif NEW_BUILDINGS.has(task.kind):
							benches[w.building] = production_station(task.kind)
							if task.kind == "fountain":
								benches[w.building].water_day = day
						else:
							beds[w.building] = {"owner": -1, "remaining": 0.0, "assigned": -1}
						for item in task.materials:
							add_stock(w.building, item, -task.materials[item])
							record_resource_use(item, task.materials[item])
						sites.erase(w.building)
						w.building = null
						w.state = "idle"
			"to_bed":
				if move_worker(w, delta):
					w.bread -= BED_PRICE
					w.bed_spent_today += BED_PRICE
					add_stock(w.bed, "bread", BED_PRICE)
					beds[w.bed].remaining = BED_LEASE_HOURS * HOUR_SECONDS
					w.state = "sleep"
			"dig":
				var target: Vector2i = w.job
				var rate := GUN_MINING_RATE if w.gun_uses > 0 else 1.0
				pay_labor(w, mining_contracts[target], delta, rate)
				w.progress = mining_contracts[target].progress
				if w.progress >= mining_seconds(target) - 0.000001:
					if w.gun_uses == 1:
						record_resource_use("bench", 1)
					w.gun_uses = maxi(0, w.gun_uses - 1)
					record_resource_output(terrain[target], 1)
					if w.carry == 0:
						w.carry = terrain[target]
					else:
						w.extra_cargo.append(terrain[target])
					terrain[target] = 0
					world_view.block_changed(target)
					navigation.set_point_solid(target, false)
					jobs.erase(target)
					world_view.sync_orders()
					mining_contracts.erase(target)
					mined += 1
					if not daily_mined.has(day):
						daily_mined[day] = {}
					daily_mined[day][w.id] = daily_mined[day].get(w.id, 0) + 1
					w.job = null
					update_fog()
					w.state = "idle"
					assign_job(w)
			"haul", "deposit":
				simulate_mined_delivery(w, delta)
			"to_meal":
				if building_kind(w.canteen) != "canteen" or w.path.any(func(cell): return terrain.get(cell, 1) != 0 or water_sources.has(cell)):
					release_meal_seat(w)
					w.path = []
					w.state = "eat"
				elif move_worker(w, delta):
					w.state = "eat"
			"eat":
				var meal_fraction := minf(delta, MEAL_SECONDS - w.progress) / MEAL_SECONDS
				if building_kind(w.canteen) == "canteen" and w.meal_seat != null and w.pos.distance_to(Vector2(w.meal_seat)) < 0.01:
					w.fatigue = maxf(0.0, w.fatigue - CANTEEN_RECOVERY * meal_fraction)
				rest_experiences.append({"worker": w, "pos": w.pos,
					"meal_fraction": meal_fraction,
					"comfortable": has_powered_effect(w.pos, "fountain")})
				w.progress += delta
				if w.progress >= MEAL_SECONDS - 0.0000001:
					w.hunger = minf(MAX_HUNGER, w.hunger + w.meal_bread * HUNGER_PER_BREAD)
					w.eaten_today += w.meal_bread
					record_resource_use("bread", w.meal_bread)
					w.meal_bread = 0
					release_meal_seat(w)
					w.state = "rest" if can_rest(w) else "idle"
					w.progress = 0.0
			"rest":
				if dispatch_timer >= 0.2:
					if not can_rest(w):
						w.pos = w.pos.round()
						w.path = []
						w.state = "idle"
						assign_job(w)
					else:
						if not try_shop_trip(w):
							try_water_trip(w, true)
				if w.state == "rest":
					wander(w, delta)
		if was_working:
			w.fatigue = minf(100.0, w.fatigue + FATIGUE_PER_HOUR * (delta - refreshed_seconds * WATER_FATIGUE_REDUCTION) / HOUR_SECONDS)
			if w.fatigue >= 100.0 - 0.000001:
				w.fatigue = 100.0
				start_sleep(w)
			elif w.payroll <= 0.000001 and w.state in ["dig", "build", "work"]:
				release_work(w)
				w.state = "idle"
			elif daily_budget_ready(w) and (can_rest(w) or needs_meal(w)) and w.state in ["dig", "build", "work"]:
				release_work(w)
				w.state = "idle"
				start_meal(w)
		if has_powered_effect(w.pos, "fountain"):
			w.fatigue = maxf(0.0, w.fatigue - 5.0 * delta / HOUR_SECONDS)
	# Apply after all operators have worked so worker iteration order cannot hide noise.
	for experience in rest_experiences:
		var noise := machine_noise_at(experience.pos)
		if experience.has("hours"):
			experience.worker.mood.slept(experience.hours, experience.bed_hours, noise)
		else:
			experience.worker.mood.ate_meal(experience.meal_fraction, experience.comfortable, noise)
	# New workers enter after this step so they cannot work or accrue time before birth.
	for p in printed_workers:
		create_worker(p)
	if not printed_workers.is_empty():
		update_fog()
	if dispatch_timer >= 0.2:
		dispatch_timer = 0.0
	fog_timer += delta
	if fog_timer >= 0.15:
		fog_timer = 0.0
		update_fog()

func release_work(w: Dictionary) -> void:
	w.drink_resume = ""
	w.drink_progress = 0.0
	if benches.has(w.station) and not benches[w.station].task.is_empty() and benches[w.station].task.owner == w.id:
		benches[w.station].task.owner = -1
	w.station = null
	if jobs.get(w.job, -1) == w.id:
		jobs[w.job] = -1
	w.job = null
	if sites.has(w.building) and sites[w.building].owner == w.id:
		sites[w.building].owner = -1
	w.building = null
	w.path = []
	w.pos = w.pos.round()
	w.progress = 0.0

func start_sleep(w: Dictionary) -> void:
	if w.state in ["sleep", "to_bed"]:
		return
	if w.state in ["eat", "to_meal"]:
		w.bread += w.meal_bread
		w.meal_bread = 0
		release_meal_seat(w)
	release_work(w)
	w.state = "sleep"
	w.used_bed_this_sleep = false
	try_sleep_in_bed(w)

func assign_bed(p: Vector2i, worker_id: int) -> void:
	if not beds.has(p) or worker_id < -1 or worker_id >= workers.size():
		return
	for other in beds:
		if worker_id >= 0 and beds[other].assigned == worker_id:
			beds[other].assigned = -1
	beds[p].assigned = worker_id

func try_sleep_in_bed(w: Dictionary) -> bool:
	if w.bread < BED_PRICE and try_borrow(w):
		return true
	if w.bread < BED_PRICE or beds.has(w.bed):
		return false
	var selected = null
	var best_path: Array[Vector2i] = []
	var preferred = null
	for p in beds:
		if beds[p].assigned == w.id:
			preferred = p
	for p in beds:
		var assigned: int = beds[p].assigned
		if beds[p].owner != -1 or (assigned >= 0 and assigned != w.id):
			continue
		if preferred != null and p != preferred:
			continue
		var path := route(Vector2i(w.pos.round()), p)
		if path.is_empty() and Vector2i(w.pos.round()) != p:
			continue
		if selected == null or path.size() < best_path.size():
			selected = p
			best_path = path
	if selected == null:
		return false
	beds[selected].owner = w.id
	w.bed = selected
	w.path = best_path
	w.used_bed_this_sleep = true
	w.state = "to_bed"
	return true

func release_bed(w: Dictionary) -> void:
	if beds.has(w.bed) and beds[w.bed].owner == w.id:
		beds[w.bed].owner = -1
		beds[w.bed].remaining = 0.0
	w.bed = null

func action_for(w: Dictionary) -> String:
	if w.state == "work" and building_kind(w.station) == "drill" and not powered_devices.has(w.station):
		return "等待"
	match w.state:
		"dig": return "挖掘"
		"work", "build", "deposit": return "工作"
		"haul", "freight_pickup", "freight_dropoff": return "搬运"
		"walk", "to_build", "to_bed", "to_work", "to_shop", "to_payroll", "to_bank": return "通勤"
		"eat", "to_meal": return "吃饭"
		"drink": return "吃饭"
		"sleep": return "睡觉"
		"idle": return "等待" if not jobs.is_empty() else "空闲"
	return "空闲"

# 日报按动作累计游戏人时；挖掘数量在矿块完成时归属工人及日期，交付只改变库存。
func record_action(w: Dictionary, delta: float) -> void:
	if not daily_records.has(day):
		daily_records[day] = {}
	if not daily_records[day].has(w.id):
		daily_records[day][w.id] = empty_totals()
	daily_records[day][w.id][action_for(w)] += delta

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
	jobs[p] = -1
	return true

func cancel_mining_order(p: Vector2i) -> void:
	var owner: int = jobs[p]
	if owner >= 0:
		var w: Dictionary = workers[owner]
		release_work(w)
		w.state = "idle"
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
		var worker_id: int = jobs.get(p, -1)
		status = "挖掘中" if worker_id >= 0 and workers[worker_id].state == "dig" else "等待挖掘"
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
	return "使用费  %.0f 面包 / %.0fh\n疲劳恢复  −%.0f / h" % [
		BED_PRICE, BED_LEASE_HOURS, BED_RECOVERY_PER_HOUR]

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
	if value in BUILDING_KINDS and not can_afford_building(value):
		return
	if value != tool:
		cancel_placement()
	tool = value
	if value in BUILDING_KINDS and is_instance_valid(build_tray):
		build_tray.show()
		furniture_button.button_pressed = true
	for name_ in tool_buttons:
		tool_buttons[name_].button_pressed = name_ == value

func update_build_availability() -> void:
	for kind in BUILDING_KINDS:
		if tool_buttons.has(kind):
			tool_buttons[kind].disabled = not can_afford_building(kind)
	if tool in BUILDING_KINDS and not can_afford_building(tool):
		set_tool("dig")

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
	for collection in [stores, benches]:
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

func request_delivery(target: Vector2i, item, amount: float) -> void:
	var remaining := maxf(0.0, amount - stock_at(target, item) - incoming(target, item))
	for source in stock_locations():
		if source == target or delivery_route(source, target).path.is_empty():
			continue
		while remaining > 0.000001 and available_at(source, item) > 0.000001:
			var moved := minf(FREIGHT_CAPACITY, minf(remaining, available_at(source, item)))
			reserve_shipment(source, target, item, moved)
			remaining -= moved

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

func prepare_deliveries() -> void:
	for p in benches:
		var bench: Dictionary = benches[p]
		if not PRODUCTS.has(bench.kind) or not has_production_order(p) or not bench.task.is_empty() or bench.growth > 0:
			continue
		var recipe := production_materials(building_kind(p))
		for item in recipe:
			if not is_same(item, 0):
				request_delivery(p, item, recipe[item])
		if recipe.has(0):
			var needed: float = recipe[0]
			for ore in range(1, ORES.size()):
				needed -= stock_at(p, ore) + incoming(p, ore)
			for ore in [1, 4, 3, 2]:
				var count := minf(maxf(0, needed), total_stock(ore))
				request_delivery(p, ore, stock_at(p, ore) + incoming(p, ore) + count)
				needed -= count
	for p in banks:
		request_delivery(p, "bread", LOAN_LIMIT)
	for p in benches:
		if benches[p].kind == "power_plant":
			var fuel := stock_at(p, 3) + incoming(p, 3)
			if fuel <= 1.0:
				request_delivery(p, 3, fuel + 2.0)
		elif benches[p].kind == "fountain" and benches[p].water_day != day:
			request_delivery(p, "raw_water", FOUNTAIN_WATER)
	recover_cancelled_sites()

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

func assign_freight(w: Dictionary) -> bool:
	for shipment in shipments:
		if shipment.owner >= 0 or shipment.get("on_belt", false):
			continue
		if route(Vector2i(w.pos.round()), shipment.source).is_empty() or delivery_route(shipment.source, shipment.target).path.is_empty():
			continue
		shipment.owner = w.id
		w.freight = shipment
		resume_freight(w)
		return true
	return false

func resume_freight(w: Dictionary, use_belts := true) -> void:
	var start := Vector2i(w.pos.round())
	if w.freight.picked:
		var leg := delivery_route(start, w.freight.target, use_belts)
		w.haul_target = leg.stop
		w.path = leg.path
	else:
		w.haul_target = w.freight.source
		w.path = route(start, w.freight.source)
	w.state = "freight_dropoff" if w.freight.picked else "freight_pickup"
	if w.path.is_empty():
		w.state = "idle"

func simulate_freight(w: Dictionary, delta: float) -> void:
	if not move_worker(w, delta):
		return
	if w.pos.distance_to(Vector2(w.haul_target)) >= 0.01:
		resume_freight(w)
		return
	var shipment: Dictionary = w.freight
	if not shipment.picked:
		shipment.picked = true
		resume_freight(w)
		return
	if w.haul_target == shipment.target:
		complete_delivery(shipment)
	elif not load_belt(w, shipment, w.haul_target):
		resume_freight(w, false)
		return
	w.freight = {}
	w.state = "idle"

func simulate_mined_delivery(w: Dictionary, delta: float) -> void:
	if w.state == "haul":
		if move_worker(w, delta):
			if w.pos.distance_to(Vector2(w.haul_target)) < 0.01:
				w.state = "deposit"
				w.progress = 0.0
			else:
				start_haul(w, false)
		return
	w.progress += delta
	if w.progress < 0.6 - 0.0000001:
		return
	if w.haul_target != BASE:
		if not load_belt(w, mined_delivery(w), w.haul_target):
			start_haul(w, false)
			return
		if w.carry > 0:
			w.progress = 0.0
			return
	else:
		while w.carry > 0:
			var delivery := mined_delivery(w)
			take_carried_ore(w)
			complete_delivery(delivery)
	w.state = "idle"
	if daily_budget_ready(w):
		start_meal(w)

# 工人到有货的建筑补充工厂随身款，劳动时才领取工资；款项不足且无可达库存时等待。
func prepare_payroll(w: Dictionary) -> bool:
	if w.payroll > 0.000001:
		return true
	var closest = null
	var best: Array[Vector2i] = []
	for p in stock_locations():
		if stock_at(p, "bread") <= 0.000001:
			continue
		var path := route(Vector2i(w.pos.round()), p)
		if not path.is_empty() and (closest == null or path.size() < best.size()):
			closest = p
			best = path
	if closest != null:
		w.cash_source = closest
		w.path = best
		w.state = "to_payroll"
	return false

func work_product(w: Dictionary, delta: float, printed_workers: Array[Vector2i]) -> void:
	var bench: Dictionary = benches[w.station]
	pay_labor(w, bench.task, delta)
	if bench.task.progress < bench.task.seconds - 0.000001:
		return
	if bench.kind == "printer":
		printed_workers.append(w.station + Vector2i.RIGHT)
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
	w.station = null
	w.state = "idle"

# Growth releases the operator; harvest is a new paid hour, even after a stop order.
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
		if terrain[target] >= 5 and (jobs[target] == -1 or jobs[target] == worker_id) and in_effect_range(p, Vector2(target), DRILL_RADIUS):
			return target
	return null

func station_staffed(p: Vector2i) -> bool:
	var task: Dictionary = benches[p].task
	if task.is_empty() or task.owner < 0 or task.owner >= workers.size():
		return false
	var w: Dictionary = workers[task.owner]
	return w.station == p and w.state == "work" and w.payroll > 0.000001 and w.fatigue < 100.0

func power_demand(p: Vector2i) -> float:
	match building_kind(p):
		"grow_light", "spotlight", "daylight": return 200.0
		"fountain": return 200.0 if benches[p].water_day == day else 0.0
		"drill":
			var owner: int = benches[p].task.get("owner", -1)
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
		var remaining := load
		while remaining > 0.000001:
			var path := power_route(residual, "source", power_key(p) + ":in")
			if path.is_empty(): break
			var flow := remaining
			for i in range(path.size() - 1):
				flow = minf(flow, residual[path[i]][path[i + 1]])
			for i in range(path.size() - 1):
				residual[path[i]][path[i + 1]] -= flow
				residual[path[i + 1]][path[i]] += flow
			remaining -= flow
		if remaining > 0.000001:
			residual = before
		else:
			powered_devices[p] = true
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

func operate_station(w: Dictionary, delta: float) -> bool:
	var p: Vector2i = w.station
	var bench: Dictionary = benches[p]
	if not operation_needed(p):
		release_work(w)
		w.state = "idle"
		return false
	if bench.kind != "drill":
		pay_labor(w, bench.task, delta)
		if bench.task.progress >= bench.task.seconds - 0.000001:
			bench.task = contract(1.0)
			if w.mood.accepts_work(bench.kind):
				bench.task.owner = w.id
			else:
				release_work(w)
				w.state = "idle"
		return true
	if not powered_devices.has(p):
		return false
	var target = w.job if jobs.get(w.job, -1) == w.id else drill_target(p, w.id)
	if target == null:
		return false
	w.job = target
	jobs[target] = w.id
	var task: Dictionary = mining_contracts[target]
	pay_labor(w, task, delta)
	if task.progress >= task.seconds - 0.000001:
		var item: int = ORES[terrain[target]].item
		add_stock(p, item, 1)
		record_resource_output(item, 1)
		mined += 1
		if not daily_mined.has(day): daily_mined[day] = {}
		daily_mined[day][w.id] = daily_mined[day].get(w.id, 0) + 1
		mining_contracts[target] = contract(DRILL_HOURS)
		jobs[target] = -1
		w.job = null
		if not w.mood.accepts_work(bench.kind):
			release_work(w)
			w.state = "idle"
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
		if not shipment.get("on_belt", false):
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
