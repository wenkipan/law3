extends RefCounted

const Context = preload("res://scripts/simulation/worker_context.gd")
const Evaluation = preload("res://scripts/simulation/activity_evaluation.gd")
const Parameters = preload("res://scripts/simulation/activity_parameters.gd")
const Slots = preload("res://scripts/simulation/smart_objects.gd")
const Intent = preload("res://scripts/simulation/activity_intent.gd")
const WorkTypes = preload("res://scripts/simulation/work_types.gd")

var evaluation
var intents: Dictionary = {}
var reason: String

func _init(g, w: Dictionary, trigger := "select", responses_only := false) -> void:
	reason = trigger
	g.ai_trace.begin_decision(w.id)
	var c = Context.new(g, w)
	var e = Evaluation.new(c)
	evaluation = e
	var choices: Array = []
	if not responses_only: add(c, e, choices, "rest", c.origin)
	life_options(c, e, choices)
	shopping_options(c, e, choices)
	var responses: Array = []
	for option in choices:
		if w.activity.response_reason(g, w, option.kind, option.data) != "": responses.append(option)
	var responding: bool = responses_only or not responses.is_empty()
	if responding: choices = responses
	var work: Array = []
	if not responding: work_options(c, e, work)
	if w.payroll > 0.000001:
		choices.append_array(work)
	elif not work.is_empty():
		for p in g.world.smart_objects.positions(Slots.Action.STORE, {"item": "money"}):
			if g.stock_at(p, "money") > 0:
				add(c, e, choices, "payroll", p, {}, [], {"work_options": work})
			else:
				e.reject("payroll", p, "no_employer_cash")
	if not responding: delivery_options(c, e, choices)
	for op in choices:
		var id := intent_key(op)
		if not intents.has(id): intents[id] = Intent.new()
		intents[id].pending.append(op)

static func intent_key(op: Dictionary) -> String:
	if WorkTypes.NAMES.has(op.kind): return "delivery" if op.data.method == "deliver" else "labor"
	match op.kind:
		"purchase", "eat", "use_item": return op.kind + ":" + str(op.data.item)
		"service": return "service:" + op.data.kind
		"payroll": return "labor"
	return op.kind

func next_option():
	var best: Dictionary = {}
	var selected = null
	var representatives: Array = []
	for intent in intents.values():
		var entry: Dictionary = intent.resolve(evaluation, best)
		if entry.is_empty(): continue
		representatives.append(entry)
		if best.is_empty() or Intent.better(entry.option.score, entry.order, best.option.score, best.order):
			best = entry
			selected = intent
	if best.is_empty(): return null
	representatives.sort_custom(func(a, b): return Intent.better(a.option.score, a.order, b.option.score, b.order))
	evaluation.trace_selection(representatives.map(func(entry): return entry.option), reason)
	selected.consume(best.option)
	return best.option

static func add(c, e, choices: Array, kind: String, p: Vector2i, data: Dictionary = {}, slots: Array[String] = [], scoring: Dictionary = {}):
	for id in slots:
		if not c.game.world.smart_objects.available(id, c.worker.id):
			e.reject(kind, p, "slot_unavailable", {"slot": id, "owner": c.game.world.smart_objects.owner(id)})
			return null
	var path: Array[Vector2i] = c.path_to(p)
	if path.is_empty():
		e.reject(kind, p, "unreachable")
		return null
	var opportunity := {"kind": kind, "target": scoring.get("target", p), "position": p, "path": path, "data": data}
	opportunity.merge(scoring)
	opportunity.slots = slots
	opportunity.order = c.proposal_order
	c.proposal_order += 1
	choices.append(opportunity)
	return opportunity

static func life_options(c, e, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	for item in w.items:
		if w.items[item] <= 0: continue
		if not item is String: continue
		if g.ITEM_USES.has(item) and g.equipped_amount(w, item) <= 0:
			add(c, e, choices, "use_item", c.origin, {"item": item})
		elif item == "ale" and w.buffs.remaining("tipsy") <= 0 and w.fatigue >= g.WorkerBuffs.ALE_RECOVERY:
			add(c, e, choices, "use_item", c.origin, {"item": item})
		elif g.eats(w, item) and w.hunger < Parameters.MEAL_HUNGER:
			var amount: float = minf(w.items[item], minf(1.0, (g.MAX_HUNGER - w.hunger) / g.FOOD_RECOVERY[item]))
			add(c, e, choices, "eat", c.origin, {"item": item, "amount": amount})
			var radius: int = g.CANTEEN_WALK_LIMIT
			var area := Rect2i(c.origin - Vector2i.ONE * radius, Vector2i.ONE * (radius * 2 + 1))
			for endpoint in g.world.smart_objects.query(Slots.Action.SEAT, {"area": area, "available_to": w.id}):
				var seat: Vector2i = endpoint.position
				if absi(seat.x - c.origin.x) + absi(seat.y - c.origin.y) > radius: continue
				var path: Array[Vector2i] = c.path_to(seat)
				if path.is_empty() or path.size() - 1 > radius: continue
				add(c, e, choices, "eat", seat, {"item": item, "amount": amount, "canteen": endpoint.instance.position}, [endpoint.id])
	for kind in g.SERVICES:
		for endpoint in g.world.smart_objects.query(Slots.Action.SERVICE, {"type": kind, "available_to": w.id}):
			var p: Vector2i = endpoint.position
			if g.can_use_service(w, p):
				add(c, e, choices, "service", p, {"kind": kind}, [endpoint.id])
	if w.fatigue >= g.MAX_FATIGUE * Parameters.SLEEP_START:
		add(c, e, choices, "sleep", c.origin, {"bed": false})
		var preferred = null
		for p in g.world.smart_objects.positions(Slots.Action.BED):
			if g.world.building_state(p, "bed").assigned == w.id:
				preferred = p
		for endpoint in g.world.smart_objects.query(Slots.Action.BED, {"available_to": w.id}):
			var p: Vector2i = endpoint.position
			if w.money < g.base_fee(p) or g.world.building_state(p, "bed").assigned not in [-1, w.id] or (preferred != null and p != preferred):
				continue
			add(c, e, choices, "sleep", p, {"bed": true}, [endpoint.id])
	# Loans fund an immediate food shortage, never optional shopping or a work quota.
	var shortfall: float = e.food_shortfall()
	if shortfall > 0.001 and e.food_need >= Parameters.BORROW_FOOD_NEED and not g.has_debt(w) and w.loan_day != g.world.day:
		for p in g.world.smart_objects.positions(Slots.Action.BANK):
			if g.building_open(p) and g.stock_at(p, "money") > 0:
				add(c, e, choices, "borrow", p, {"amount": minf(g.LOAN_LIMIT, shortfall)})

static func shopping_options(c, e, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	for endpoint in g.world.smart_objects.query(Slots.Action.SHOP, {"items": c.shopping_items()}):
		var p: Vector2i = endpoint.position
		var kind: String = endpoint.instance.definition.kind
		for item in g.shop_goods(p):
			if g.stock_at(p, item) <= 0 or not g.wants_item(w, item): continue
			var price: float = g.sale_price(p, item)
			if w.money < price:
				e.reject("purchase", p, "insufficient_balance", {"price": price, "balance": w.money})
				continue
			var limit: int = mini(g.purchase_capacity(w, item), mini(g.stock_at(p, item), floori(w.money / price)))
			if item == "clean_water": limit = mini(limit, w.mood.water_limit(g.WATER_CAPACITY))
			if limit > 0:
				add(c, e, choices, "purchase", p, {"kind": kind, "item": item, "limit": limit, "identity": endpoint.instance.source})

static func work_options(c, e, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	if not w.delivery_tasks.is_empty() or g.cargo_count(w) >= g.carry_capacity(w):
		e.reject("work", null, "cargo_commitment_or_capacity")
		return
	if is_same(w.carry, 0):
		for endpoint in c.job_slots():
			var p: Vector2i = endpoint.instance.position
			if not g.can_take_job(w, p): continue
			var data: Dictionary = g.world.smart_objects.labor_offer(endpoint, w.id)
			if data.has("reason"):
				e.reject(endpoint.definition.action, p, data.reason, {"method": endpoint.definition.method})
				continue
			var position: Vector2i = p
			if data.method == "build" and endpoint.instance.definition.kind in g.WorldState.BLOCKING_KINDS:
				var approach: Array[Vector2i] = g.construction_route(c.origin, p)
				if approach.is_empty():
					e.reject(endpoint.definition.action, p, "no_reachable_neighbor")
					continue
				position = approach.back()
			var slots: Array[String] = [endpoint.id]
			if data.get("job") != null: slots.append(Slots.key("mine", data.job))
			add(c, e, choices, endpoint.definition.action, position, data, slots, {"target": p})

static func delivery_options(c, e, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	if w.skill != WorkTypes.LOGISTICS: return
	if not w.delivery_tasks.is_empty():
		add_delivery(c, e, choices, w.delivery_tasks[0].source, w.delivery_tasks,
			w.delivery_tasks.map(func(task): return task.item), w.delivery_tasks[0].get("mined", false))
		return
	var requests: Array = g.world.available_delivery_requests(w.skill)
	if not is_same(w.carry, 0):
		var count: int = choices.size()
		held_deliveries(c, e, choices, requests)
		if choices.size() == count:
			var held: Array = [w.carry] + w.extra_cargo
			var receiver = null
			var distance := 0
			for target in g.world.smart_objects.positions(Slots.Action.STORE):
				if g.world.has_building(target, "site") or g.is_built_market(target) or g.delivery_building_at(target) != target: continue
				var leg: Dictionary = g.delivery_route(c.origin, target)
				if not leg.path.is_empty() and (receiver == null or leg.path.size() < distance):
					receiver = target
					distance = leg.path.size()
			if receiver != null:
				var tasks: Array = []
				for item in held: tasks.append(g.delivery_request(receiver, item, g.delivery_receiver_id(receiver)))
				add_delivery(c, e, choices, c.origin, tasks, held, true)
		return
	var grouped: Dictionary = {}
	for request in requests:
		var key := [request.target, request.bound, request.requested_item, request.source if request.bound else null]
		if not grouped.has(key): grouped[key] = []
		grouped[key].append(request)
	for batch in grouped.values():
		var request: Dictionary = batch[0]
		if request.bound:
			if not g.can_deliver(w, request.source, request.target): continue
			var tasks: Array = []
			var amount := 0.0
			for part in batch:
				if amount + part.amount > g.FREIGHT_CAPACITY: break
				tasks.append(part)
				amount += part.amount
			add_delivery(c, e, choices, request.source, tasks, tasks.map(func(task): return task.item), false)
			continue
		var items: Array = [1, 4, 3, 2, 7, 8] if is_same(request.requested_item, 0) else [request.requested_item]
		for item in items:
			for source in g.world.smart_objects.positions(Slots.Action.STORE, {"item": item}):
				if source == request.target or not g.can_deliver(w, source, request.target): continue
				var limit := mini(batch.size(), mini(int(g.FREIGHT_CAPACITY), floori(g.available_at(source, item) + 0.000001)))
				if limit > 0:
					var bindings: Array = []
					bindings.resize(limit)
					bindings.fill(item)
					add_delivery(c, e, choices, source, batch.slice(0, limit), bindings, false)

static func held_deliveries(c, e, choices: Array, requests: Array) -> void:
	var g = c.game
	var receivers: Dictionary = {}
	for request in requests:
		if not request.bound:
			if not receivers.has(request.target): receivers[request.target] = []
			receivers[request.target].append(request)
	for p in receivers:
		var tasks: Array = []
		var items: Array = []
		for item in [c.worker.carry] + c.worker.extra_cargo:
			for request in receivers[p]:
				if not tasks.has(request) and g.delivery_task_accepts(request, item):
					tasks.append(request)
					items.append(item)
					break
		if not tasks.is_empty(): add_delivery(c, e, choices, c.origin, tasks, items, true)

static func add_delivery(c, e, choices: Array, source: Vector2i, tasks: Array, items: Array, mined: bool) -> void:
	if not c.game.can_deliver(c.worker, source, tasks[0].target): return
	var picked: bool = mined or tasks[0].picked
	var leg: Dictionary = c.game.delivery_route(c.origin if picked else source, tasks[0].target)
	if not leg.path.is_empty():
		add(c, e, choices, tasks[0].kind, leg.stop if picked else source,
			{"method": tasks[0].method, "source": source, "tasks": tasks.duplicate(), "items": items, "mined": mined}, [],
			{"target": tasks[0].target, "onward": [] if picked else leg.path})
