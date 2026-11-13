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
const Slots = preload("res://scripts/simulation/smart_objects.gd")

static var ACTIONS = {"eat": Life.meal, "sleep": Life.sleep, "rest": Life.rest,
	"sell": Economy.sell,
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
var state: Dictionary
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
	environment = EnvironmentEvaluation.new(facts)
	state = environment.initial()
	state.make_read_only()
	resources = Resources.new(self)
	food_need = clampf(1.0 - facts.worker.hunger / facts.game.MAX_HUNGER, 0, 1)
	tracing = facts.game.ai_trace.watches(facts.worker.id)
	resources.prepare()

func upper_bound(op: Dictionary) -> float:
	# Unsupported bounds stay infinite and receive the ordinary, exact comparison.
	var g = context.game
	var w: Dictionary = context.worker
	var use_hours := 0.0
	var bed_hours := 0.0
	match op.kind:
		"eat": use_hours = g.MEAL_SECONDS / g.HOUR_SECONDS
		"purchase":
			if not g.FOOD_RECOVERY.has(op.data.item): return INF
			use_hours = g.item_use_hours(op.data.item)
		"service": use_hours = g.SERVICES[op.data.kind].hours
		"sleep":
			var passive: float = g.FOUNTAIN_RECOVERY_PER_HOUR if g.has_powered_effect(Vector2(op.position), "fountain") else 0.0
			if op.data.bed: bed_hours = minf(g.BED_LEASE_HOURS, state.fatigue / (g.BED_RECOVERY_PER_HOUR + passive))
			use_hours = bed_hours + maxf(0, state.fatigue - bed_hours * (g.BED_RECOVERY_PER_HOUR + passive)) / (g.SLEEP_RECOVERY_PER_HOUR + passive)
		"sell", "borrow": pass
		_: return INF
	var travel_hours: float = environment.walk_hours(op.path)
	var value := 0.0
	match op.kind:
		"sell": value += resources.income(op.data.amount * g.market_price(op.target, op.data.item, true)) + 0.02 * op.data.amount
		"borrow": value += resources.income(minf(op.data.amount, g.stock_at(op.target, "money")))
		"purchase":
			var best := -INF
			for amount in range(1, op.data.limit + 1):
				best = maxf(best, needs.food_gain(state.hunger + g.personal_food(w), g.FOOD_RECOVERY[op.data.item] * amount)
					- resources.cost(g.sale_price(op.target, op.data.item) * amount, ["food"]))
			value += best
		"eat":
			value += needs.food_gain(state.hunger, op.data.amount * g.FOOD_RECOVERY[op.data.item])
			if op.data.has("canteen"): value += needs.fatigue_gain(w.fatigue, g.CANTEEN_RECOVERY)
			if g.has_powered_effect(Vector2(op.position), "fountain"):
				value += needs.mood_gain(-w.mood.LIMIT, w.mood.COMFORTABLE_MEAL_GAIN, Parameters.FORECAST_HOURS)
		"sleep":
			value += needs.fatigue_gain(w.fatigue, w.fatigue)
			if bed_hours > 0: value += needs.mood_gain(-w.mood.LIMIT, w.mood.BED_GAIN_PER_HOUR * bed_hours, Parameters.FORECAST_HOURS)
			value -= resources.cost(g.base_fee(op.target), ["fatigue"]) if op.data.bed else 0.0
		"service":
			var kind: String = op.data.kind
			var rule: Dictionary = g.SERVICES[kind]
			if kind == "laundry":
				var horizon: float = minf(Parameters.FORECAST_HOURS, state.clothes_hours)
				value += Parameters.CLOTHING_WEIGHT * horizon / Parameters.FORECAST_HOURS
				value += needs.mood_gain(-w.mood.LIMIT, g.WorkerBuffs.CLOTHES_MOOD, horizon)
			else:
				value += needs.pollution_gain(g.Pollution.BODY_CAPACITY, rule.recovery)
				if kind == "bathhouse": value += needs.mood_gain(-w.mood.LIMIT, g.WorkerBuffs.BATH_MOOD, g.WorkerBuffs.BATH_EFFECT_HOURS)
			var excluded: Array = ["clothing", "mood"] if kind == "laundry" else (["pollution", "mood"] if kind == "bathhouse" else ["pollution"])
			value -= resources.cost(g.base_fee(op.target), excluded)
	var weighted_hours: float = use_hours + Parameters.TRAVEL_TIME_WEIGHT * travel_hours
	return value / (1.0 + Parameters.TIME_COST * weighted_hours) + w.activity.inertia_bonus(op) + 0.00000001

func evaluate(op: Dictionary) -> Dictionary:
	if op.kind == "service": return SERVICES[op.data.kind].call(self, op)
	return ACTIONS[op.kind].call(self, op)

func item_effects(item: String, state: Dictionary, amount := 1) -> Dictionary:
	if context.game.FOOD_RECOVERY.has(item):
		return {"food": needs.food_gain(state.hunger + context.game.personal_food(context.worker), context.game.FOOD_RECOVERY[item] * amount)}
	return ITEM_EFFECTS[item].call(self, state, amount) if ITEM_EFFECTS.has(item) else {}

func service_effects(kind: String, state: Dictionary) -> Dictionary:
	return SERVICE_EFFECTS[kind].call(self, state, context.game.SERVICES[kind])

func item_group(item: String) -> String:
	if context.game.FOOD_RECOVERY.has(item): return "food"
	return ITEM_GROUPS.get(item, "equipment")

func result(estimate: Dictionary, benefits: Dictionary, cash := 0.0, excluded: Array = []) -> Dictionary:
	var parts := benefits.duplicate()
	parts.payment = -resources.cost(cash, excluded) if cash > 0 else 0.0
	var value: float = Resources.total(parts)
	var weighted_hours: float = estimate.hours + (Parameters.TRAVEL_TIME_WEIGHT - 1.0) * estimate.travel_hours
	return {"score": value / (1.0 + Parameters.TIME_COST * weighted_hours), "hours": estimate.hours, "parts": parts}

func food_shortfall() -> float:
	return context.game.food_cash_shortfall(context.worker)

func work_facts() -> Array[Dictionary]:
	if _work_ready: return _work_facts
	_work_ready = true
	var g = context.game
	for endpoint in context.job_slots(Slots.Action.WORK):
		var p: Vector2i = endpoint.instance.position
		if not g.can_take_job(context.worker, p): continue
		var kind: String = endpoint.instance.definition.kind
		if not g.can_work(context.worker, "operate" if kind in g.OPERATED_KINDS else "produce", kind): continue
		if context.path_to(p).is_empty(): continue
		if endpoint.instance.definition.work_activity == &"operate":
			if g.operation_needed(p) and (kind != "drill" or g.cache.ready_drills.has(p)):
				_work_facts.append({"kind": "operate", "target": p, "position": p, "station": kind, "contract": g.world.building_state(p, "station").task, "hours": 1.0})
			continue
		if not g.PRODUCTS.has(kind) or g.world.building_state(p, "station").growth > 0: continue
		if context.path_to(p).is_empty() or not g.has_production_order(p): continue
		var task: Dictionary = g.world.building_state(p, "station").task
		if task.is_empty() and not g.recipe_ready(p, g.station_materials(p)): continue
		var hours: float = maxf(0, task.seconds - task.progress) / g.HOUR_SECONDS if not task.is_empty() else g.station_work_hours(p)
		_work_facts.append({"kind": "produce", "target": p, "position": p, "station": kind, "contract": task, "hours": hours})
	for endpoint in context.job_slots(Slots.Action.BUILD):
		var p: Vector2i = endpoint.instance.position
		if not g.can_take_job(context.worker, p): continue
		if g.site_cleared(p) and g.site_supplied(p) and not context.path_to(p).is_empty():
			_work_facts.append({"kind": "build", "target": p, "position": p, "station": "", "contract": g.world.building_state(p, "site"), "hours": maxf(0, g.world.building_state(p, "site").seconds - g.world.building_state(p, "site").progress) / g.HOUR_SECONDS})
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
			"comparison_hours": entry.result.get("comparison_hours", entry.result.hours),
			"base_score": entry.result.score, "inertia_bonus": entry.inertia_bonus,
			"eligible": true, "representative": choices.has(entry.option)})
		evaluated.append(row)
	g.ai_trace.selection(g, context.worker, {"trigger": reason, "food_need": food_need,
		"ranked": ranked, "candidates": evaluated, "rejected": rejected,
		"opportunities": {"mines": g.world.mining_contracts.size(), "sites": g.world.building_positions("site").size(),
			"facilities": g.world.building_positions("station").size(), "delivery_tasks": g.world.delivery_tasks.size()}})
