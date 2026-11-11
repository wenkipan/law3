extends RefCounted

enum Domain { BUILDING, RESOURCE, DEPOSIT, REQUEST, STOCK }
enum Action { WORK, BUILD, HARVEST, SHOP, MARKET, BED, SEAT, SERVICE, BANK, STORE, DELIVERY, MINE }
enum Gate { ALWAYS, STAFFED }

const JOB_SKILLS := {
	"market": "trade", "bank": "trade", "storage_box": "transport",
	"mine": "mining", "drill": "mining",
	"farm": "farming", "barn": "farming", "pump": "farming",
	"power_plant": "power", "manual_generator": "power", "transformer": "power",
	"research_bench": "research", "hospital": "medicine",
	"bench": "processing", "workbench": "processing", "purifier": "processing",
	"printer": "processing", "mill": "processing", "weaver": "processing",
	"tailor": "processing", "brewery": "processing", "smelter": "processing",
	"sawmill": "processing", "smithy": "processing", "chemical_plant": "processing",
	"soapworks": "processing", "bathhouse": "processing", "laundry": "processing", "pharmacy": "processing",
}
const CHILD_WORK_KINDS := ["farm", "mill", "weaver", "tailor"]
const MINERALS := [1, 2, 3, 4, 7, 8]

class SlotDefinition extends RefCounted:
	var action: int
	var name: StringName
	var skill: StringName
	var shared: bool
	var gate: int
	var items: Array
	var offsets: Array[Vector2i] = [Vector2i.ZERO]

	func _init(activity: int, slot_name: StringName, required_skill: StringName = &"", sharing := false, goods: Array = [], availability := Gate.ALWAYS) -> void:
		action = activity
		name = slot_name
		skill = required_skill
		shared = sharing
		gate = availability
		items = goods.duplicate()
		items.make_read_only()

class ObjectDefinition extends RefCounted:
	var kind: StringName
	var domain: int
	var blueprint := false
	var work_activity: StringName = &""
	var materials: Dictionary = {}
	var products: Array = []
	var interactions: Array[SlotDefinition] = []

	func _init(type_name: StringName, category: int) -> void:
		kind = type_name
		domain = category

var buildings: Dictionary = {}
var blueprints: Dictionary = {}
var resources: Dictionary = {}
var requests: Dictionary = {}
var deposit: ObjectDefinition
var stock: ObjectDefinition
var configured := false

static func work_skill(kind: String) -> String:
	return JOB_SKILLS.get(kind, "processing")

func configure(g) -> void:
	if configured: return
	for kind in g.BUILDING_KINDS:
		var definition := ObjectDefinition.new(kind, Domain.BUILDING)
		definition.materials = g.production_materials(kind)
		if g.PRODUCTS.has(kind) and kind != "printer": definition.products = [g.product_item(kind)]
		elif kind == "mine": definition.products = MINERALS.duplicate()
		elif kind == "drill": definition.products = [2, 3]
		if kind == "barn": definition.products.append("meat")
		if JOB_SKILLS.has(kind):
			definition.work_activity = &"operate" if kind in g.OPERATED_KINDS + g.DUTY_KINDS + ["mine"] else &"produce"
			definition.interactions.append(SlotDefinition.new(Action.WORK, &"work", JOB_SKILLS[kind], false, definition.products))
		definition.interactions.append(SlotDefinition.new(Action.STORE, &"store", &"", true, g.RESOURCE_ITEMS))
		if kind == "market":
			definition.interactions.append(SlotDefinition.new(Action.SHOP, &"shop", &"", true, g.MARKET_GOODS, Gate.STAFFED))
			definition.interactions.append(SlotDefinition.new(Action.MARKET, &"market", &"", true, g.MARKET_GOODS, Gate.STAFFED))
		elif kind == "bank": definition.interactions.append(SlotDefinition.new(Action.BANK, &"bank", &"", true, ["money"], Gate.STAFFED))
		elif kind == "bed": definition.interactions.append(SlotDefinition.new(Action.BED, &"bed"))
		elif kind == "canteen":
			var seats := SlotDefinition.new(Action.SEAT, &"seat")
			seats.offsets = [Vector2i.ZERO, Vector2i.RIGHT]
			definition.interactions.append(seats)
		if g.SERVICES.has(kind):
			var service: Dictionary = g.SERVICES[kind]
			definition.materials = service.materials
			definition.interactions.append(SlotDefinition.new(Action.SERVICE, service.slot, &"", false, [], Gate.STAFFED))
		buildings[kind] = definition
		var planned := ObjectDefinition.new(kind, Domain.BUILDING)
		planned.blueprint = true
		planned.work_activity = &"build"
		planned.materials = g.building_materials(kind)
		planned.interactions.append(SlotDefinition.new(Action.BUILD, &"build", &"construction"))
		blueprints[kind] = planned
	for item in g.MapGenerator.WILD_ITEMS.values():
		var definition := ObjectDefinition.new("wild_" + item, Domain.RESOURCE)
		definition.products = [item]
		definition.interactions.append(SlotDefinition.new(Action.HARVEST, &"harvest", &"hunting" if item == "meat" else &"gathering", false, [item]))
		resources[item] = definition
	for skill in [""] + g.SKILLS.keys():
		var definition := ObjectDefinition.new(&"delivery_request", Domain.REQUEST)
		definition.interactions.append(SlotDefinition.new(Action.DELIVERY, &"delivery", skill))
		requests[skill] = definition
	deposit = ObjectDefinition.new(&"mineral_deposit", Domain.DEPOSIT)
	deposit.interactions.append(SlotDefinition.new(Action.MINE, &"mine", &"mining"))
	stock = ObjectDefinition.new(&"stock", Domain.STOCK)
	stock.interactions.append(SlotDefinition.new(Action.STORE, &"store", &"", true, g.RESOURCE_ITEMS))
	for definition in buildings.values() + blueprints.values() + resources.values() + requests.values() + [deposit, stock]:
		definition.materials.make_read_only()
		definition.products.make_read_only()
		definition.interactions.make_read_only()
		for interaction in definition.interactions: interaction.offsets.make_read_only()
	configured = true
