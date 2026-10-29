extends RefCounted

signal traced(worker_id: int, event: String, data: Dictionary)

var tracing := false
# Slot identity includes an incarnation and claim serial, never just a coordinate.
var objects: Dictionary = {}
var next_identity := 1
var next_claim := 1

static func key(kind: String, p: Vector2i) -> String:
	return "%s:%d:%d" % [kind, p.x, p.y]

func clear() -> void:
	for id in objects:
		note(objects[id].owner, "invalidated", {"slot": id, "reason": "world_reset"})
	objects.clear()
	# Keep serials monotonic so stale handles cannot refer to a reset world's slots.

func sync(game) -> void:
	var present: Dictionary = {}
	for p in game.beds:
		register(present, key("bed", p), game.beds[p], p)
	for p in game.sites:
		if not game.sites[p].get("cancelled", false):
			register(present, key("build", p), game.sites[p], p)
			register(present, key("supply", p), game.sites[p], p, true)
	for p in game.benches:
		register(present, key("work", p), game.benches[p], p)
		register(present, key("supply", p), game.benches[p], p, true)
		if game.PRODUCTS.get(game.building_kind(p), {}).has("price"):
			register(present, key("shop", p), game.benches[p], p, true)
		if game.building_kind(p) == "canteen":
			for seat in game.building_cells(p, "canteen"):
				register(present, key("seat", seat), game.benches[p], seat)
	for p in game.mining_contracts:
		register(present, key("mine", p), game.mining_contracts[p], p)
	for p in game.banks:
		register(present, key("bank", p), game.banks[p], p, true)
		register(present, key("supply", p), game.banks[p], p, true)
	for p in game.stock_locations():
		var source: Dictionary = game.benches[p] if game.benches.has(p) else game.stores.get(p, {})
		register(present, key("store", p), source, p, true)
	for id in objects.keys():
		if not present.has(id):
			invalidate(id)

func register(present: Dictionary, id: String, source: Dictionary, p: Vector2i, shared := false) -> void:
	present[id] = true
	if objects.has(id) and is_same(objects[id].source, source):
		return
	if objects.has(id):
		note(objects[id].owner, "invalidated", {"slot": id, "reason": "object_replaced"})
	objects[id] = {"identity": next_identity, "source": source, "position": p, "shared": shared,
		"owner": -1, "claim": 0, "occupied": false}
	next_identity += 1

func query(kind: String) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for id in objects:
		if id.begins_with(kind + ":"):
			positions.append(objects[id].position)
	return positions

func available(id: String, worker_id := -1) -> bool:
	return objects.has(id) and (objects[id].owner == -1 or objects[id].owner == worker_id)

func identity(id: String) -> int:
	return objects.get(id, {}).get("identity", -1)

func acquire(ids: Array[String], worker_id: int) -> Array[Dictionary]:
	# Validate the entire bundle before writing any slot (e.g. drill + mineral).
	for id in ids:
		if not available(id) or objects[id].shared:
			note(worker_id, "claim_rejected", {"slots": ids, "blocked_slot": id,
				"owner": owner(id), "reason": "missing" if not objects.has(id) else "shared" if objects[id].shared else "occupied"})
			return []
	var handles: Array[Dictionary] = []
	for id in ids:
		var slot: Dictionary = objects[id]
		slot.owner = worker_id
		slot.claim = next_claim
		next_claim += 1
		handles.append({"key": id, "identity": slot.identity, "claim": slot.claim, "owner": worker_id})
	if not handles.is_empty():
		note(worker_id, "reserved", {"claims": handles})
	return handles

func valid(handle: Dictionary) -> bool:
	var slot: Dictionary = objects.get(handle.key, {})
	return not slot.is_empty() and slot.identity == handle.identity and slot.claim == handle.claim and slot.owner == handle.owner

func occupy(handles: Array[Dictionary]) -> bool:
	for handle in handles:
		if not valid(handle):
			note(handle.owner, "occupy_rejected", {"claim": handle, "reason": "stale_handle"})
			return false
	for handle in handles:
		objects[handle.key].occupied = true
	if not handles.is_empty():
		note(handles[0].owner, "occupied", {"claims": handles})
	return true

func release(handles: Array[Dictionary]) -> void:
	for handle in handles:
		if valid(handle):
			note(handle.owner, "released", {"claim": handle})
			var slot: Dictionary = objects[handle.key]
			slot.owner = -1
			slot.occupied = false
			slot.claim = 0
		else:
			note(handle.owner, "release_ignored", {"claim": handle, "reason": "stale_handle"})

func invalidate(id: String) -> void:
	if objects.has(id):
		note(objects[id].owner, "invalidated", {"slot": id, "reason": "removed"})
	objects.erase(id)

func note(worker_id: int, event: String, data: Dictionary) -> void:
	if tracing and worker_id >= 0:
		traced.emit(worker_id, event, data)

func owner(id: String) -> int:
	return objects.get(id, {}).get("owner", -1)
