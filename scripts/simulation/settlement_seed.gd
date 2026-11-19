extends RefCounted

const Map = preload("res://scripts/map_generator.gd")
const Work = preload("res://scripts/simulation/work_types.gd")
const SEARCH_STRIDE := 12
const SEARCH_RINGS := 32
const WORK_PATH_LIMIT := 15
const STORE_GOODS := {"bread": 16, 7: 12, 1: 12}
const CORE := [
	["market", Vector2i.ZERO],
	["storage_box", Vector2i(-1, 0)],
	["bed", Vector2i(-1, 0)],
	["bed", Vector2i(2, 0)],
]

# Only used while starting a new world. All resulting objects are ordinary
# residents and facilities; there is no settlement account or scheduled upkeep.
static func locate(g, generator, origin: Vector2i) -> Dictionary:
	for ring in range(SEARCH_RINGS + 1):
		for y in range(-ring, ring + 1):
			for x in range(-ring, ring + 1):
				if maxi(absi(x), absi(y)) != ring: continue
				var center := origin + Vector2i(x, y) * SEARCH_STRIDE
				if not near_ecotone(generator, center): continue
				var plan := try_site(g, generator, center, origin)
				if not plan.is_empty(): return plan
	return {}

static func near_ecotone(generator, center: Vector2i) -> bool:
	var forest := false
	var grass := false
	for y in [-9, 0, 9]:
		for x in [-9, 0, 9]:
			var biome: int = generator.biome_at(center + Vector2i(x, y))
			forest = forest or biome == Map.Biome.FOREST
			grass = grass or biome == Map.Biome.GRASSLAND
	return forest and grass

static func try_site(g, generator, center: Vector2i, origin: Vector2i) -> Dictionary:
	var occupied: Dictionary = {}
	var core: Array[Vector2i] = []
	# Keep the store immediately next to the market. Try the beds on either side.
	for bed_row in [-2, 3]:
		occupied.clear()
		core.clear()
		for member in CORE:
			var offset: Vector2i = member[1]
			var p := center + Vector2i(offset.x, bed_row if member[0] == "bed" else offset.y)
			var cells: Array = g.building_cells(p, member[0])
			if cells.any(func(cell): return occupied.has(cell) or generator.base_material(cell) != 0): break
			for cell in cells: occupied[cell] = true
			core.append(p)
		if core.size() == CORE.size(): break
	if core.size() != CORE.size(): return {}

	var region := Rect2i(center - Vector2i.ONE * 19, Vector2i.ONE * 39)
	var candidates := {"gathering_garden": [], "hunting_ground": []}
	for y in range(-WORK_PATH_LIMIT + 1, WORK_PATH_LIMIT):
		for x in range(-WORK_PATH_LIMIT + 1, WORK_PATH_LIMIT):
			if absi(x) + absi(y) >= WORK_PATH_LIMIT: continue
			var p := center + Vector2i(x, y)
			var biome: int = generator.biome_at(p)
			if biome not in [Map.Biome.FOREST, Map.Biome.GRASSLAND]: continue
			var kind := "gathering_garden" if biome == Map.Biome.FOREST else "hunting_ground"
			var resource := Map.BERRIES if biome == Map.Biome.FOREST else Map.ANIMAL
			var found := false
			var valid := true
			for cell in g.building_cells(p, kind):
				if occupied.has(cell) or generator.biome_at(cell) != biome:
					valid = false
					break
				var material: int = generator.base_material(cell)
				if Map.WILD_ITEMS.has(material) and material != resource:
					valid = false
					break
				found = found or material == resource
			if valid and found: candidates[kind].append(p)
	if candidates.values().any(func(sites): return sites.is_empty()): return {}

	var grid := AStarGrid2D.new()
	grid.region = region
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var p := Vector2i(x, y)
			if generator.biome_at(p) == Map.Biome.WATER: grid.set_point_solid(p)
	var production: Dictionary = {}
	for kind in candidates:
		var best := WORK_PATH_LIMIT + 1
		for p in candidates[kind]:
			var path := grid.get_id_path(center, p)
			if not path.is_empty() and path.size() < best:
				best = path.size()
				production[kind] = p
		if not production.has(kind): return {}
		for cell in g.building_cells(production[kind], kind): occupied[cell] = true

	var camp = null
	var nearest := INF
	for y in range(-15, 16):
		for x in range(-15, 16):
			if absi(x) + absi(y) not in [12, 13, 14, 15]: continue
			var p := center + Vector2i(x, y)
			var rank := p.distance_squared_to(origin)
			if rank >= nearest or occupied.has(p) or generator.base_material(p) != 0: continue
			var path := grid.get_id_path(center, p)
			if not path.is_empty() and path.size() <= 19:
				camp = p
				nearest = rank
	if camp == null: return {}
	return {"camp": camp, "core": core, "production": production, "area": region}

static func populate(g, plan: Dictionary) -> void:
	g.ensure_region(plan.area)
	var core: Array = plan.core
	var garden: Vector2i = plan.production.gathering_garden
	var hunt: Vector2i = plan.production.hunting_ground
	var positions := [core[2], core[1], core[0], garden, hunt]
	var people := ["林禾", "阿槐", "米粒", "青禾", "石穗"]
	var skills := [Work.LOGISTICS, Work.LOGISTICS, Work.OPERATIONS, Work.FARMING, Work.FARMING]
	var proprietor := -1
	for i in people.size():
		var resident: Dictionary = g.create_worker(positions[i])
		resident.name = people[i]
		resident.skill = skills[i]
		resident.items["bread"] = 4
		resident.money = 120.0 if i == 0 else 6.0
		if i == 0: proprietor = resident.id

	var market: Dictionary = g.production_station("market")
	market.owner = proprietor
	g.create_building(core[0], "market", market)
	for item in ["berries", "meat", "bread"]: g.add_stock(core[0], item, 4)
	var storage: Dictionary = g.production_station("storage_box")
	storage.owner = proprietor
	g.create_building(core[1], "storage_box", storage)
	for item in STORE_GOODS: g.add_stock(core[1], item, STORE_GOODS[item])
	for i in [2, 3]:
		g.create_building(core[i], "bed", {"owner": proprietor, "remaining": 0.0, "assigned": -1})
	for kind in plan.production:
		var settings: Dictionary = g.production_station(kind)
		settings.merge({"owner": proprietor, "wage": 2.0}, true)
		g.create_building(plan.production[kind], kind, settings)
	g.trace_economy("opening", core[0], {"storage": core[1], "garden": garden, "hunt": hunt, "camp": plan.camp})
