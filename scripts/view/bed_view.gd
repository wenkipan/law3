extends Area2D

const Art = preload("res://scripts/view/art.gd")
const Reveal = preload("res://assets/world/construction.gdshader")
const BeltArt = preload("res://scripts/view/belt_art.gd")
const BarrierArt = preload("res://scripts/view/barrier_art.gd")
var progress := -1.0
var belt_art: Node2D
var barrier_art: Node2D
var line_art: Dictionary = {}
var kind := ""
var visual_size := Vector2.ZERO
var sheep: Sprite2D
var sheep_anchor: Node2D
var operating := false
@onready var shortage_bubble: Node2D = $ShortageBubble

func _ready() -> void:
	$Solid.texture = Art.texture("res://assets/icons/bed.svg")
	$Blueprint.texture = Art.texture("res://assets/icons/bed-blueprint.svg")
	for sprite in [$Solid, $Blueprint]:
		sprite.scale = Vector2(80, 40) / sprite.texture.get_size()
		var material := ShaderMaterial.new()
		material.shader = Reveal
		material.set_shader_parameter("blueprint", sprite == $Blueprint)
		sprite.material = material
	$Blueprint.modulate.a = 0.7

func set_progress(value: float) -> void:
	value = clampf(value, 0, 1)
	if is_equal_approx(progress, value):
		return
	progress = value
	$Solid.material.set_shader_parameter("progress", value)
	$Blueprint.material.set_shader_parameter("progress", value)
	$Blueprint.visible = value < 1
	if is_instance_valid(sheep):
		sheep.visible = value >= 1.0
	if is_instance_valid(belt_art):
		$Blueprint.hide()
		belt_art.set_progress(value)
	if is_instance_valid(barrier_art):
		$Blueprint.hide()
	for art in line_art.values():
		art.set_progress(value)
	if kind in ["high_line", "low_line"]:
		$Blueprint.hide()

func set_kind(value: String) -> void:
	if kind == value:
		return
	kind = value
	$Solid.texture = Art.building_texture(kind)
	$Blueprint.texture = Art.building_texture(kind, true)
	if kind == "barn":
		sheep_anchor = Node2D.new()
		add_child(sheep_anchor)
		sheep = Sprite2D.new()
		sheep.name = "Sheep"
		sheep.texture = Art.texture("res://assets/icons/sheep.svg")
		sheep.scale = Vector2.ONE * 0.65
		sheep_anchor.add_child(sheep)
		var motion := AnimationPlayer.new()
		motion.process_mode = Node.PROCESS_MODE_PAUSABLE
		motion.add_animation_library(&"", preload("res://assets/world/sheep-motion.tres"))
		sheep_anchor.add_child(motion)
		motion.play(&"sheep")
	for sprite in [$Solid, $Blueprint]:
		var size := Vector2(40, 40) if kind in ["belt", "electric_belt", "low_line"] else Vector2(80, 40)
		sprite.scale = size / sprite.texture.get_size()
	if kind in ["belt", "electric_belt"]:
		$PickShape.shape.size = Vector2(40, 40)
		$PickShape.position = Vector2(20, 20)
		$Solid.hide()
		$Blueprint.hide()
		belt_art = BeltArt.new()
		belt_art.position = Vector2(20, 20)
		add_child(belt_art)
		if kind == "electric_belt":
			belt_art.modulate = Color("#8de4e4")
	elif kind in ["high_line", "low_line"]:
		$Solid.hide()
		$Blueprint.hide()
	elif kind in ["wall", "fence", "door"]:
		$Solid.hide()
		$Blueprint.hide()
		barrier_art = BarrierArt.new(kind)
		barrier_art.position = Vector2(20, 20)
		add_child(barrier_art)

func set_size(size: Vector2) -> void:
	if visual_size == size:
		return
	visual_size = size
	if sheep_anchor != null: sheep_anchor.position = size * Vector2(0.69, 0.71)
	if $PickShape.shape.size != size:
		$PickShape.shape.size = size
	$PickShape.position = size / 2
	for sprite in [$Solid, $Blueprint]:
		var vertical := kind == "high_line" and size.x > size.y
		sprite.rotation = PI / 2 if vertical else 0.0
		sprite.position = Vector2(size.x, 0) if vertical else Vector2.ZERO
		sprite.scale = (Vector2(size.y, size.x) if vertical else size) / sprite.texture.get_size()

func set_operating(active: bool) -> void:
	active = active and progress >= 1.0
	if operating == active: return
	operating = active
	$Machinery.play(("machine" if kind in ["drill", "power_plant", "manual_generator"] else "powered") if active else "RESET")
	$Machinery.advance(0)

func set_belt_connections(connections: int, direction: Vector2i) -> void:
	belt_art.configure(connections, direction, progress)

func set_barrier_connections(connections: int, nearby: bool) -> void:
	barrier_art.configure(connections, progress, nearby)

func set_line_connections(connections: Dictionary) -> void:
	for offset in connections:
		if not line_art.has(offset):
			var art := BeltArt.new(kind)
			art.position = (Vector2(offset) + Vector2.ONE * 0.5) * 40
			add_child(art)
			line_art[offset] = art
		line_art[offset].configure(connections[offset], Vector2i.ZERO, progress)

func set_shortages(items: Array, amounts: Dictionary = {}) -> void:
	shortage_bubble.sync(items, amounts)

func position_shortage(zoom: float) -> void:
	shortage_bubble.position = Vector2(visual_size.x / 2, -2)
	shortage_bubble.sync_zoom(zoom)
