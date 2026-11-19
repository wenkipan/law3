extends RefCounted

const Building = preload("res://scripts/entities/building.gd")
const SmartObjects = preload("res://scripts/simulation/smart_objects.gd")

# Full food, rest and health with a neutral mood yield a quality of 0.59375.
const OUTSIDE_LIVING_QUALITY := 0.57
const EMIGRATION_LIVING_QUALITY := 0.35
const JOB_ADVANTAGE_PER_PERSON := 0.1
const MAX_JOB_ADVANTAGE := 0.4
const FULL_ARRIVAL_ADVANTAGE := 0.25
const MAX_EXPECTED_ARRIVALS_PER_HOUR := 5.0 / 6.0
const FULL_DEPARTURE_HARDSHIP := 0.25
const INITIAL_PAYROLL_HOURS := 4.0

static func advance_hour(g) -> void:
	var entry: Vector2i = g.world.migration_entry
	var reachable_residents := 0
	var seekers := {}
	var living := 0.0
	for resident in g.world.workers:
		var quality: float = g.resident_living_quality(resident)
		living += quality
		advance_departure(g, resident, quality)
		if g.route(entry, Vector2i(resident.pos.round())).is_empty(): continue
		reachable_residents += 1
		if not g.is_child(resident) and resident.employer == null:
			seekers[resident.skill] = seekers.get(resident.skill, 0) + 1
	var average: float = living / g.world.workers.size() if not g.world.workers.is_empty() else OUTSIDE_LIVING_QUALITY
	g.world.living_quality = lerpf(g.world.living_quality, average, 1.0 - exp(-g.HOUR_SECONDS / g.DAY_SECONDS))
	advance_arrivals(g, measure_vacancies(g, entry), seekers, reachable_residents)

static func advance_departure(g, resident: Dictionary, quality: float) -> void:
	if g.is_child(resident) or resident.residence_seconds + 0.000001 < g.MIGRATION_GRACE_DAYS * g.DAY_SECONDS:
		return
	var hardship := EMIGRATION_LIVING_QUALITY - quality
	var rate := minf(hardship / FULL_DEPARTURE_HARDSHIP, 1.0) if hardship > 0.0 else -2.0
	resident.discontent_seconds = clampf(resident.discontent_seconds + g.HOUR_SECONDS * rate, 0.0, g.EMIGRATION_DAYS * g.DAY_SECONDS)

static func measure_vacancies(g, entry: Vector2i) -> Dictionary:
	var openings: Array[Dictionary] = []
	var payroll_needed := {"player": 0.0}
	for building in g.world.buildings_in("station"):
		if not g.has_job(building.kind): continue
		var wage: float = building.state.get("wage", 0.0)
		if wage <= 0.0: continue
		var position: Vector2i = g.world.building_map.origin(building.id)
		if building.kind in g.EXTRACTIVE_KINDS and g.mine_deposit(position) == null: continue
		if building.kind == "drill" and g.drill_target(position) == null: continue
		var owner = building.state.get("owner", "player")
		var reachable: bool = not g.route(entry, position).is_empty()
		if not reachable and not owner is int: continue
		var cost := wage * INITIAL_PAYROLL_HOURS
		var employee: Dictionary = g.world.worker(building.state.employee)
		if not employee.is_empty(): cost = maxf(0.0, cost - employee.payroll)
		payroll_needed[owner] = payroll_needed.get(owner, 0.0) + cost
		if reachable and employee.is_empty():
			openings.append({"owner": owner, "skill": g.work_skill(building.kind)})
	if openings.is_empty(): return {}
	var public_cash := 0.0
	for source in g.world.smart_objects.positions(SmartObjects.Action.STORE, {"item": "money"}):
		if not is_same(g.proprietor_at(source), "player") or g.world.has_building(source, "site"): continue
		var cash: float = g.stock_at(source, "money")
		if cash > 0.0 and not g.route(entry, source).is_empty(): public_cash += cash
	var coverage := {}
	for owner in payroll_needed:
		var cash: float = g.private_cash(owner) if owner is int else public_cash
		coverage[owner] = payroll_coverage(cash, payroll_needed[owner])
	var vacancies := {}
	for job in openings:
		var funded: float = coverage[job.owner]
		if funded > 0.0: vacancies[job.skill] = vacancies.get(job.skill, 0.0) + funded
	return vacancies

static func payroll_coverage(cash: float, needed: float) -> float:
	return minf(cash / needed, 1.0) if needed > 0.0 else 1.0

static func job_advantage(vacancies: Dictionary, seekers: Dictionary, skill: String) -> float:
	var net: float = vacancies.get(skill, 0.0) - seekers.get(skill, 0)
	return clampf(net * JOB_ADVANTAGE_PER_PERSON, -MAX_JOB_ADVANTAGE, MAX_JOB_ADVANTAGE)

static func advance_arrivals(g, vacancies: Dictionary, seekers: Dictionary, reachable_residents: int) -> void:
	var entry = g.immigration_position()
	var entry_available: bool = entry != null and (reachable_residents > 0 or not vacancies.is_empty()
		or not g.route(g.world.migration_entry, g.BASE).is_empty())
	var weights := PackedFloat32Array()
	var attraction := 0.0
	var living_advantage: float = g.world.living_quality - OUTSIDE_LIVING_QUALITY
	var skills: Array = g.SKILLS.keys()
	for skill in skills:
		var weight := maxf(0.0, living_advantage + job_advantage(vacancies, seekers, skill))
		weights.append(weight)
		attraction += weight
	var demand := MAX_EXPECTED_ARRIVALS_PER_HOUR * minf(attraction / FULL_ARRIVAL_ADVANTAGE, 1.0)
	# Stochastically round this connection's fractional hourly demand.
	var arrives: bool = entry_available and demand > 0.0 and g.world.migration_rng.randf() < demand
	if g.economy_tracing:
		g.trace_economy("immigration_demand", g.world.migration_entry, {
			"living_quality": g.world.living_quality, "vacancies": vacancies, "seekers": seekers,
			"expected_arrivals": demand, "entry_available": entry_available, "arrives": arrives})
	if not arrives: return
	var migrant: Dictionary = g.create_worker(entry, g.world.migration_rng.randf_range(g.CHILD_DAYS, g.OLD_DAYS - 1.0))
	migrant.skill = skills[g.world.migration_rng.rand_weighted(weights)]
	migrant.items["bread"] = g.MIGRANT_FOOD
	g.record_migration_goods({"bread": g.MIGRANT_FOOD}, true)
	g.trace_economy("immigration", entry, {"worker": migrant.id, "skill": migrant.skill, "living_quality": g.world.living_quality,
		"job_advantage": job_advantage(vacancies, seekers, migrant.skill)})
	g.update_fog()
