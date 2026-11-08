extends RefCounted

const CLOTHES_CAPACITY := 50.0
const BODY_CAPACITY := 100.0
const DISCOMFORT := 30.0
const DISEASE := 70.0
const EXPOSURE_PER_HOUR := 0.1
const CLEANER_REMOVAL := 0.5
const SOURCES := {
	"power_plant": {"radius": 3, "strength": 35.0},
	"drill": {"radius": 3, "strength": 20.0},
	"electric_belt": {"radius": 1, "strength": 8.0},
	"smelter": {"radius": 3, "strength": 30.0},
	"chemical_plant": {"radius": 3, "strength": 25.0},
}
var cells: Dictionary = {}
var revision := 0

func clear() -> void:
	cells.clear()
	revision += 1

static func record_operation(world, p: Vector2i, kind: String, fraction: float) -> void:
	if not SOURCES.has(kind): return
	var profile: Dictionary = SOURCES[kind]
	var strength: float = profile.strength * clampf(fraction, 0, 1)
	world.pollution_operations[p] = {"radius": profile.radius,
		"strength": maxf(strength, world.pollution_operations.get(p, {}).get("strength", 0.0))}

func spread(p: Vector2i, strength: float, radius: int) -> void:
	if strength <= 0: return
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var cell := p + Vector2i(x, y)
			var amount := strength * (1.0 - float(maxi(absi(x), absi(y))) / (radius + 1))
			cells[cell] = cells.get(cell, 0.0) + amount

func rebuild(g) -> void:
	rebuild_world(g.world)

func rebuild_world(world) -> void:
	var previous := cells
	cells = {}
	for p in world.pollution_operations:
		var source: Dictionary = world.pollution_operations[p]
		spread(p, source.strength, source.radius)
	for p in world.wastewater:
		spread(p, world.wastewater[p], 2)
	# Reserved goods remain at the source until picked; carried loads move with their holder.
	for shipment in world.delivery_tasks:
		if not shipment.bound or shipment.get("on_belt", false): continue
		var p: Vector2i = shipment.source
		if shipment.picked and shipment.owner >= 0:
			p = Vector2i(world.workers[shipment.owner].pos.round())
		spread(p, shipment.get("pollution", 0.0), 2)
	for cargo in world.belt_cargo.values():
		var p := Vector2i(Vector2(cargo.from).lerp(Vector2(cargo.to), clampf(cargo.progress, 0, 1)).round())
		spread(p, cargo.delivery.get("pollution", 0.0), 2)
	for w in world.workers:
		if w.pollution >= DISEASE:
			spread(Vector2i(w.pos.round()), 20.0, 2)
	if cells != previous: revision += 1

func at(p: Vector2i) -> float:
	return cells.get(p, 0.0)

static func absorb(w: Dictionary, amount: float) -> void:
	if w.equipment.get("clothes", 0) > 0:
		var absorbed := minf(amount, maxf(0, CLOTHES_CAPACITY - w.clothes_pollution))
		w.clothes_pollution += absorbed
		amount -= absorbed
	w.pollution = minf(BODY_CAPACITY, w.pollution + amount)

func expose(g, delta: float) -> void:
	var new_source := false
	for w in g.world.workers:
		# A patient emits into the field but does not infect themself a second time.
		var was_sick: bool = w.pollution >= DISEASE
		var external := maxf(0, at(Vector2i(w.pos.round())) - (20.0 if was_sick else 0.0))
		absorb(w, external * EXPOSURE_PER_HOUR * delta / g.HOUR_SECONDS)
		if not was_sick and w.pollution >= DISEASE:
			new_source = true
	if new_source: rebuild(g)

static func work_factor(w: Dictionary) -> float:
	return 0.75 if w.pollution >= DISEASE else (0.9 if w.pollution > DISCOMFORT else 1.0)

static func status(w: Dictionary) -> String:
	return "患病 · 可传染" if w.pollution >= DISEASE else ("不适" if w.pollution > DISCOMFORT else "正常")
