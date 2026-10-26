extends Area2D

const Art = preload("res://scripts/view/art.gd")
const Reveal = preload("res://assets/world/construction.gdshader")
const BeltArt = preload("res://scripts/view/belt_art.gd")
var progress := -1.0
var belt_art: Node2D
var crops: Sprite2D

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

func set_kind(kind: String) -> void:
	$Solid.texture = Art.texture("res://assets/icons/%s.svg" % kind)
	$Blueprint.texture = Art.texture("res://assets/icons/%s-blueprint.svg" % kind)
	for sprite in [$Solid, $Blueprint]:
		var size := Vector2(80, 80) if kind == "high_line" else Vector2(40, 40) if kind in ["belt", "electric_belt", "low_line"] else Vector2(80, 40)
		sprite.scale = size / sprite.texture.get_size()
	if kind == "farm":
		crops = Sprite2D.new()
		crops.texture = Art.texture("res://assets/icons/crops.svg")
		crops.offset = Vector2(0, -14)
		crops.position = Vector2(42, 32)
		add_child(crops)
	if kind == "low_line":
		$PickShape.shape.size = Vector2(40, 40)
		$PickShape.position = Vector2(20, 20)
	if kind in ["belt", "electric_belt"]:
		$PickShape.shape.size = Vector2(40, 40)
		$PickShape.position = Vector2(20, 20)
		$Solid.hide()
		$Blueprint.hide()
		belt_art = BeltArt.new()
		belt_art.position = Vector2(20, 20)
		add_child(belt_art)
	if kind == "high_line":
		$PickShape.shape.size = Vector2(80, 80)
		$PickShape.position = Vector2(40, 40)
	if kind in ["belt", "electric_belt"]:
		$Solid.hide()
		$Blueprint.hide()
		belt_art = BeltArt.new()
		belt_art.position = Vector2(20, 20)
		add_child(belt_art)

func set_belt_connections(connections: int, direction: Vector2i) -> void:
	belt_art.configure(connections, direction, progress)

func set_crop_growth(growth: float, planted: bool) -> void:
	crops.visible = planted
	crops.scale.y = lerpf(0.2, 1.0, growth)
	crops.modulate = Color("#78b880").lerp(Color.WHITE, growth)
