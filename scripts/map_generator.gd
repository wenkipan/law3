extends RefCounted

# Macro terrain, surface resources and underground oil are independent layers.
# Every query is coordinate/seed based, including negative coordinates and seams.
const VERSION := 12
const CHUNK_SIZE := 32
const WATER_BLOCK := 9
const WATER := 10
const BERRIES := 11
const WILD_GRAIN := 12
const ANIMAL := 13
const WILD_ITEMS := {BERRIES: "berries", WILD_GRAIN: "wheat", ANIMAL: "meat"}
enum Biome { PLAIN, GRASSLAND, FOREST, MOUNTAIN, WATER }
const BIOME_NAMES := ["平原", "草地", "森林", "山地", "水域"]
const REGION_SIZE := 96
const FOREST_STOCK := 6
const FOREST_REGROWTH_HOURS := 12.0
static var chunk_cache: Dictionary = {}
var seed_value: int
var land_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var lake_noise := FastNoiseLite.new()
var region_cache: Dictionary = {}
var biome_cache: Dictionary = {}

func _init(world_seed: int) -> void:
	seed_value = world_seed
	for entry in [[land_noise, 17, 0.009], [detail_noise, 47, 0.09], [lake_noise, 71, 0.014]]:
		var noise: FastNoiseLite = entry[0]
		noise.seed = int(posmod(world_seed + entry[1], 2147483647))
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = entry[2]
		noise.fractal_octaves = 2

static func chunk_at(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE))

func random_at(cell: Vector2i, channel: int) -> float:
	var value := posmod(seed_value + cell.x * 73856093 + cell.y * 19349663 + channel * 83492791, 2147483647)
	value = posmod((value ^ (value >> 13)) * 1274126177, 2147483647)
	return float(value) / 2147483647.0

func region_at(index: Vector2i) -> Dictionary:
	if not region_cache.has(index):
		region_cache[index] = {"center": (Vector2(index) + Vector2(0.2 + random_at(index, 1) * 0.6, 0.2 + random_at(index, 2) * 0.6)) * REGION_SIZE,
			"biome": mini(3, floori(random_at(index, 3) * 4)), "ore": [2, 3, 4, 8][mini(3, floori(random_at(index, 4) * 4))]}
	return region_cache[index]

func land_region(cell: Vector2i) -> Dictionary:
	var point := Vector2(cell) + Vector2(land_noise.get_noise_2d(cell.x, cell.y), land_noise.get_noise_2d(cell.x + 900, cell.y - 900)) * 22.0
	var index := Vector2i((point / REGION_SIZE).floor())
	var nearest := INF
	var result := {}
	for y in range(index.y - 2, index.y + 3):
		for x in range(index.x - 2, index.x + 3):
			var candidate := region_at(Vector2i(x, y))
			var distance := point.distance_squared_to(candidate.center)
			if distance < nearest:
				nearest = distance
				result = candidate
	return result

func biome_at(cell: Vector2i) -> int:
	if biome_cache.has(cell): return biome_cache[cell]
	var biome: int = land_region(cell).biome
	var dx := float(cell.x)
	var phase := random_at(Vector2i.ZERO, 70) * TAU
	# Connected meandering rivers, not independent water dots. Lakes may join them.
	var river := 16.0 + 8.0 * (sin(dx / 45.0 + phase) - sin(phase)) + 3.0 * sin(dx / 19.0)
	var river_distance := absf(fposmod(cell.y - river + 120.0, 240.0) - 120.0)
	var river_extent := absf(fposmod(dx + 192.0, 384.0) - 192.0)
	var river_water := river_distance < 2.0 and river_extent < 158.0
	var river_lake := pow((river_extent - 145.0) / 10.0, 2) + pow(river_distance / 7.0, 2) < 1.0
	if river_water or river_lake or lake_noise.get_noise_2d(cell.x, cell.y) > 0.58: biome = Biome.WATER
	if biome_cache.size() > 65536: biome_cache.clear()
	biome_cache[cell] = biome
	return biome

func starting_position() -> Vector2i:
	# Select from the ordinary map, without editing land, adding resources or
	# favoring a biome. The opening only requires a physically walkable bank.
	var attempt := 0
	while true:
		var candidate := Vector2i(floori(random_at(Vector2i(attempt, 0), 120) * 4096) - 2048,
			floori(random_at(Vector2i(attempt, 0), 121) * 4096) - 2048)
		if biome_at(candidate) != Biome.WATER: return candidate
		attempt += 1
	return Vector2i.ZERO

func base_material(cell: Vector2i) -> int:
	var biome := biome_at(cell)
	if biome == Biome.WATER: return WATER
	var patch := detail_noise.get_noise_2d(cell.x, cell.y)
	var scatter := random_at(cell, 30)
	match biome:
		Biome.MOUNTAIN:
			if patch > -0.12 and scatter < 0.42:
				var region := land_region(cell)
				var ore: int = region.ore
				if scatter < 0.015 and ore in [2, 3]: return 5 if ore == 2 else 6
				return ore if patch > 0.10 else (1 if scatter < 0.21 else 4)
		Biome.FOREST:
			if patch > -0.3 and scatter < 0.42: return 7
			if patch < -0.2 and scatter < 0.13: return BERRIES
		Biome.PLAIN:
			if patch > 0.0 and scatter < 0.09: return WILD_GRAIN
		Biome.GRASSLAND:
			if patch > -0.05 and scatter < 0.06: return ANIMAL
	# Off-region resources are only one-shot loose outcrops, never full mines.
	if scatter < 0.075: return [1, 2, 3, 4, 7, 8, BERRIES, WILD_GRAIN, ANIMAL][floori(random_at(cell, 31) * 9)]
	return 0

func deposit_stock(cell: Vector2i, material: int, hours: float) -> int:
	if material == 7 and biome_at(cell) == Biome.FOREST: return FOREST_STOCK
	if biome_at(cell) == Biome.MOUNTAIN and material != 7: return maxi(1, floori(80.0 / hours))
	return 1

func oil_at(cell: Vector2i) -> int:
	if biome_at(cell) != Biome.FOREST: return 0
	var index := Vector2i((Vector2(cell) / 24.0).floor())
	var center := index * 24 + Vector2i(4 + int(random_at(index, 90) * 16), 4 + int(random_at(index, 91) * 16))
	return 240 if random_at(index, 92) < 0.3 and Vector2(cell - center).length_squared() <= 4 else 0

func generate_chunk(index: Vector2i) -> PackedByteArray:
	var key := [VERSION, seed_value, index]
	if chunk_cache.has(key): return chunk_cache[key]
	var result := PackedByteArray()
	result.resize(CHUNK_SIZE * CHUNK_SIZE)
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			result[y * CHUNK_SIZE + x] = base_material(index * CHUNK_SIZE + Vector2i(x, y))
	if chunk_cache.size() >= 64: chunk_cache.clear()
	chunk_cache[key] = result
	return result
