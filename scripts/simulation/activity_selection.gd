extends RefCounted

const Context = preload("res://scripts/simulation/worker_context.gd")
const Evaluation = preload("res://scripts/simulation/activity_evaluation.gd")
const Parameters = preload("res://scripts/simulation/activity_parameters.gd")
const Option = preload("res://scripts/simulation/activity_option.gd")
const Slots = preload("res://scripts/simulation/smart_objects.gd")

static func options(g, w: Dictionary, reason := "select") -> Array:
	g.ai_trace.begin_decision(w.id)
	var c = Context.new(g, w)
	var e = Evaluation.new(c)
	var choices: Array = []
	add(c, e, choices, "rest", c.origin)
	life_options(c, e, choices)
	shopping_options(c, e, choices)
	var work: Array = []
	work_options(c, e, work)
	if w.payroll > 0.000001:
		choices.append_array(work)
	elif not work.is_empty():
		for p in g.smart_objects.query("store"):
			if g.stock_at(p, "bread") > 0:
				add(c, e, choices, "payroll", p, {}, [], {"work_options": work})
			else:
				e.reject("payroll", p, "no_employer_cash")
	delivery_options(c, e, choices)
	var order: Dictionary = {}
	for i in choices.size():
		order[choices[i]] = i
	# Stable sort keeps deterministic ties without giving prolific categories more weight.
	choices.sort_custom(func(a, b): return order[a] < order[b] if is_equal_approx(a.score, b.score) else a.score > b.score)
	e.trace_selection(choices, reason)
	return choices

static func add(c, e, choices: Array, kind: String, p: Vector2i, data: Dictionary = {}, slots: Array[String] = [], scoring: Dictionary = {}):
	for id in slots:
		if not c.game.smart_objects.available(id, c.worker.id):
			e.reject(kind, p, "slot_unavailable", {"slot": id, "owner": c.game.smart_objects.owner(id)})
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
		for p in g.smart_objects.query(service.slot):
			if g.can_use_service(w, p):
				add(c, e, choices, "service", p, {"kind": kind}, [Slots.key(service.slot, p)])
	var meal: float = e.meal_amount()
	if meal <= 0 or w.hunger >= Parameters.MEAL_HUNGER:
		e.reject("eat", c.origin, "no_food" if meal <= 0 else "above_meal_threshold",
			{"bread_raw": String.num(w.bread, 17), "whole_bread": floori(w.bread), "meal": meal})
	if meal > 0 and w.hunger < Parameters.MEAL_HUNGER:
		add(c, e, choices, "eat", c.origin, {"amount": meal})
		for p in g.benches:
			if g.building_kind(p) != "canteen":
				continue
			for seat in g.building_cells(p, "canteen"):
				var path: Array[Vector2i] = c.path_to(seat)
				if path.is_empty() or path.size() - 1 > g.CANTEEN_WALK_LIMIT:
					continue
				add(c, e, choices, "eat", seat, {"amount": meal, "canteen": p}, [Slots.key("seat", seat)])
	if w.fatigue >= g.MAX_FATIGUE * Parameters.SLEEP_START:
		add(c, e, choices, "sleep", c.origin, {"bed": false})
		var preferred = null
		for p in g.smart_objects.query("bed"):
			if g.beds[p].assigned == w.id:
				preferred = p
		if w.bread >= g.BED_PRICE:
			for p in g.smart_objects.query("bed"):
				if g.beds[p].assigned not in [-1, w.id] or (preferred != null and p != preferred):
					continue
				add(c, e, choices, "sleep", p, {"bed": true}, [Slots.key("bed", p)])
	# Loans fund an immediate food shortage, never optional shopping or a work quota.
	var shortfall: float = e.food_shortfall()
	if shortfall > 0.001 and e.food_need >= Parameters.BORROW_FOOD_NEED and not g.has_debt(w) and w.loan_day != g.day:
		for p in g.smart_objects.query("bank"):
			if g.stock_at(p, "bread") > 0:
				add(c, e, choices, "borrow", p, {"amount": minf(g.LOAN_LIMIT, shortfall)})

static func shopping_options(c, e, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	for p in g.smart_objects.query("shop"):
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
				add(c, e, choices, "purchase", p, {"kind": kind, "item": item, "amount": amount, "identity": g.benches[p]})

static func work_options(c, e, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	if not w.freight.is_empty() or not w.ore_delivery.is_empty() or g.cargo_count(w) >= g.carry_capacity(w):
		e.reject("work", null, "cargo_commitment_or_capacity")
		return
	if w.carry == 0:
		for p in g.smart_objects.query("build"):
			if g.sites[p].get("cancelled", false) or not g.site_cleared(p) or not g.site_supplied(p):
				e.reject("build", p, "cancelled" if g.sites[p].get("cancelled", false) else "footprint_blocked" if not g.site_cleared(p) else "missing_materials")
				continue
			add(c, e, choices, "build", p, {"identity": g.sites[p]}, [Slots.key("build", p)])
		for p in g.smart_objects.query("work"):
			var b: Dictionary = g.benches[p]
			var kind: String = g.building_kind(p)
			if kind in g.OPERATED_KINDS:
				if not g.operation_needed(p):
					e.reject("operate", p, "operation_not_needed_or_disconnected")
					continue
				var slots: Array[String] = [Slots.key("work", p)]
				var data := {"identity": b, "job": null}
				if kind == "drill":
					# Waiting at an unpowered drill must not consume the generation crew.
					if not g.ready_drills.has(p):
						e.reject("operate", p, "drill_power_unavailable")
						continue
					data.job = g.drill_target(p, w.id)
					if data.job == null:
						e.reject("operate", p, "no_available_deposit")
						continue
					slots.append(Slots.key("mine", data.job))
				add(c, e, choices, "operate", p, data, slots)
			elif g.PRODUCTS.has(kind) and b.growth <= 0 and g.has_production_order(p):
				if b.task.is_empty() and not (kind == "barn" and b.slaughter) and not g.recipe_ready(p, g.production_materials(kind)):
					e.reject("produce", p, "missing_materials")
					continue
				add(c, e, choices, "produce", p, {"identity": b}, [Slots.key("work", p)])
			else:
				e.reject("produce", p, "growing" if b.growth > 0 else "no_production_order")
	for p in g.smart_objects.query("mine"):
		if g.terrain[p] in [5, 6]:
			e.reject("mine", p, "requires_drill")
			continue
		var best: Array[Vector2i] = []
		for direction in g.DIRS:
			var path: Array[Vector2i] = c.path_to(p + direction)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
				best = path
		if not best.is_empty():
			add(c, e, choices, "mine", best.back(), {"job": p, "identity": g.mining_contracts[p]}, [Slots.key("mine", p)], {"target": p})
		else:
			e.reject("mine", p, "no_reachable_neighbor")

static func delivery_options(c, e, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	if w.carry > 0:
		if not w.ore_delivery.is_empty():
			var leg: Dictionary = g.delivery_route(c.origin, w.ore_delivery.target)
			add(c, e, choices, "deliver", leg.stop, {"mined": true, "shipment": w.ore_delivery})
			return
		var storage := storage_delivery(c)
		var count: int = choices.size()
		for p in g.smart_objects.query("supply"):
			if g.delivery_need(p, w.carry) < 1.0:
				continue
			var leg: Dictionary = g.delivery_route(c.origin, p)
			if leg.path.is_empty():
				continue
			add(c, e, choices, "deliver", leg.stop,
				{"mined": true, "source": storage.target, "target": p, "item": w.carry,
				"identity": g.smart_objects.identity(Slots.key("supply", p))})
		if choices.size() == count and not storage.leg.path.is_empty():
			add(c, e, choices, "deliver", storage.leg.stop,
				{"mined": true, "source": storage.target, "target": storage.target, "item": w.carry})
		return
	if not w.freight.is_empty():
		var leg: Dictionary = g.delivery_route(c.origin if w.freight.picked else w.freight.source, w.freight.target)
		var approach: Vector2i = leg.stop if w.freight.picked else w.freight.source
		add(c, e, choices, "deliver", approach, {"shipment": w.freight},
			[], {"onward": [] if w.freight.picked else leg.path})
		return
	for shipment in g.shipments:
		if shipment.owner >= 0 or shipment.get("on_belt", false):
			continue
		var leg: Dictionary = g.delivery_route(shipment.source, shipment.target)
		if not leg.path.is_empty():
			add(c, e, choices, "deliver", shipment.source, {"shipment": shipment}, [], {"onward": leg.path})
	for p in g.smart_objects.query("supply"):
		var recipe: Dictionary = g.delivery_requirements(p)
		var items: Array = recipe.keys()
		if recipe.has(0):
			items = [1, 4, 3, 2, 7, 8]
		for item in items:
			if g.delivery_need(p, item) <= 0.000001:
				continue
			for source in g.stock_locations():
				if source == p or g.available_at(source, item) <= 0.000001:
					continue
				var leg: Dictionary = g.delivery_route(source, p)
				if not leg.path.is_empty():
					add(c, e, choices, "deliver", source,
						{"source": source, "target": p, "item": item,
						"identity": g.smart_objects.identity(Slots.key("supply", p))}, [], {"onward": leg.path})

static func storage_delivery(c) -> Dictionary:
	var g = c.game
	var result := {"target": g.BASE, "leg": g.delivery_route(c.origin, g.BASE)}
	for p in g.smart_objects.query("store"):
		if g.sites.has(p) or g.delivery_building_at(p) != p:
			continue
		var leg: Dictionary = g.delivery_route(c.origin, p)
		if not leg.path.is_empty() and (result.leg.path.is_empty() or leg.path.size() < result.leg.path.size()):
			result = {"target": p, "leg": leg}
	return result
