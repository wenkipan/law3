extends RefCounted

const MapGenerator = preload("res://scripts/map_generator.gd")

var buckets: Dictionary = {}
var locations: Dictionary = {}

func place(id, cell: Vector2i) -> void:
	var chunk := MapGenerator.chunk_at(cell)
	if locations.get(id) == chunk: return
	remove(id)
	locations[id] = chunk
	if not buckets.has(chunk): buckets[chunk] = {}
	buckets[chunk][id] = true

func remove(id) -> void:
	if not locations.has(id): return
	var chunk: Vector2i = locations[id]
	buckets[chunk].erase(id)
	if buckets[chunk].is_empty(): buckets.erase(chunk)
	locations.erase(id)

func at(chunk: Vector2i) -> Dictionary:
	return buckets.get(chunk, {})

func clear() -> void:
	buckets.clear()
	locations.clear()
