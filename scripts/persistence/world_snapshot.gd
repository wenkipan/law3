extends RefCounted

const VERSION := 1
const RULES_VERSION := 1
const MAX_NODES := 200000
const MAX_BYTES := 64 * 1024 * 1024
const MAGIC := "LAW3SNAP"
const MapGenerator = preload("res://scripts/map_generator.gd")
const WorldState = preload("res://scripts/world_state.gd")
const Portal = preload("res://scripts/portal.gd")
const Slots = preload("res://scripts/simulation/smart_objects.gd")
const StateTree = preload("res://scripts/simulation/worker_state_tree.gd")
const Record = preload("res://scripts/simulation/activity_record.gd")
const Work = preload("res://scripts/simulation/activities/work.gd")
const Life = preload("res://scripts/simulation/activities/life.gd")
const Economy = preload("res://scripts/simulation/activities/economy.gd")
const Delivery = preload("res://scripts/simulation/activities/delivery.gd")
const Mood = preload("res://scripts/worker_mood.gd")
const Buffs = preload("res://scripts/simulation/worker_buffs.gd")
const SCRIPTS := {"world": WorldState, "portal": Portal, "slots": Slots,
	"tree": StateTree, "record": Record, "work": Work, "life": Life,
	"economy": Economy, "delivery": Delivery, "mood": Mood, "buffs": Buffs}
const ACTIVITY_FIELDS := ["record", "source_identity", "handles", "path", "destination", "phase", "elapsed", "age"]
static var FIELDS := {
	"world": ["world_seed", "generated_chunks", "terrain", "water_sources", "explored",
		"mining_contracts", "sites", "beds", "benches", "banks", "belts", "power_lines",
		"belt_cargo", "next_cargo_id", "stores", "shipments", "workers", "smart_objects",
		"delivered", "mined", "day", "day_elapsed", "portal", "wander_rng", "daily_records",
		"daily_mined", "resource_flows", "inventory_history", "inventory_sample_time",
		"fog_timer", "recovery_timer", "wastewater", "pollution_operations"],
	"portal": ["input_blocks", "lent_bread", "repaid_principal", "freight_bread"],
	"slots": ["objects", "next_identity", "next_claim"],
	"tree": ["active", "drink_elapsed", "decision_wait", "review_elapsed", "inertia_group", "inertia_hours"],
	"record": ["_values"],
	"work": ACTIVITY_FIELDS + ["segment"],
	"life": ACTIVITY_FIELDS, "economy": ACTIVITY_FIELDS,
	"delivery": ACTIVITY_FIELDS + ["mined", "shipment", "receiver"],
	"mood": ["value", "low_hours", "avoids_machines", "shopping"],
	"buffs": ["timed"], "rng": ["seed", "state"],
}

var error := ""
var nodes: Array = []
var identities: Array = []
var instances: Array = []

static func capture(g) -> Dictionary:
	if not g.world.newborns.is_empty():
		return failure("World is not at a completed simulation step.")
	var codec = load("res://scripts/persistence/world_snapshot.gd").new()
	var root = codec.pack({"world": g.world,
		"sample": {"powered_devices": g.cache.powered_devices, "ready_drills": g.cache.ready_drills,
			"power_output": g.cache.power_output, "visible_tiles": g.cache.visible_tiles},
		"view": {"center": Vector2(g.interaction.view_origin) + g.world_view.camera.position / g.CELL,
			"zoom": g.world_view.camera.zoom.x, "speed": g.interaction.speed,
			"paused": g.interaction.simulation_paused, "pollution": g.interaction.pollution_visible}})
	if codec.error != "": return failure(codec.error)
	var payload := {"version": VERSION, "rules": RULES_VERSION, "map": MapGenerator.VERSION,
		"root": root, "nodes": codec.nodes}
	var data := seal(payload)
	if data.size() > MAX_BYTES: return failure("Snapshot is too large.")
	return {"ok": true, "data": data}

static func digest(data: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish()

static func seal(payload: Dictionary) -> PackedByteArray:
	var data := var_to_bytes(payload)
	return MAGIC.to_ascii_buffer() + digest(data) + data

static func decode(data: PackedByteArray, building_kinds: Array, day_seconds: float) -> Dictionary:
	# Object deserialization is deliberately disabled; only our closed schema may
	# instantiate scripts. Dictionary identities also preserve shared task/freight bindings.
	if data.size() < 44 or data.size() > MAX_BYTES or data.slice(0, 8).get_string_from_ascii() != MAGIC:
		return failure("Invalid snapshot header.")
	var encoded := data.slice(40)
	if digest(encoded) != data.slice(8, 40): return failure("Snapshot checksum failed.")
	var payload = bytes_to_var(encoded)
	if not payload is Dictionary: return failure("Invalid snapshot data.")
	if payload.get("version") != VERSION or payload.get("rules") != RULES_VERSION or payload.get("map") != MapGenerator.VERSION:
		return failure("Incompatible snapshot or game rules version.", "version")
	if not payload.get("nodes") is Array or payload.nodes.size() > MAX_NODES:
		return failure("Invalid snapshot object table.")
	var codec = load("res://scripts/persistence/world_snapshot.gd").new()
	codec.nodes = payload.nodes
	if not codec.check_graph(payload.get("root")): return failure(codec.error)
	codec.allocate()
	codec.fill()
	if codec.error != "": return failure(codec.error)
	var root = codec.unpack(payload.root)
	if not codec.validate(root, building_kinds, day_seconds): return failure(codec.error)
	codec.finish()
	return {"ok": true, "world": root.world, "sample": root.sample, "view": root.view}

static func failure(message: String, code := "invalid") -> Dictionary:
	return {"ok": false, "error": message, "code": code}

func object_kind(value: Object) -> String:
	if value is RandomNumberGenerator: return "rng"
	for kind in SCRIPTS:
		if value.get_script() == SCRIPTS[kind]: return kind
	return ""

func pack(value, depth := 0):
	if depth > 64:
		error = "Snapshot graph is too deep."
		return null
	if value is Dictionary or value is Array or value is Object:
		for i in identities.size():
			if is_same(identities[i], value): return {"ref": i}
		var kind := "dict" if value is Dictionary else ("array" if value is Array else object_kind(value))
		if kind == "" or nodes.size() >= MAX_NODES:
			error = "Unsupported snapshot object."
			return null
		var id := nodes.size()
		identities.append(value)
		var entry := {"kind": kind, "values": []}
		nodes.append(entry)
		if kind == "dict":
			for key in value:
				entry.values.append([pack(key, depth + 1), pack(value[key], depth + 1)])
		elif kind == "array":
			entry.builtin = value.get_typed_builtin()
			if value.get_typed_script() != null or value.get_typed_class_name() != &"":
				error = "Runtime object arrays cannot be saved."
			for item in value: entry.values.append(pack(item, depth + 1))
		else:
			for field in FIELDS[kind]:
				entry.values.append(pack(value.get(field), depth + 1))
		return {"ref": id}
	if not leaf(value): error = "Unsupported snapshot value."
	return value

func leaf(value) -> bool:
	return typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2I, TYPE_COLOR] or (value is float and is_finite(value)) or (value is Vector2 and value.is_finite())

func valid_ref(value) -> bool:
	if value is Dictionary:
		return value.size() == 1 and value.get("ref") is int and value.ref >= 0 and value.ref < nodes.size()
	return leaf(value)

func check_graph(root) -> bool:
	if not valid_ref(root):
		error = "Invalid snapshot root."
		return false
	var dependencies: Array = []
	for entry in nodes:
		if not entry is Dictionary or not entry.get("kind") is String or not entry.get("values") is Array:
			error = "Invalid snapshot entry."
			return false
		var kind: String = entry.kind
		if kind not in ["dict", "array"] and not FIELDS.has(kind):
			error = "Unknown snapshot object type."
			return false
		if kind == "array" and entry.get("builtin") not in [TYPE_NIL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2I, TYPE_DICTIONARY]:
			error = "Invalid snapshot array type."
			return false
		if FIELDS.has(kind) and entry.values.size() != FIELDS[kind].size():
			error = "Incomplete snapshot object."
			return false
		var refs: Array = []
		for item in entry.values:
			var values: Array = [item]
			if kind == "dict":
				if not item is Array or item.size() != 2:
					error = "Invalid snapshot dictionary."
					return false
				values = item
			for token in values:
				if not valid_ref(token):
					error = "Invalid snapshot reference."
					return false
				if token is Dictionary: refs.append(token.ref)
		dependencies.append(refs)
	# No world state supported by this schema contains ownership cycles.
	var marks: Dictionary = {}
	for i in nodes.size():
		if not visit(i, dependencies, marks, 0):
			error = "Cyclic or excessively deep snapshot."
			return false
	return true

func visit(id: int, dependencies: Array, marks: Dictionary, depth: int) -> bool:
	if marks.get(id, 0) == 2: return true
	if marks.get(id, 0) == 1 or depth > 64: return false
	marks[id] = 1
	for other in dependencies[id]:
		if not visit(other, dependencies, marks, depth + 1): return false
	marks[id] = 2
	return true

func allocate() -> void:
	for entry in nodes:
		match entry.kind:
			"dict": instances.append({})
			"array": instances.append(Array([], entry.builtin, &"", null))
			"record": instances.append(Record.new("rest", Vector2i.ZERO, {}))
			"rng": instances.append(RandomNumberGenerator.new())
			_: instances.append(SCRIPTS[entry.kind].new())

func unpack(value):
	return instances[value.ref] if value is Dictionary else value

func fill() -> void:
	# Populate containers before assigning object properties so typed arrays and
	# reference validation never observe half-created content.
	for i in nodes.size():
		var entry: Dictionary = nodes[i]
		var target = instances[i]
		if entry.kind == "dict":
			for pair in entry.values:
				var key = unpack(pair[0])
				if not leaf(key):
					error = "Invalid dictionary key."
					return
				target[key] = unpack(pair[1])
		elif entry.kind == "array":
			for token in entry.values:
				var value = unpack(token)
				if entry.builtin != TYPE_NIL and typeof(value) != entry.builtin:
					error = "Invalid array element."
					return
				target.append(value)
	for i in nodes.size():
		var entry: Dictionary = nodes[i]
		if not FIELDS.has(entry.kind): continue
		var target: Object = instances[i]
		var properties: Dictionary = {}
		for property in target.get_property_list(): properties[property.name] = property
		for j in FIELDS[entry.kind].size():
			var field: String = FIELDS[entry.kind][j]
			var value = unpack(entry.values[j])
			var expected: int = properties[field].type
			if expected != TYPE_NIL and typeof(value) != expected:
				error = "Invalid snapshot property: " + field
				return
			if field == "record" and not value is Record:
				error = "Invalid activity record."
				return
			var original = target.get(field)
			if original is Object and value is Object and (original.get_script() != value.get_script() or original.get_class() != value.get_class()):
				error = "Invalid snapshot service: " + field
				return
			if original is Array and original.is_typed() and (not value is Array or original.get_typed_builtin() != value.get_typed_builtin()):
				error = "Invalid typed collection: " + field
				return
			target.set(field, value)

func validate(root, building_kinds: Array, day_seconds: float) -> bool:
	if not root is Dictionary or not root.get("world") is WorldState or not root.get("sample") is Dictionary or not root.get("view") is Dictionary:
		return invalid("Incomplete snapshot.")
	var w: WorldState = root.world
	if not w.smart_objects is Slots or not w.portal is Portal or not w.wander_rng is RandomNumberGenerator or w.day < 1 or w.day_elapsed < 0 or w.day_elapsed >= day_seconds:
		return invalid("Invalid world clock or services.")
	for field in ["powered_devices", "ready_drills", "power_output", "visible_tiles"]:
		if not root.sample.get(field) is Dictionary: return invalid("Missing step sample.")
	if not root.view.get("center") is Vector2 or not root.view.get("zoom") is float or root.view.zoom < 0.45 or root.view.zoom > 2.2 or not is_number(root.view.get("speed")) or root.view.speed <= 0 or not root.view.get("paused") is bool or not root.view.get("pollution") is bool:
		return invalid("Invalid saved camera settings.")
	for collection in [w.generated_chunks, w.terrain, w.water_sources, w.explored,
			w.mining_contracts, w.sites, w.beds, w.benches, w.banks, w.belts, w.power_lines, w.stores, w.wastewater, w.pollution_operations]:
		for key in collection:
			if not key is Vector2i: return invalid("Invalid world coordinate.")
	for cell in w.terrain:
		if not w.terrain[cell] is int or w.terrain[cell] < 0 or w.terrain[cell] > 9: return invalid("Invalid terrain.")
	for field in ["powered_devices", "ready_drills", "power_output", "visible_tiles"]:
		for key in root.sample[field]:
			if not key is Vector2i: return invalid("Invalid step sample position.")
	for stock in w.stores.values():
		if not valid_stock(stock): return invalid("Invalid warehouse inventory.")
	for collection in [w.mining_contracts, w.sites]:
		for cell in collection:
			if not w.terrain.has(cell) or not valid_task(collection[cell]): return invalid("Invalid world task.")
	for site in w.sites.values():
		if site.get("kind") not in building_kinds or not valid_stock(site.get("materials")): return invalid("Invalid blueprint.")
	for bench in w.benches.values():
		if not bench is Dictionary or bench.get("kind") not in building_kinds or not bench.get("task") is Dictionary:
			return invalid("Invalid production facility.")
		if not bench.task.is_empty() and not valid_task(bench.task): return invalid("Invalid production task.")
		if not numeric_fields(bench, ["queue", "daily_output", "produced_today", "stock", "growth", "water_day"]) or not bench.get("harvest") is bool:
			return invalid("Incomplete production facility.")
		if bench.kind == "barn" and (not numeric_fields(bench, ["sheep"]) or not bench.get("slaughter") is bool): return invalid("Invalid livestock.")
	for bed in w.beds.values():
		if not bed is Dictionary or not numeric_fields(bed, ["remaining", "assigned"]) or bed.assigned < -1 or bed.assigned >= w.workers.size(): return invalid("Invalid bed.")
	for bank in w.banks.values():
		if not bank is Dictionary or not numeric_fields(bank, ["interest_received"]): return invalid("Invalid bank.")
	for line in w.power_lines.values():
		if not line is Dictionary or line.get("kind") not in ["high_line", "low_line"] or not line.get("axis") is Vector2i or not valid_stock(line.get("materials")): return invalid("Invalid power line.")
	for belt in w.belts.values():
		if not belt is Dictionary or not belt.get("direction") is Vector2i or not belt.get("inputs") is Array or not belt.get("last_input") is int or not valid_stock(belt.get("materials")): return invalid("Invalid conveyor.")
	for shipment in w.shipments:
		if not valid_shipment(shipment, w.workers.size()): return invalid("Invalid freight.")
		if shipment.has("next_ore"):
			var next = shipment.next_ore
			if not valid_shipment(next, w.workers.size()) or not w.shipments.has(next): return invalid("Invalid mineral delivery batch.")
			for part in [shipment, next]:
				if not part.get("mined", false) or not part.get("carried_ore", false) or not part.picked or part.get("on_belt", false) or part.amount != 1.0 or not valid_mined_item(part.item) or part.owner < 0: return invalid("Invalid batched mineral.")
			if next.owner != shipment.owner or next.target != shipment.target or next.source != shipment.source: return invalid("Mismatched mineral delivery batch.")
	for id in w.belt_cargo:
		var cargo = w.belt_cargo[id]
		if not id is int or id >= w.next_cargo_id or not cargo is Dictionary or not cargo.get("from") is Vector2i or not cargo.get("to") is Vector2i or not numeric_fields(cargo, ["progress", "fee", "worker"]) or cargo.worker < 0 or cargo.worker >= w.workers.size() or not valid_shipment(cargo.get("delivery"), w.workers.size()): return invalid("Invalid conveyor cargo.")
	for load in w.wastewater.values():
		if not is_number(load) or load < 0: return invalid("Invalid wastewater load.")
	for source in w.pollution_operations.values():
		if not source is Dictionary or not numeric_fields(source, ["strength", "radius"]) or not source.radius is int or source.radius < 0 or source.radius > 256: return invalid("Invalid emission sample.")
	for key in w.smart_objects.objects:
		var slot = w.smart_objects.objects[key]
		if not key is String or not slot is Dictionary or not slot.get("source") is Dictionary or not slot.get("position") is Vector2i or not slot.get("shared") is bool or not slot.get("occupied") is bool or not numeric_fields(slot, ["owner", "identity", "claim"]) or not slot.owner is int or slot.owner < -1 or slot.owner >= w.workers.size(): return invalid("Invalid reservation.")
	for i in w.workers.size():
		var person: Dictionary = w.workers[i]
		if person.get("id") != i or not person.get("name") is String or not person.get("pos") is Vector2 or not person.get("activity") is StateTree or not person.get("mood") is Mood or not person.get("buffs") is Buffs:
			return invalid("Invalid worker.")
		for field in ["bread", "earned_today", "eaten_today", "hunger", "meal_bread", "bed_spent_today", "shop_spent_today", "fatigue", "gun_uses", "backpack_uses", "water", "pollution", "clothes_pollution", "loan_principal", "loan_interest", "loan_day", "unloaded_this_trip", "payroll"]:
			if not person.get(field) is float and not person.get(field) is int: return invalid("Missing worker balance or condition.")
		for field in ["items", "equipment", "freight", "ore_delivery"]:
			if not person.get(field) is Dictionary: return invalid("Missing worker inventory.")
		if not valid_stock(person.items) or not valid_stock(person.equipment): return invalid("Invalid personal inventory.")
		for field in ["freight", "ore_delivery"]:
			if not person[field].is_empty() and not valid_shipment(person[field], w.workers.size()): return invalid("Invalid carried freight.")
		if not person.get("extra_cargo") is Array or not (is_same(person.get("carry"), 0) or valid_mined_item(person.get("carry"))) or not person.get("color") is Color or not person.get("facing") is float or not person.has("loan_bank"):
			return invalid("Incomplete worker state.")
		for item in person.extra_cargo:
			if not valid_mined_item(item): return invalid("Invalid mined cargo.")
	for i in nodes.size():
		var entry: Dictionary = nodes[i]
		if entry.kind == "tree" and not validate_activity(instances[i]): return false
		if entry.kind in ["work", "life", "economy", "delivery"]:
			var process = instances[i]
			if not process.record is Record or process.phase not in ["approach", "use", "pickup", "transport", "handoff"]: return invalid("Invalid active process.")
			for handle in process.handles:
				if not handle.get("key") is String or not numeric_fields(handle, ["identity", "claim", "owner"]): return invalid("Invalid reservation handle.")
			if entry.kind == "work" and not process.segment.is_empty():
				if not valid_task(process.segment.get("task")) or not numeric_fields(process.segment, ["goal", "rate", "labor", "fatigue_factor"]) or process.segment.rate <= 0 or not process.segment.get("kind") is String: return invalid("Invalid labor segment.")
			if entry.kind == "delivery" and not valid_shipment(process.shipment, w.workers.size()): return invalid("Invalid delivery process.")
		if entry.kind == "record":
			var values: Dictionary = instances[i]._values
			if values.get("kind") not in ["mine", "build", "produce", "operate", "eat", "sleep", "rest", "use_item", "service", "purchase", "borrow", "payroll", "deliver"] or not values.get("target") is Vector2i or not values.get("data") is Dictionary:
				return invalid("Invalid chosen activity.")
			var required: Array = Record.PARAMETER_KEYS.get(values.kind, [])
			for field in required:
				if field not in ["canteen", "mined"] and not values.data.has(field): return invalid("Missing activity parameter.")
	return true

func valid_mined_item(value) -> bool:
	return (value is int and value > 0 and value <= 8) or is_same(value, "clean_water")

func is_number(value) -> bool:
	return value is int or (value is float and is_finite(value))

func numeric_fields(value: Dictionary, fields: Array) -> bool:
	for field in fields:
		if not is_number(value.get(field)): return false
	return true

func valid_stock(value) -> bool:
	if not value is Dictionary: return false
	for item in value:
		if not (item is int or item is String) or not is_number(value[item]) or value[item] < -0.000001: return false
	return true

func valid_task(value) -> bool:
	return value is Dictionary and numeric_fields(value, ["progress", "seconds"]) and value.seconds > 0 and value.progress >= 0 and (not value.has("reward") or (numeric_fields(value, ["reward", "paid"]) and value.reward > 0))

func valid_shipment(value, population: int) -> bool:
	return value is Dictionary and value.get("source") is Vector2i and value.get("target") is Vector2i and (value.get("item") is int or value.get("item") is String) and numeric_fields(value, ["amount", "owner"]) and value.amount > 0 and value.owner is int and value.owner >= -1 and value.owner < population and value.get("picked") is bool and (not value.has("pollution") or is_number(value.pollution))

func validate_activity(tree) -> bool:
	var a = tree.active
	if a == null: return tree.drink_elapsed < 0 or invalid("Orphaned drink process.")
	if not (a is Work or a is Life or a is Economy or a is Delivery): return invalid("Unknown active process.")
	if a.phase not in ["approach", "use", "pickup", "transport", "handoff"]: return invalid("Invalid process phase.")
	if a is Work and not a.segment.is_empty():
		if not a.segment.get("task") is Dictionary: return invalid("Missing labor task.")
		for field in ["goal", "rate", "labor", "fatigue_factor"]:
			if not a.segment.get(field) is float and not a.segment.get(field) is int: return invalid("Invalid labor segment.")
	return true

func invalid(message: String) -> bool:
	error = message
	return false

func finish() -> void:
	for i in nodes.size():
		var value = instances[i]
		if nodes[i].kind == "record":
			value._values.data.make_read_only()
			value._values.make_read_only()
		elif nodes[i].kind == "work" and not value.segment.is_empty():
			value.fatigue_factor = value.segment.fatigue_factor
