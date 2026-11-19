extends RefCounted

const Storage = preload("res://scripts/entities/storage.gd")
enum Phase { BLUEPRINT, BUILT, RECOVERING, DEMOLISHING }
const BELTS := ["belt", "electric_belt"]
const LINES := ["high_line", "low_line"]
const GROUPS := ["site", "station", "bed", "bank", "belt", "line", "growing"]

var id := -1
var phase: int = Phase.BLUEPRINT
var inventory := Storage.new()
# Kind-specific work, employment and service state belongs to this entity.
var state: Dictionary = {}
var kind: String:
	get: return state.get("kind", "")

func in_group(group: String) -> bool:
	if group == "": return true
	if group == "site": return phase != Phase.BUILT
	if phase != Phase.BUILT: return false
	match group:
		"station": return kind != "bed" and kind not in BELTS and kind not in LINES
		"bed": return kind == "bed"
		"bank": return kind == "bank"
		"belt": return kind in BELTS
		"line": return kind in LINES
		"growing":
			var remaining = state.get("growth", 0.0)
			return (remaining is float or remaining is int) and remaining > 0.0 and in_group("station")
	return false

func complete(settings: Dictionary) -> void:
	state = settings
	phase = Phase.BUILT

func recover(settings: Dictionary) -> void:
	state = settings
	state.cancelled = true
	phase = Phase.RECOVERING
