extends RefCounted

# A read-only proposal until enter succeeds. World orders are referenced, not copied.
var kind: String
var target = null
var destination: Vector2i
var path: Array[Vector2i] = []
var slots: Array[String] = []
var data: Dictionary = {}
var score := 0.0
var order := 0

func _init(activity: String, place: Vector2i, value: float, details: Dictionary = {}) -> void:
	kind = activity
	target = place
	destination = place
	score = value
	data = details

func same_activity(other) -> bool:
	return other != null and kind == other.kind and target == other.target and data.get("job") == other.data.get("job") and is_same(data.get("shipment"), other.data.get("shipment"))
