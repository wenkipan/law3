extends RefCounted

const Definitions = preload("res://scripts/simulation/smart_object_definitions.gd")

var id: StringName
var definition: Definitions.ObjectDefinition
var source: Dictionary
var position: Vector2i
# IDs only: endpoints refer to their instance without creating an ownership cycle.
var slot_ids: Dictionary = {}

func _init(object_id: StringName, object_type: Definitions.ObjectDefinition, binding: Dictionary, origin: Vector2i) -> void:
	id = object_id
	definition = object_type
	source = binding
	position = origin

class Endpoint extends RefCounted:
	var id: String
	var instance: RefCounted
	var definition: Definitions.SlotDefinition
	var state: Dictionary
	var position: Vector2i
	var items: Array
	var materials: Array
	var order: int

	func _init(slot_id: String, object: RefCounted, interaction: Definitions.SlotDefinition, claim_state: Dictionary, point: Vector2i, goods: Array, inputs: Array, sequence: int) -> void:
		id = slot_id
		instance = object
		definition = interaction
		state = claim_state
		position = point
		items = goods.duplicate()
		items.make_read_only()
		materials = inputs.duplicate()
		materials.make_read_only()
		order = sequence

	func available_to(worker_id: int) -> bool:
		return state.owner == -1 or state.owner == worker_id
