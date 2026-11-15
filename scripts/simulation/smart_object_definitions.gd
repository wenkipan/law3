extends RefCounted

enum Domain { BUILDING, RESOURCE, DEPOSIT, REQUEST, STOCK }
const Action := {
	"SHOP": "shop", "BED": "bed", "SEAT": "seat",
	"SERVICE": "service", "BANK": "bank", "STORE": "store",
}
enum Gate { ALWAYS, STAFFED }

const WorkTypes = preload("res://scripts/simulation/work_types.gd")
const JOB_TYPES := {
	"market": WorkTypes.OPERATIONS, "bank": WorkTypes.OPERATIONS, "storage_box": WorkTypes.LOGISTICS,
	"mine": WorkTypes.MINING, "drill": WorkTypes.MINING,
	"farm": WorkTypes.FARMING, "barn": WorkTypes.FARMING, "pump": WorkTypes.FARMING,
	"hunting_ground": WorkTypes.FARMING, "gathering_garden": WorkTypes.FARMING,
	"power_plant": WorkTypes.OPERATIONS, "manual_generator": WorkTypes.OPERATIONS, "transformer": WorkTypes.OPERATIONS,
	"research_bench": WorkTypes.OPERATIONS, "hospital": WorkTypes.MEDICINE,
	"bench": WorkTypes.OPERATIONS, "workbench": WorkTypes.OPERATIONS, "purifier": WorkTypes.OPERATIONS,
	"printer": WorkTypes.OPERATIONS, "mill": WorkTypes.OPERATIONS, "weaver": WorkTypes.OPERATIONS,
	"tailor": WorkTypes.OPERATIONS, "brewery": WorkTypes.OPERATIONS, "smelter": WorkTypes.OPERATIONS,
	"sawmill": WorkTypes.OPERATIONS, "smithy": WorkTypes.OPERATIONS, "chemical_plant": WorkTypes.OPERATIONS,
	"soapworks": WorkTypes.OPERATIONS, "bathhouse": WorkTypes.OPERATIONS, "laundry": WorkTypes.OPERATIONS, "pharmacy": WorkTypes.OPERATIONS,
}
const CHILD_WORK_KINDS := ["farm", "mill", "weaver", "tailor"]
const MINERALS := [1, 2, 3, 4, 7, 8]

class SlotDefinition extends RefCounted:
	# Work endpoints use the resident's work type as their action. The method
	# describes how this particular target fulfills it.
	var action: String
	var name: StringName
	var method: String
	var shared: bool
	var gate: int
	var items: Array
	var offsets: Array[Vector2i] = [Vector2i.ZERO]

	func _init(activity: String, slot_name: StringName, execution_method := "", sharing := false, goods: Array = [], availability := Gate.ALWAYS) -> void:
		action = activity
		name = slot_name
		method = execution_method
		shared = sharing
		gate = availability
		items = goods.duplicate()
		items.make_read_only()

class ObjectDefinition extends RefCounted:
	var kind: StringName
	var domain: int
	var blueprint := false
	var materials: Dictionary = {}
	var products: Array = []
	var interactions: Array[SlotDefinition] = []

	func _init(type_name: StringName, category: int) -> void:
		kind = type_name
		domain = category

var buildings: Dictionary = {}
var blueprints: Dictionary = {}
var resources: Dictionary = {}
var delivery: ObjectDefinition
var deposit: ObjectDefinition
var stock: ObjectDefinition
var configured := false

func configure(g) -> void:
	if configured: return
	for kind in g.BUILDING_KINDS:
		var definition := ObjectDefinition.new(kind, Domain.BUILDING)
		definition.materials = g.production_materials(kind)
		if g.PRODUCTS.has(kind) and kind != "printer": definition.products = [g.product_item(kind)]
		elif kind == "mine": definition.products = MINERALS.duplicate()
		elif kind == "drill": definition.products = [2, 3]
		if JOB_TYPES.has(kind):
			var method := "operate" if kind in g.OPERATED_KINDS + g.DUTY_KINDS + ["mine"] else "produce"
			definition.interactions.append(SlotDefinition.new(JOB_TYPES[kind], &"work", method, false, definition.products))
		var stored_items: Array = ["money"] if kind == "market" else g.RESOURCE_ITEMS
		definition.interactions.append(SlotDefinition.new(Action.STORE, &"store", "", true, stored_items))
		if kind == "market":
			definition.interactions.append(SlotDefinition.new(Action.SHOP, &"shop", "", true, g.MARKET_GOODS, Gate.STAFFED))
		elif kind == "bank": definition.interactions.append(SlotDefinition.new(Action.BANK, &"bank", "", true, ["money"], Gate.STAFFED))
		elif kind == "bed": definition.interactions.append(SlotDefinition.new(Action.BED, &"bed"))
		elif kind == "canteen":
			var seats := SlotDefinition.new(Action.SEAT, &"seat")
			seats.offsets = [Vector2i.ZERO, Vector2i.RIGHT]
			definition.interactions.append(seats)
		if g.SERVICES.has(kind):
			var service: Dictionary = g.SERVICES[kind]
			definition.materials = service.materials
			definition.interactions.append(SlotDefinition.new(Action.SERVICE, service.slot, "", false, [], Gate.STAFFED))
		buildings[kind] = definition
		var planned := ObjectDefinition.new(kind, Domain.BUILDING)
		planned.blueprint = true
		planned.materials = g.building_materials(kind)
		planned.interactions.append(SlotDefinition.new(WorkTypes.LOGISTICS, &"build", "build"))
		blueprints[kind] = planned
	for item in g.MapGenerator.WILD_ITEMS.values():
		var definition := ObjectDefinition.new("wild_" + item, Domain.RESOURCE)
		definition.products = [item]
		definition.interactions.append(SlotDefinition.new(WorkTypes.FARMING, &"harvest", "harvest", false, [item]))
		resources[item] = definition
	delivery = ObjectDefinition.new(&"delivery_request", Domain.REQUEST)
	delivery.interactions.append(SlotDefinition.new(WorkTypes.LOGISTICS, &"delivery", "deliver"))
	deposit = ObjectDefinition.new(&"mineral_deposit", Domain.DEPOSIT)
	deposit.interactions.append(SlotDefinition.new(WorkTypes.MINING, &"mine", "mine"))
	stock = ObjectDefinition.new(&"stock", Domain.STOCK)
	stock.interactions.append(SlotDefinition.new(Action.STORE, &"store", "", true, g.RESOURCE_ITEMS))
	for definition in buildings.values() + blueprints.values() + resources.values() + [delivery, deposit, stock]:
		definition.materials.make_read_only()
		definition.products.make_read_only()
		definition.interactions.make_read_only()
		for interaction in definition.interactions: interaction.offsets.make_read_only()
	configured = true
