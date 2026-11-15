extends RefCounted

# Concrete action. Scoring, paths and slot claims do not change its work type.
const WorkTypes = preload("res://scripts/simulation/work_types.gd")
const PARAMETER_KEYS := {
	"payroll": ["employer"],
	"purchase": ["kind", "item", "amount"],
	"use_item": ["item"],
	"service": ["kind"],
	"eat": ["amount", "item", "canteen"],
	"sleep": ["bed"],
	"borrow": ["amount"],
}
const WORK_PARAMETERS := {
	"build": [], "produce": ["project"], "operate": ["job"],
	"deliver": ["mined"], "mine": [], "harvest": [],
}

var _values: Dictionary
var kind: String:
	get: return _values.kind
	set(_value): reject_write()
var target: Vector2i:
	get: return _values.target
	set(_value): reject_write()
var method: String:
	get: return _values.data.get("method", "")
var data: Dictionary:
	get: return _values.data
	set(_value): reject_write()

func _init(activity: String, entity: Vector2i, details: Dictionary) -> void:
	var parameters: Dictionary = {}
	var fields: Array = PARAMETER_KEYS.get(activity, [])
	if WorkTypes.NAMES.has(activity):
		parameters.method = details.method
		fields = WORK_PARAMETERS[details.method]
	for key in fields:
		if details.has(key):
			parameters[key] = details[key]
	parameters.make_read_only()
	_values = {"kind": activity, "target": entity, "data": parameters}
	_values.make_read_only()

func reject_write() -> void:
	push_error("ActivityRecord is read-only; execution state belongs to its activity.")
