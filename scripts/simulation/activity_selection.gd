extends RefCounted

const Context = preload("res://scripts/simulation/worker_context.gd")
const Option = preload("res://scripts/simulation/activity_option.gd")
const Slots = preload("res://scripts/simulation/smart_objects.gd")

static func options(g, w: Dictionary, reason := "select") -> Array:
	g.ai_trace.begin_decision(w.id)
	var c = Context.new(g, w)
	var choices: Array = []
	life_options(c, choices)
	shopping_options(c, choices)
	var work: Array = []
	work_options(c, work)
	if w.payroll > 0.000001:
		choices.append_array(work)
	elif not work.is_empty():
		var best := 0.0
		for option in work:
			best = maxf(best, option.score)
		for p in g.smart_objects.query("store"):
			if g.stock_at(p, "bread") > 0:
				add(c, choices, "payroll", p, best + 0.02)
			else:
				c.reject("payroll", p, "no_employer_cash")
	delivery_options(c, choices)
	add(c, choices, "rest", c.origin, 0.12)
	for i in choices.size():
		choices[i].order = i
	# Stable sort keeps deterministic ties without giving prolific categories more weight.
	choices.sort_custom(func(a, b): return a.order < b.order if is_equal_approx(a.score, b.score) else a.score > b.score)
	c.trace_selection(choices, reason)
	return choices

static func add(c, choices: Array, kind: String, p: Vector2i, score: float, data: Dictionary = {}, slots: Array[String] = []):
	if score <= 0:
		c.reject(kind, p, "nonpositive_score", {"score": score})
		return null
	for id in slots:
		if not c.game.smart_objects.available(id, c.worker.id):
			c.reject(kind, p, "slot_unavailable", {"slot": id, "owner": c.game.smart_objects.owner(id)})
			return null
	var path: Array[Vector2i] = c.path_to(p)
	if path.is_empty():
		c.reject(kind, p, "unreachable")
		return null
	var option = Option.new(kind, p, score * c.travel_factor(path), data)
	option.path = path
	option.slots = slots
	option.order = choices.size()
	choices.append(option)
	if c.tracing:
		c.proposals.append({"option": option, "base_score": score,
			"travel_factor": c.travel_factor(path), "steps": path.size() - 1})
	return option

static func life_options(c, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	for item in w.items:
		if w.items[item] <= 0: continue
		if g.ITEM_USES.has(item) and g.equipped_amount(w, item) <= 0:
			add(c, choices, "use_item", c.origin, 1.0, {"item": item})
		elif item == "ale" and w.buffs.remaining("tipsy") <= 0 and w.fatigue >= g.WorkerBuffs.ALE_RECOVERY:
			add(c, choices, "use_item", c.origin, 0.8 + 0.2 * w.fatigue / g.MAX_FATIGUE, {"item": item})
		elif item == "meat" and w.hunger < 70:
			add(c, choices, "use_item", c.origin, 1.05 * pow(c.food_need, 2), {"item": item})
		elif item == "cleaner" and g.needs_clothes_wash(w):
			add(c, choices, "use_item", c.origin, 0.8, {"item": item})
	for p in g.smart_objects.query("bath"):
		if g.can_bathe(w, p) and w.carry == 0 and w.freight.is_empty():
			add(c, choices, "bathe", p, 0.55 if w.mood.shopping > 0 else 0.4, {}, [Slots.key("bath", p)])
	var meal := minf(maxf(0, w.bread), maxf(0, g.MAX_HUNGER - w.hunger) / g.HUNGER_PER_BREAD)
	if meal <= 0 or w.hunger >= 70:
		c.reject("eat", c.origin, "no_food" if meal <= 0 else "above_meal_threshold",
			{"bread_raw": String.num(w.bread, 17), "whole_bread": floori(w.bread), "meal": meal})
	if meal > 0 and w.hunger < 70:
		var benefit := pow(c.food_need, 2) * minf(1.0, meal / 4.0)
		add(c, choices, "eat", c.origin, benefit, {"amount": meal})
		for p in g.benches:
			if g.building_kind(p) != "canteen":
				continue
			for seat in g.building_cells(p, "canteen"):
				var path: Array[Vector2i] = c.path_to(seat)
				if path.is_empty() or path.size() - 1 > g.CANTEEN_WALK_LIMIT:
					continue
				var option = add(c, choices, "eat", seat, benefit + 0.22 + 0.1 * w.fatigue / g.MAX_FATIGUE,
					{"amount": meal, "canteen": p}, [Slots.key("seat", seat)])
				if option != null and g.has_powered_effect(Vector2(seat), "fountain"):
					option.score += 0.08
	if w.fatigue >= g.MAX_FATIGUE * 0.2:
		var tired := 1.15 * pow(w.fatigue / g.MAX_FATIGUE, 3)
		if w.fatigue >= g.MAX_FATIGUE:
			tired = 4.0
		add(c, choices, "sleep", c.origin, tired, {"bed": false})
		var preferred = null
		for p in g.smart_objects.query("bed"):
			if g.beds[p].assigned == w.id:
				preferred = p
		if w.bread >= g.BED_PRICE:
			for p in g.smart_objects.query("bed"):
				if g.beds[p].assigned not in [-1, w.id] or (preferred != null and p != preferred):
					continue
				var quiet: float = 1.0 - g.machine_noise_at(Vector2(p)) * 0.15
				add(c, choices, "sleep", p, tired * 1.45 * quiet, {"bed": true}, [Slots.key("bed", p)])
	# Loans fund an immediate food shortage, never optional shopping or a work quota.
	var shortfall := maxf(0, 10.0 - w.hunger / g.HUNGER_PER_BREAD - w.bread)
	if shortfall > 0.001 and c.food_need >= 0.7 and not g.has_debt(w) and w.loan_day != g.day:
		for p in g.smart_objects.query("bank"):
			if g.stock_at(p, "bread") > 0:
				add(c, choices, "borrow", p, 1.1 * c.food_need, {"amount": minf(g.LOAN_LIMIT, shortfall)})

static func shopping_options(c, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	if w.carry > 0 or not w.freight.is_empty():
		c.reject("purchase", null, "carrying_goods")
		return
	for p in g.smart_objects.query("shop"):
		var kind: String = g.building_kind(p)
		for item in g.shop_goods(p):
			if g.stock_at(p, item) <= 0 or not g.wants_item(w, item): continue
			var product: Dictionary = g.sale_product(p, item)
			var price: float = g.sale_price(p, item)
			if w.bread < price:
				c.reject("purchase", p, "insufficient_balance", {"price": price, "balance": w.bread})
				continue
			var amount := 1
			var score := 0.85 * float(product.price) / price
			if item == "clean_water":
				amount = mini(w.mood.water_limit(g.WATER_CAPACITY), mini(g.stock_at(p, item), floori(w.bread / price)))
				score = (0.65 if w.mood.shopping > 0 else 0.5) / price
			elif item == "ale":
				score = (0.65 if w.mood.shopping > 0 else 0.5) * product.price / price
			elif item == "meat":
				score = 1.05 * pow(c.food_need, 2)
			elif item == "cleaner":
				score = 0.8 * (1.0 - w.clothes_cleanliness / 100.0) * product.price / price
			add(c, choices, "purchase", p, score, {"kind": kind, "item": item, "amount": amount, "identity": g.benches[p]})

static func work_options(c, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	if not w.freight.is_empty() or not w.ore_delivery.is_empty() or g.cargo_count(w) >= g.carry_capacity(w):
		c.reject("work", null, "cargo_commitment_or_capacity")
		return
	if w.carry == 0:
		for p in g.smart_objects.query("build"):
			if g.sites[p].get("cancelled", false) or not g.site_cleared(p) or not g.site_supplied(p):
				c.reject("build", p, "cancelled" if g.sites[p].get("cancelled", false) else "footprint_blocked" if not g.site_cleared(p) else "missing_materials")
				continue
			add(c, choices, "build", p, c.labor_score(null, g.sites[p]), {"identity": g.sites[p]}, [Slots.key("build", p)])
		for p in g.smart_objects.query("work"):
			var b: Dictionary = g.benches[p]
			var kind: String = g.building_kind(p)
			if kind in g.OPERATED_KINDS:
				if not g.operation_needed(p):
					c.reject("operate", p, "operation_not_needed_or_disconnected")
					continue
				var slots: Array[String] = [Slots.key("work", p)]
				var data := {"identity": b, "job": null}
				if kind == "drill":
					# Waiting at an unpowered drill must not consume the generation crew.
					if not g.ready_drills.has(p):
						c.reject("operate", p, "drill_power_unavailable")
						continue
					data.job = g.drill_target(p, w.id)
					if data.job == null:
						c.reject("operate", p, "no_available_deposit")
						continue
					slots.append(Slots.key("mine", data.job))
				var task: Dictionary = g.mining_contracts[data.job] if kind == "drill" else b.task
				add(c, choices, "operate", p, c.labor_score(p, task), data, slots)
			elif g.PRODUCTS.has(kind) and b.growth <= 0 and g.has_production_order(p):
				if b.task.is_empty() and not (kind == "barn" and b.slaughter) and not g.recipe_ready(p, g.production_materials(kind)):
					c.reject("produce", p, "missing_materials")
					continue
				add(c, choices, "produce", p, c.labor_score(p, b.task), {"identity": b}, [Slots.key("work", p)])
			else:
				c.reject("produce", p, "growing" if b.growth > 0 else "no_production_order")
	for p in g.smart_objects.query("mine"):
		if g.terrain[p] in [5, 6]:
			c.reject("mine", p, "requires_drill")
			continue
		var best: Array[Vector2i] = []
		for direction in g.DIRS:
			var path: Array[Vector2i] = c.path_to(p + direction)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
				best = path
		if not best.is_empty():
			var option = add(c, choices, "mine", best.back(), c.labor_score(null, g.mining_contracts[p]), {"job": p, "identity": g.mining_contracts[p]}, [Slots.key("mine", p)])
			if option != null:
				option.target = p
		else:
			c.reject("mine", p, "no_reachable_neighbor")

static func delivery_options(c, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	if w.carry > 0:
		var full: bool = g.cargo_count(w) >= g.carry_capacity(w)
		if not w.ore_delivery.is_empty():
			var leg: Dictionary = g.delivery_route(c.origin, w.ore_delivery.target)
			add(c, choices, "deliver", leg.stop, 1.1, {"mined": true, "shipment": w.ore_delivery})
			return
		var storage := storage_delivery(c)
		var count: int = choices.size()
		for p in g.smart_objects.query("supply"):
			if g.delivery_need(p, w.carry) < 1.0:
				continue
			var leg: Dictionary = g.delivery_route(c.origin, p)
			if leg.path.is_empty():
				continue
			add(c, choices, "deliver", leg.stop, 1.1 if full else 0.4,
				{"mined": true, "source": storage.target, "target": p, "item": w.carry,
				"identity": g.smart_objects.identity(Slots.key("supply", p))})
		if choices.size() == count and not storage.leg.path.is_empty():
			add(c, choices, "deliver", storage.leg.stop, 1.1 if full else 0.4,
				{"mined": true, "source": storage.target, "target": storage.target, "item": w.carry})
		return
	if not w.freight.is_empty():
		var leg: Dictionary = g.delivery_route(c.origin, w.freight.target)
		add(c, choices, "deliver", leg.stop, 1.1, {"shipment": w.freight})
		return
	for shipment in g.shipments:
		if shipment.owner >= 0 or shipment.get("on_belt", false):
			continue
		var leg: Dictionary = g.delivery_route(shipment.source, shipment.target)
		if not leg.path.is_empty():
			add(c, choices, "deliver", shipment.source, 0.7 + 0.15 * c.income_need, {"shipment": shipment})
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
					var score: float = 0.7 + 0.15 * c.income_need
					var option = add(c, choices, "deliver", source, score,
						{"source": source, "target": p, "item": item,
						"identity": g.smart_objects.identity(Slots.key("supply", p))})
					if option != null:
						option.score = score * c.travel_factor(option.path, leg.path)

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
