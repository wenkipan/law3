extends RefCounted

# Observations only: alerts never reserve goods, publish jobs or direct workers.
const HUNGER_THRESHOLD := 20.0
const CHECK_SECONDS := 0.5
var entries: Array[Dictionary] = []
var notices: Dictionary = {}
var pending: Dictionary = {}
var last_time := -INF
var last_refresh := -1000
var money_low := false

func reset() -> void:
	entries.clear()
	notices.clear()
	pending.clear()
	last_time = -INF
	last_refresh = -1000
	money_low = false

func research_completed(g: Node, project: String) -> void:
	var id := "research:" + project
	notices[id] = {"id": id, "text": "研究完成：" + g.Technology.PROJECTS[project].name,
		"severity": 0, "targets": [], "project": project}

func dismiss(id: String) -> void:
	notices.erase(id)

func refresh(g: Node, force := false) -> void:
	var now: float = (g.world.day - 1) * g.DAY_SECONDS + g.world.day_elapsed
	var ticks := Time.get_ticks_msec()
	if not force and now - last_time < CHECK_SECONDS and ticks - last_refresh < 250:
		return
	last_time = now
	last_refresh = ticks
	var observed: Dictionary = {}
	var groups: Dictionary = {}
	var inventory: Dictionary = g.player_inventory()
	var reserve := 0.0
	for w in g.world.workers:
		if w.employer != null: reserve += g.hunger_decay(w) / 20.0
	var food: float = inventory.berries + inventory.meat + inventory.wheat + inventory.bread
	money_low = reserve > 0 and food < reserve * (1.25 if money_low else 1.0)
	if money_low:
		groups.money = {"id": "money", "text": "食物不足", "severity": 1, "targets": [{"entity": g.BASE}]}
	var sick := false
	for w in g.world.workers:
		if not g.cache.visible_tiles.has(Vector2i(w.pos.round())): continue
		var target := {"worker": w.id}
		if w.pollution >= g.Pollution.DISEASE:
			sick = true
			add(groups, "illness", "名工人患病", 2, target)
		if w.hunger < HUNGER_THRESHOLD and w.meal_food <= 0 and mature("hunger:" + str(w.id), now, g.HOUR_SECONDS * 0.5, observed):
			add(groups, "hunger", "名工人饥饿", 2, target)
	for p in g.world.building_positions("station"):
		if not g.cache.visible_tiles.has(p): continue
		var b: Dictionary = g.world.building_state(p, "station")
		for item in production_shortages(g, p):
			var id := "input:%s:%s" % [b.kind, item]
			if shortage_mature(g, id + str(p), p, item, now, observed):
				add(groups, id, "个%s缺少%s" % [g.building_name(b.kind), "方块" if is_same(item, 0) else g.item_name(item)], 1, {"entity": p})
		if b.kind == "hospital" and sick and missing(g, p, "medical", g.SERVICES.hospital.materials.medical):
			if shortage_mature(g, "medical:" + str(p), p, "medical", now, observed):
				add(groups, "medical", "个医院缺少医疗用品", 2, {"entity": p})
	for p in g.world.building_positions("station") + g.world.building_positions("belt"):
		if not g.cache.visible_tiles.has(p): continue
		if g.power_demand(p) > 0 and not g.cache.powered_devices.has(p):
			if mature("power:" + str(p), now, g.HOUR_SECONDS, observed):
				add(groups, "power", "个设备未供电", 1, {"entity": p})
	for p in g.world.building_positions("site"):
		if g.world.building_state(p, "site").get("cancelled", false) or not g.cache.visible_tiles.has(p) or not g.site_cleared(p): continue
		var reachable := false
		for w in g.world.workers:
			if not g.construction_route(Vector2i(w.pos.round()), p).is_empty():
				reachable = true
				break
		if not reachable and not g.world.workers.is_empty() and mature("access:" + str(p), now, g.HOUR_SECONDS, observed):
			add(groups, "access", "处工地无法到达", 1, {"entity": p})
	for key in pending.keys():
		if not observed.has(key): pending.erase(key)
	entries.clear()
	for entry in groups.values():
		if entry.id != "money": entry.text = "%d %s" % [entry.targets.size(), entry.text]
		entries.append(entry)
	for entry in notices.values(): entries.append(entry)
	entries.sort_custom(func(a, b): return a.id < b.id if a.severity == b.severity else a.severity > b.severity)

func mature(key: String, now: float, delay: float, observed: Dictionary) -> bool:
	observed[key] = true
	if not pending.has(key): pending[key] = now
	return now - pending[key] >= delay - 0.000001

func shortage_mature(g: Node, key: String, p: Vector2i, item, now: float, observed: Dictionary) -> bool:
	var supplying := incoming(g, p, item) > 0
	return mature(key + (":delivery" if supplying else ""), now, g.HOUR_SECONDS * (4.0 if supplying else 1.0), observed)

func add(groups: Dictionary, id: String, text: String, severity: int, target: Dictionary) -> void:
	if not groups.has(id): groups[id] = {"id": id, "text": text, "severity": severity, "targets": []}
	groups[id].targets.append(target)

func missing(g: Node, p: Vector2i, item, amount: float) -> bool:
	var stock := 0.0
	if is_same(item, 0):
		for ore in range(1, g.ORES.size()): stock += g.stock_at(p, ore)
	else:
		stock = g.stock_at(p, item)
	return stock + 0.000001 < amount

func production_shortages(g: Node, p: Vector2i) -> Array:
	var items: Array = []
	if not g.world.has_building(p, "station"): return items
	var b: Dictionary = g.world.building_state(p, "station")
	if b.get("wage", g.WAGE_PER_HOUR) == 0: return items
	if not (g.PRODUCTS.has(b.kind) or b.kind == "research_bench"): return items
	if not g.has_production_order(p) or not b.task.is_empty() or b.growth > 0 or b.harvest: return items
	var recipe: Dictionary = g.station_materials(p)
	for item in recipe:
		if missing(g, p, item, recipe[item]): items.append(item)
	return items

func incoming(g: Node, p: Vector2i, item) -> float:
	if not is_same(item, 0): return g.incoming(p, item)
	var amount := 0.0
	for ore in range(1, g.ORES.size()): amount += g.incoming(p, ore)
	return amount

func money_targets(g: Node) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for p in g.stock_locations() + g.world.building_positions("site"):
		if g.cache.visible_tiles.has(p) and g.storage_contents(p).get("money", 0.0) > 0:
			var target := {"entity": p}
			if target not in targets: targets.append(target)
	for w in g.world.workers:
		var carrying := false
		for shipment in g.world.delivery_tasks:
			if shipment.picked and not shipment.get("on_belt", false) and shipment.owner == w.id and is_same(shipment.item, "money"):
				carrying = true
		if w.money + w.payroll + w.meal_food > 0 or carrying:
			targets.append({"worker": w.id})
	for cargo in g.world.belt_cargo.values():
		if not is_same(cargo.delivery.item, "money"): continue
		var p: Vector2i = cargo.to if g.world.has_building(cargo.to, "belt") else cargo.from
		var target := {"entity": p}
		if g.cache.visible_tiles.has(p) and target not in targets: targets.append(target)
	return targets

func find(id: String) -> Dictionary:
	for entry in entries:
		if entry.id == id: return entry
	return {}
