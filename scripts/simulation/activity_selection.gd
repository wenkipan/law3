extends RefCounted

const Context = preload("res://scripts/simulation/worker_context.gd")
const Option = preload("res://scripts/simulation/activity_option.gd")
const Slots = preload("res://scripts/simulation/smart_objects.gd")

static func options(g, w: Dictionary) -> Array:
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
	delivery_options(c, choices)
	add(c, choices, "rest", c.origin, 0.12)
	for i in choices.size():
		choices[i].order = i
	# Stable sort keeps deterministic ties without giving prolific categories more weight.
	choices.sort_custom(func(a, b): return a.order < b.order if is_equal_approx(a.score, b.score) else a.score > b.score)
	return choices

static func add(c, choices: Array, kind: String, p: Vector2i, score: float, data: Dictionary = {}, slots: Array[String] = []):
	if score <= 0:
		return null
	for id in slots:
		if not c.game.smart_objects.available(id, c.worker.id):
			return null
	var path: Array[Vector2i] = c.path_to(p)
	if path.is_empty():
		return null
	var option = Option.new(kind, p, score * c.travel_factor(path), data)
	option.path = path
	option.slots = slots
	option.order = choices.size()
	choices.append(option)
	return option

static func life_options(c, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	var meal := mini(floori(w.bread), ceili(maxf(0, 100.0 - w.hunger) / g.HUNGER_PER_BREAD))
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
				var option = add(c, choices, "eat", seat, benefit + 0.22 + 0.1 * w.fatigue / 100.0,
					{"amount": meal, "canteen": p}, [Slots.key("seat", seat)])
				if option != null and g.has_powered_effect(Vector2(seat), "fountain"):
					option.score += 0.08
	if w.fatigue >= 20:
		var tired := 1.15 * pow(w.fatigue / 100.0, 3)
		if w.fatigue >= 100:
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
		return
	for p in g.smart_objects.query("shop"):
		var kind: String = g.building_kind(p)
		var product: Dictionary = g.PRODUCTS.get(kind, {})
		if not product.has("price") or g.benches[p].stock <= 0:
			continue
		var price: float = g.sale_price(p)
		if w.bread < price:
			continue
		var amount := 1
		var score := 0.85 * float(product.price) / price
		if product.has("durability"):
			if w[product.durability] > 0:
				continue
		else:
			if w.water > 0 or w.water_effect > 0 or g.has_debt(w):
				continue
			amount = mini(w.mood.water_limit(g.WATER_CAPACITY), mini(g.benches[p].stock, floori(w.bread / price)))
			score = (0.65 if w.mood.shopping > 0 else 0.5) / price
		add(c, choices, "purchase", p, score, {"kind": kind, "amount": amount, "identity": g.benches[p]})

static func work_options(c, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	if not w.freight.is_empty() or g.cargo_count(w) >= g.carry_capacity(w):
		return
	if w.carry == 0:
		for p in g.smart_objects.query("build"):
			if g.sites[p].get("cancelled", false) or not g.site_cleared(p) or not g.site_supplied(p):
				continue
			add(c, choices, "build", p, c.labor_score(), {"identity": g.sites[p]}, [Slots.key("build", p)])
		for p in g.smart_objects.query("work"):
			var b: Dictionary = g.benches[p]
			var kind: String = g.building_kind(p)
			if kind in g.OPERATED_KINDS:
				if not g.operation_needed(p):
					continue
				var slots: Array[String] = [Slots.key("work", p)]
				var data := {"identity": b, "job": null}
				if kind == "drill":
					# Waiting at an unpowered drill must not consume the generation crew.
					if not g.ready_drills.has(p):
						continue
					data.job = g.drill_target(p, w.id)
					if data.job == null:
						continue
					slots.append(Slots.key("mine", data.job))
				add(c, choices, "operate", p, c.labor_score(p), data, slots)
			elif g.PRODUCTS.has(kind) and b.growth <= 0 and g.has_production_order(p):
				if b.task.is_empty() and not g.recipe_ready(p, g.production_materials(kind)):
					continue
				add(c, choices, "produce", p, c.labor_score(p), {"identity": b}, [Slots.key("work", p)])
	for p in g.smart_objects.query("mine"):
		if g.terrain[p] >= 5:
			continue
		var best: Array[Vector2i] = []
		for direction in g.DIRS:
			var path: Array[Vector2i] = c.path_to(p + direction)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
				best = path
		if not best.is_empty():
			var option = add(c, choices, "mine", best.back(), c.labor_score(), {"job": p, "identity": g.mining_contracts[p]}, [Slots.key("mine", p)])
			if option != null:
				option.target = p

static func delivery_options(c, choices: Array) -> void:
	var g = c.game
	var w: Dictionary = c.worker
	if w.carry > 0:
		var leg: Dictionary = g.delivery_route(c.origin, g.BASE)
		var full: bool = g.cargo_count(w) >= g.carry_capacity(w)
		add(c, choices, "deliver", leg.stop, 1.1 if full else 0.4, {"mined": true})
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
