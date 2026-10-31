extends RefCounted

const VERSION := 5
const CHUNK_SIZE := 32
const WATER := 9
const REGION_SIZE := 128
const SPOT_GRID := 16
const MIN_RADIUS := 6.0
const MAX_RADIUS := 14.0
const SPOT_RATE := 1.5
const SPOT_SEPARATION := 0.6
const SPOT_GAP := 0.5
const SPOT_THRESHOLD := 0.025
const SPECIAL_GRID := 12
const SPECIAL_GAP := 7.0
const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
# Copper, coal, granite, cave density. Sandstone fills the remaining solid ground.
const PROFILES := [Vector4(0.85, 0.18, 0.25, 0.25), Vector4(0.18, 0.85, 0.2, 0.4),
	Vector4(0.2, 0.15, 0.9, 0.15), Vector4(0.25, 0.25, 0.2, 0.85)]
const SPECIALS := {
	5: {"chance": 0.16, "size": Vector2i(1, 1)},
	6: {"chance": 0.16, "size": Vector2i(1, 1)},
	WATER: {"chance": 0.65, "size": Vector2i(1, 1)},
}
static var chunk_cache: Dictionary = {}
var seed_value: int
var camp: Rect2i
var region_cache: Dictionary = {}
var candidate_cache: Dictionary = {}
var spot_cache: Dictionary = {}
var special_cache: Dictionary = {}
var base_cache: Dictionary = {}

func _init(world_seed: int, starting_area := Rect2i()) -> void:
	seed_value = world_seed
	camp = starting_area

static func chunk_at(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE))

func random_at(cell: Vector2i, channel: int) -> float:
	# Bounded integer arithmetic keeps the hash stable for negative coordinates too.
	var value := posmod(seed_value + cell.x * 73856093 + cell.y * 19349663 + channel * 83492791, 2147483647)
	value = posmod((value ^ (value >> 13)) * 1274126177, 2147483647)
	return float(value) / 2147483647.0

func remember(cache: Dictionary, key: Vector2i, value, limit := 2048) -> void:
	if cache.size() >= limit:
		cache.clear()
	cache[key] = value

func region_at(index: Vector2i) -> Dictionary:
	if not region_cache.has(index):
		remember(region_cache, index, {
			"center": (Vector2(index) + Vector2(random_at(index, 1), random_at(index, 2))) * REGION_SIZE,
			"profile": PROFILES[mini(3, int(random_at(index, 3) * PROFILES.size()))],
		}, 128)
	return region_cache[index]

func profile_at(point: Vector2) -> Vector4:
	var index := Vector2i((point / REGION_SIZE).floor())
	var neighbors: Array[Dictionary] = []
	var nearest := INF
	# One feature per grid square: a two-square halo includes every feature within
	# the nearest distance plus the 24-cell transition band, even at grid corners.
	for y in range(index.y - 2, index.y + 3):
		for x in range(index.x - 2, index.x + 3):
			var region := region_at(Vector2i(x, y))
			var distance := point.distance_to(region.center)
			nearest = minf(nearest, distance)
			neighbors.append({"distance": distance, "profile": region.profile})
	var result := Vector4.ZERO
	var total := 0.0
	for region in neighbors:
		var weight := pow(maxf(0.0, 1.0 - (region.distance - nearest) / 24.0), 2)
		result += region.profile * weight
		total += weight
	return result / total

func spot_candidates_at(index: Vector2i) -> Array:
	if not candidate_cache.has(index):
		var result: Array = []
		for field in 4:
			var channel := 20 + field * 10
			var center := (Vector2(index) + Vector2(random_at(index, channel), random_at(index, channel + 1))) * SPOT_GRID
			var profile := profile_at(center)
			# Region weights change composition, not the total amount of sandstone.
			var probability := profile[field] * SPOT_RATE / (profile.x + profile.y + profile.z + profile.w)
			if random_at(index, channel + 2) > probability:
				continue
			# Most deposits are small, with a tail of larger, more elongated deposits.
			var radius := lerpf(MIN_RADIUS, MAX_RADIUS, pow(random_at(index, channel + 3), 2.0))
			result.append({"center": center, "radius": radius,
				"aspect": lerpf(0.55, 1.0, random_at(index, channel + 4)),
				"angle": random_at(index, channel + 5) * TAU,
				"phase": random_at(index, channel + 6) * TAU, "field": field,
				"priority": random_at(index, channel + 7), "index": index,
				"material": (7 if field == 0 else 8) if field < 2 and random_at(index, channel + 8) < 0.35 else field + 2})
		remember(candidate_cache, index, result)
	return candidate_cache[index]

func spot_wins(candidate: Dictionary) -> bool:
	var index: Vector2i = candidate.index
	var reach := ceili((MAX_RADIUS * 2 + SPOT_GAP) / SPOT_GRID)
	for y in range(index.y - reach, index.y + reach + 1):
		for x in range(index.x - reach, index.x + reach + 1):
			for other in spot_candidates_at(Vector2i(x, y)):
				if other.index == index and other.field == candidate.field:
					continue
				if other.priority > candidate.priority:
					continue
				if other.priority == candidate.priority and (y > index.y or (y == index.y and (x > index.x or (x == index.x and other.field > candidate.field)))):
					continue
				if candidate.center.distance_to(other.center) < (candidate.radius + other.radius) * SPOT_SEPARATION + SPOT_GAP:
					return false
	return true

func spots_at(index: Vector2i) -> Array:
	if not spot_cache.has(index):
		var result: Array = []
		# Keep centers apart without forcing every deposit into an isolated circular island.
		for candidate in spot_candidates_at(index):
			if spot_wins(candidate):
				result.append(candidate)
		remember(spot_cache, index, result)
	return spot_cache[index]

func base_material(cell: Vector2i) -> int:
	if camp.has_point(cell):
		return 0
	if base_cache.has(cell):
		return base_cache[cell]
	var point := Vector2(cell) + Vector2.ONE * 0.5
	var index := Vector2i((point / SPOT_GRID).floor())
	var strengths := {0: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 7: 0.0, 8: 0.0}
	var reach := ceili(MAX_RADIUS / SPOT_GRID)
	for y in range(index.y - reach, index.y + reach + 1):
		for x in range(index.x - reach, index.x + reach + 1):
			for spot in spots_at(Vector2i(x, y)):
				var delta: Vector2 = point - spot.center
				if delta.length_squared() >= spot.radius * spot.radius:
					continue
				delta = delta.rotated(-spot.angle)
				delta.y /= spot.aspect
				var angle := delta.angle()
				var edge := 0.84 + 0.1 * sin(angle * 3.0 + spot.phase) + 0.06 * sin(angle * 5.0 - spot.phase * 2.0)
				var falloff := maxf(0.0, 1.0 - delta.length() / (spot.radius * edge))
				var material: int = 0 if spot.field == 3 else spot.material
				strengths[material] = maxf(strengths[material], falloff * falloff)
	var material := 1
	if strengths[0] > SPOT_THRESHOLD:
		material = 0
	else:
		var strongest := SPOT_THRESHOLD
		for ore in [2, 3, 4, 7, 8]:
			if strengths[ore] > strongest:
				strongest = strengths[ore]
				material = ore
	remember(base_cache, cell, material, 16384)
	return material

func special_at(index: Vector2i) -> Dictionary:
	if special_cache.has(index):
		return special_cache[index]
	var center := index * SPECIAL_GRID + Vector2i(int(random_at(index, 80) * SPECIAL_GRID), int(random_at(index, 81) * SPECIAL_GRID))
	var profile := profile_at(Vector2(center))
	var choice := random_at(index, 82)
	var kind := WATER if choice < 0.4 else (5 if choice < 0.4 + 0.6 * profile.x / (profile.x + profile.y) else 6)
	var definition: Dictionary = SPECIALS[kind]
	var cells: Array[Vector2i] = []
	if random_at(index, 83) < definition.chance:
		if kind == WATER:
			var local := center - index * SPECIAL_GRID
			var found := false
			# Search only this candidate's square, not whichever neighbor loaded first.
			for step in SPECIAL_GRID * SPECIAL_GRID:
				var offset := Vector2i((local.x + step % SPECIAL_GRID) % SPECIAL_GRID, (local.y + step / SPECIAL_GRID) % SPECIAL_GRID)
				var location := index * SPECIAL_GRID + offset
				if not camp.grow(2).has_point(location) and base_material(location) != 0 and water_accessible(location, []):
					center = location
					found = true
					break
			if not found:
				var absent := {"kind": kind, "cells": cells, "priority": random_at(index, 86), "index": index}
				remember(special_cache, index, absent)
				return absent
		var size: Vector2i = definition.size
		var count := size.x + int(random_at(index, 84) * (size.y - size.x + 1))
		cells.append(center)
		# A bounded connected footprint; changing size never changes candidate density.
		for step in range(1, count):
			var next := center + Vector2i(step, 0) if random_at(index, 85) < 0.5 else center + Vector2i(0, step)
			cells.append(next)
		for cell in cells:
			if camp.grow(2).has_point(cell) or base_material(cell) == 0:
				cells.clear()
				break
		if kind == WATER and not cells.is_empty():
			var accessible := false
			for cell in cells:
				accessible = accessible or water_accessible(cell, cells)
			if not accessible:
				cells.clear()
	var result := {"kind": kind, "cells": cells, "priority": random_at(index, 86), "index": index}
	remember(special_cache, index, result)
	return result

func water_accessible(cell: Vector2i, footprint: Array) -> bool:
	# Pump is two horizontal cells; retain room for its full footprint.
	for direction in DIRS:
		var neighbor: Vector2i = cell + direction
		if not footprint.has(neighbor) and base_material(neighbor) == 0 and base_material(neighbor + Vector2i.RIGHT) == 0 and not footprint.has(neighbor + Vector2i.RIGHT):
			return true
	return false

func special_wins(candidate: Dictionary) -> bool:
	var reach := ceili((SPECIAL_GAP + max_special_size() * 2) / SPECIAL_GRID) + 1
	var index: Vector2i = candidate.index
	for y in range(index.y - reach, index.y + reach + 1):
		for x in range(index.x - reach, index.x + reach + 1):
			if Vector2i(x, y) == index:
				continue
			var other := special_at(Vector2i(x, y))
			if other.priority > candidate.priority or (other.priority == candidate.priority and (y > index.y or (y == index.y and x > index.x))):
				continue
			for a in candidate.cells:
				for b in other.cells:
					if Vector2(a).distance_to(Vector2(b)) < SPECIAL_GAP:
						return false
	return true

func max_special_size() -> int:
	var result := 1
	for definition in SPECIALS.values():
		result = maxi(result, definition.size.y)
	return result

func generate_chunk(index: Vector2i) -> PackedByteArray:
	var key := [VERSION, seed_value, camp, index]
	if chunk_cache.has(key):
		return chunk_cache[key]
	var result := PackedByteArray()
	result.resize(CHUNK_SIZE * CHUNK_SIZE)
	var origin := index * CHUNK_SIZE
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			result[y * CHUNK_SIZE + x] = base_material(origin + Vector2i(x, y))
	var area := Rect2i(origin, Vector2i.ONE * CHUNK_SIZE)
	var margin := max_special_size()
	var first := Vector2i((Vector2(origin - Vector2i.ONE * margin) / SPECIAL_GRID).floor())
	var last := Vector2i((Vector2(area.end + Vector2i.ONE * margin) / SPECIAL_GRID).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var candidate := special_at(Vector2i(x, y))
			if candidate.cells.is_empty() or not special_wins(candidate):
				continue
			for cell in candidate.cells:
				if area.has_point(cell):
					var local: Vector2i = cell - origin
					result[local.y * CHUNK_SIZE + local.x] = candidate.kind
	if chunk_cache.size() >= 64:
		chunk_cache.clear()
	chunk_cache[key] = result
	return result
