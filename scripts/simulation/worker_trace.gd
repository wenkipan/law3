extends RefCounted

const MAX_BYTES := 8 * 1024 * 1024
const SAMPLE_SECONDS := 1.0

var enabled := false
var worker_id := -1
var path := "user://logs/worker-ai.jsonl"
var max_bytes := MAX_BYTES
var file: FileAccess
var session := "%s-%d" % [Time.get_datetime_string_from_system(true), Time.get_ticks_usec()]
var world := 0
var sequence := 0
var decisions: Dictionary = {}
var next_sample: Dictionary = {}
var evaluations: Dictionary = {}

func configure(args: PackedStringArray) -> void:
	for arg in args:
		if arg == "--trace-ai":
			enabled = true
		elif arg.begins_with("--trace-ai="):
			var value := arg.trim_prefix("--trace-ai=")
			if value.is_valid_int() and int(value) >= 0:
				enabled = true
				worker_id = int(value)
			else:
				push_warning("--trace-ai expects a nonnegative worker ID.")
		elif arg.begins_with("--trace-ai-file="):
			path = arg.trim_prefix("--trace-ai-file=")
		elif arg.begins_with("--trace-ai-max-mib="):
			var value := arg.trim_prefix("--trace-ai-max-mib=")
			if value.is_valid_int() and int(value) >= 1 and int(value) <= 256:
				max_bytes = int(value) * 1024 * 1024
			else:
				push_warning("--trace-ai-max-mib expects 1 to 256 MiB.")
	if enabled:
		open_file()
		print("Worker AI trace: ", ProjectSettings.globalize_path(path), " worker=", worker_id)

func open_file() -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error == OK:
		file = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE_READ)
		if file != null:
			file.seek_end()
	if file == null:
		push_warning("Cannot open worker AI trace; JSON events will use the engine log instead.")

func watches(id: int) -> bool:
	return enabled and (worker_id < 0 or worker_id == id)

func reset(g) -> void:
	world += 1
	decisions.clear()
	next_sample.clear()
	evaluations.clear()
	record(g, {}, "world", "reset", {"seed": g.world_seed, "max_hunger": g.MAX_HUNGER,
		"hunger_per_bread": g.HUNGER_PER_BREAD, "filter": worker_id})

func begin_decision(id: int) -> void:
	if watches(id):
		decisions[id] = decisions.get(id, 0) + 1

func observe(g, w: Dictionary) -> void:
	if not watches(w.id):
		return
	var now: float = (g.day - 1) * g.DAY_SECONDS + g.day_elapsed
	if now < next_sample.get(w.id, -1.0):
		return
	next_sample[w.id] = now + SAMPLE_SECONDS
	record(g, w, "simulation", "snapshot")

func selection(g, w: Dictionary, data: Dictionary) -> void:
	if not watches(w.id):
		return
	evaluations[w.id] = data
	record(g, w, "utility", "evaluated", data)

func entered(g, w: Dictionary) -> void:
	record(g, w, "state_tree", "entered")
	if not watches(w.id) or w.activity.active.option.kind != "rest" or w.hunger >= 20:
		return
	var evaluation: Dictionary = evaluations.get(w.id, {})
	var blocked: Dictionary = {}
	for candidate in evaluation.get("rejected", []):
		blocked[candidate.reason] = blocked.get(candidate.reason, 0) + 1
	var best_work := 0.0
	var best_meal := 0.0
	var best_payroll := 0.0
	var unfunded_work := false
	for candidate in evaluation.get("candidates", []):
		if candidate.kind in ["mine", "build", "produce", "operate"]:
			best_work = maxf(best_work, candidate.score)
			unfunded_work = unfunded_work or not candidate.eligible
		elif candidate.kind == "eat":
			best_meal = maxf(best_meal, candidate.score)
		elif candidate.kind == "payroll":
			best_payroll = maxf(best_payroll, candidate.score)
	var higher_ranked: Array = []
	for candidate in evaluation.get("ranked", []):
		if candidate.kind == "rest":
			break
		higher_ranked.append(candidate)
	# This is an actual rest entry, not a prediction made before slot acquisition.
	record(g, w, "diagnostic", "hungry_idle", {"idle_score": w.activity.active.option.score,
		"best_work_score": best_work, "best_meal_score": best_meal,
		"best_payroll_score": best_payroll,
		"work_needs_employer_cash": unfunded_work, "higher_ranked": higher_ranked,
		"blocked": blocked, "opportunities": evaluation.get("opportunities", {})})

func record(g, w: Dictionary, system: String, event: String, data: Dictionary = {}) -> void:
	if not enabled or (not w.is_empty() and not watches(w.id)):
		return
	sequence += 1
	var row := {"schema": 1, "session": session, "world": world, "seq": sequence,
		"day": g.day, "second": g.day_elapsed, "system": system, "event": event, "data": data}
	if not w.is_empty():
		row.worker_id = w.id
		row.worker_name = w.name
		row.decision = decisions.get(w.id, 0)
		row.components = components(w)
	# Preserve double precision: a displayed 1.0 may actually floor to zero bread.
	var line := JSON.stringify(row, "", false, true)
	if file == null:
		print("AI_JSON ", line)
		return
	if file.get_position() + line.length() >= max_bytes:
		file.close()
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path + ".1"):
			DirAccess.remove_absolute(absolute + ".1")
		DirAccess.rename_absolute(absolute, absolute + ".1")
		file = FileAccess.open(path, FileAccess.WRITE_READ)
	if file != null:
		file.store_line(line)
		file.flush()
	else:
		print("AI_JSON ", line)

func components(w: Dictionary) -> Dictionary:
	var a = w.activity.active
	var activity := {"kind": "none"}
	if a != null:
		activity = proposal(a.option)
		activity.merge({"phase": a.phase, "age": a.age, "elapsed": a.elapsed,
			"destination": cell(a.destination), "path_remaining": a.path.size(),
			"claims": a.handles.duplicate(true), "drink_elapsed": w.activity.drink_elapsed})
	return {"position": [w.pos.x, w.pos.y],
		"needs": {"hunger": w.hunger, "fatigue": w.fatigue},
		"economy": {"bread": w.bread, "bread_raw": String.num(w.bread, 17),
			"bread_display": "%.1f" % w.bread, "whole_bread": floori(w.bread),
			"meal_bread": w.meal_bread, "payroll": w.payroll,
			"earned_today": w.earned_today, "eaten_today": w.eaten_today,
			"loan_principal": w.loan_principal, "loan_interest": w.loan_interest},
		"cargo": {"ore": w.carry, "extra_ore": w.extra_cargo.duplicate(),
			"freight": shipment(w.freight), "ore_delivery": shipment(w.ore_delivery)},
		"equipment": {"gun_uses": w.gun_uses, "backpack_uses": w.backpack_uses,
			"water": w.water, "buffs": w.buffs.timed, "items": w.items, "equipment": w.equipment},
		"mood": {"value": w.mood.value, "shopping": w.mood.shopping, "avoids_machines": w.mood.avoids_machines},
		"activity": activity}

static func cell(p) -> Array:
	return [] if p == null else [p.x, p.y]

static func proposal(option) -> Dictionary:
	var result := {"kind": option.kind, "target": cell(option.target), "score": option.score,
		"slots": option.slots.duplicate()}
	for key in ["amount", "bed", "kind", "mined"]:
		if option.data.has(key):
			result["product" if key == "kind" else key] = option.data[key]
	for key in ["job", "canteen", "source", "target", "receiver"]:
		if option.data.has(key):
			result["delivery_target" if key == "target" else key] = cell(option.data[key])
	if option.data.has("shipment"):
		result.shipment = shipment(option.data.shipment)
	return result

static func shipment(value: Dictionary) -> Dictionary:
	if value.is_empty():
		return {}
	return {"source": cell(value.source), "target": cell(value.target), "item": value.item,
		"amount": value.amount, "owner": value.owner, "picked": value.picked,
		"on_belt": value.get("on_belt", false)}
