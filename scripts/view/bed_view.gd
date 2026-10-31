extends Area2D

const Art = preload("res://scripts/view/art.gd")
const Reveal = preload("res://assets/world/construction.gdshader")
const BeltArt = preload("res://scripts/view/belt_art.gd")
var progress := -1.0
var belt_art: Node2D
var line_art: Dictionary = {}
var kind := ""
var visual_size := Vector2.ZERO
var sheep: Sprite2D

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
	if is_instance_valid(belt_art):
		$Blueprint.hide()
		belt_art.set_progress(value)
	for art in line_art.values():
		art.set_progress(value)
	if kind in ["high_line", "low_line"]:
		$Blueprint.hide()

func set_kind(value: String) -> void:
	if kind == value:
		return
	kind = value
	$Solid.texture = Art.texture("res://assets/icons/%s.svg" % kind)
	$Blueprint.texture = Art.texture("res://assets/icons/%s-blueprint.svg" % kind)
	if kind == "barn":
		sheep = Sprite2D.new()
		sheep.texture = Art.texture("res://assets/icons/sheep.svg")
		sheep.scale = Vector2.ONE * 0.65
		add_child(sheep)
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

func set_size(size: Vector2) -> void:
	if visual_size == size:
		return
	visual_size = size
	if $PickShape.shape.size != size:
		$PickShape.shape.size = size
	$PickShape.position = size / 2
	for sprite in [$Solid, $Blueprint]:
		var vertical := kind == "high_line" and size.x > size.y
		sprite.rotation = PI / 2 if vertical else 0.0
		sprite.position = Vector2(size.x, 0) if vertical else Vector2.ZERO
		sprite.scale = (Vector2(size.y, size.x) if vertical else size) / sprite.texture.get_size()

func animate(active: bool, time: float) -> void:
	$Solid.modulate = Color.WHITE if not active else Color(1, 1, 0.85 + 0.15 * sin(time * 5.0))
	if kind in ["drill", "power_plant", "manual_generator"]:
		$Solid.position.y = sin(time * 24.0) * 0.6 if active else 0.0

func sync_sheep(count: int, time: float) -> void:
	sheep.visible = count > 0
	sheep.position = Vector2(46 + sin(time * 0.4) * 8, 25 + sin(time * 2) * 0.4)
	sheep.rotation = sin(time * 0.7) * 0.03

func set_belt_connections(connections: int, direction: Vector2i) -> void:
	belt_art.configure(connections, direction, progress)

func set_line_connections(connections: Dictionary) -> void:
	for offset in connections:
		if not line_art.has(offset):
			var art := BeltArt.new(kind)
			art.position = (Vector2(offset) + Vector2.ONE * 0.5) * 40
			add_child(art)
			line_art[offset] = art
		line_art[offset].configure(connections[offset], Vector2i.ZERO, progress)
