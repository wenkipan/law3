extends RefCounted

const Context = preload("res://scripts/simulation/worker_context.gd")
const Evaluation = preload("res://scripts/simulation/activity_evaluation.gd")
const Parameters = preload("res://scripts/simulation/activity_parameters.gd")
const Option = preload("res://scripts/simulation/activity_option.gd")
const Slots = preload("res://scripts/simulation/smart_objects.gd")

static func options(g, w: Dictionary, reason := "select", responses_only := false) -> Array:
	g.ai_trace.begin_decision(w.id)
	var c = Context.new(g, w)
	var e = Evaluation.new(c)
	var choices: Array = []
	if not responses_only: add(c, e, choices, "rest", c.origin)
	life_options(c, e, choices)
	shopping_options(c, e, choices)
	var work: Array = []
	if not responses_only: work_options(c, e, work)
	if w.payroll > 0.000001:
		choices.append_array(work)
	elif not work.is_empty():
		for p in g.world.smart_objects.query("store"):
			if g.stock_at(p, "bread") > 0:
				add(c, e, choices, "payroll", p, {}, [], {"work_options": work})
			else:
				e.reject("payroll", p, "no_employer_cash")
	if not responses_only: delivery_options(c, e, choices)
	if e.tracing:
		for entry in e.proposals:
			if not choices.has(entry.option): entry.excluded_reason = "needs_employer_cash"
	var responses: Array = []
	for option in choices:
		if w.activity.response_reason(g, w, option.kind, option.data) != "": responses.append(option)
	if responses_only or not responses.is_empty():
		if e.tracing:
			for entry in e.proposals:
				if choices.has(entry.option) and not responses.has(entry.option): entry.excluded_reason = "hard_limit_response_required"
		choices = responses
	var order: Dictionary = {}
	for i in choices.size():
		order[choices[i]] = i
	# Stable sort keeps deterministic ties without giving prolific categories more weight.
	choices.sort_custom(func(a, b): return order[a] < order[b] if is_equal_approx(a.score, b.score) else a.score > b.score)
	e.trace_selection(choices, reason)
	return choices

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
	var result: Dictionary = e.evaluate(opportunity)
	if not is_finite(result.score):
		e.reject(kind, p, "no_finite_estimate")
		return null
	var option = Option.new(kind, opportunity.target, p, path, slots, result.score, data)
	var bonus: float = c.worker.activity.inertia_bonus(option)
	if bonus > 0:
		option = Option.new(kind, opportunity.target, p, path, slots, result.score + bonus, data)
	choices.append(option)
	if e.tracing:
		e.proposals.append({"option": option, "result": result, "inertia_bonus": bonus})
	return option

static func life_options(c, e, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	for item in w.items:
		if w.items[item] <= 0: continue
		if g.ITEM_USES.has(item) and g.equipped_amount(w, item) <= 0:
			add(c, e, choices, "use_item", c.origin, {"item": item})
		elif item == "ale" and w.buffs.remaining("tipsy") <= 0 and w.fatigue >= g.WorkerBuffs.ALE_RECOVERY:
			add(c, e, choices, "use_item", c.origin, {"item": item})
		elif item == "meat" and w.hunger < Parameters.MEAL_HUNGER:
			add(c, e, choices, "use_item", c.origin, {"item": item})
	for kind in g.SERVICES:
		var service: Dictionary = g.SERVICES[kind]
		for p in g.world.smart_objects.query(service.slot):
			if g.can_use_service(w, p):
				add(c, e, choices, "service", p, {"kind": kind}, [Slots.key(service.slot, p)])
	var meal: float = e.meal_amount()
	if meal <= 0 or w.hunger >= Parameters.MEAL_HUNGER:
		e.reject("eat", c.origin, "no_food" if meal <= 0 else "above_meal_threshold",
			{"bread_raw": String.num(w.bread, 17), "whole_bread": floori(w.bread), "meal": meal})
	if meal > 0 and w.hunger < Parameters.MEAL_HUNGER:
		add(c, e, choices, "eat", c.origin, {"amount": meal})
		for p in g.world.benches:
			if g.building_kind(p) != "canteen":
				continue
			for seat in g.canteen_seats(p):
				var path: Array[Vector2i] = c.path_to(seat)
				if path.is_empty() or path.size() - 1 > g.CANTEEN_WALK_LIMIT:
					continue
				add(c, e, choices, "eat", seat, {"amount": meal, "canteen": p}, [Slots.key("seat", seat)])
	if w.fatigue >= g.MAX_FATIGUE * Parameters.SLEEP_START:
		add(c, e, choices, "sleep", c.origin, {"bed": false})
		var preferred = null
		for p in g.world.smart_objects.query("bed"):
			if g.world.beds[p].assigned == w.id:
				preferred = p
		for p in g.world.smart_objects.query("bed"):
			if w.bread < g.base_fee(p) or g.world.beds[p].assigned not in [-1, w.id] or (preferred != null and p != preferred):
				continue
			add(c, e, choices, "sleep", p, {"bed": true}, [Slots.key("bed", p)])
	# Loans fund an immediate food shortage, never optional shopping or a work quota.
	var shortfall: float = e.food_shortfall()
	if shortfall > 0.001 and e.food_need >= Parameters.BORROW_FOOD_NEED and not g.has_debt(w) and w.loan_day != g.world.day:
		for p in g.world.smart_objects.query("bank"):
			if g.stock_at(p, "bread") > 0:
				add(c, e, choices, "borrow", p, {"amount": minf(g.LOAN_LIMIT, shortfall)})

static func shopping_options(c, e, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	for p in g.world.smart_objects.query("shop"):
		var kind: String = g.building_kind(p)
		for item in g.shop_goods(p):
			if g.stock_at(p, item) <= 0 or not g.wants_item(w, item): continue
			var price: float = g.sale_price(p, item)
			if w.bread < price:
				e.reject("purchase", p, "insufficient_balance", {"price": price, "balance": w.bread})
				continue
			var limit: int = mini(g.purchase_capacity(w, item), mini(g.stock_at(p, item), floori(w.bread / price)))
			if item == "clean_water": limit = mini(limit, w.mood.water_limit(g.WATER_CAPACITY))
			for amount in range(1, limit + 1):
				add(c, e, choices, "purchase", p, {"kind": kind, "item": item, "amount": amount, "identity": g.world.benches[p]})

static func work_options(c, e, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	if not w.delivery_tasks.is_empty() or g.cargo_count(w) >= g.carry_capacity(w):
		e.reject("work", null, "cargo_commitment_or_capacity")
		return
	if is_same(w.carry, 0):
		for p in g.world.smart_objects.query("build"):
			if g.world.sites[p].get("cancelled", false) or not g.site_cleared(p) or not g.site_supplied(p):
				e.reject("build", p, "cancelled" if g.world.sites[p].get("cancelled", false) else "footprint_blocked" if not g.site_cleared(p) else "missing_materials")
				continue
			add(c, e, choices, "build", p, {"identity": g.world.sites[p]}, [Slots.key("build", p)])
		for p in g.world.smart_objects.query("work"):
			var b: Dictionary = g.world.benches[p]
			var kind: String = g.building_kind(p)
			if kind in g.OPERATED_KINDS:
				if not g.operation_needed(p):
					e.reject("operate", p, "operation_not_needed_or_disconnected")
					continue
				var slots: Array[String] = [Slots.key("work", p)]
				var data := {"identity": b, "job": null}
				if kind == "drill":
					# Waiting at an unpowered drill must not consume the generation crew.
					if not g.cache.ready_drills.has(p):
						e.reject("operate", p, "drill_power_unavailable")
						continue
					data.job = g.drill_target(p, w.id)
					if data.job == null:
						e.reject("operate", p, "no_available_deposit")
						continue
					slots.append(Slots.key("mine", data.job))
				add(c, e, choices, "operate", p, data, slots)
			elif (g.PRODUCTS.has(kind) or kind == "research_bench") and b.growth <= 0 and g.has_production_order(p):
				if b.task.is_empty() and not (kind == "barn" and b.slaughter) and not g.recipe_ready(p, g.station_materials(p)):
					e.reject("produce", p, "missing_materials")
					continue
				add(c, e, choices, "produce", p, {"identity": b}, [Slots.key("work", p)])
			else:
				e.reject("produce", p, "growing" if b.growth > 0 else "no_production_order")
	for p in g.world.smart_objects.query("mine"):
		if g.world.terrain[p] in [5, 6]:
			e.reject("mine", p, "requires_drill")
			continue
		var best: Array[Vector2i] = []
		for direction in g.DIRS:
			var path: Array[Vector2i] = c.path_to(p + direction)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
				best = path
		if not best.is_empty():
			add(c, e, choices, "mine", best.back(), {"job": p, "identity": g.world.mining_contracts[p]}, [Slots.key("mine", p)], {"target": p})
		else:
			e.reject("mine", p, "no_reachable_neighbor")

static func delivery_options(c, e, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	if not w.delivery_tasks.is_empty():
		add_delivery(c, e, choices, w.delivery_tasks[0].source, w.delivery_tasks,
			w.delivery_tasks.map(func(task): return task.item), w.delivery_tasks[0].get("mined", false))
		return
	var requests: Array = g.world.smart_objects.delivery_requests()
	if not is_same(w.carry, 0):
		var count: int = choices.size()
		held_deliveries(c, e, choices, requests)
		if choices.size() == count:
			var held: Array = [w.carry] + w.extra_cargo
			var receiver = null
			var distance := 0
			for target in g.stock_locations():
				if g.world.sites.has(target) or g.delivery_building_at(target) != target: continue
				var leg: Dictionary = g.delivery_route(c.origin, target)
				if not leg.path.is_empty() and (receiver == null or leg.path.size() < distance):
					receiver = target
					distance = leg.path.size()
			if receiver != null:
				var tasks: Array = []
				for item in held: tasks.append(g.delivery_request(receiver, item, g.delivery_receiver_identity(receiver)))
				add_delivery(c, e, choices, c.origin, tasks, held, true)
		return
	var grouped: Array = []
	for request in requests:
		if grouped.has(request): continue
		var batch: Array = []
		for other in requests:
			if other.target == request.target and other.bound == request.bound and is_same(other.requested_item, request.requested_item):
				if not other.bound or other.source == request.source:
					batch.append(other)
					grouped.append(other)
		if request.bound:
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
			for source in g.stock_locations():
				if source == request.target: continue
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
	var picked: bool = mined or tasks[0].picked
	var leg: Dictionary = c.game.delivery_route(c.origin if picked else source, tasks[0].target)
	if not leg.path.is_empty():
		add(c, e, choices, "deliver", leg.stop if picked else source,
			{"source": source, "tasks": tasks.duplicate(), "items": items, "mined": mined}, [],
			{"target": tasks[0].target, "onward": [] if picked else leg.path})
