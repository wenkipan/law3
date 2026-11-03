extends RefCounted

const Parameters = preload("res://scripts/simulation/activity_parameters.gd")
const Needs = preload("res://scripts/simulation/evaluation/needs.gd")
const EnvironmentEvaluation = preload("res://scripts/simulation/evaluation/environment.gd")
const Resources = preload("res://scripts/simulation/evaluation/resources.gd")
const Life = preload("res://scripts/simulation/evaluation/life.gd")
const Items = preload("res://scripts/simulation/evaluation/items.gd")
const Labor = preload("res://scripts/simulation/evaluation/labor.gd")
const Economy = preload("res://scripts/simulation/evaluation/economy.gd")
const Delivery = preload("res://scripts/simulation/evaluation/delivery.gd")

static var ACTIONS = {"eat": Life.meal, "sleep": Life.sleep, "rest": Life.rest,
	"use_item": Items.use, "purchase": Economy.purchase, "borrow": Economy.borrow,
	"payroll": Economy.payroll, "mine": Labor.mining, "build": Labor.construction,
	"produce": Labor.production, "operate": Labor.operation, "deliver": Delivery.evaluate}
static var SERVICES = {"hospital": Life.treatment, "bathhouse": Life.bath, "laundry": Life.laundry}
static var SERVICE_EFFECTS = {"hospital": Life.treatment_effects, "bathhouse": Life.bath_effects, "laundry": Life.laundry_effects}
static var ITEM_EFFECTS = {"meat": Items.food, "ale": Items.ale, "clothes": Items.clothing,
	"bench": Items.mining_equipment, "workbench": Items.cargo_equipment,
	"tools": Items.production_equipment, "clean_water": Items.hydration}
const ITEM_GROUPS = {"meat": "food", "ale": "mood", "clothes": "clothing",
	"bench": "equipment", "workbench": "equipment", "tools": "equipment", "clean_water": "fatigue"}

var context
var needs
var environment
var resources
var food_need := 0.0
var tracing := false
var rejected: Array[Dictionary] = []
var proposals: Array[Dictionary] = []
var _work_facts: Array[Dictionary] = []
var _work_ready := false

func _init(facts) -> void:
	context = facts
	needs = Needs.new(facts)
	environment = EnvironmentEvaluation.new(facts, needs)
	resources = Resources.new(self)
	food_need = clampf(1.0 - facts.worker.hunger / facts.game.MAX_HUNGER, 0, 1)
	tracing = facts.game.ai_trace.watches(facts.worker.id)
	resources.prepare()

func evaluate(op: Dictionary) -> Dictionary:
	if op.kind == "service": return SERVICES[op.data.kind].call(self, op)
	return ACTIONS[op.kind].call(self, op)

func item_effects(item: String, state: Dictionary, amount := 1) -> Dictionary:
	return ITEM_EFFECTS[item].call(self, state, amount) if ITEM_EFFECTS.has(item) else {}

func service_effects(kind: String, state: Dictionary) -> Dictionary:
	return SERVICE_EFFECTS[kind].call(self, state, context.game.SERVICES[kind])

func item_group(item: String) -> String:
	return ITEM_GROUPS.get(item, "equipment")

func result(forecast: Dictionary, benefits: Dictionary, cash := 0.0, excluded: Array = []) -> Dictionary:
	var parts := benefits.duplicate()
	parts.environment = forecast.environment
	parts.payment = -resources.cost(cash, excluded) if cash > 0 else 0.0
	var value: float = Resources.total(parts)
	return {"score": value / (1.0 + Parameters.TIME_COST * forecast.hours), "hours": forecast.hours, "parts": parts}

func meal_amount() -> float:
	return minf(maxf(0, context.worker.bread), maxf(0, context.game.MAX_HUNGER - context.worker.hunger) / context.game.HUNGER_PER_BREAD)

func food_shortfall() -> float:
	return maxf(0, Parameters.BORROW_FOOD_RESERVE - context.worker.hunger / context.game.HUNGER_PER_BREAD - context.worker.bread)

func work_facts() -> Array[Dictionary]:
	if _work_ready: return _work_facts
	_work_ready = true
	var g = context.game
	for p in g.smart_objects.query("mine"):
		if g.terrain[p] in [5, 6]: continue
		for direction in g.DIRS:
			if not context.path_to(p + direction).is_empty():
				var task: Dictionary = g.mining_contracts[p]
				_work_facts.append({"kind": "mine", "target": p, "position": p + direction, "station": "", "hours": maxf(0, task.seconds - task.progress) / g.HOUR_SECONDS})
				break
	for p in g.smart_objects.query("work"):
		var kind: String = g.building_kind(p)
		if context.path_to(p).is_empty(): continue
		if kind in g.OPERATED_KINDS:
			if g.operation_needed(p) and (kind != "drill" or g.ready_drills.has(p)):
				_work_facts.append({"kind": "operate", "target": p, "position": p, "station": kind, "hours": 1.0})
			continue
		if not g.PRODUCTS.has(kind) or g.benches[p].growth > 0: continue
		if context.path_to(p).is_empty() or not g.has_production_order(p): continue
		var task: Dictionary = g.benches[p].task
		if task.is_empty() and not (kind == "barn" and g.benches[p].slaughter) and not g.recipe_ready(p, g.production_materials(kind)): continue
		var hours: float = maxf(0, task.seconds - task.progress) / g.HOUR_SECONDS if not task.is_empty() else (1.0 if kind in ["farm", "barn"] else g.PRODUCTS[kind].hours)
		_work_facts.append({"kind": "produce", "target": p, "position": p, "station": kind, "hours": hours})
	for p in g.smart_objects.query("build"):
		if g.site_cleared(p) and g.site_supplied(p) and not context.path_to(p).is_empty():
			_work_facts.append({"kind": "build", "target": p, "position": p, "station": "", "hours": maxf(0, g.sites[p].seconds - g.sites[p].progress) / g.HOUR_SECONDS})
	return _work_facts

func work_hours() -> float:
	var hours := 0.0
	for work in work_facts(): hours += work.hours
	return minf(Parameters.FORECAST_HOURS, hours)

func reject(kind: String, p, reason: String, details: Dictionary = {}) -> void:
	if tracing:
		var entry := {"kind": kind, "target": context.game.WorkerTrace.cell(p), "reason": reason}
		entry.merge(details)
		rejected.append(entry)

func trace_selection(choices: Array, reason: String) -> void:
	if not tracing: return
	var g = context.game
	var ranked: Array[Dictionary] = []
	for option in choices: ranked.append(g.WorkerTrace.proposal(option))
	var evaluated: Array[Dictionary] = []
	for entry in proposals:
		var row: Dictionary = g.WorkerTrace.proposal(entry.option)
		row.merge({"components": entry.result.parts, "hours": entry.result.hours,
			"base_score": entry.result.score, "inertia_bonus": entry.inertia_bonus,
			"eligible": choices.has(entry.option)})
		if not row.eligible: row.reason = "needs_employer_cash"
		evaluated.append(row)
	g.ai_trace.selection(g, context.worker, {"trigger": reason, "food_need": food_need,
		"ranked": ranked, "candidates": evaluated, "rejected": rejected,
		"opportunities": {"mines": g.mining_contracts.size(), "sites": g.sites.size(),
			"facilities": g.benches.size(), "shipments": g.shipments.size()}})
