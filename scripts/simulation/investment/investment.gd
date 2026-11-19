extends RefCounted

const Transactions = preload("res://scripts/simulation/transactions.gd")
const Slots = preload("res://scripts/simulation/smart_objects.gd")
const OPERATING_HOURS := 8.0

var tracing := OS.get_cmdline_user_args().has("--trace-investment")

func review(g) -> void:
	var candidates: Array = g.BUILDING_KINDS.filter(func(kind): return g.can_plan_building(kind))
	var land := {}
	for owner in g.world.workers:
		if g.is_child(owner) or owner.money <= 0.0:
			continue
		var origins: Array[Vector2i] = []
		for building in g.world.buildings_owned_by(owner.id):
			origins.append(g.world.building_map.origin(building.id))
		var resident := Vector2i(owner.pos.round())
		if origins.is_empty(): origins.append(resident)
		var best := {}
		for kind in candidates:
			var operation := operating_cycle(g, kind)
			if operation.is_empty(): continue
			if not land.has(kind): land[kind] = sites_by_output(g, kind, operation.output)
			var evaluated := {}
			for origin in origins:
				for sites in land[kind].values():
					var site = nearest_site(g, kind, sites, origin)
					if site == null or evaluated.has(site): continue
					evaluated[site] = true
					var result := evaluate(g, kind, site, operation)
					result.owner = owner.id
					log_event(g, "return", result)
					if result.construction_wage <= owner.money and result.rate > 0.0 and (best.is_empty() or result.rate > best.rate):
						best = result
		if not best.is_empty():
			if g.start_investment(best.position, best.kind, owner.id, 0.0):
				log_event(g, "started", best)

static func sites_by_output(g, kind: String, output) -> Dictionary:
	var sites := {}
	for cell in g.world.terrain:
		if not g.investment_site_valid(cell, kind): continue
		var item = output
		if kind in g.EXTRACTIVE_KINDS:
			var deposit = g.mine_deposit(cell, kind)
			var ore: int = g.world.terrain[deposit]
			item = g.ORES[ore].get("item", ore)
		if not sites.has(item): sites[item] = []
		sites[item].append(cell)
	return sites

static func nearest_site(g, kind: String, land: Array, origin: Vector2i):
	var best = null
	var best_distance := INF
	for cell in land:
		var distance: float = origin.distance_squared_to(cell)
		if distance >= best_distance or not g.investment_site_valid(cell, kind): continue
		if not g.cache.navigation.connected(origin, cell): continue
		best = cell
		best_distance = distance
	return best

static func evaluate(g, kind: String, site: Vector2i, operation: Dictionary) -> Dictionary:
	var output = operation.output
	var hours: float = operation.hours
	if kind in g.EXTRACTIVE_KINDS:
		var deposit = g.mine_deposit(site, kind)
		var ore: int = g.world.terrain[deposit]
		output = g.ORES[ore].get("item", ore)
		hours = g.ORES[ore].hours
	var output_price := Transactions.quote(g, output, site, site)
	var skill: String = g.work_skill(kind)
	var wage := Transactions.quote(g, Transactions.labor(skill), site, site)
	var batches := minf(OPERATING_HOURS / hours, 24.0 / (hours + operation.recovery))
	var revenue: float = batches * operation.units * output_price
	var operating_cost := value_of(g, operation.inputs, site) * batches
	if not skill.is_empty(): operating_cost += batches * hours * wage
	var construction_wage: float = g.building_hours(kind) * Transactions.quote(g, Transactions.labor(g.WorkTypes.LOGISTICS), site, site, 1.0)
	var capital: float = construction_wage + value_of(g, g.building_materials(kind), site)
	return {"kind": kind, "position": site, "output": output, "value": output_price, "operating_cost": operating_cost,
		"construction_wage": construction_wage, "capital": capital, "rate": (revenue - operating_cost) / capital}

static func value_of(g, materials: Dictionary, site: Vector2i) -> float:
	var cost := 0.0
	for item in materials:
		cost += float(materials[item]) * g.DeliveryTrade.bid(g, site, item)
	return cost

static func operating_cycle(g, kind: String) -> Dictionary:
	var definition = g.world.smart_objects.definitions.buildings[kind]
	var inputs: Dictionary = g.production_materials(kind)
	if g.PRODUCTS.has(kind) and not definition.products.is_empty():
		var recipe: Dictionary = g.PRODUCTS[kind]
		var growth: float = g.FARM_GROWTH_HOURS if kind == "farm" else (g.SHEEP_GROWTH_HOURS if kind == "barn" else 0.0)
		return {"output": definition.products[0], "hours": float(recipe.hours), "units": float(recipe.get("amount", 1)),
			"inputs": inputs, "recovery": recipe.get("recovery_hours", growth)}
	if kind in g.EXTRACTIVE_KINDS:
		return {"output": null, "hours": 1.0, "units": 1.0, "inputs": {}, "recovery": 0.0}
	for endpoint in definition.interactions:
		if endpoint.action in [Slots.Action.BED, Slots.Action.SERVICE, Slots.Action.SHOP]:
			var profile: Dictionary = g.SERVICES.get(kind, {})
			var hours: float = profile.get("hours", g.BED_LEASE_HOURS if endpoint.action == Slots.Action.BED else 1.0)
			var units: float = g.MARKET_STOCK if endpoint.action == Slots.Action.SHOP else 1.0
			return {"output": Transactions.service(kind), "hours": hours, "units": units, "inputs": profile.get("materials", {}), "recovery": 0.0}
	return {}

func log_event(g, event: String, fields: Dictionary) -> void:
	if not tracing: return
	var row := {"event": event, "day": g.world.day}
	row.merge(fields)
	print("INVESTMENT ", JSON.stringify(row))
