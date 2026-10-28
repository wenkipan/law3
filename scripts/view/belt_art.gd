extends Node2D

const Art = preload("res://scripts/view/art.gd")
const Reveal = preload("res://assets/world/construction.gdshader")
var solid: Sprite2D
var blueprint: Sprite2D
var arrow: Sprite2D
var progress := -1.0
var kind: String

func _init(value := "belt") -> void:
	kind = value

func _ready() -> void:
	var atlas := "power-line" if kind in ["high_line", "low_line"] else "belt"
	solid = make_strip("res://assets/world/%s-atlas.svg" % atlas, false)
	blueprint = make_strip("res://assets/world/%s-blueprint-atlas.svg" % atlas, true)
	if atlas == "power-line":
		for sprite in [solid, blueprint]:
			sprite.vframes = 2
			sprite.material.set_shader_parameter("atlas_rows", 2.0)
		set_line_kind(kind)
		return
	arrow = Sprite2D.new()
	arrow.texture = Art.texture("res://assets/world/belt-arrow.svg")
	add_child(arrow)

func set_line_kind(value: String) -> void:
	kind = value
	var row := 1 if kind == "low_line" else 0
	for sprite in [solid, blueprint]:
		if sprite.frame_coords.y != row:
			sprite.frame_coords.y = row

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
	if solid.frame_coords.x != connections:
		solid.frame_coords.x = connections
		blueprint.frame_coords.x = connections
	if is_instance_valid(arrow):
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
	if is_instance_valid(arrow):
		arrow.modulate = Color.WHITE if value >= 1.0 else Color(0.65, 0.9, 0.9, 0.7)
