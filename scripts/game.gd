extends Node2D

signal personal_item_event(worker_id: int, kind: String, item: String, amount: float)

const CELL := 40.0
const BASE := Vector2i(32, 13)
const VISION_RADIUS := 9
const DAY_SECONDS := 180.0
# 面包兼作食物和支付物。饱食度全天衰减，最低为零；出生时满饱食，不增加实物面包。
const MEAL_SECONDS := 2.0
const HUNGER_PER_BREAD := 10.0
const MAX_HUNGER := 180.0
const STARTING_HUNGER := MAX_HUNGER
const HUNGER_DECAY_PER_DAY := 80.0
# 挖掘、建造与生产增加疲劳，通勤和搬运不增加；疲劳提高睡眠意愿，满后强制休息。
const MAX_FATIGUE := 180.0
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
const FOUNTAIN_RECOVERY_PER_HOUR := 5.0
const PAYROLL_COLLECTION := 4.0
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
const RESOURCE_ITEMS := [1, 2, 3, 4, 7, 8, "bread", "wheat", "raw_water", "clean_water", "bench", "workbench", "wool", "cloth", "clothes", "ale", "iron", "planks", "tools", "meat", "chemicals", "cleaner", "medical", "wastewater"]
const PROCESSING_KINDS := ["bench", "workbench", "purifier", "mill", "weaver", "tailor", "brewery", "smelter", "sawmill", "smithy", "chemical_plant", "soapworks", "pharmacy"]
const WASH_HOURS := 0.5
const BATH_HOURS := 0.5
const BATH_PRICE := 2.0
const BATH_MATERIALS := {"clean_water": 1, "cleaner": 1, 3: 1}
const SERVICES := {
	"bathhouse": {"slot": "bath", "action": "沐浴", "hours": BATH_HOURS, "price": BATH_PRICE, "recovery": 50.0, "materials": BATH_MATERIALS},
	"laundry": {"slot": "wash", "action": "洗衣", "hours": WASH_HOURS, "price": 2.0, "recovery": 50.0, "materials": {"clean_water": 1, "cleaner": 1}},
	"hospital": {"slot": "treat", "action": "诊疗", "hours": 1.0, "price": 4.0, "recovery": 50.0, "materials": {"medical": 1}},
}
const SHEEP_GROWTH_HOURS := 12.0
const SHEEP_MEAT := 6
const MEAT_HUNGER := 20.0
const ITEM_USES := {
	"bench": {"slot": "gun_uses", "uses": GUN_USES},
	"workbench": {"slot": "backpack_uses", "uses": BACKPACK_USES},
	"clothes": {"slot": "clothes", "uses": 72.0 * HOUR_SECONDS},
	"tools": {"slot": "tools", "uses": 12},
}
const MEAT_PRODUCT := {"name": "肉", "unit": "份", "price": 1.0, "item": "meat"}
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
	"storage_box": {"name": "储物箱", "materials": {7: 4}, "hours": 2.0},
	"barn": {"name": "畜棚", "materials": {1: 8, 7: 4}, "hours": 4.0},
	"mill": {"name": "磨房", "materials": {1: 6, 4: 2}, "hours": 4.0},
	"weaver": {"name": "纺织坊", "materials": {1: 4, 7: 4}, "hours": 4.0},
	"tailor": {"name": "裁缝铺", "materials": {1: 4, "planks": 2}, "hours": 4.0},
	"brewery": {"name": "酿酒坊", "materials": {1: 6, "planks": 2}, "hours": 4.0},
	"smelter": {"name": "熔炉", "materials": {1: 8, 4: 4}, "hours": 6.0},
	"sawmill": {"name": "锯木厂", "materials": {1: 6, 7: 2}, "hours": 4.0},
	"smithy": {"name": "铁匠铺", "materials": {1: 6, "iron": 2}, "hours": 4.0},
	"chemical_plant": {"name": "化工厂", "materials": {1: 8, "iron": 2}, "hours": 6.0},
	"soapworks": {"name": "日化厂", "materials": {1: 6, "planks": 2}, "hours": 4.0},
	"bathhouse": {"name": "澡堂", "materials": {1: 8, "planks": 2}, "hours": 4.0},
	"laundry": {"name": "洗衣房", "materials": {1: 8, "planks": 2}, "hours": 4.0},
	"pharmacy": {"name": "制药厂", "materials": {1: 8, "iron": 2}, "hours": 6.0},
	"hospital": {"name": "医院", "materials": {1: 10, "planks": 2}, "hours": 6.0},
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
const BUILDING_KINDS := ["bed", "bench", "workbench", "pump", "purifier", "printer", "bank", "belt", "farm", "power_plant", "high_line", "low_line", "transformer", "grow_light", "fountain", "electric_belt", "drill", "manual_generator", "spotlight", "daylight", "canteen", "mill", "barn", "weaver", "tailor", "brewery", "smelter", "sawmill", "smithy", "chemical_plant", "soapworks", "bathhouse", "laundry", "pharmacy", "hospital", "storage_box"]
# 生产批次的产物、工时与售价；原料见 production_materials，建材见 building_materials。
const PRODUCTS := {
	"mill": {"name": "面包", "unit": "份", "hours": 2.0, "amount": 8, "item": "bread", "materials": {"wheat": 4}},
	"barn": {"name": "羊毛", "unit": "份", "hours": 2.0, "amount": 2, "item": "wool", "materials": {"wheat": 2, "raw_water": 2}},
	"weaver": {"name": "布", "unit": "匹", "hours": 2.0, "amount": 2, "item": "cloth", "materials": {"wool": 2}},
	"tailor": {"name": "衣物", "unit": "件", "hours": 2.0, "amount": 1, "item": "clothes", "price": 4.0, "materials": {"cloth": 2}},
	"brewery": {"name": "麦酒", "unit": "份", "hours": 2.0, "amount": 4, "item": "ale", "price": 2.0, "materials": {"wheat": 2, "raw_water": 2}},
	"smelter": {"name": "铁锭", "unit": "块", "hours": 2.0, "amount": 2, "item": "iron", "materials": {8: 2, 3: 1}},
	"sawmill": {"name": "木板", "unit": "块", "hours": 1.0, "amount": 2, "item": "planks", "materials": {7: 1}},
	"smithy": {"name": "铁工具", "unit": "套", "hours": 2.0, "amount": 1, "item": "tools", "price": 5.0, "materials": {"iron": 1, "planks": 1}},
	"chemical_plant": {"name": "基础化学品", "unit": "份", "hours": 2.0, "amount": 4, "item": "chemicals", "materials": {3: 2, "raw_water": 2}},
	"soapworks": {"name": "清洁用品", "unit": "份", "hours": 2.0, "amount": 4, "item": "cleaner", "materials": {"chemicals": 2, "raw_water": 2}},
	"pharmacy": {"name": "医疗用品", "unit": "份", "hours": 2.0, "amount": 4, "item": "medical", "materials": {"chemicals": 2, "raw_water": 2, "cloth": 1}},
	"farm": {"name": "小麦", "unit": "份", "hours": 2.0, "amount": 8, "item": "wheat"},
	"bench": {"name": "矿枪", "unit": "把", "hours": GUN_WORK_HOURS, "price": GUN_PRICE, "uses": GUN_USES, "durability": "gun_uses"},
	"workbench": {"name": "背包", "unit": "个", "hours": BACKPACK_WORK_HOURS, "price": BACKPACK_PRICE, "uses": BACKPACK_USES, "durability": "backpack_uses"},
	"pump": {"name": "原水", "unit": "份", "hours": WATER_WORK_HOURS, "amount": WATER_BATCH},
	"purifier": {"name": "清水", "unit": "份", "hours": WATER_WORK_HOURS, "amount": WATER_BATCH, "price": WATER_PRICE},
	"printer": {"name": "工人", "unit": "名", "hours": PRINT_WORKER_HOURS},
}
const MapGenerator = preload("res://scripts/map_generator.gd")
const WorldState = preload("res://scripts/world_state.gd")
const WorldCache = preload("res://scripts/world_cache.gd")
const InteractionState = preload("res://scripts/view/interaction_state.gd")
const WorldSnapshot = preload("res://scripts/persistence/world_snapshot.gd")
const SaveStore = preload("res://scripts/persistence/save_store.gd")
const WorkerMood = preload("res://scripts/worker_mood.gd")
const WorkerBuffs = preload("res://scripts/simulation/worker_buffs.gd")
const Pollution = preload("res://scripts/simulation/pollution.gd")
const WorkerStateTree = preload("res://scripts/simulation/worker_state_tree.gd")
const ActivityRecord = preload("res://scripts/simulation/activity_record.gd")
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
	{"name": "木材", "color": Color("#8b9860"), "time": 7.5},
	{"name": "铁矿", "color": Color("#83a1a3"), "time": 9.0},
	{"name": "水方块", "color": Color("#68c5d5"), "time": 2.4, "item": "clean_water"},
]

var world := WorldState.new()
var cache := WorldCache.new()
var interaction := InteractionState.new()
var simulating := false

# Aggregates are queries, not another balance or inventory to save.
var player_bread: float:
	get:
		var total := total_stock("bread")
		for shipment in world.shipments:
			if is_same(shipment.item, "bread"):
				total += shipment.amount
		for w in world.workers:
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
var ai_trace := WorkerTrace.new()
@onready var world_view: Node2D = $World
@onready var hud: CanvasLayer = $UI

func _ready() -> void:
	ai_trace.configure(OS.get_cmdline_user_args())
	world.smart_objects.tracing = ai_trace.enabled
	world.smart_objects.traced.connect(trace_smart_object)
	get_viewport().physics_object_picking = true
	get_viewport().physics_object_picking_sort = true
	get_viewport().physics_object_picking_first_only = true
	hud.build_ui(self)
	reset_world()

func reset_world(new_seed: int = -1) -> void:
	world_view.initialized = false
	world.reset(randi() if new_seed == -1 else new_seed, BASE, STARTING_BREAD)
	cache.reset(world.world_seed, Rect2i(BASE - Vector2i(4, 2), Vector2i(9, 5)))
	interaction.reset()
	ai_trace.reset(self)
	hud.reset_screen()
	set_tool("dig")
	generate_terrain()
	for i in 3:
		create_worker(BASE + Vector2i(i - 1, 1))
	sample_inventory()
	world_view.camera.position = tile_center(BASE)
	update_fog()
	update_ui()
	world_view.rebuild(self)

func capture_snapshot() -> Dictionary:
	if simulating: return WorldSnapshot.failure("Wait until the simulation step is complete.", "busy")
	return WorldSnapshot.capture(self)

func restore_snapshot(data: PackedByteArray) -> Dictionary:
	if simulating: return WorldSnapshot.failure("Wait until the simulation step is complete.", "busy")
	var restored := WorldSnapshot.decode(data, BUILDING_KINDS, DAY_SECONDS)
	if not restored.ok: return restored
	# Prepare the new simulation in isolation. No activity entry/exit, wages,
	# exploration or power simulation may run while reconstructing it.
	var next_cache := WorldCache.new()
	next_cache.rebuild(restored.world, Rect2i(BASE - Vector2i(4, 2), Vector2i(9, 5)), restored.sample)
	world_view.initialized = false
	world = restored.world
	cache = next_cache
	world.smart_objects.tracing = ai_trace.enabled
	world.smart_objects.traced.connect(trace_smart_object)
	interaction.reset()
	interaction.speed = restored.view.speed
	interaction.simulation_paused = restored.view.paused
	interaction.pollution_visible = restored.view.pollution
	interaction.view_origin = MapGenerator.chunk_at(Vector2i(restored.view.center.floor())) * MapGenerator.CHUNK_SIZE
	world_view.camera.position = (restored.view.center - Vector2(interaction.view_origin)) * CELL
	world_view.camera.zoom = Vector2.ONE * restored.view.zoom
	ai_trace.reset(self)
	hud.reset_screen()
	hud.sync_speed()
	hud.sync_tool()
	rebuild_power_graph()
	world_view.camera.force_update_scroll()
	world_view.rebuild(self)
	update_ui()
	return {"ok": true}

func save_game(path: String) -> Dictionary:
	var snapshot := capture_snapshot()
	if not snapshot.ok: return snapshot
	return SaveStore.write_save(path, snapshot.data)

func load_game(path: String) -> Dictionary:
	var saved := SaveStore.read_save(path)
	if not saved.ok: return saved
	return restore_snapshot(saved.data)

func generate_terrain() -> void:
	ensure_region(Rect2i(BASE - Vector2i(16, 12), Vector2i(48, 32)))

func ensure_region(area: Rect2i) -> void:
	var first := MapGenerator.chunk_at(area.position)
	var last := MapGenerator.chunk_at(area.end - Vector2i.ONE)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var index := Vector2i(x, y)
			if world.generated_chunks.has(index):
				continue
			var data: PackedByteArray = cache.generator.generate_chunk(index)
			world.generated_chunks[index] = true
			for dy in MapGenerator.CHUNK_SIZE:
				for dx in MapGenerator.CHUNK_SIZE:
					var cell := index * MapGenerator.CHUNK_SIZE + Vector2i(dx, dy)
					# Existing edits and fixtures are never overwritten by lazy generation.
					if world.terrain.has(cell):
						continue
					var material := int(data[dy * MapGenerator.CHUNK_SIZE + dx])
					world.terrain[cell] = 0 if material == MapGenerator.WATER else material
					if material == MapGenerator.WATER:
						world.water_sources[cell] = true
					if material == 0:
						cache.navigation.set_point_solid(cell, false)
			world_view.refresh_chunk(index)

func create_worker(p: Vector2i) -> Dictionary:
	var id := world.workers.size()
	var worker := {"id": id, "name": WORKER_NAMES[id] if id < WORKER_NAMES.size() else "矿工%d" % (id + 1),
		"color": WORKER_COLORS[id % WORKER_COLORS.size()], "pos": Vector2(p), "facing": 1.0,
		"activity": WorkerStateTree.new(), "carry": 0, "extra_cargo": [], "freight": {}, "ore_delivery": {},
		"bread": 0.0, "earned_today": 0.0, "eaten_today": 0.0, "hunger": STARTING_HUNGER, "meal_bread": 0.0,
		"bed_spent_today": 0.0, "shop_spent_today": 0.0, "fatigue": 0.0,
		"gun_uses": 0, "backpack_uses": 0, "water": 0,
		"items": {}, "equipment": {}, "pollution": 0.0, "clothes_pollution": 0.0, "buffs": WorkerBuffs.new(),
		"mood": WorkerMood.new(), "loan_principal": 0.0, "loan_interest": 0.0, "loan_day": 0, "loan_bank": null,
		"unloaded_this_trip": 0, "payroll": 0.0}
	world.workers.append(worker)
	ai_trace.record(self, worker, "simulation", "spawn")
	return worker

func trace_smart_object(worker_id: int, event: String, data: Dictionary) -> void:
	if worker_id >= 0 and worker_id < world.workers.size():
		ai_trace.record(self, world.workers[worker_id], "smart_objects", event, data)

func tile_center(p: Vector2) -> Vector2:
	return (p - Vector2(interaction.view_origin) + Vector2(0.5, 0.5)) * CELL

func tile_corner(p: Vector2i) -> Vector2:
	return Vector2(p - interaction.view_origin) * CELL

func world_cell(point: Vector2) -> Vector2i:
	return Vector2i((point / CELL).floor()) + interaction.view_origin

func rebase_view() -> void:
	if world_view.camera.position.length_squared() < pow(CELL * 256, 2):
		return
	var shift := MapGenerator.chunk_at(Vector2i((world_view.camera.position / CELL).floor())) * MapGenerator.CHUNK_SIZE
	interaction.view_origin += shift
	var offset := Vector2(shift) * CELL
	world_view.camera.position -= offset
	interaction.belt_pointer -= offset
	world_view.reposition()

func in_bounds(p) -> bool:
	return p != null and world.terrain.has(p)

func route(start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	if not in_bounds(start) or not in_bounds(target) or world.terrain[target] != 0 or world.water_sources.has(target):
		return []
	return cache.navigation.get_id_path(start, target)

func has_debt(w: Dictionary) -> bool:
	return w.loan_principal + w.loan_interest > 0.000001

func worker_special_items(w: Dictionary) -> Dictionary:
	# A loan is one personal contract, not physical stock or a second debt balance.
	return {"loan": 1} if has_debt(w) else {}

func receive_income(w: Dictionary, amount: float) -> void:
	# Repayment stays in the carried employer purse; the bank records interest only.
	var repayment := minf(amount * LOAN_REPAYMENT_RATE, w.loan_principal + w.loan_interest)
	var principal := minf(repayment, w.loan_principal)
	var interest := repayment - principal
	w.loan_principal = maxf(0.0, w.loan_principal - principal)
	w.loan_interest = maxf(0.0, w.loan_interest - interest)
	world.portal.repaid_principal += principal
	w.payroll += repayment
	if world.banks.has(w.loan_bank):
		world.banks[w.loan_bank].interest_received += interest
	w.bread += amount - repayment
	w.earned_today += amount
	personal_item_event.emit(w.id, "gain", "bread", amount - repayment)

func cargo_count(w: Dictionary) -> int:
	return (0 if is_same(w.carry, 0) else 1) + w.extra_cargo.size()

func carry_capacity(w: Dictionary) -> int:
	return w.buffs.carry_capacity(w)

# A delivery names its receiver first; walking and tracks are interchangeable transport legs.
func delivery_route(start: Vector2i, target: Vector2i, use_belts := true) -> Dictionary:
	var result := {"stop": target, "path": route(start, target)}
	if use_belts:
		var occupied := belt_occupancy()
		for p in world.belts:
			if occupied.has(p) or belt_destination(p) != target:
				continue
			var path := route(start, p)
			if not path.is_empty() and (result.path.is_empty() or path.size() < result.path.size()):
				result = {"stop": p, "path": path}
	return result

func take_carried_ore(w: Dictionary, item = null):
	var ore = w.carry if item == null else item
	if is_same(ore, w.carry):
		w.carry = w.extra_cargo.pop_front() if not w.extra_cargo.is_empty() else 0
	else:
		var index: int = w.extra_cargo.find(ore)
		if index < 0: return 0
		w.extra_cargo.remove_at(index)
	w.unloaded_this_trip += 1
	if is_same(w.carry, 0):
		if w.unloaded_this_trip >= 2:
			if w.backpack_uses == 1:
				record_resource_use("workbench", 1)
			w.backpack_uses = maxi(0, w.backpack_uses - 1)
		w.unloaded_this_trip = 0
	return ore

func delivery_building_at(cell: Vector2i):
	if cell == BASE:
		return BASE
	for collection in [world.sites, world.benches, world.banks, world.beds]:
		for origin in collection:
			if is_same(collection, world.sites):
				if collection[origin].get("cancelled", false) or building_kind(origin) in BELT_KINDS or building_kind(origin) in LINE_KINDS:
					continue
			if cell in building_cells(origin, building_kind(origin)):
				return origin
	return null

func belt_destination(p: Vector2i):
	var visited: Dictionary = {}
	while world.belts.has(p) and not visited.has(p):
		visited[p] = true
		var direction: Vector2i = world.belts[p].direction
		if direction == Vector2i.ZERO:
			break
		p += direction
		var receiver = delivery_building_at(p)
		if receiver != null:
			return receiver
		if not world.belts.has(p) or -direction not in world.belts[p].inputs:
			break
	return null

# Cargo reserves its destination cell before its rendered movement finishes.
func belt_occupancy() -> Dictionary:
	var occupied: Dictionary = {}
	for id in world.belt_cargo:
		var cell: Vector2i = world.belt_cargo[id].to
		if world.belts.has(cell):
			occupied[cell] = id
	return occupied

func belt_cargo_at(p: Vector2i) -> int:
	if world.belts.has(p):
		for id in world.belt_cargo:
			if world.belt_cargo[id].to == p:
				return id
	return -1

func can_edit_belt(p: Vector2i) -> bool:
	if not world.belts.has(p) or belt_cargo_at(p) >= 0:
		return false
	for cargo in world.belt_cargo.values():
		if cargo.from == p and cargo.progress < 1.0:
			return false
	return true

func remove_belt(p: Vector2i) -> bool:
	if not can_edit_belt(p):
		return false
	return_materials(world.belts[p].materials, p)
	world.sites[p] = contract(BELT_BUILD_HOURS)
	var kind: String = world.belts[p].get("kind", "belt")
	world.sites[p].merge({"kind": kind, "materials": world.belts[p].materials, "cancelled": true, "direction": world.belts[p].direction, "inputs": world.belts[p].inputs})
	world.belts.erase(p)
	recover_cancelled_sites()
	return true

func belt_direction_at(p: Vector2i) -> Vector2i:
	return belt_data(p).get("direction", Vector2i.ZERO)

func belt_data(p: Vector2i, overrides: Dictionary = {}) -> Dictionary:
	if overrides.has(p):
		return overrides[p]
	if world.sites.has(p) and building_kind(p) in BELT_KINDS:
		return world.sites[p]
	return world.belts.get(p, {})

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

func belt_plan_valid(path: Array[Vector2i], line_kind := "belt") -> bool:
	if line_kind not in BELT_KINDS:
		return false
	if path.is_empty() or delivery_building_at(path[0]) != null:
		return false
	var plan := belt_path_plan(path)
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
		if world.belts.has(p) or (world.sites.has(p) and building_kind(p) in BELT_KINDS):
			if world.belts.has(p) and plan[p].direction != world.belts[p].direction and not can_edit_belt(p):
				return false
			continue
		if not building_space_valid(p, line_kind):
			return false
	return true

func place_belt_path(path: Array[Vector2i], line_kind := "belt") -> bool:
	if not belt_plan_valid(path, line_kind):
		return false
	var placed: Array[Vector2i] = []
	for p in path:
		if delivery_building_at(p) == null and not world.belts.has(p) and not world.sites.has(p):
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
	var start := interaction.belt_pointer / CELL + Vector2(interaction.view_origin)
	var end := world_position / CELL + Vector2(interaction.view_origin)
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
		if interaction.belt_path.size() > 1 and cell == interaction.belt_path[-2]:
			interaction.belt_path.pop_back()
		else:
			interaction.belt_path.append(cell)
	interaction.belt_pointer = world_position

func finish_belt_drag(screen_position: Vector2) -> void:
	interaction.belt_drawing = false
	if get_viewport().gui_get_hovered_control() == null:
		var world_position := get_global_transform_with_canvas().affine_inverse() * screen_position
		extend_belt_path(world_position)
		if interaction.belt_path.size() == 1 and building_at(interaction.belt_path[0]):
			select_entity(interaction.belt_path[0])
		else:
			place_belt_path(interaction.belt_path.duplicate(), interaction.tool)
	interaction.belt_path.clear()

func complete_delivery(delivery: Dictionary, fee := 0.0) -> void:
	if not world.shipments.has(delivery):
		return
	add_stock(delivery.target, delivery.item, delivery.amount)
	if is_same(delivery.item, "wastewater"): world.add_waste(delivery.target, delivery.get("pollution", 0.0))
	if delivery.get("mined", false):
		world.delivered += int(delivery.amount)
		if delivery.target == BASE:
			world.portal.input_blocks[delivery.item] = world.portal.input_blocks.get(delivery.item, 0) + int(delivery.amount)
	add_stock(BASE, "bread", fee)
	world.portal.freight_bread += fee
	world.shipments.erase(delivery)
	recover_cancelled_sites()

func load_belt(w: Dictionary, delivery: Dictionary, p: Vector2i) -> bool:
	if not world.belts.has(p) or belt_cargo_at(p) >= 0 or belt_destination(p) != delivery.target:
		return false
	var fee := 0.0
	if delivery.get("mined", false):
		fee = minf(w.bread, BELT_FEE)
		w.bread -= fee
		take_carried_ore(w, delivery.item)
		w.ore_delivery = delivery.get("next_ore", {})
		delivery.erase("next_ore")
		delivery.carried_ore = false
	delivery.on_belt = true
	delivery.owner = -1
	world.belt_cargo[world.next_cargo_id] = {"delivery": delivery, "worker": w.id,
		"from": p, "to": p, "progress": 0.0, "fee": fee}
	world.next_cargo_id += 1
	return true

func simulate_belts(delta: float) -> void:
	for id in world.belt_cargo.keys():
		var cargo: Dictionary = world.belt_cargo[id]
		var carrier: Vector2i = cargo.to if world.belts.has(cargo.to) else cargo.from
		var electric: bool = world.belts.get(carrier, {}).get("kind", "belt") == "electric_belt"
		if electric and not cache.powered_devices.has(carrier):
			continue
		if electric and cargo.from != cargo.to:
			var moving_seconds := minf(delta, maxf(0.0, 1.0 - cargo.progress) / (BELT_SPEED * 1.2))
			Pollution.record_operation(world, carrier, "electric_belt", moving_seconds / delta)
		cargo.progress += delta * BELT_SPEED * (1.2 if electric else 1.0)
		if delivery_building_at(cargo.to) == cargo.delivery.target and cargo.progress >= 1.0:
			complete_delivery(cargo.delivery, cargo.fee)
			world.belt_cargo.erase(id)
	# Resolve against a snapshot so dictionary order cannot move cargo several cells at once.
	var occupied := belt_occupancy()
	var requests: Dictionary = {}
	for p in world.belts:
		var id: int = occupied.get(p, -1)
		if id < 0 or world.belt_cargo[id].progress < 1.0:
			continue
		# Keep the intended receiver across edits; do not enter a broken or redirected branch.
		if belt_destination(p) != world.belt_cargo[id].delivery.target:
			world.belt_cargo[id].progress = 1.0
			continue
		var target: Vector2i = p + world.belts[p].direction
		var receiving: bool = delivery_building_at(target) == world.belt_cargo[id].delivery.target
		if world.belts[p].direction != Vector2i.ZERO and (receiving or (world.belts.has(target) and -world.belts[p].direction in world.belts[target].inputs and not occupied.has(target))):
			if not requests.has(target):
				requests[target] = []
			requests[target].append(p)
		else:
			world.belt_cargo[id].progress = 1.0
	for target in requests:
		var sources: Array = requests[target]
		var chosen: Vector2i = sources[0]
		if world.belts.has(target):
			var last: int = world.belts[target].last_input
			for offset in range(1, 5):
				var index := (last + offset) % DIRS.size()
				var candidate: Vector2i = target + DIRS[index]
				if candidate in sources:
					chosen = candidate
					world.belts[target].last_input = index
					break
		for source in sources:
			if source != chosen:
				world.belt_cargo[occupied[source]].progress = 1.0
		var id: int = occupied[chosen]
		var cargo: Dictionary = world.belt_cargo[id]
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
	if world.terrain[p] in [5, 6]:
		return DRILL_HOURS * HOUR_SECONDS
	return maxf(MIN_MINING_HOURS * HOUR_SECONDS, ORES[world.terrain[p]].time)

func building_at(p: Vector2i) -> bool:
	for origin in world.power_lines:
		if p in building_cells(origin, world.power_lines[origin].kind):
			return true
	for collection in [world.sites, world.beds, world.benches, world.banks, world.belts]:
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
	for site in world.sites.values():
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
	if PRODUCTS.get(kind, {}).has("materials"):
		return PRODUCTS[kind].materials
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

func building_cells(p: Vector2i, kind: String, planned_axis := Vector2i.RIGHT) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [p]
	if kind == "high_line":
		var data: Dictionary = world.sites[p] if world.sites.get(p, {}).get("kind", "") == kind else world.power_lines.get(p, {})
		var axis: Vector2i = data.get("axis", planned_axis)
		cells.append(p + (Vector2i.RIGHT if axis == Vector2i.DOWN else Vector2i.DOWN))
	elif kind not in BELT_KINDS and kind not in ["low_line", "storage_box"]:
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
			if world.water_sources.has(cell + direction):
				return true
	return false

func building_kind(p) -> String:
	if world.sites.has(p):
		return world.sites[p].kind
	if world.banks.has(p):
		return "bank"
	if world.belts.has(p):
		return world.belts[p].get("kind", "belt")
	if world.benches.has(p):
		return world.benches[p].kind
	if world.beds.has(p):
		return "bed"
	return world.power_lines.get(p, {}).get("kind", "")

func building_kind_at(p: Vector2i) -> String:
	for collection in [world.sites, world.beds, world.benches, world.banks, world.belts]:
		for origin in collection:
			if p in building_cells(origin, building_kind(origin)):
				return building_kind(origin)
	for origin in world.power_lines:
		if p in building_cells(origin, world.power_lines[origin].kind):
			return world.power_lines[origin].kind
	return ""

func building_space_valid(p: Vector2i, kind: String, planned_axis := Vector2i.RIGHT) -> bool:
	if kind not in BUILDING_KINDS:
		return false
	if kind == "pump" and not near_water_source(p):
		return false
	for cell in building_cells(p, kind, planned_axis):
		if not in_bounds(cell) or not world.explored.has(cell) or world.water_sources.has(cell) or cell == BASE or world.terrain[cell] in [5, 6]:
			return false
		for collection in [world.sites, world.beds, world.benches, world.banks, world.belts, world.power_lines]:
			for origin in collection:
				var other: String = collection[origin].kind if is_same(collection, world.power_lines) else (collection[origin].get("kind", "belt") if is_same(collection, world.belts) else building_kind(origin))
				if cell not in building_cells(origin, other):
					continue
				# Completed cables and tracks can cross, but two blueprints cannot share a store.
				if not is_same(collection, world.sites) and ((kind in BELT_KINDS and other in LINE_KINDS) or (kind in LINE_KINDS and other in BELT_KINDS)):
					continue
				if kind in LINE_KINDS and kind == other and origin != p:
					continue
				return false
	return true

func site_cleared(p: Vector2i) -> bool:
	for cell in building_cells(p, building_kind(p)):
		if world.terrain[cell] != 0:
			return false
	return true

# 蓝图按数量占用可规划建材，不扣实物或绑定货源；实物到齐、占地清空后才施工。
func place_building(p: Vector2i, kind: String, planned_axis := Vector2i.RIGHT) -> bool:
	if not building_space_valid(p, kind, planned_axis) or not can_plan_building(kind):
		return false
	world.sites[p] = contract(building_hours(kind))
	world.sites[p].kind = kind
	world.sites[p].materials = building_materials(kind).duplicate()
	if kind in BELT_KINDS:
		world.sites[p].direction = Vector2i.ZERO
		world.sites[p].inputs = []
	if kind in LINE_KINDS:
		world.sites[p].axis = Vector2i.DOWN if planned_axis == Vector2i.DOWN else Vector2i.RIGHT
	for cell in building_cells(p, kind):
		if add_mining_order(cell):
			world.mining_contracts[cell].site = p
	world_view.sync_orders()
	update_ui()
	return true

func update_building_drag(cell: Vector2i) -> void:
	interaction.building_end = cell
	var delta := cell - interaction.building_start
	if interaction.building_axis == Vector2i.ZERO and delta != Vector2i.ZERO:
		interaction.building_axis = Vector2i.RIGHT if absi(delta.x) >= absi(delta.y) else Vector2i.DOWN

func building_row() -> Array[Vector2i]:
	var result: Array[Vector2i] = [interaction.building_start]
	if interaction.building_axis == Vector2i.ZERO:
		return result
	var footprint := building_cells(Vector2i.ZERO, interaction.tool, interaction.building_axis)
	var span: Vector2i = footprint.back() + Vector2i.ONE
	var delta := interaction.building_end - interaction.building_start
	var distance := delta.x if interaction.building_axis.x else delta.y
	var stride: int = span.x if interaction.building_axis.x else span.y
	for i in range(1, absi(distance) / stride + 1):
		result.append(interaction.building_start + interaction.building_axis * signi(distance) * stride * i)
	return result

func building_batch_valid(positions: Array[Vector2i], kind: String, planned_axis := Vector2i.RIGHT) -> bool:
	if positions.is_empty():
		return false
	var occupied: Dictionary = {}
	for p in positions:
		if existing_line(p, kind):
			continue
		if not building_space_valid(p, kind, planned_axis):
			return false
		for cell in building_cells(p, kind, planned_axis):
			if occupied.has(cell):
				return false
			occupied[cell] = true
	return true

func place_building_batch(positions: Array[Vector2i], kind: String, planned_axis := Vector2i.RIGHT) -> bool:
	if not building_batch_valid(positions, kind, planned_axis):
		return false
	var placed := false
	for p in positions:
		if not existing_line(p, kind) and not place_building(p, kind, planned_axis):
			break
		placed = true
	return placed

func existing_line(p: Vector2i, kind: String) -> bool:
	return kind in LINE_KINDS and (world.power_lines.get(p, {}).get("kind", "") == kind or world.sites.get(p, {}).get("kind", "") == kind)

func finish_building_drag(screen_position: Vector2) -> void:
	interaction.building_drawing = false
	if get_viewport().gui_get_hovered_control() == null:
		var world_position := get_global_transform_with_canvas().affine_inverse() * screen_position
		update_building_drag(world_cell(world_position))
		if interaction.building_start == interaction.building_end and interaction.building_pick != null and existing_line(interaction.building_pick, interaction.tool):
			interaction.selected_entity = interaction.building_pick
			interaction.selected_line = true
			update_entity_panel()
		else:
			place_building_batch(building_row(), interaction.tool, interaction.building_axis)
	interaction.building_axis = Vector2i.ZERO
	interaction.building_pick = null

func cancel_placement() -> void:
	interaction.belt_drawing = false
	interaction.belt_path.clear()
	interaction.building_drawing = false
	interaction.building_axis = Vector2i.ZERO
	interaction.building_pick = null
	interaction.moving_drill_from = null
	if interaction.tool == "move_drill":
		interaction.tool = "dig"

func begin_drill_move(p: Vector2i) -> void:
	if building_kind(p) == "drill" and world.benches.has(p):
		set_tool("move_drill")
		interaction.moving_drill_from = p

func move_drill_to(target: Vector2i) -> bool:
	var origin = interaction.moving_drill_from
	if not world.benches.has(origin) or not building_space_valid(target, "drill"):
		return false
	for cell in building_cells(target, "drill"):
		if world.terrain[cell] != 0:
			return false
	if route(origin, target).is_empty():
		return false
	# Keep the warehouse at its old location until existing freight is delivered.
	for shipment in world.shipments:
		if shipment.source == origin or shipment.target == origin:
			return false
	var owner := slot_owner("work", origin)
	if owner >= 0:
		world.workers[owner].activity.exit(self, world.workers[owner], "moved")
	world.smart_objects.invalidate(SmartObjects.key("work", origin))
	world.benches[target] = world.benches[origin]
	world.benches.erase(origin)
	if world.stores.has(origin):
		for item in world.stores[origin]:
			add_stock(target, item, world.stores[origin][item])
		world.stores.erase(origin)
	world.add_waste(target, world.wastewater.get(origin, 0.0))
	world.wastewater.erase(origin)
	cache.powered_devices.erase(origin)
	cache.ready_drills.erase(origin)
	set_tool("dig")
	select_entity(target)
	world_view.sync_dynamic()
	return true

func remove_power_line(p: Vector2i) -> bool:
	if not world.power_lines.has(p):
		return false
	return_materials(world.power_lines[p].materials)
	world.power_lines.erase(p)
	cache.powered_devices.clear()
	cache.ready_drills.clear()
	update_ui()
	return true

# 取消时原地解锁未取走的货物，携带中的货物返回来源，已到工地的材料搬回传送门。
func cancel_site(p: Vector2i) -> bool:
	var origin = null
	for candidate in world.sites:
		if p in building_cells(candidate, building_kind(candidate)):
			origin = candidate
			break
	if origin == null:
		return false
	var task: Dictionary = world.sites[origin]
	if task.get("cancelled", false):
		return false
	var owner := slot_owner("build", origin)
	if owner >= 0:
		world.workers[owner].activity.exit(self, world.workers[owner], "cancelled")
	world.smart_objects.invalidate(SmartObjects.key("build", origin))
	task.cancelled = true
	for cell in building_cells(origin, task.kind):
		if world.mining_contracts.get(cell, {}).get("site", null) == origin:
			cancel_mining_order(cell)
	world_view.sync_orders()
	for shipment in world.shipments.duplicate():
		if shipment.target != origin:
			continue
		if shipment.picked:
			shipment.target = shipment.source
			# Carriers and belts replan against the shipment's current receiver.
		else:
			if shipment.owner >= 0:
				var carrier: Dictionary = world.workers[shipment.owner]
				carrier.activity.exit(self, carrier, "cancelled")
				carrier.freight = {}
			release_shipment(shipment)
	recover_cancelled_sites()
	update_ui()
	return true

func uses_daily_output(kind: String) -> bool:
	return PRODUCTS.has(kind) and kind != "printer"

func production_station(kind: String) -> Dictionary:
	var result := {"kind": kind, "queue": 0, "daily_output": 0, "produced_today": 0, "stock": 0, "task": {}, "growth": 0.0, "harvest": false, "water_day": 0}
	if kind == "barn":
		result.merge({"sheep": 1, "slaughter": false})
	return result

func request_slaughter(p: Vector2i) -> void:
	if building_kind(p) == "barn" and world.benches.has(p) and world.benches[p].sheep > 0:
		world.benches[p].slaughter = true

# 日产量跨天保留，完成量按完成当天计入；缺产不累积，销售库存不增加配额。
# 已开工或正在生长的批次完成后才检查新配额；打印仓使用有限待制数量。
func has_production_order(p: Vector2i) -> bool:
	var bench: Dictionary = world.benches[p]
	if bench.kind == "barn" and (bench.sheep <= 0 or bench.slaughter):
		return bench.sheep > 0
	if not bench.task.is_empty() or bench.growth > 0:
		return true
	var kind := building_kind(p)
	if not uses_daily_output(kind):
		return bench.queue > 0
	var amount: int = PRODUCTS[kind].get("amount", 1)
	return bench.produced_today + amount <= bench.daily_output

func adjust_production(p: Vector2i, change: int) -> void:
	if not world.benches.has(p):
		return
	var bench: Dictionary = world.benches[p]
	var kind := building_kind(p)
	if uses_daily_output(kind):
		var amount: int = PRODUCTS[kind].get("amount", 1)
		bench.daily_output = maxi(0, bench.daily_output + change * amount)
	else:
		bench.queue = maxi(0 if bench.task.is_empty() else 1, bench.queue + change)

func product_item(kind: String):
	return PRODUCTS.get(kind, {}).get("item", {"pump": "raw_water", "purifier": "clean_water"}.get(kind, kind))

func shop_goods(p: Vector2i) -> Array:
	if building_kind(p) == "barn": return ["meat"]
	return [product_item(building_kind(p))] if PRODUCTS.get(building_kind(p), {}).has("price") else []

func sale_product(p: Vector2i, item = null) -> Dictionary:
	return MEAT_PRODUCT if item == "meat" else PRODUCTS.get(building_kind(p), {})

func sale_price(p: Vector2i, item = null) -> float:
	return sale_product(p, item).get("price", 0.0) * (1.0 + LIGHT_BONUS if has_powered_effect(Vector2(p), "spotlight") else 1.0)

func station_wage(p) -> float:
	return WAGE_PER_HOUR * (1.0 + LIGHT_BONUS if p != null and world.benches.has(p) and has_powered_effect(Vector2(p), "daylight") else 1.0)

func simulate(delta: float) -> void:
	if simulating: return
	simulating = true
	# Split at midnight so deliveries are credited to the correct day.
	var remaining := delta
	while remaining > 0.0000001:
		var step := minf(0.05, minf(remaining, DAY_SECONDS - world.day_elapsed))
		world.recovery_timer += step
		if world.recovery_timer >= 0.2:
			recover_cancelled_sites()
			world.recovery_timer = 0.0
		world.smart_objects.sync(self)
		world.pollution_operations.clear()
		simulate_power(step)
		simulate_growth(step)
		simulate_belts(step)
		simulate_workers(step)
		cache.pollution.rebuild(self)
		cache.pollution.expose(self, step)
		world.day_elapsed += step
		remaining -= step
		if (world.day - 1) * DAY_SECONDS + world.day_elapsed >= world.inventory_sample_time + HOUR_SECONDS - 0.000001:
			sample_inventory()
		if world.day_elapsed >= DAY_SECONDS - 0.0000001:
			world.day_elapsed = 0.0
			world.day += 1
			world.resource_flows.erase(world.day - 2)
			for p in world.benches:
				if uses_daily_output(building_kind(p)):
					world.benches[p].produced_today = 0
			for w in world.workers:
				w.earned_today = 0
				w.eaten_today = 0
				w.bed_spent_today = 0.0
				w.shop_spent_today = 0.0
	simulating = false

func simulate_workers(delta: float) -> void:
	var experiences: Array[Dictionary] = []
	for w in world.workers:
		w.buffs.advance(delta)
		wear_clothes(w, delta)
		w.mood.advance(delta / HOUR_SECONDS, w.buffs.mood_bonus(w))
		w.hunger = maxf(0.0, w.hunger - HUNGER_DECAY_PER_DAY * delta / DAY_SECONDS)
		var experience: Dictionary = w.activity.tick(self, w, delta)
		if not experience.is_empty():
			experience.worker = w
			experience.pos = w.pos
			experiences.append(experience)
		if has_powered_effect(w.pos, "fountain"):
			w.fatigue = maxf(0, w.fatigue - FOUNTAIN_RECOVERY_PER_HOUR * delta / HOUR_SECONDS)
		ai_trace.observe(self, w)
	for experience in experiences:
		if experience.has("hours"):
			experience.worker.mood.slept(experience.bed_hours)
		else:
			experience.worker.mood.ate_meal(experience.meal_fraction, experience.comfortable)
	for p in world.newborns:
		create_worker(p)
	if not world.newborns.is_empty():
		update_fog()
	world.newborns.clear()
	world.fog_timer += delta
	if world.fog_timer >= 0.15:
		world.fog_timer = 0.0
		update_fog()

func assign_bed(p: Vector2i, worker_id: int) -> void:
	if not world.beds.has(p) or worker_id < -1 or worker_id >= world.workers.size():
		return
	for other in world.beds:
		if worker_id >= 0 and world.beds[other].assigned == worker_id:
			world.beds[other].assigned = -1
	world.beds[p].assigned = worker_id

func action_for(w: Dictionary) -> String:
	return w.activity.report_action(self)

func worker_display(w: Dictionary) -> Dictionary:
	var display := w.duplicate()
	display.merge(w.activity.presentation(self), true)
	return display

func slot_owner(kind: String, p: Vector2i) -> int:
	return world.smart_objects.owner(SmartObjects.key(kind, p))

func record_worker_time(w: Dictionary, action: String, delta: float) -> void:
	if not world.daily_records.has(world.day):
		world.daily_records[world.day] = {}
	if not world.daily_records[world.day].has(w.id):
		world.daily_records[world.day][w.id] = empty_totals()
	world.daily_records[world.day][w.id][action] += maxf(0, delta)

func empty_totals() -> Dictionary:
	var result := {}
	for action in ACTIONS:
		result[action] = 0.0
	return result

func report_totals(report_day: int, worker_id := -1) -> Dictionary:
	var result := empty_totals()
	for id in world.daily_records.get(report_day, {}):
		if worker_id >= 0 and id != worker_id:
			continue
		for action in ACTIONS:
			result[action] += world.daily_records[report_day][id][action]
	return result

func report_mined(report_day: int, worker_id := -1) -> int:
	var counts: Dictionary = world.daily_mined.get(report_day, {})
	if worker_id >= 0:
		return counts.get(worker_id, 0)
	var total := 0
	for count in counts.values():
		total += count
	return total

func open_report() -> void:
	hud.open_report()

func _process(delta: float) -> void:
	var movement := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if not hud.blocks_simulation():
		world_view.camera.position += movement.normalized() * delta * 550.0 / world_view.camera.zoom.x
	rebase_view()
	if not interaction.simulation_paused and not hud.blocks_simulation():
		interaction.animation_time += delta * interaction.speed
		simulate(minf(delta, 0.1) * interaction.speed)
	update_ui()
	world_view.sync_dynamic()

# Workers reveal a circular radius through terrain; exploration persists.
func update_fog() -> void:
	var changed := cache.visible_tiles.duplicate()
	cache.visible_tiles.clear()
	for w in world.workers:
		var origin := Vector2i(w.pos.round())
		ensure_region(Rect2i(origin - Vector2i.ONE * (VISION_RADIUS + 1), Vector2i.ONE * (VISION_RADIUS * 2 + 3)))
		for y in range(-VISION_RADIUS, VISION_RADIUS + 1):
			for x in range(-VISION_RADIUS, VISION_RADIUS + 1):
				var target := origin + Vector2i(x, y)
				if not in_bounds(target) or x * x + y * y > VISION_RADIUS * VISION_RADIUS:
					continue
				cache.visible_tiles[target] = true
				world.explored[target] = true
	changed.merge(cache.visible_tiles, true)
	world_view.sync_fog(changed)

func add_mining_order(p: Vector2i) -> bool:
	if not world.explored.has(p) or world.terrain.get(p, 0) == 0 or world.mining_contracts.has(p):
		return false
	world.mining_contracts[p] = contract(mining_seconds(p) / HOUR_SECONDS)
	return true

func cancel_mining_order(p: Vector2i) -> void:
	var owner := slot_owner("mine", p)
	if owner >= 0:
		world.workers[owner].activity.exit(self, world.workers[owner], "cancelled")
	world.smart_objects.invalidate(SmartObjects.key("mine", p))
	world.mining_contracts.erase(p)

func designate(a: Vector2i, b: Vector2i, cancel := false) -> int:
	var count := 0
	var area := Rect2i(a.min(b), (a - b).abs() + Vector2i.ONE)
	# Iterate known cells rather than an arbitrarily large rectangle across the world.
	for p in world.explored:
		if not area.has_point(p):
			continue
		if cancel and cancel_site(p):
			count += 1
		elif cancel and remove_belt(p):
			count += 1
		if cancel and world.mining_contracts.has(p):
			cancel_mining_order(p)
			count += 1
		elif not cancel:
			if add_mining_order(p):
				count += 1
			if world.mining_contracts.has(p):
				world.mining_contracts[p].erase("site")
	world_view.sync_orders()
	return count

func mouse_tile() -> Vector2i:
	return world_cell(get_global_mouse_position())

func select_entity(p: Vector2i) -> bool:
	interaction.selected_line = false
	interaction.selected_worker = -1
	interaction.selected_tile = null
	interaction.selected_entity = null
	if p == BASE:
		interaction.selected_entity = BASE
	else:
		for collection in [world.beds, world.sites, world.benches, world.banks, world.belts]:
			for origin in collection:
				if p in building_cells(origin, building_kind(origin)):
					interaction.selected_entity = origin
					interaction.selected_line = building_kind(origin) in LINE_KINDS
					break
		if interaction.selected_entity == null:
			for origin in world.power_lines:
				if p in building_cells(origin, world.power_lines[origin].kind):
					interaction.selected_entity = origin
					interaction.selected_line = true
					break
	update_entity_panel()
	return interaction.selected_entity != null

func clear_entity_selection() -> void:
	interaction.selected_line = false
	interaction.selected_worker = -1
	interaction.selected_entity = null
	interaction.selected_tile = null
	update_entity_panel()

func select_tile(p: Vector2i) -> void:
	clear_entity_selection()
	if in_bounds(p) and world.explored.has(p):
		interaction.selected_tile = p
		update_entity_panel()

func tile_details(p: Vector2i) -> Dictionary:
	if not in_bounds(p) or not world.explored.has(p):
		return {}
	if world.water_sources.has(p):
		return {"title": "水源", "text": "不可通行\n可供抽水与灌溉"}
	var ore: int = world.terrain[p]
	if ore in [5, 6]:
		return {"title": ORES[ore].name, "text": "%s\n矿钻开采  %.0fh / 块\n产物  %s × 1\n矿脉可反复开采" % ["已标记开采" if world.mining_contracts.has(p) else "需要矿钻", DRILL_HOURS, item_name(ORES[ore].item)]}
	if ore == 0:
		return {"title": "空地", "text": "可通行"}
	var status := "未标记挖掘"
	if world.mining_contracts.has(p):
		var task: Dictionary = world.mining_contracts[p]
		var worker_id := slot_owner("mine", p)
		status = "挖掘中" if worker_id >= 0 and action_for(world.workers[worker_id]) == "挖掘" else "等待挖掘"
		if task.progress > 0:
			status += "  %.0f%%" % (task.progress / task.seconds * 100)
	return {"title": ORES[ore].name,
		"text": "%s\n开采工时  %.1fh\n产物  %s × 1" % [status, mining_seconds(p) / HOUR_SECONDS, item_name(ORES[ore].get("item", ore))]}

func select_worker(worker_id: int) -> bool:
	if worker_id < 0 or worker_id >= world.workers.size():
		return false
	interaction.selected_worker = worker_id
	interaction.selected_entity = null
	interaction.selected_tile = null
	update_entity_panel()
	return true

func update_entity_panel() -> void:
	hud.update_entity_panel()

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
	if kind == "barn":
		recipe += "\n喂养 1h · 产毛 %.0fh · 剪毛 1h" % SHEEP_GROWTH_HOURS
	return recipe

func building_effects_text(kind: String, p = null) -> String:
	if kind == "storage_box":
		return "存放物品 · 容量不限"
	if SERVICES.has(kind):
		var service: Dictionary = SERVICES[kind]
		var recovery := "衣物" if kind == "laundry" else "身体"
		var text := "%s %.1fh · 收费 %s 面包\n%s污染 -%.0f\n每次消耗  %s" % [service.action, service.hours, String.num(service.price, 1), recovery, service.recovery, material_requirements_text(service.materials)]
		if kind == "bathhouse": text += "\n心情 +%.0f · 持续 %.0fh" % [WorkerBuffs.BATH_MOOD, WorkerBuffs.BATH_EFFECT_HOURS]
		if kind != "hospital": text += "\n产出废水 ×1 · 转移污染减半"
		return text
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
	if kind == "soapworks": return "用于洗衣房与澡堂 · 转移污染减半"
	if kind == "pharmacy": return "用于医院诊疗"
	if kind == "barn":
		return "建成带 1 只羊\n屠宰 1h → 肉 ×%d\n肉售价 %s 面包 · 饱食 +%.0f" % [SHEEP_MEAT, String.num(sale_price(p, "meat") if p != null else MEAT_PRODUCT.price, 1), MEAT_HUNGER]
	if kind in ["tailor", "brewery", "smithy"]:
		var price: float = sale_price(p) if p != null else PRODUCTS[kind].price
		var effect: String = {
			"tailor": "穿着 %.0fh · 洁净时心情 +%.0f\n吸收污染上限 50 · 污染削弱心情加成" % [ITEM_USES.clothes.uses / HOUR_SECONDS, WorkerBuffs.CLOTHES_MOOD],
			"brewery": "疲劳 -%.0f · 酒意 %.0fh\n心情 +%.0f · 工作效率 -%.0f%%" % [WorkerBuffs.ALE_RECOVERY, WorkerBuffs.ALE_HOURS, WorkerBuffs.ALE_MOOD, (1 - WorkerBuffs.ALE_RATE) * 100],
			"smithy": "农田劳动/加工效率 +%.0f%%\n耐久 %d 次劳动阶段" % [(WorkerBuffs.TOOL_RATE - 1) * 100, ITEM_USES.tools.uses],
		}[kind]
		return "售价 %s 面包\n%s" % [String.num(price, 1), effect]
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
	if kind == "bench":
		return "售价  %s 面包\n耐久  %d 格\n挖掘速度  +%.0f%%" % [String.num(sale_price(p) if p != null else GUN_PRICE, 1), GUN_USES, (GUN_MINING_RATE - 1.0) * 100.0]
	return ""

func icon_texture(path: String) -> Texture2D:
	return Art.texture(path)

func _unhandled_input(event: InputEvent) -> void:
	if hud.blocks_simulation(): return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F5: hud.save_current()
			KEY_F9: hud.load_current()
			KEY_SPACE: toggle_pause()
			KEY_G: set_tool("dig")
			KEY_X: set_tool("cancel")
			KEY_HOME: world_view.camera.position = tile_center(BASE)
			KEY_ESCAPE:
				interaction.dragging = false
				cancel_placement()
				clear_entity_selection()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			world_view.camera.zoom = Vector2.ONE * minf(2.2, world_view.camera.zoom.x * 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			world_view.camera.zoom = Vector2.ONE * maxf(0.45, world_view.camera.zoom.x / 1.12)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			interaction.panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if interaction.tool in BUILDING_KINDS:
				if interaction.belt_drawing or interaction.building_drawing:
					cancel_placement()
				else:
					set_tool("dig")
			else:
				set_tool("cancel")
	if event is InputEventMouseMotion:
		if interaction.panning:
			world_view.camera.position -= event.relative / world_view.camera.zoom
		if interaction.dragging:
			interaction.selection_end = mouse_tile()
		if interaction.belt_drawing and get_viewport().gui_get_hovered_control() == null:
			var world_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			extend_belt_path(world_position)
		if interaction.building_drawing and get_viewport().gui_get_hovered_control() == null:
			var world_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			update_building_drag(world_cell(world_position))

func finish_ground_drag(screen_position: Vector2) -> void:
	interaction.dragging = false
	if get_viewport().gui_get_hovered_control() != null:
		return
	var world_position := get_global_transform_with_canvas().affine_inverse() * screen_position
	interaction.selection_end = world_cell(world_position)
	designate(interaction.selection_start, interaction.selection_end, interaction.tool == "cancel")
	if interaction.selection_start == interaction.selection_end:
		select_tile(interaction.selection_end)

func handle_world_input(event: InputEvent, worker_id: int, entity, line := false) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		if interaction.belt_drawing:
			finish_belt_drag(event.position)
		if interaction.building_drawing:
			finish_building_drag(event.position)
		if interaction.dragging:
			finish_ground_drag(event.position)
		return
	if line and interaction.tool == "cancel" and world.power_lines.has(entity):
		remove_power_line(entity)
		get_viewport().set_input_as_handled()
		return
	var belt_entity := entity != null and building_kind(entity) in BELT_KINDS
	var crossing := (line and (interaction.tool in BELT_KINDS or interaction.tool in LINE_KINDS)) or (belt_entity and interaction.tool in LINE_KINDS)
	if interaction.tool != "move_drill" and not crossing and (worker_id >= 0 or (entity != null and not (interaction.tool == "cancel" and (world.sites.has(entity) or world.belts.has(entity))) and not (interaction.tool in BELT_KINDS and belt_entity))):
		interaction.selected_worker = worker_id
		interaction.selected_entity = entity
		interaction.selected_line = line
		interaction.selected_tile = null
		update_entity_panel()
		interaction.dragging = false
	else:
		var world_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var cell := world_cell(world_position)
		clear_entity_selection()
		if interaction.tool == "move_drill":
			move_drill_to(cell)
		elif interaction.tool in BELT_KINDS:
			interaction.belt_drawing = true
			interaction.belt_path = [cell]
			interaction.belt_pointer = world_position
		elif interaction.tool in BUILDING_KINDS:
			interaction.building_drawing = true
			interaction.building_pick = entity if line else null
			interaction.building_start = cell
			interaction.building_end = cell
			interaction.building_axis = Vector2i.ZERO
		else:
			interaction.dragging = true
			interaction.selection_start = cell
			interaction.selection_end = cell
	get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and (interaction.belt_drawing or interaction.building_drawing):
		cancel_placement()
		get_viewport().set_input_as_handled()
	# Release even over a HUD panel, so pointer capture cannot leave a stuck drag.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and interaction.belt_drawing:
			finish_belt_drag(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT and interaction.building_drawing:
			finish_building_drag(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT and interaction.dragging:
			finish_ground_drag(event.position)
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			interaction.panning = false
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_SPACE:
		if event.echo:
			return
		if not hud.blocks_simulation():
			toggle_pause()
			get_viewport().set_input_as_handled()

func set_tool(value: String) -> void:
	if value in BUILDING_KINDS and not can_plan_building(value):
		return
	if value != interaction.tool:
		cancel_placement()
	interaction.tool = value
	hud.sync_tool()

func set_speed(value: int) -> void:
	interaction.speed = float(value)
	hud.sync_speed()

func toggle_pause() -> void:
	interaction.simulation_paused = not interaction.simulation_paused
	hud.sync_pause()

func update_ui() -> void:
	hud.update_ui()

# 每座建筑及传送门有无限容量的仓储，产物留在生产地点；stock 是生产建筑的产物格。
# 预留货物在取货前仍位于来源建筑，取走后由工人携带，送达后才进入目标仓储。
func stock_at(p: Vector2i, item) -> float:
	if world.benches.has(p) and is_same(product_item(building_kind(p)), item):
		return world.benches[p].stock
	return world.stores.get(p, {}).get(item, 0.0)

func add_stock(p: Vector2i, item, amount: float) -> void:
	if world.benches.has(p) and is_same(product_item(building_kind(p)), item):
		world.benches[p].stock = maxf(0.0, world.benches[p].stock + amount)
	else:
		if not world.stores.has(p):
			world.stores[p] = {}
		world.stores[p][item] = maxf(0.0, stock_at(p, item) + amount)

func stock_locations() -> Array:
	var locations: Array = [BASE]
	for collection in [world.stores, world.benches, world.beds, world.banks]:
		for p in collection:
			if p not in locations and not world.sites.has(p):
				locations.append(p)
	return locations

func total_stock(item) -> float:
	var total := 0.0
	for p in stock_locations():
		total += available_at(p, item)
	return total

func available_at(p: Vector2i, item) -> float:
	if world.benches.has(p):
		if world.benches[p].kind == "power_plant" and is_same(item, 3):
			return maxf(0.0, stock_at(p, item) - 2.0)
		if world.benches[p].kind == "fountain" and is_same(item, "raw_water"):
			return maxf(0.0, stock_at(p, item) - FOUNTAIN_WATER)
		if SERVICES.has(world.benches[p].kind) and SERVICES[world.benches[p].kind].materials.has(item):
			return maxf(0.0, stock_at(p, item) - SERVICES[world.benches[p].kind].materials[item])
	if world.benches.has(p) and has_production_order(p):
		var recipe := production_materials(building_kind(p))
		if recipe.has(item) or (item is int and recipe.has(0)):
			return 0.0
	return stock_at(p, item)

func item_name(item) -> String:
	if item is int:
		return ORES[item].name
	return {"bread": "面包", "wheat": "小麦", "raw_water": "原水",
		"clean_water": "清水", "bench": "矿枪", "workbench": "背包", "wool": "羊毛", "cloth": "布", "clothes": "衣物", "ale": "麦酒", "iron": "铁锭", "planks": "木板", "tools": "铁工具", "meat": "肉", "loan": "贷款", "chemicals": "基础化学品", "cleaner": "清洁用品", "medical": "医疗用品", "wastewater": "废水"}.get(item, str(item))

func storage_contents(p: Vector2i) -> Dictionary:
	var contents: Dictionary = world.stores.get(p, {}).duplicate()
	if world.benches.has(p) and PRODUCTS.has(building_kind(p)) and building_kind(p) != "printer":
		var item = product_item(building_kind(p))
		contents[item] = stock_at(p, item)
	for shipment in world.shipments:
		if not shipment.picked and shipment.source == p:
			contents[shipment.item] = contents.get(shipment.item, 0.0) + shipment.amount
	return contents

func incoming(p: Vector2i, item) -> float:
	var amount := 0.0
	for shipment in world.shipments:
		if shipment.target == p and is_same(shipment.item, item):
			amount += shipment.amount
	return amount

func reserve_shipment(source: Vector2i, target: Vector2i, item, amount: float) -> void:
	var load := world.take_waste(source, amount, stock_at(source, item)) if is_same(item, "wastewater") else 0.0
	add_stock(source, item, -amount)
	world.shipments.append({"source": source, "target": target, "item": item,
		"amount": amount, "owner": -1, "picked": false, "pollution": load})

func release_shipment(shipment: Dictionary) -> void:
	if world.shipments.has(shipment) and not shipment.picked:
		add_stock(shipment.source, shipment.item, shipment.amount)
		if is_same(shipment.item, "wastewater"): world.add_waste(shipment.source, shipment.get("pollution", 0.0))
		world.shipments.erase(shipment)

# Shared supply endpoints publish demand; only entering a delivery commits physical goods.
func delivery_requirements(p: Vector2i) -> Dictionary:
	if world.sites.has(p):
		return {} if world.sites[p].get("cancelled", false) else world.sites[p].materials
	if world.banks.has(p):
		return {"bread": LOAN_LIMIT}
	if not world.benches.has(p):
		return {}
	var b: Dictionary = world.benches[p]
	if b.kind == "barn" and (b.sheep <= 0 or b.slaughter):
		return {}
	if PRODUCTS.has(b.kind) and has_production_order(p) and b.task.is_empty() and b.growth <= 0:
		return production_materials(b.kind)
	if b.kind == "power_plant":
		var fuel := stock_at(p, 3) + incoming(p, 3)
		return {3: fuel + 2.0} if fuel <= 1.0 else {}
	if b.kind == "fountain" and b.water_day != world.day:
		return {"raw_water": FOUNTAIN_WATER}
	if SERVICES.has(b.kind):
		return SERVICES[b.kind].materials
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

# One receiver may accept several mineral types, but never more than its unmet recipe.
func mined_delivery_items(w: Dictionary, target: Vector2i, supply: bool) -> Array:
	var items: Array = []
	var held: Array = [w.carry] + w.extra_cargo
	var accepted: Dictionary = {}
	var recipe := delivery_requirements(target)
	for item in held:
		if is_same(item, 0): continue
		var key = 0 if item is int and recipe.has(0) else item
		if supply and delivery_need(target, item) - accepted.get(key, 0) < 1.0:
			continue
		items.append(item)
		accepted[key] = accepted.get(key, 0) + 1
	return items

func ore_delivery_batch(shipment: Dictionary) -> Array[Dictionary]:
	var batch: Array[Dictionary] = []
	var current := shipment
	while not current.is_empty():
		batch.append(current)
		current = current.get("next_ore", {})
	return batch

func claim_delivery(w: Dictionary, plan: Dictionary) -> Dictionary:
	var target: Vector2i = plan.target
	var mined_cargo: bool = plan.get("mined", false)
	var origin := Vector2i(w.pos.round())
	if not w.freight.is_empty() or not w.ore_delivery.is_empty():
		return {}
	if mined_cargo:
		if delivery_route(origin, target).path.is_empty():
			return {}
	elif not is_same(w.carry, 0) or route(origin, plan.source).is_empty() or delivery_route(plan.source, target).path.is_empty():
		return {}
	var amount := 1.0 if mined_cargo else minf(FREIGHT_CAPACITY, available_at(plan.source, plan.item))
	if plan.has("identity"):
		if world.smart_objects.identity(SmartObjects.key("supply", target)) != plan.identity:
			return {}
		amount = minf(amount, delivery_need(target, plan.item))
	elif not mined_cargo or world.sites.has(target) or delivery_building_at(target) != target:
		return {}
	if amount <= 0.000001 or (mined_cargo and amount < 1.0):
		return {}
	if mined_cargo:
		var items := mined_delivery_items(w, target, plan.has("identity"))
		if items.is_empty(): return {}
		var first: Dictionary = {}
		var previous: Dictionary = {}
		# Keep per-item freight records for demand, cancellation and conveyor capacity.
		for item in items:
			var part := {"source": plan.source, "target": target, "item": item,
				"amount": 1.0, "owner": w.id, "picked": true, "mined": true, "carried_ore": true}
			world.shipments.append(part)
			if first.is_empty(): first = part
			else: previous.next_ore = part
			previous = part
		w.ore_delivery = first
		return first
	var shipment := {"source": plan.source, "target": target, "item": plan.item,
		"amount": amount, "owner": w.id, "picked": mined_cargo,
		"mined": mined_cargo, "carried_ore": mined_cargo}
	if is_same(shipment.item, "wastewater"): shipment.pollution = world.take_waste(shipment.source, amount, stock_at(shipment.source, shipment.item))
	add_stock(shipment.source, shipment.item, -amount)
	world.shipments.append(shipment)
	return shipment

func site_supplied(p: Vector2i) -> bool:
	for item in world.sites[p].materials:
		if stock_at(p, item) + 0.000001 < world.sites[p].materials[item]:
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
	for ore in [1, 4, 3, 2, 7, 8]:
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
	for p in world.sites.keys():
		if not world.sites[p].get("cancelled", false):
			continue
		for item in world.stores.get(p, {}).keys():
			while stock_at(p, item) > 0.000001:
				reserve_shipment(p, BASE, item, minf(FREIGHT_CAPACITY, stock_at(p, item)))
		var recovering := false
		for shipment in world.shipments:
			if shipment.source == p or shipment.target == p:
				recovering = true
				break
		if not recovering:
			world.sites.erase(p)
			world.stores.erase(p)

func simulate_growth(delta: float) -> void:
	for p in world.benches:
		var bench: Dictionary = world.benches[p]
		if bench.growth <= 0:
			continue
		bench.growth = maxf(0.0, bench.growth - delta * (2.0 if bench.kind == "farm" and has_powered_effect(Vector2(p), "grow_light") else 1.0))
		if bench.growth == 0:
			bench.harvest = true
			bench.task = contract(1.0)

func in_effect_range(source: Vector2i, target: Vector2, radius := EFFECT_RADIUS) -> bool:
	return absf(source.x - target.x) <= radius and absf(source.y - target.y) <= radius

func has_powered_effect(p: Vector2, kind: String) -> bool:
	for source in cache.powered_devices:
		if building_kind(source) == kind and in_effect_range(source, p):
			return true
	return false

func drill_target(p: Vector2i, worker_id := -1):
	for target in world.mining_contracts:
		if world.terrain[target] in [5, 6] and world.smart_objects.available(SmartObjects.key("mine", target), worker_id) and in_effect_range(p, Vector2(target), DRILL_RADIUS):
			return target
	return null

func station_staffed(p: Vector2i) -> bool:
	var owner := slot_owner("work", p)
	if owner < 0 or owner >= world.workers.size():
		return false
	var w: Dictionary = world.workers[owner]
	var active = w.activity.active
	return active != null and active.record.target == p and active.phase == "use" and w.activity.drink_elapsed < 0 and w.payroll > 0.000001 and w.fatigue < MAX_FATIGUE

func power_demand(p: Vector2i) -> float:
	match building_kind(p):
		"grow_light", "spotlight", "daylight": return 200.0
		"fountain": return 200.0 if world.benches[p].water_day == world.day else 0.0
		"drill":
			var owner := slot_owner("work", p)
			return 400.0 if drill_target(p, owner) != null else 0.0
		"electric_belt":
			var amount := 0.0
			for cargo in world.belt_cargo.values():
				var carrier: Vector2i = cargo.to if world.belts.has(cargo.to) else cargo.from
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
	for p in world.power_lines:
		signature_data.append([p, world.power_lines[p].kind, world.power_lines[p].get("axis", Vector2i.RIGHT)])
	for p in world.benches:
		signature_data.append([p, world.benches[p].kind])
	for p in world.belts:
		signature_data.append([p, world.belts[p].get("kind", "belt")])
	var signature := hash(signature_data)
	if signature == cache.power_signature and not cache.power_graph.is_empty():
		return
	cache.power_signature = signature
	cache.power_graph = {"source": {}}
	cache.power_nodes.clear()
	var cells: Dictionary = {}
	for p in world.power_lines:
		var kind: String = world.power_lines[p].kind
		var key := power_key(p, true)
		power_edge(cache.power_graph, key + ":in", key + ":out", 3200.0 if kind == "high_line" else 800.0)
		for cell in building_cells(p, kind):
			if not cells.has(cell): cells[cell] = []
			cells[cell].append(key)
	for cell in cells:
		for direction in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			for a in cells[cell]:
				for b in cells.get(cell + direction, []):
					if a != b:
						power_edge(cache.power_graph, a + ":out", b + ":in", 1000000.0)
	for p in world.benches.keys() + world.belts.keys():
		var kind := building_kind(p)
		if kind not in OPERATED_KINDS and kind not in ["grow_light", "fountain", "electric_belt", "spotlight", "daylight"]:
			continue
		var key := power_key(p)
		cache.power_nodes[p] = key
		if not cache.power_graph.has(key + ":in"): cache.power_graph[key + ":in"] = {}
		if kind in GENERATOR_KINDS:
			power_edge(cache.power_graph, "source", key + ":out", 400.0 if kind == "manual_generator" else 3200.0)
		elif kind == "transformer":
			power_edge(cache.power_graph, key + ":in", key + ":out", 800.0)
		if kind == "transformer":
			for cable in cells.get(p + Vector2i.LEFT, []):
				power_edge(cache.power_graph, cable + ":out", key + ":in", 3200.0)
			for cable in cells.get(p + Vector2i.RIGHT * 2, []):
				power_edge(cache.power_graph, key + ":out", cable + ":in", 800.0)
		else:
			for cell in building_cells(p, kind):
				for direction in DIRS:
					for cable in cells.get(cell + direction, []):
						if kind in GENERATOR_KINDS:
							power_edge(cache.power_graph, key + ":out", cable + ":in", 3200.0)
						else:
							power_edge(cache.power_graph, cable + ":out", key + ":in", 3200.0)

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
	if world.power_lines.is_empty():
		return false
	rebuild_power_graph()
	var kind := building_kind(p)
	if kind == "drill":
		return power_demand(p) > 0 and not power_route(cache.power_graph, "source", power_key(p) + ":in").is_empty()
	if kind == "power_plant" and stock_at(p, 3) <= 0.000001:
		return false
	if kind == "transformer" and power_route(cache.power_graph, "source", power_key(p) + ":in").is_empty():
		return false
	for target in cache.power_nodes:
		if power_demand(target) > 0 and not power_route(cache.power_graph, power_key(p) + ":out", power_key(target) + ":in").is_empty():
			return true
	return false

func simulate_power(delta: float) -> void:
	cache.powered_devices.clear()
	cache.ready_drills.clear()
	cache.power_output.clear()
	if world.power_lines.is_empty():
		return
	for p in world.benches:
		if world.benches[p].kind == "fountain" and world.benches[p].water_day != world.day and stock_at(p, "raw_water") >= FOUNTAIN_WATER:
			consume_recipe(p, {"raw_water": FOUNTAIN_WATER})
			world.benches[p].water_day = world.day
	rebuild_power_graph()
	var residual: Dictionary = cache.power_graph.duplicate(true)
	var supplies: Dictionary = {}
	for p in world.benches:
		var key := power_key(p)
		if world.benches[p].kind in GENERATOR_KINDS:
			var supply := 400.0 if world.benches[p].kind == "manual_generator" else minf(3200.0, stock_at(p, 3) * 1600.0 * HOUR_SECONDS / delta)
			if not station_staffed(p): supply = 0.0
			supplies[p] = supply
			residual.source[key + ":out"] = supply
		elif world.benches[p].kind == "transformer" and not station_staffed(p):
			residual[key + ":in"][key + ":out"] = 0.0
	for p in cache.power_nodes:
		var load := power_demand(p)
		if load <= 0 or (building_kind(p) == "drill" and not station_staffed(p)):
			continue
		var before: Dictionary = residual.duplicate(true)
		if allocate_power(residual, p, load):
			cache.powered_devices[p] = true
		else:
			residual = before
	# Preview idle drill capacity without spending fuel or reserving any real flow.
	for p in world.benches:
		if building_kind(p) != "drill": continue
		if cache.powered_devices.has(p):
			cache.ready_drills[p] = true
		elif not station_staffed(p) and power_demand(p) > 0:
			var preview: Dictionary = residual.duplicate(true)
			if allocate_power(preview, p, power_demand(p)):
				cache.ready_drills[p] = true
	for p in supplies:
		var used: float = supplies[p] - residual.source[power_key(p) + ":out"]
		cache.power_output[p] = used
		if world.benches[p].kind == "manual_generator":
			continue
		var coal := used / 1600.0 * delta / HOUR_SECONDS
		add_stock(p, 3, -coal)
		record_resource_use(3, coal)
		if used > 0.000001:
			Pollution.record_operation(world, p, "power_plant", 1.0)
	for p in world.benches:
		if world.benches[p].kind == "transformer":
			var key := power_key(p)
			cache.power_output[p] = residual[key + ":out"].get(key + ":in", 0.0)

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
	if not world.resource_flows.has(world.day):
		world.resource_flows[world.day] = {}
	if not world.resource_flows[world.day].has(item):
		world.resource_flows[world.day][item] = {"produced": 0.0, "consumed": 0.0}
	world.resource_flows[world.day][item].produced += amount

func record_resource_use(item, amount: float) -> void:
	if amount <= 0:
		return
	if not world.resource_flows.has(world.day):
		world.resource_flows[world.day] = {}
	if not world.resource_flows[world.day].has(item):
		world.resource_flows[world.day][item] = {"produced": 0.0, "consumed": 0.0}
	world.resource_flows[world.day][item].consumed += amount

func resource_activity(item, report_day: int) -> Dictionary:
	return world.resource_flows.get(report_day, {}).get(item, {"produced": 0.0, "consumed": 0.0}).duplicate()

# Count physical goods once, including reservations, cargo, personal supplies and equipped items.
# Wages, sales, loans and delivery only move goods; they do not produce or consume them.
func resource_inventory() -> Dictionary:
	var result: Dictionary = {}
	for item in RESOURCE_ITEMS:
		result[item] = 0.0
	for p in world.stores:
		for item in world.stores[p]:
			result[item] = result.get(item, 0.0) + world.stores[p][item]
	for p in world.benches:
		if PRODUCTS.has(building_kind(p)) and building_kind(p) != "printer":
			var item = product_item(building_kind(p))
			result[item] += world.benches[p].stock
	for shipment in world.shipments:
		if not shipment.get("on_belt", false) and not shipment.get("carried_ore", false):
			result[shipment.item] += shipment.amount
	for cargo in world.belt_cargo.values():
		result[cargo.delivery.item] += cargo.delivery.amount
	for w in world.workers:
		if not is_same(w.carry, 0):
			result[w.carry] += 1
		for ore in w.extra_cargo:
			result[ore] += 1
		result.bread += w.bread + w.payroll + w.meal_bread
		result.clean_water += w.water
		result.bench += 1 if w.gun_uses > 0 else 0
		result.workbench += 1 if w.backpack_uses > 0 else 0
		for item in w.items:
			result[item] += w.items[item]
		for item in w.equipment:
			result[item] += 1 if w.equipment[item] > 0 else 0
	return result

func sample_inventory() -> void:
	world.inventory_sample_time = (world.day - 1) * DAY_SECONDS + world.day_elapsed
	world.inventory_history.append({"time": world.inventory_sample_time, "stock": resource_inventory()})
	while world.inventory_history.size() > 121:
		world.inventory_history.pop_front()

# Domain operations own all material, production and payment writes.
func work_available(record: ActivityRecord, w: Dictionary, source_identity: Dictionary) -> bool:
	var p = record.target
	match record.kind:
		"mine":
			return world.mining_contracts.has(p) and is_same(world.mining_contracts[p], source_identity) and world.terrain[p] in [1, 2, 3, 4, 7, 8, MapGenerator.WATER_BLOCK] and cargo_count(w) < carry_capacity(w)
		"build":
			return world.sites.has(p) and is_same(world.sites[p], source_identity) and not world.sites[p].get("cancelled", false) and site_cleared(p) and site_supplied(p)
		"produce":
			return world.benches.has(p) and is_same(world.benches[p], source_identity) and has_production_order(p) and world.benches[p].growth <= 0
		"operate":
			return world.benches.has(p) and is_same(world.benches[p], source_identity) and operation_needed(p) and (record.data.job == null or (world.mining_contracts.has(record.data.job) and cache.ready_drills.has(p)))
	return false

func begin_work(record: ActivityRecord, w: Dictionary, segment: Dictionary, source_identity: Dictionary) -> bool:
	if not work_available(record, w, source_identity):
		return false
	if record.kind in ["produce", "operate"]:
		var p: Vector2i = record.target
		var bench: Dictionary = world.benches[p]
		if bench.task.is_empty():
			var slaughter: bool = bench.kind == "barn" and bench.slaughter
			if record.kind == "produce" and not slaughter:
				var recipe := production_materials(bench.kind)
				if not recipe_ready(p, recipe):
					return false
				consume_recipe(p, recipe)
			bench.task = contract(1.0 if bench.kind in OPERATED_KINDS or bench.kind in ["farm", "barn"] else PRODUCTS[bench.kind].hours)
			if slaughter: bench.task.slaughter = true
	var task: Dictionary
	var station = record.target if record.kind in ["produce", "operate"] else null
	var kind := building_kind(station) if station != null else ""
	if record.kind == "mine": task = world.mining_contracts[record.target]
	elif record.kind == "build": task = world.sites[record.target]
	elif kind == "drill": task = world.mining_contracts[record.data.job]
	else: task = world.benches[station].task
	if not task.has("reward"):
		task.reward = task.seconds / HOUR_SECONDS * station_wage(station)
		task.paid = 0.0
	var goal: float = minf(task.seconds, (task.paid + w.payroll) / task.reward * task.seconds)
	if goal <= task.progress + 0.0000001:
		return false
	var rate: float = w.buffs.work_rate(self, w, record.kind, kind)
	segment.merge({"task": task, "goal": goal, "rate": rate, "kind": kind, "labor": 0.0,
		"fatigue_factor": w.buffs.fatigue_factor(self, w)}, true)
	ai_trace.record(self, w, "labor", "started", {"reward": task.reward, "already_paid": task.paid,
		"rate": rate, "goal": goal, "fatigue_factor": segment.fatigue_factor})
	return true

func perform_work(record: ActivityRecord, w: Dictionary, delta: float, segment: Dictionary) -> Dictionary:
	var task: Dictionary = segment.task
	var p = record.target
	if record.kind == "operate" and building_kind(p) == "drill" and not cache.powered_devices.has(p):
		return {"seconds": 0.0, "complete": false, "funding": false}
	var seconds := advance_labor(segment, delta)
	var complete: bool = task.progress >= task.seconds - 0.0000001
	var funding: bool = not complete and task.progress >= segment.goal - 0.0000001
	if record.kind in ["produce", "operate"] and seconds > 0:
		Pollution.record_operation(world, p, building_kind(p), seconds / delta)
	if complete:
		task.progress = task.seconds
		settle_labor(w, segment, "completed")
		complete_work(record, w)
	elif funding:
		settle_labor(w, segment, "funding")
	return {"seconds": seconds, "complete": complete, "funding": funding}

func complete_work(record: ActivityRecord, w: Dictionary) -> void:
	var p: Vector2i = record.target
	match record.kind:
		"mine":
			if w.gun_uses == 1: record_resource_use("bench", 1)
			w.gun_uses = maxi(0, w.gun_uses - 1)
			var item = ORES[world.terrain[p]].get("item", world.terrain[p])
			record_resource_output(item, 1)
			if is_same(w.carry, 0): w.carry = item
			else: w.extra_cargo.append(item)
			world.terrain[p] = 0
			world_view.block_changed(p)
			cache.navigation.set_point_solid(p, false)
			world.mining_contracts.erase(p)
			world.smart_objects.invalidate(SmartObjects.key("mine", p))
			world_view.sync_orders()
			record_excavation(w)
			update_fog()
		"build": complete_building(p)
		"produce":
			if tool_work(building_kind(p)) and w.equipment.get("tools", 0) > 0:
				w.equipment.tools -= 1
				if w.equipment.tools == 0: record_resource_use("tools", 1)
			complete_product(p)
		"operate":
			var bench: Dictionary = world.benches[p]
			if bench.kind == "drill":
				var mineral: Vector2i = record.data.job
				var task: Dictionary = world.mining_contracts[mineral]
				var item: int = ORES[world.terrain[mineral]].item
				add_stock(p, item, 1)
				record_resource_output(item, 1)
				record_excavation(w)
				task.clear()
				task.merge(contract(DRILL_HOURS))
			else:
				bench.task = {}

func record_excavation(w: Dictionary) -> void:
	world.mined += 1
	if not world.daily_mined.has(world.day): world.daily_mined[world.day] = {}
	world.daily_mined[world.day][w.id] = world.daily_mined[world.day].get(w.id, 0) + 1

func complete_product(p: Vector2i) -> void:
	var bench: Dictionary = world.benches[p]
	if bench.kind == "printer":
		world.newborns.append(p + Vector2i.RIGHT)
		bench.queue -= 1
	elif bench.task.get("slaughter", false):
		bench.sheep = 0
		bench.slaughter = false
		bench.daily_output = 0
		add_stock(p, "meat", SHEEP_MEAT)
		record_resource_output("meat", SHEEP_MEAT)
	elif bench.kind in ["farm", "barn"] and not bench.harvest:
		bench.growth = (FARM_GROWTH_HOURS if bench.kind == "farm" else SHEEP_GROWTH_HOURS) * HOUR_SECONDS
	else:
		var amount: int = PRODUCTS[bench.kind].get("amount", 1)
		bench.stock += amount
		bench.produced_today += amount
		record_resource_output(product_item(bench.kind), amount)
		bench.harvest = false
	bench.task = {}

func complete_building(p: Vector2i) -> void:
	var task: Dictionary = world.sites[p]
	if PRODUCTS.has(task.kind) or NEW_BUILDINGS.has(task.kind) and task.kind not in LINE_KINDS and task.kind not in BELT_KINDS:
		world.benches[p] = production_station(task.kind)
		if task.kind == "fountain": world.benches[p].water_day = world.day
	elif task.kind == "bank":
		world.banks[p] = {"interest_received": 0.0}
	elif task.kind in BELT_KINDS:
		world.belts[p] = {"kind": task.kind, "direction": task.direction, "inputs": task.inputs, "last_input": -1, "materials": task.materials}
	elif task.kind in LINE_KINDS:
		world.power_lines[p] = {"kind": task.kind, "axis": task.axis, "materials": task.materials.duplicate()}
	else:
		world.beds[p] = {"remaining": 0.0, "assigned": -1}
	for item in task.materials:
		add_stock(p, item, -task.materials[item])
		record_resource_use(item, task.materials[item])
	world.sites.erase(p)
	world.smart_objects.invalidate(SmartObjects.key("build", p))

func purchase(w: Dictionary, p: Vector2i, limit: int, item = null) -> void:
	if not world.benches.has(p) or w.pos.distance_to(Vector2(p)) > 0.01:
		return
	if item == null: item = product_item(building_kind(p))
	if item not in shop_goods(p): return
	var price := sale_price(p, item)
	var count := mini(limit, mini(floori(stock_at(p, item)), floori((w.bread + 0.000001) / price)))
	count = mini(count, purchase_capacity(w, item))
	if count <= 0: return
	add_stock(p, item, -count)
	w.bread -= count * price
	w.shop_spent_today += count * price
	add_stock(p, "bread", count * price)
	if item == "clean_water": w.water += count
	else: w.items[item] = w.items.get(item, 0) + count
	personal_item_event.emit(w.id, "gain", item, count)

func collect_payroll(w: Dictionary, p: Vector2i) -> void:
	var cash := minf(PAYROLL_COLLECTION, stock_at(p, "bread"))
	add_stock(p, "bread", -cash)
	w.payroll += cash

func borrow(w: Dictionary, p: Vector2i, limit: float) -> void:
	if not world.banks.has(p) or has_debt(w) or w.loan_day == world.day:
		return
	var need := maxf(0, 10.0 - w.hunger / HUNGER_PER_BREAD - w.bread)
	var amount := minf(need, minf(limit, minf(LOAN_LIMIT, stock_at(p, "bread"))))
	if amount <= 0: return
	add_stock(p, "bread", -amount)
	w.bread += amount
	world.portal.lent_bread += amount
	w.loan_principal = amount
	w.loan_interest = amount * LOAN_INTEREST_RATE
	w.loan_day = world.day
	w.loan_bank = p
	personal_item_event.emit(w.id, "borrow", "bread", amount)

func drink(w: Dictionary) -> void:
	if w.water <= 0: return
	w.water -= 1
	record_resource_use("clean_water", 1)
	w.buffs.apply("hydrated", WATER_EFFECT_HOURS * HOUR_SECONDS)
	personal_item_event.emit(w.id, "use", "clean_water", 1)

func tool_work(kind: String) -> bool:
	return kind == "farm" or kind in PROCESSING_KINDS

func equipped_amount(w: Dictionary, item: String) -> float:
	if item == "bench": return w.gun_uses
	if item == "workbench": return w.backpack_uses
	return w.equipment.get(item, 0.0)

func purchase_capacity(w: Dictionary, item: String) -> int:
	if item == "clean_water": return WATER_CAPACITY - w.water
	if ITEM_USES.has(item) and equipped_amount(w, item) > 0: return 0
	return maxi(0, (2 if item == "meat" else 1) - w.items.get(item, 0))

func wants_item(w: Dictionary, item: String) -> bool:
	if purchase_capacity(w, item) <= 0: return false
	if item == "clean_water": return w.water == 0 and w.buffs.remaining("hydrated") <= 0
	if item == "ale": return w.buffs.remaining("tipsy") <= 0 and w.fatigue >= WorkerBuffs.ALE_RECOVERY
	if item in ["cleaner", "medical", "wastewater"]: return false
	if item == "meat": return w.hunger < 70
	return true

func use_item(w: Dictionary, item: String) -> bool:
	if w.items.get(item, 0) <= 0: return false
	if ITEM_USES.has(item):
		if equipped_amount(w, item) > 0: return false
		var rule: Dictionary = ITEM_USES[item]
		if item in ["bench", "workbench"]: w[rule.slot] = rule.uses
		else: w.equipment[rule.slot] = rule.uses
		if item == "clothes": w.clothes_pollution = 0.0
	elif item == "ale":
		if w.buffs.remaining("tipsy") > 0: return false
		w.fatigue = maxf(0.0, w.fatigue - WorkerBuffs.ALE_RECOVERY)
		w.buffs.apply("tipsy", WorkerBuffs.ALE_HOURS * HOUR_SECONDS)
		record_resource_use(item, 1)
	elif item == "meat":
		w.hunger = minf(MAX_HUNGER, w.hunger + MEAT_HUNGER)
		record_resource_use(item, 1)
	else:
		return false
	w.items[item] -= 1
	personal_item_event.emit(w.id, "use", item, 1)
	return true

func wear_clothes(w: Dictionary, delta: float) -> void:
	if w.equipment.get("clothes", 0) <= 0: return
	w.equipment.clothes = maxf(0.0, w.equipment.clothes - delta)
	if w.equipment.clothes == 0:
		w.clothes_pollution = 0.0
		record_resource_use("clothes", 1)

func item_use_hours(item: String) -> float:
	return DRINK_HOURS

func wants_service(w: Dictionary, kind: String) -> bool:
	match kind:
		"hospital": return w.pollution >= Pollution.DISEASE
		"laundry": return w.equipment.get("clothes", 0) > 0 and w.clothes_pollution >= 30.0
		"bathhouse": return w.pollution < Pollution.DISEASE and (w.pollution > Pollution.DISCOMFORT or w.buffs.remaining("bathed") <= 0)
	return false

func can_use_service(w: Dictionary, p: Vector2i) -> bool:
	var kind := building_kind(p)
	return world.benches.has(p) and SERVICES.has(kind) and wants_service(w, kind) and w.bread >= SERVICES[kind].price and recipe_ready(p, SERVICES[kind].materials)

func finish_service(w: Dictionary, p: Vector2i) -> bool:
	var kind := building_kind(p)
	if not can_use_service(w, p) or slot_owner(SERVICES[kind].slot, p) != w.id or w.pos.distance_to(Vector2(p)) > 0.01:
		return false
	var service: Dictionary = SERVICES[kind]
	var field := "clothes_pollution" if kind == "laundry" else "pollution"
	var removed: float = minf(w[field], service.recovery)
	consume_recipe(p, service.materials)
	w[field] -= removed
	w.bread -= service.price
	w.shop_spent_today += service.price
	add_stock(p, "bread", service.price)
	if kind != "hospital":
		add_stock(p, "wastewater", service.materials.clean_water)
		record_resource_output("wastewater", service.materials.clean_water)
		world.add_waste(p, removed * (1.0 - Pollution.CLEANER_REMOVAL))
	if kind == "bathhouse": w.buffs.apply("bathed", WorkerBuffs.BATH_EFFECT_HOURS * HOUR_SECONDS)
	return true

func rent_bed(w: Dictionary, p: Vector2i) -> bool:
	if not world.beds.has(p) or w.bread < BED_PRICE or slot_owner("bed", p) != w.id:
		return false
	w.bread -= BED_PRICE
	w.bed_spent_today += BED_PRICE
	add_stock(p, "bread", BED_PRICE)
	world.beds[p].remaining = BED_LEASE_HOURS * HOUR_SECONDS
	return true

func eat_portion(w: Dictionary, record: ActivityRecord, seconds: float) -> void:
	var fraction := seconds / MEAL_SECONDS
	var eaten := minf(w.meal_bread, record.data.amount * fraction)
	w.meal_bread = maxf(0, w.meal_bread - eaten)
	# Announce the first actual bite, not the reservation or each simulation step.
	if eaten > 0 and record.data.amount - w.meal_bread <= eaten + 0.000001:
		personal_item_event.emit(w.id, "use", "bread", eaten)
	w.eaten_today += eaten
	w.hunger = minf(MAX_HUNGER, w.hunger + eaten * HUNGER_PER_BREAD)
	record_resource_use("bread", eaten)
	if record.data.has("canteen"):
		w.fatigue = maxf(0, w.fatigue - CANTEEN_RECOVERY * fraction)

func sleep_seconds(w: Dictionary, bed, delta: float) -> Dictionary:
	var bed_seconds := 0.0
	if bed != null and world.beds.has(bed):
		bed_seconds = minf(delta, minf(world.beds[bed].remaining, w.fatigue / BED_RECOVERY_PER_HOUR * HOUR_SECONDS))
		world.beds[bed].remaining = maxf(0, world.beds[bed].remaining - bed_seconds)
		w.fatigue = maxf(0, w.fatigue - bed_seconds / HOUR_SECONDS * BED_RECOVERY_PER_HOUR)
	var ground_seconds := minf(delta - bed_seconds, w.fatigue / SLEEP_RECOVERY_PER_HOUR * HOUR_SECONDS)
	w.fatigue = maxf(0, w.fatigue - ground_seconds / HOUR_SECONDS * SLEEP_RECOVERY_PER_HOUR)
	if w.fatigue < 0.000001:
		w.fatigue = 0.0
	return {"hours": (bed_seconds + ground_seconds) / HOUR_SECONDS, "bed_hours": bed_seconds / HOUR_SECONDS}
