extends RefCounted

# Proposal containers are immutable. Referenced world orders retain their own live identity.
var _values: Dictionary
var kind: String:
	get: return _values.kind
	set(_value): reject_write()
var target:
	get: return _values.target
	set(_value): reject_write()
var approach_position: Vector2i:
	get: return _values.approach_position
	set(_value): reject_write()
var approach_path: Array[Vector2i]:
	get: return _values.approach_path
	set(_value): reject_write()
var slots: Array[String]:
	get: return _values.slots
	set(_value): reject_write()
var data: Dictionary:
	get: return _values.data
	set(_value): reject_write()
var score: float:
	get: return _values.score
	set(_value): reject_write()

func _init(activity: String, entity, approach: Vector2i, route: Array[Vector2i], required_slots: Array[String], value: float, details: Dictionary = {}) -> void:
	var initial_path: Array[Vector2i] = route.duplicate()
	initial_path.make_read_only()
	var slot_keys: Array[String] = required_slots.duplicate()
	slot_keys.make_read_only()
	var parameters := details.duplicate()
	parameters.make_read_only()
	_values = {"kind": activity, "target": entity, "approach_position": approach,
		"approach_path": initial_path, "slots": slot_keys, "score": value, "data": parameters}
	_values.make_read_only()

func reject_write() -> void:
	push_error("ActivityOption is read-only; execution state belongs to its activity.")

func same_activity(other) -> bool:
	return other != null and kind == other.kind and target == other.target and data.get("job") == other.data.get("job") and is_same(data.get("shipment"), other.data.get("shipment"))
