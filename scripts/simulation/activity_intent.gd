extends RefCounted

const Option = preload("res://scripts/simulation/activity_option.gd")

var pending: Array = []
var evaluated: Array = []
var ordered := false
var cursor := 0

static func better(score: float, order: int, other_score: float, other_order: int) -> bool:
	if score == other_score or is_equal_approx(score, other_score): return order < other_order
	return score > other_score

func resolve(e, incumbent: Dictionary) -> Dictionary:
	# Keep alternatives for entry failure; only a proven upper bound may skip exact scoring.
	if not ordered:
		for op in pending: op.bound = e.upper_bound(op)
		pending.sort_custom(func(a, b): return better(a.bound, a.order, b.bound, b.order))
		ordered = true
	var best: Dictionary = {}
	for entry in evaluated:
		if best.is_empty() or better(entry.option.score, entry.order, best.option.score, best.order): best = entry
	while cursor < pending.size():
		var floor: Dictionary = best
		if floor.is_empty() or (not incumbent.is_empty() and better(incumbent.option.score, incumbent.order, floor.option.score, floor.order)):
			floor = incumbent
		var next: Dictionary = pending[cursor]
		if not floor.is_empty() and not better(next.bound, next.order, floor.option.score, floor.order): break
		cursor += 1
		var result: Dictionary = e.evaluate(next)
		if not is_finite(result.score):
			e.reject(next.kind, next.target, "no_finite_estimate")
			continue
		var data: Dictionary = next.data.duplicate()
		data.merge(result.get("data", {}), true)
		var option = Option.new(next.kind, next.target, next.position, next.path, next.slots, result.score, data)
		var bonus: float = e.context.worker.activity.inertia_bonus(option)
		if bonus > 0: option = Option.new(next.kind, next.target, next.position, next.path, next.slots, result.score + bonus, data)
		var entry := {"option": option, "order": next.order}
		evaluated.append(entry)
		if e.tracing: e.proposals.append({"option": option, "result": result, "inertia_bonus": bonus})
		if best.is_empty() or better(option.score, next.order, best.option.score, best.order): best = entry
	return best

func consume(option) -> void:
	for i in evaluated.size():
		if evaluated[i].option == option:
			evaluated.remove_at(i)
			return
