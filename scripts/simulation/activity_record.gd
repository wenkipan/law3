extends RefCounted

# Chosen intent only. Query paths, scores, slots and live object bindings belong
# to the proposal or executor, never to this record.
const PARAMETER_KEYS := {
	"mine": ["job"],
	"operate": ["job"],
	"purchase": ["kind", "item", "amount"],
	"use_item": ["item"],
	"service": ["kind"],
	"eat": ["amount", "canteen"],
	"sleep": ["bed"],
	"borrow": ["amount"],
	"deliver": ["mined"],
}

var _values: Dictionary
var kind: String:
	get: return _values.kind
	set(_value): reject_write()
var target: Vector2i:
	get: return _values.target
	set(_value): reject_write()
var data: Dictionary:
	get: return _values.data
	set(_value): reject_write()

func _init(activity: String, entity: Vector2i, details: Dictionary) -> void:
	var parameters: Dictionary = {}
	for key in PARAMETER_KEYS.get(activity, []):
		if details.has(key):
			parameters[key] = details[key]
	parameters.make_read_only()
	_values = {"kind": activity, "target": entity, "data": parameters}
	_values.make_read_only()

func reject_write() -> void:
	push_error("ActivityRecord is read-only; execution state belongs to its activity.")
