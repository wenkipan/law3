extends Node2D

const SIZE := Vector2i(72, 44)
const CELL := 40.0
const BASE := Vector2i(32, 13)
const VISION_RADIUS := 7
const DAY_SECONDS := 180.0
const MEAL_SECONDS := 2.0
const HUNGER_PER_BREAD := 10.0
const MAX_HUNGER := 180.0
const HUNGER_DECAY_PER_DAY := 100.0
const FATIGUE_PER_HOUR := 10.0
const SLEEP_RECOVERY_PER_HOUR := 10.0
const FATIGUING_STATES := ["dig", "work", "build", "use_tool"]
const HOUR_SECONDS := DAY_SECONDS / 24.0
const MIN_MINING_HOURS := 1.0
const BED_BLOCKS := 6
const BED_BUILD_HOURS := 4.0
const WAGE_PER_HOUR := 1.0
const BED_PRICE := 5.0
const BED_LEASE_HOURS := 8.0
const BED_RECOVERY_PER_HOUR := 15.0
const BENCH_BLOCKS := 6
const BENCH_BUILD_HOURS := 4.0
const GUN_WORK_HOURS := 2.0
const GUN_PRICE := 5.0
const GUN_USES := 10
const GUN_MINING_RATE := 2.0
const WORKBENCH_BLOCKS := 6
const WORKBENCH_BUILD_HOURS := 4.0
const BACKPACK_WORK_HOURS := 2.0
const BACKPACK_PRICE := 4.0
const BACKPACK_USES := 10
const WATER_BUILD_BLOCKS := 8
const WATER_BUILD_HOURS := 4.0
const WATER_WORK_HOURS := 1.0
const WATER_BATCH := 4
const WATER_PRICE := 1.0
const WATER_CAPACITY := 4
const DRINK_HOURS := 0.1
const WATER_EFFECT_HOURS := 4.0
const WATER_FATIGUE_REDUCTION := 0.3
const PRINTER_BLOCKS := 12
const PRINTER_BUILD_HOURS := 6.0
const PRINT_WORKER_BLOCKS := 10
const PRINT_WORKER_HOURS := 4.0
const BANK_BLOCKS := 12
const BANK_BUILD_HOURS := 6.0
const LOAN_LIMIT := 10.0
const LOAN_INTEREST_RATE := 0.2
const LOAN_REPAYMENT_RATE := 0.25
const BELT_BLOCKS := 1
const BELT_BUILD_HOURS := 0.25
const BELT_SPEED := 9.0
const BELT_FEE := 0.2
const WORKER_NAMES := ["阿麦", "米粒", "石头", "小满", "青禾", "阿砾", "谷雨", "小川"]
const WORKER_COLORS := [Color("#d6ba72"), Color("#a4cbb5"), Color("#d99987")]
const BUILDING_KINDS := ["bed", "bench", "workbench", "pump", "purifier", "printer", "bank", "belt"]
const PRODUCTS := {
	"bench": {"name": "矿枪", "unit": "把", "hours": GUN_WORK_HOURS, "price": GUN_PRICE, "uses": GUN_USES, "durability": "gun_uses"},
	"workbench": {"name": "背包", "unit": "个", "hours": BACKPACK_WORK_HOURS, "price": BACKPACK_PRICE, "uses": BACKPACK_USES, "durability": "backpack_uses"},
	"pump": {"name": "原水", "unit": "份", "hours": WATER_WORK_HOURS, "amount": WATER_BATCH},
	"purifier": {"name": "清水", "unit": "份", "hours": WATER_WORK_HOURS, "amount": WATER_BATCH, "price": WATER_PRICE},
	"printer": {"name": "工人", "unit": "名", "hours": PRINT_WORKER_HOURS},
}
const Portal = preload("res://scripts/portal.gd")
const DailyReport = preload("res://scripts/daily_report.gd")
const Art = preload("res://scripts/view/art.gd")
const ACTIONS := ["挖掘", "工作", "搬运", "等待", "空闲", "通勤", "吃饭", "睡觉"]
const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const ORES := [
	{"name": "空地", "color": Color("#263337"), "time": 0.0},
	{"name": "砂岩", "color": Color("#797c68"), "time": 2.4},
	{"name": "铜矿", "color": Color("#9b7860"), "time": 3.8},
	{"name": "煤矿", "color": Color("#484e59"), "time": 3.0},
	{"name": "花岗岩", "color": Color("#777187"), "time": 4.2},
]

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
var belt_cargo: Dictionary = {}
var next_cargo_id := 0
var belt_drawing := false
var belt_path: Array[Vector2i] = []
var belt_pointer := Vector2.ZERO
var building_drawing := false
var building_start := Vector2i.ZERO
var building_end := Vector2i.ZERO
var building_axis := Vector2i.ZERO
var player_bread := 0.0
var player_blocks := 0
var workers: Array[Dictionary] = []
var navigation := AStarGrid2D.new()
var camera := Camera2D.new()
var delivered := 0
var mined := 0
var day := 1
var day_elapsed := 0.0
var portal := Portal.new()
var wander_rng := RandomNumberGenerator.new()
var daily_records: Dictionary = {}
var daily_mined: Dictionary = {}
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
var selected_entity := Vector2i(-1, -1)
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

func reset_world() -> void:
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
	belt_cargo.clear()
	next_cargo_id = 0
	belt_drawing = false
	belt_path.clear()
	building_drawing = false
	building_axis = Vector2i.ZERO
	player_bread = 0.0
	player_blocks = 0
	workers.clear()
	selected_entity = Vector2i(-1, -1)
	selected_worker = -1
	daily_records.clear()
	daily_mined.clear()
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 1020
	for y in SIZE.y:
		for x in SIZE.x:
			var p := Vector2i(x, y)
			var roll := rng.randf()
			terrain[p] = 2 if roll > 0.84 else (3 if roll < 0.18 else (4 if y > 26 else 1))
			if x >= 28 and x <= 36 and y >= 11 and y <= 15:
				terrain[p] = 0
	for p in [Vector2i(29, 10), Vector2i(43, 22), Vector2i(20, 27), Vector2i(52, 33)]:
		water_sources[p] = true
		terrain[p] = 0
	navigation.region = Rect2i(Vector2i.ZERO, SIZE)
	navigation.cell_size = Vector2.ONE
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	navigation.update()
	for p in terrain:
		navigation.set_point_solid(p, terrain[p] != 0 or water_sources.has(p))
	for i in 3:
		create_worker(BASE + Vector2i(i - 1, 1))
	camera.position = tile_center(BASE)
	update_fog()
	update_ui()
	if is_instance_valid(report_window):
		report_window.queue_free()
		report_window = null
	world_view.rebuild(self)

func create_worker(p: Vector2i) -> Dictionary:
	var id := workers.size()
	var worker := {"id": id, "name": WORKER_NAMES[id] if id < WORKER_NAMES.size() else "矿工%d" % (id + 1),
		"color": WORKER_COLORS[id % WORKER_COLORS.size()], "pos": Vector2(p), "state": "idle",
		"path": [], "job": Vector2i(-1, -1), "progress": 0.0, "carry": 0,
		"bread": 0, "earned_today": 0, "eaten_today": 0, "hunger": 0.0, "meal_day": 0, "meal_bread": 0,
		"bed_spent_today": 0.0, "shop_spent_today": 0.0,
		"wander_wait": 0.0, "facing": 1.0, "fatigue": 0.0,
		"bed": Vector2i(-1, -1), "building": Vector2i(-1, -1),
		"station": Vector2i(-1, -1), "gun_uses": 0, "backpack_uses": 0, "extra_cargo": [],
		"water": 0, "water_effect": 0.0, "drink_progress": 0.0, "drink_resume": "",
		"loan_principal": 0.0, "loan_interest": 0.0, "loan_day": 0, "loan_bank": Vector2i(-1, -1),
		"haul_target": BASE, "unloaded_this_trip": 0}
	workers.append(worker)
	return worker

func tile_center(p: Vector2) -> Vector2:
	return (p + Vector2(0.5, 0.5)) * CELL

func in_bounds(p: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, SIZE).has_point(p)

func route(start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	if not in_bounds(start) or not in_bounds(target) or terrain[target] != 0 or water_sources.has(target):
		return []
	return navigation.get_id_path(start, target)

func daily_budget(w: Dictionary) -> Dictionary:
	var food := maxf(HUNGER_DECAY_PER_DAY / HUNGER_PER_BREAD, w.eaten_today + w.meal_bread)
	var planned_bed := false
	var planned_shops: Dictionary = {}
	for bench in benches.values():
		planned_shops[bench.get("kind", "bench")] = true
	for task in sites.values():
		if task.get("kind", "bed") == "bed":
			planned_bed = true
		elif PRODUCTS.has(task.get("kind", "bed")):
			planned_shops[task.kind] = true
	var bed_cost: float = w.bed_spent_today
	if bed_cost < BED_PRICE:
		for p in beds:
			var assigned: int = beds[p].get("assigned", -1)
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
			shopping += product.price
	var total: float = food + bed_cost + shopping
	var paid: float = w.eaten_today + w.meal_bread + w.bed_spent_today + w.shop_spent_today
	return {"food": food, "bed": bed_cost, "shopping": shopping,
		"total": total, "paid": paid, "remaining": maxf(0.0, total - paid)}

func daily_budget_ready(w: Dictionary) -> bool:
	return w.bread >= daily_budget(w).remaining - 0.000001

func has_debt(w: Dictionary) -> bool:
	return w.loan_principal + w.loan_interest > 0.000001

func can_rest(w: Dictionary) -> bool:
	return daily_budget_ready(w) and not has_debt(w)

func needs_meal(w: Dictionary) -> bool:
	return w.meal_day != day and w.hunger < MAX_HUNGER

func try_borrow(w: Dictionary) -> void:
	if has_debt(w) or w.loan_day == day:
		return
	var amount := minf(LOAN_LIMIT, daily_budget(w).remaining - w.bread)
	if amount <= 0.000001:
		return
	for p in banks:
		if route(Vector2i(w.pos.round()), p).is_empty():
			continue
		w.bread += portal.lend(amount)
		w.loan_principal = amount
		w.loan_interest = amount * LOAN_INTEREST_RATE
		w.loan_day = day
		w.loan_bank = p
		return

func receive_income(w: Dictionary, amount: float) -> void:
	# Only new earnings repay debt. Principal returns to the portal, not the player.
	var repayment := minf(amount * LOAN_REPAYMENT_RATE, w.loan_principal + w.loan_interest)
	var principal := minf(repayment, w.loan_principal)
	var interest := repayment - principal
	w.loan_principal = maxf(0.0, w.loan_principal - principal)
	w.loan_interest = maxf(0.0, w.loan_interest - interest)
	portal.repaid_principal += principal
	player_bread += interest
	if banks.has(w.loan_bank):
		banks[w.loan_bank].interest_received += interest
	w.bread += amount - repayment
	w.earned_today += amount

func assign_job(w: Dictionary) -> void:
	if w.state in ["eat", "sleep", "to_bed", "drink"]:
		return
	if w.carry > 0:
		if cargo_count(w) >= carry_capacity(w) or can_rest(w) or (daily_budget_ready(w) and needs_meal(w)) or not assign_mining_job(w):
			start_haul(w)
		return
	try_borrow(w)
	if daily_budget_ready(w):
		if try_shop_trip(w):
			return
		if not has_debt(w) or needs_meal(w):
			start_meal(w)
			return
	var start := Vector2i(w.pos.round())
	for target in sites:
		if sites[target].owner != -1:
			continue
		var path := route(start, target)
		if not path.is_empty():
			if try_water_trip(w):
				return
			sites[target].owner = w.id
			w.building = target
			w.path = path
			w.state = "to_build"
			return
	for target in benches:
		var bench: Dictionary = benches[target]
		if not has_production_order(target) or (not bench.task.is_empty() and bench.task.owner != -1):
			continue
		var path := route(start, target)
		if path.is_empty():
			continue
		if bench.task.is_empty() and building_kind(target) == "purifier" and raw_water_stock() < WATER_BATCH:
			continue
		if bench.task.is_empty() and building_kind(target) == "printer" and player_blocks < PRINT_WORKER_BLOCKS:
			continue
		if try_water_trip(w):
			return
		if bench.task.is_empty():
			if building_kind(target) == "purifier":
				consume_raw_water(WATER_BATCH)
			elif building_kind(target) == "printer":
				player_blocks -= PRINT_WORKER_BLOCKS
				update_build_availability()
			bench.task = contract(PRODUCTS[bench.get("kind", "bench")].hours)
		bench.task.owner = w.id
		w.station = target
		w.path = path
		w.state = "to_work"
		return
	assign_mining_job(w)

func assign_mining_job(w: Dictionary) -> bool:
	var start := Vector2i(w.pos.round())
	for target in jobs:
		if jobs[target] != -1:
			continue
		for direction in DIRS:
			var stand: Vector2i = target + direction
			var path := route(start, stand)
			if not path.is_empty():
				if w.carry == 0 and try_shop_trip(w):
					return true
				if try_water_trip(w):
					return true
				jobs[target] = w.id
				w.job = target
				w.path = path
				w.state = "walk"
				w.progress = mining_contracts[target].progress if mining_contracts.has(target) else 0.0
				return true
	return false

func cargo_count(w: Dictionary) -> int:
	return (1 if w.carry > 0 else 0) + w.extra_cargo.size()

func carry_capacity(w: Dictionary) -> int:
	return 2 if w.backpack_uses > 0 else 1

func start_haul(w: Dictionary, use_belts := true) -> void:
	var start := Vector2i(w.pos.round())
	w.path = route(start, BASE)
	w.haul_target = BASE
	if use_belts:
		for p in belts:
			if belts[p].cargo >= 0 or not belt_reaches_base(p):
				continue
			var path := route(start, p)
			if not path.is_empty() and (w.path.is_empty() or path.size() < w.path.size()):
				w.path = path
				w.haul_target = p
	w.state = "haul"

func take_carried_ore(w: Dictionary) -> int:
	var ore: int = w.carry
	w.carry = w.extra_cargo.pop_front() if not w.extra_cargo.is_empty() else 0
	w.unloaded_this_trip += 1
	if w.carry == 0:
		if w.unloaded_this_trip >= 2:
			w.backpack_uses = maxi(0, w.backpack_uses - 1)
		w.unloaded_this_trip = 0
	return ore

func deliver_ore(ore: int, worker_id: int, transported := false) -> void:
	var bread := float(portal.exchange(ore))
	var fee := minf(BELT_FEE, bread) if transported else 0.0
	delivered += 1
	player_blocks += 1
	player_bread += fee
	receive_income(workers[worker_id], bread - fee)

func belt_reaches_base(p: Vector2i) -> bool:
	var visited: Dictionary = {}
	while belts.has(p) and not visited.has(p):
		visited[p] = true
		var direction: Vector2i = belts[p].direction
		if direction == Vector2i.ZERO:
			return false
		p += direction
		if p == BASE:
			return true
		if not belts.has(p) or -direction not in belts[p].inputs:
			return false
	return false

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
	belts.erase(p)
	player_blocks += BELT_BLOCKS
	update_build_availability()
	return true

func belt_direction_at(p: Vector2i) -> Vector2i:
	return belt_data(p).get("direction", Vector2i.ZERO)

func belt_data(p: Vector2i, overrides: Dictionary = {}) -> Dictionary:
	if overrides.has(p):
		return overrides[p]
	if sites.has(p) and building_kind(p) == "belt":
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
		if p == BASE:
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
	if path.is_empty() or path[0] == BASE:
		return false
	var plan := belt_path_plan(path)
	var cost := 0
	var visited: Dictionary = {}
	for i in path.size():
		var p := path[i]
		if visited.has(p) or (i > 0 and p - path[i - 1] not in DIRS):
			return false
		visited[p] = true
		if p == BASE:
			if i != path.size() - 1:
				return false
			continue
		if belts.has(p) or (sites.has(p) and building_kind(p) == "belt"):
			if belts.has(p) and plan[p].direction != belts[p].direction and not can_edit_belt(p):
				return false
			continue
		if not explored.has(p) or terrain.get(p, 1) != 0 or water_sources.has(p) or building_at(p) or route(BASE, p).is_empty():
			return false
		cost += BELT_BLOCKS
	return cost <= player_blocks

func place_belt_path(path: Array[Vector2i]) -> bool:
	if not belt_plan_valid(path):
		return false
	var plan := belt_path_plan(path)
	for p in plan:
		if not belts.has(p) and not sites.has(p):
			place_building(p, "belt")
		var data := belt_data(p)
		data.direction = plan[p].direction
		data.inputs = plan[p].inputs
	return true

func extend_belt_path(world_position: Vector2) -> void:
	# Traverse crossed cell boundaries, including fast mouse motions, instead of an X-first route.
	var start := belt_pointer / CELL
	var end := world_position / CELL
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

func simulate_belts(delta: float) -> void:
	for id in belt_cargo.keys():
		var cargo: Dictionary = belt_cargo[id]
		cargo.progress += delta * BELT_SPEED
		if cargo.to == BASE and cargo.progress >= 1.0:
			deliver_ore(cargo.ore, cargo.worker, true)
			belt_cargo.erase(id)
	# Resolve against a snapshot so dictionary order cannot move cargo several cells at once.
	var requests: Dictionary = {}
	for p in belts:
		var id: int = belts[p].cargo
		if id < 0 or belt_cargo[id].progress < 1.0:
			continue
		var target: Vector2i = p + belts[p].direction
		if belts[p].direction != Vector2i.ZERO and (target == BASE or (belts.has(target) and -belts[p].direction in belts[target].inputs and belts[target].cargo < 0)):
			if not requests.has(target):
				requests[target] = []
			requests[target].append(p)
		else:
			belt_cargo[id].progress = 1.0
	for target in requests:
		var sources: Array = requests[target]
		var chosen: Vector2i = sources[0]
		if target != BASE:
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
		if target != BASE:
			belts[target].cargo = id
		cargo.from = chosen
		cargo.to = target
		cargo.progress = minf(cargo.progress - 1.0, delta * BELT_SPEED)

func contract(hours: float) -> Dictionary:
	return {"progress": 0.0, "seconds": hours * HOUR_SECONDS,
		"escrow": hours * WAGE_PER_HOUR, "owner": -1}

func pay_labor(w: Dictionary, task: Dictionary, delta: float, rate := 1.0) -> void:
	var work := minf(delta * rate, task.seconds - task.progress)
	var wage := minf(task.escrow, work / rate / HOUR_SECONDS * WAGE_PER_HOUR)
	task.progress += work
	task.escrow = maxf(0, task.escrow - wage)
	receive_income(w, wage)

func mining_seconds(p: Vector2i) -> float:
	return maxf(MIN_MINING_HOURS * HOUR_SECONDS, ORES[terrain[p]].time)

func building_at(p: Vector2i) -> bool:
	for collection in [sites, beds, benches, banks, belts]:
		for origin in collection:
			if p in building_cells(origin, building_kind(origin)):
				return true
	return false

func can_afford_bed() -> bool:
	return player_blocks >= BED_BLOCKS

func place_bed(p: Vector2i) -> bool:
	return place_building(p, "bed")

func building_blocks(kind: String) -> int:
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
	return {"bed": "床", "bench": "武器桌", "workbench": "工作桌", "pump": "抽水机", "purifier": "净水器", "printer": "打印仓", "bank": "银行", "belt": "矿道"}[kind]

func building_cells(p: Vector2i, kind: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [p]
	if kind != "belt":
		cells.append(p + Vector2i.RIGHT)
	return cells

func near_water_source(p: Vector2i) -> bool:
	for cell in [p, p + Vector2i.RIGHT]:
		for direction in DIRS:
			if water_sources.has(cell + direction):
				return true
	return false

func building_kind(p: Vector2i) -> String:
	if sites.has(p):
		return sites[p].get("kind", "bed")
	if banks.has(p):
		return "bank"
	if belts.has(p):
		return "belt"
	return benches[p].get("kind", "bench") if benches.has(p) else "bed"

func building_space_valid(p: Vector2i, kind: String) -> bool:
	if kind not in BUILDING_KINDS:
		return false
	if kind == "pump" and not near_water_source(p):
		return false
	for cell in building_cells(p, kind):
		if not explored.has(cell) or terrain.get(cell, 1) != 0 or water_sources.has(cell) or cell == BASE or building_at(cell):
			return false
	if route(BASE, p).is_empty():
		return false
	return true

func place_building(p: Vector2i, kind: String) -> bool:
	if not building_space_valid(p, kind) or player_blocks < building_blocks(kind):
		return false
	player_blocks -= building_blocks(kind)
	sites[p] = contract(building_hours(kind))
	sites[p].kind = kind
	if kind == "belt":
		sites[p].direction = Vector2i.ZERO
		sites[p].inputs = []
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
	if positions.is_empty() or player_blocks < positions.size() * building_blocks(kind):
		return false
	var occupied: Dictionary = {}
	for p in positions:
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
		place_building(p, kind)
	return true

func finish_building_drag(screen_position: Vector2) -> void:
	building_drawing = false
	if get_viewport().gui_get_hovered_control() == null:
		var world_position := get_global_transform_with_canvas().affine_inverse() * screen_position
		update_building_drag(Vector2i((world_position / CELL).floor()))
		place_building_batch(building_row(), tool)
	building_axis = Vector2i.ZERO

func cancel_placement() -> void:
	belt_drawing = false
	belt_path.clear()
	building_drawing = false
	building_axis = Vector2i.ZERO

func cancel_site(p: Vector2i) -> bool:
	var origin := p if sites.has(p) else p - Vector2i.RIGHT
	if not sites.has(origin) or p not in building_cells(origin, building_kind(origin)):
		return false
	var task: Dictionary = sites[origin]
	if task.owner >= 0:
		var w: Dictionary = workers[task.owner]
		w.building = Vector2i(-1, -1)
		w.path = []
		w.pos = w.pos.round()
		w.state = "idle"
		w.drink_resume = ""
	player_blocks += building_blocks(task.get("kind", "bed"))
	sites.erase(origin)
	update_build_availability()
	return true

func queue_gun(p: Vector2i, change: int) -> void:
	queue_product(p, change)

func queue_product(p: Vector2i, change: int) -> void:
	adjust_production(p, change)

func uses_daily_output(kind: String) -> bool:
	return kind in ["bench", "workbench", "pump", "purifier"]

func production_station(kind: String) -> Dictionary:
	return {"kind": kind, "queue": 0, "daily_output": 0, "produced_today": 0, "stock": 0, "task": {}}

func has_production_order(p: Vector2i) -> bool:
	var bench: Dictionary = benches[p]
	if not bench.task.is_empty():
		return true
	var kind := building_kind(p)
	if not uses_daily_output(kind):
		return bench.queue > 0
	var amount: int = PRODUCTS[kind].get("amount", 1)
	return bench.get("produced_today", 0) + amount <= bench.get("daily_output", 0)

func adjust_production(p: Vector2i, change: int) -> void:
	if not benches.has(p):
		return
	var bench: Dictionary = benches[p]
	var kind := building_kind(p)
	if uses_daily_output(kind):
		var amount: int = PRODUCTS[kind].get("amount", 1)
		bench.daily_output = maxi(0, bench.get("daily_output", 0) + change * amount)
	else:
		bench.queue = maxi(0 if bench.task.is_empty() else 1, bench.queue + change)

func try_shop_trip(w: Dictionary) -> bool:
	if w.carry > 0:
		return false
	for p in benches:
		var product: Dictionary = PRODUCTS[building_kind(p)]
		if not product.has("durability") or benches[p].stock <= 0 or w[product.durability] > 0 or w.bread < product.price:
			continue
		var path := route(Vector2i(w.pos.round()), p)
		if path.is_empty():
			continue
		w.station = p
		w.path = path
		w.state = "to_shop"
		return true
	return false

func raw_water_stock() -> int:
	var total := 0
	for p in benches:
		if building_kind(p) == "pump":
			total += benches[p].stock
	return total

func consume_raw_water(amount: int) -> void:
	assert(raw_water_stock() >= amount)
	for p in benches:
		if building_kind(p) == "pump":
			var taken := mini(amount, benches[p].stock)
			benches[p].stock -= taken
			amount -= taken
			if amount == 0:
				return

func water_purchase_count(w: Dictionary, stock: int) -> int:
	return maxi(0, mini(WATER_CAPACITY - w.water, mini(stock, floori(w.bread / WATER_PRICE))))

func try_water_trip(w: Dictionary) -> bool:
	# Water is optional: never reserve wages or delay work for unavailable water.
	if w.carry > 0 or w.water > 0 or w.water_effect > 0 or w.bread < WATER_PRICE:
		return false
	for p in benches:
		if building_kind(p) != "purifier" or water_purchase_count(w, benches[p].stock) == 0:
			continue
		var path := route(Vector2i(w.pos.round()), p)
		if path.is_empty():
			continue
		w.station = p
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

func start_meal(w: Dictionary) -> void:
	if w.state == "eat":
		return
	if w.carry > 0:
		start_haul(w)
		return
	if w.meal_day == day:
		w.state = "idle" if has_debt(w) else "rest"
	elif w.hunger >= MAX_HUNGER:
		w.meal_day = day
		w.state = "idle" if has_debt(w) else "rest"
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
		simulate_belts(step)
		simulate_workers(step)
		day_elapsed += step
		remaining -= step
		if day_elapsed >= DAY_SECONDS - 0.0000001:
			day_elapsed = 0.0
			day += 1
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
	for w in workers:
		var refreshed_seconds := minf(delta, w.water_effect)
		w.water_effect = maxf(0.0, w.water_effect - delta)
		w.hunger = maxf(0.0, w.hunger - HUNGER_DECAY_PER_DAY * delta / DAY_SECONDS)
		if w.fatigue >= 100.0 and w.state not in ["sleep", "to_bed"]:
			start_sleep(w)
		if w.state == "sleep" and not beds.has(w.bed) and not w.get("used_bed_this_sleep", false) and dispatch_timer >= 0.2:
			try_sleep_in_bed(w)
		if refreshed_seconds == 0:
			start_drink(w)
		record_action(w, delta)
		var was_working: bool = w.state in FATIGUING_STATES
		match w.state:
			"drink":
				w.drink_progress += delta
				if w.drink_progress >= DRINK_HOURS * HOUR_SECONDS - 0.000001:
					w.water -= 1
					w.water_effect = WATER_EFFECT_HOURS * HOUR_SECONDS
					w.state = w.drink_resume
					w.drink_resume = ""
					w.drink_progress = 0.0
			"sleep":
				var recovery := SLEEP_RECOVERY_PER_HOUR
				if beds.has(w.bed):
					var bed: Dictionary = beds[w.bed]
					recovery = BED_RECOVERY_PER_HOUR
					bed.remaining = maxf(0, bed.remaining - delta)
					if bed.remaining <= 0:
						release_bed(w)
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
					pay_labor(w, bench.task, delta)
					if bench.task.progress >= bench.task.seconds - 0.000001:
						if building_kind(w.station) == "printer":
							printed_workers.append(w.station + Vector2i.RIGHT)
							bench.queue -= 1
						else:
							var amount: int = PRODUCTS[building_kind(w.station)].get("amount", 1)
							bench.stock += amount
							bench.produced_today = bench.get("produced_today", 0) + amount
						bench.task = {}
						w.station = Vector2i(-1, -1)
						w.state = "idle"
			"to_shop":
				if move_worker(w, delta):
					if benches.has(w.station):
						var product: Dictionary = PRODUCTS[building_kind(w.station)]
						if building_kind(w.station) == "purifier":
							var amount := water_purchase_count(w, benches[w.station].stock)
							benches[w.station].stock -= amount
							w.water += amount
							w.bread -= amount * WATER_PRICE
							w.shop_spent_today += amount * WATER_PRICE
							player_bread += amount * WATER_PRICE
						elif product.has("durability") and benches[w.station].stock > 0 and w.bread >= product.price and w[product.durability] == 0:
							benches[w.station].stock -= 1
							w.bread -= product.price
							w.shop_spent_today += product.price
							player_bread += product.price
							w[product.durability] = product.uses
					w.station = Vector2i(-1, -1)
					w.state = "idle"
			"build":
				if sites.has(w.building):
					var task: Dictionary = sites[w.building]
					pay_labor(w, task, delta)
					if task.progress >= task.seconds - 0.000001:
						if PRODUCTS.has(task.get("kind", "bed")):
							benches[w.building] = production_station(task.kind)
						elif task.get("kind", "bed") == "bank":
							banks[w.building] = {"interest_received": 0.0}
						elif task.get("kind", "bed") == "belt":
							belts[w.building] = {"direction": task.direction, "inputs": task.inputs, "cargo": -1, "last_input": -1}
						else:
							beds[w.building] = {"owner": -1, "remaining": 0.0, "assigned": -1}
						sites.erase(w.building)
						w.building = Vector2i(-1, -1)
						w.state = "idle"
			"to_bed":
				if move_worker(w, delta):
					beds[w.bed].remaining = BED_LEASE_HOURS * HOUR_SECONDS
					w.state = "sleep"
			"dig":
				var target: Vector2i = w.job
				var rate := GUN_MINING_RATE if w.gun_uses > 0 else 1.0
				if mining_contracts.has(target):
					pay_labor(w, mining_contracts[target], delta, rate)
					w.progress = mining_contracts[target].progress
				else:
					w.progress += delta * rate
				if w.progress >= mining_seconds(target) - 0.000001:
					w.gun_uses = maxi(0, w.gun_uses - 1)
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
					w.job = Vector2i(-1, -1)
					update_fog()
					w.state = "idle"
					assign_job(w)
			"haul":
				if move_worker(w, delta):
					if w.pos.distance_to(Vector2(w.haul_target)) < 0.01:
						w.state = "deposit"
						w.progress = 0.0
					else:
						start_haul(w, false)
			"deposit":
				w.progress += delta
				if w.progress >= 0.6 - 0.0000001:
					var target: Vector2i = w.haul_target
					if target != BASE:
						if not belts.has(target) or belts[target].cargo >= 0 or not belt_reaches_base(target):
							start_haul(w, false)
							continue
						var ore := take_carried_ore(w)
						belt_cargo[next_cargo_id] = {"ore": ore, "worker": w.id, "from": target, "to": target, "progress": 0.0}
						belts[target].cargo = next_cargo_id
						next_cargo_id += 1
						if w.carry > 0:
							w.progress = 0.0
							continue
					else:
						while w.carry > 0:
							deliver_ore(take_carried_ore(w), w.id)
					w.state = "idle"
					if daily_budget_ready(w):
						start_meal(w)
			"eat":
				w.progress += delta
				if w.progress >= MEAL_SECONDS - 0.0000001:
					w.hunger = minf(MAX_HUNGER, w.hunger + w.meal_bread * HUNGER_PER_BREAD)
					w.eaten_today += w.meal_bread
					w.meal_bread = 0
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
						try_shop_trip(w)
				if w.state == "rest":
					wander(w, delta)
		if was_working:
			w.fatigue = minf(100.0, w.fatigue + FATIGUE_PER_HOUR * (delta - refreshed_seconds * WATER_FATIGUE_REDUCTION) / HOUR_SECONDS)
			if w.fatigue >= 100.0 - 0.000001:
				w.fatigue = 100.0
				start_sleep(w)
			elif daily_budget_ready(w) and (not has_debt(w) or needs_meal(w)) and w.state in ["dig", "build", "work"]:
				release_work(w)
				w.state = "idle"
				start_meal(w)
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
	w.station = Vector2i(-1, -1)
	if jobs.get(w.job, -1) == w.id:
		jobs[w.job] = -1
	w.job = Vector2i(-1, -1)
	if sites.has(w.building) and sites[w.building].owner == w.id:
		sites[w.building].owner = -1
	w.building = Vector2i(-1, -1)
	w.path = []
	w.pos = w.pos.round()
	w.progress = 0.0

func start_sleep(w: Dictionary) -> void:
	if w.state in ["sleep", "to_bed"]:
		return
	release_work(w)
	w.state = "sleep"
	w.used_bed_this_sleep = false
	try_sleep_in_bed(w)

func assign_bed(p: Vector2i, worker_id: int) -> void:
	if not beds.has(p) or worker_id < -1 or worker_id >= workers.size():
		return
	for other in beds:
		if worker_id >= 0 and beds[other].get("assigned", -1) == worker_id:
			beds[other].assigned = -1
	beds[p].assigned = worker_id

func try_sleep_in_bed(w: Dictionary) -> bool:
	try_borrow(w)
	if w.bread < BED_PRICE or beds.has(w.bed):
		return false
	var selected := Vector2i(-1, -1)
	var best_path: Array[Vector2i] = []
	var preferred := Vector2i(-1, -1)
	for p in beds:
		if beds[p].get("assigned", -1) == w.id:
			preferred = p
	for p in beds:
		var assigned: int = beds[p].get("assigned", -1)
		if beds[p].owner != -1 or (assigned >= 0 and assigned != w.id):
			continue
		if preferred != Vector2i(-1, -1) and p != preferred:
			continue
		var path := route(Vector2i(w.pos.round()), p)
		if path.is_empty() and Vector2i(w.pos.round()) != p:
			continue
		if selected == Vector2i(-1, -1) or path.size() < best_path.size():
			selected = p
			best_path = path
	if selected == Vector2i(-1, -1):
		return false
	w.bread -= BED_PRICE
	w.bed_spent_today += BED_PRICE
	player_bread += BED_PRICE
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
	w.bed = Vector2i(-1, -1)

func action_for(w: Dictionary) -> String:
	match w.state:
		"dig": return "挖掘"
		"work", "build", "use_tool", "deposit": return "工作"
		"haul": return "搬运"
		"walk", "to_build", "to_bed", "to_work", "to_shop": return "通勤"
		"eat": return "吃饭"
		"drink": return "吃饭"
		"sleep": return "睡觉"
		"wait": return "等待"
		"idle": return "等待" if not jobs.is_empty() else "空闲"
	return "空闲"

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
	camera.position = camera.position.clamp(Vector2.ZERO, Vector2(SIZE) * CELL)
	if not simulation_paused and not reset_dialog.visible:
		animation_time += delta * speed
		simulate(minf(delta, 0.1) * speed)
	update_ui()
	world_view.sync_dynamic()

# Workers reveal a circular radius through terrain; exploration persists.
func update_fog() -> void:
	visible_tiles.clear()
	for w in workers:
		var origin := Vector2i(w.pos.round())
		for y in range(-VISION_RADIUS, VISION_RADIUS + 1):
			for x in range(-VISION_RADIUS, VISION_RADIUS + 1):
				var target := origin + Vector2i(x, y)
				if not in_bounds(target) or x * x + y * y > VISION_RADIUS * VISION_RADIUS:
					continue
				visible_tiles[target] = true
				explored[target] = true
	world_view.sync_fog()

func designate(a: Vector2i, b: Vector2i, cancel := false) -> int:
	var count := 0
	for y in range(maxi(1, mini(a.y, b.y)), mini(SIZE.y - 2, maxi(a.y, b.y)) + 1):
		for x in range(maxi(1, mini(a.x, b.x)), mini(SIZE.x - 2, maxi(a.x, b.x)) + 1):
			var p := Vector2i(x, y)
			if cancel and cancel_site(p):
				count += 1
			elif cancel and remove_belt(p):
				count += 1
			if cancel and jobs.has(p):
				var owner: int = jobs[p]
				if owner >= 0:
					var w := workers[owner]
					w.state = "idle"
					w.path = []
					w.pos = w.pos.round()
					w.job = Vector2i(-1, -1)
					w.drink_resume = ""
				jobs.erase(p)
				if mining_contracts.has(p):
					mining_contracts.erase(p)
				count += 1
			elif not cancel and explored.has(p) and terrain[p] != 0 and not jobs.has(p):
				var hours := mining_seconds(p) / HOUR_SECONDS
				mining_contracts[p] = contract(hours)
				jobs[p] = -1
				count += 1
	world_view.sync_orders()
	return count

func mouse_tile() -> Vector2i:
	return Vector2i((get_global_mouse_position() / CELL).floor())

func select_entity(p: Vector2i) -> bool:
	selected_worker = -1
	selected_entity = Vector2i(-1, -1)
	if p == BASE:
		selected_entity = BASE
	else:
		for collection in [beds, sites, benches, banks, belts]:
			for origin in collection:
				if p in building_cells(origin, building_kind(origin)):
					selected_entity = origin
					break
	update_entity_panel()
	return selected_entity != Vector2i(-1, -1)

func clear_entity_selection() -> void:
	selected_worker = -1
	selected_entity = Vector2i(-1, -1)
	update_entity_panel()

func select_worker(worker_id: int) -> bool:
	if worker_id < 0 or worker_id >= workers.size():
		return false
	selected_worker = worker_id
	selected_entity = Vector2i(-1, -1)
	update_entity_panel()
	return true

func update_entity_panel() -> void:
	$UI.update_entity_panel()

func bed_effects_text() -> String:
	return "使用费  %.0f 面包 / %.0fh\n疲劳恢复  −%.0f / h" % [
		BED_PRICE, BED_LEASE_HOURS, BED_RECOVERY_PER_HOUR]

func gun_recipe_text() -> String:
	return product_recipe_text("bench")

func product_recipe_text(kind: String) -> String:
	var product: Dictionary = PRODUCTS[kind]
	var recipe := "%s  %d %s / %.0fh\n工资  %.0f 面包" % [product.name, product.get("amount", 1), product.unit, product.hours, product.hours * WAGE_PER_HOUR]
	if kind == "purifier":
		recipe += "\n原料  %d 份原水" % WATER_BATCH
	elif kind == "printer":
		recipe += "\n原料  %d 矿石方块" % PRINT_WORKER_BLOCKS
	return recipe

func building_effects_text(kind: String) -> String:
	if kind == "belt":
		return "运费  %.1f 面包 / 块\n单格容量  1 块" % BELT_FEE
	if kind == "bank":
		return "借款上限  %.0f 面包\n一次性利息  %.0f%%\n收入还款  %.0f%%\n每日最多一笔 · 还清后再借" % [LOAN_LIMIT, LOAN_INTEREST_RATE * 100, LOAN_REPAYMENT_RATE * 100]
	var effects := product_recipe_text(kind) if PRODUCTS.has(kind) else bed_effects_text()
	if kind == "pump":
		effects += "\n建于水源旁"
	return effects

func gun_effects_text() -> String:
	return product_effects_text("bench")

func product_effects_text(kind: String) -> String:
	if kind == "printer":
		return "完成后加入矿区"
	if kind == "pump":
		return "原水用于净化"
	if kind == "purifier":
		return "售价  %.0f 面包 / 份\n饮用  %.1fh · 持续 %.0fh\n劳动疲劳增长  −%.0f%%" % [WATER_PRICE, DRINK_HOURS, WATER_EFFECT_HOURS, WATER_FATIGUE_REDUCTION * 100]
	if kind == "workbench":
		return "售价  %.0f 面包\n使用次数  %d 次（每次交付两块）\n携带方块  +1" % [BACKPACK_PRICE, BACKPACK_USES]
	return "售价  %.0f 面包\n耐久  %d 格\n挖掘速度  +%.0f%%" % [GUN_PRICE, GUN_USES, (GUN_MINING_RATE - 1.0) * 100.0]

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
			update_building_drag(Vector2i((world_position / CELL).floor()))

func handle_world_input(event: InputEvent, worker_id: int, entity: Vector2i) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		if belt_drawing:
			finish_belt_drag(event.position)
		if building_drawing:
			finish_building_drag(event.position)
		if dragging:
			designate(selection_start, selection_end, tool == "cancel")
			dragging = false
		return
	var belt_entity := entity != Vector2i(-1, -1) and building_kind(entity) == "belt"
	if worker_id >= 0 or (entity != Vector2i(-1, -1) and not (tool == "cancel" and (sites.has(entity) or belts.has(entity))) and not (tool == "belt" and belt_entity)):
		selected_worker = worker_id
		selected_entity = entity
		update_entity_panel()
		dragging = false
	else:
		var world_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var cell := Vector2i((world_position / CELL).floor())
		clear_entity_selection()
		if tool == "belt":
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
			designate(selection_start, selection_end, tool == "cancel")
			dragging = false
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
	if value in BUILDING_KINDS and player_blocks < building_blocks(value):
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
			tool_buttons[kind].disabled = player_blocks < building_blocks(kind)
	if tool in BUILDING_KINDS and player_blocks < building_blocks(tool):
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
