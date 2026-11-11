extends Node2D

const Art = preload("res://scripts/view/art.gd")
const Reveal = preload("res://assets/world/construction.gdshader")
var kind: String
var solid := Sprite2D.new()
var blueprint := Sprite2D.new()
var hinge: Node2D
var gate_motion: Tween
var wants_open := false
var completed := false

func _init(value: String) -> void:
	kind = value
	for sprite in [solid, blueprint]:
		var material := ShaderMaterial.new()
		material.shader = Reveal
		material.set_shader_parameter("blueprint", sprite == blueprint)
		sprite.material = material
		add_child(sprite)
	blueprint.modulate = Color(0.6, 0.95, 1.0, 0.7)
	if kind == "door":
		solid.texture = Art.texture("res://assets/world/door-frame.svg")
		blueprint.texture = solid.texture
		hinge = Node2D.new()
		hinge.position.x = -13
		add_child(hinge)
		for template in [solid, blueprint]:
			var leaf := Sprite2D.new()
			leaf.texture = Art.texture("res://assets/world/door-leaf.svg")
			leaf.centered = false
			leaf.position.y = -5
			leaf.material = template.material
			leaf.modulate = template.modulate
			hinge.add_child(leaf)
	else:
		solid.texture = Art.texture("res://assets/world/%s-atlas.svg" % kind)
		blueprint.texture = Art.texture("res://assets/world/%s-blueprint-atlas.svg" % kind)
		for sprite in [solid, blueprint]: sprite.region_enabled = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func configure(mask: int, progress: float, nearby := false) -> void:
	completed = progress >= 1.0
	var open := completed and nearby
	if kind == "door" and open != wants_open:
		wants_open = open
		if gate_motion != null: gate_motion.kill()
		gate_motion = hinge.create_tween()
		gate_motion.tween_property(hinge, "rotation", -PI * 0.46 if open else 0.0, 0.14)
	for sprite in [solid, blueprint]:
		sprite.material.set_shader_parameter("progress", progress)
	if kind == "door":
		rotation = PI / 2 if (mask & 12) != 0 and (mask & 3) == 0 else 0.0
	else:
		for sprite in [solid, blueprint]: sprite.region_rect = Rect2((mask if mask != 0 else 3) * 40, 0, 40, 40)

