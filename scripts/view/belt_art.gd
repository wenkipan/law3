extends Node2D

const Art = preload("res://scripts/view/art.gd")
const Reveal = preload("res://assets/world/construction.gdshader")
var solid: Sprite2D
var blueprint: Sprite2D
var arrow: Sprite2D
var progress := -1.0

func _ready() -> void:
	solid = make_strip("res://assets/world/belt-atlas.svg", false)
	blueprint = make_strip("res://assets/world/belt-blueprint-atlas.svg", true)
	arrow = Sprite2D.new()
	arrow.texture = Art.texture("res://assets/world/belt-arrow.svg")
	add_child(arrow)

func make_strip(path: String, is_blueprint: bool) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = Art.texture(path)
	sprite.hframes = 16
	var material := ShaderMaterial.new()
	material.shader = Reveal
	material.set_shader_parameter("blueprint", is_blueprint)
	sprite.material = material
	add_child(sprite)
	return sprite

func configure(connections: int, direction: Vector2i, value: float) -> void:
	solid.frame = connections
	blueprint.frame = connections
	arrow.visible = direction != Vector2i.ZERO
	arrow.rotation = Vector2(direction).angle()
	set_progress(value)

func set_progress(value: float) -> void:
	if is_equal_approx(progress, value):
		return
	progress = value
	solid.material.set_shader_parameter("progress", value)
	blueprint.material.set_shader_parameter("progress", value)
	blueprint.visible = value < 1.0
	arrow.modulate = Color.WHITE if value >= 1.0 else Color(0.65, 0.9, 0.9, 0.7)
