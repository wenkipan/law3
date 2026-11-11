extends Area2D

const Art = preload("res://scripts/view/art.gd")
const Reveal = preload("res://assets/world/construction.gdshader")
const BeltArt = preload("res://scripts/view/belt_art.gd")
const BarrierArt = preload("res://scripts/view/barrier_art.gd")
const SHORTAGE_INTERVAL := 3.0
const SHORTAGE_FLIP_SECONDS := 0.24
var progress := -1.0
var belt_art: Node2D
var barrier_art: Node2D
var line_art: Dictionary = {}
var kind := ""
var visual_size := Vector2.ZERO
var sheep: Sprite2D
var sheep_anchor: Node2D
var operating := false
var shortage_bubble: TextureRect
var shortage_icon: TextureRect
var shortage_quantity: Label
var shortage_items: Array = []
var shortage_amounts: Dictionary = {}
var shortage_item = null
var shortage_age := 0.0

func _ready() -> void:
	set_process(false)
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

func sync_sheep(count: int) -> void:
	sheep.visible = count > 0 and progress >= 1.0

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
	if items == shortage_items and amounts == shortage_amounts: return
	var changed_items := items != shortage_items
	shortage_items = items.duplicate()
	shortage_amounts = amounts.duplicate()
	if changed_items: shortage_age = 0.0
	set_process(not items.is_empty())
	if items.is_empty():
		shortage_item = null
		if shortage_bubble != null: shortage_bubble.hide()
		return
	if shortage_bubble == null:
		shortage_bubble = TextureRect.new()
		shortage_bubble.texture = Art.texture("res://assets/world/material-shortage.svg")
		shortage_bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shortage_bubble.size = Vector2(32, 34)
		shortage_bubble.pivot_offset = Vector2(16, 34)
		shortage_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shortage_bubble)
		shortage_icon = TextureRect.new()
		shortage_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shortage_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shortage_icon.size = Vector2(20, 20)
		shortage_icon.pivot_offset = shortage_icon.size / 2
		shortage_icon.position = Vector2(6, 4)
		shortage_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shortage_bubble.add_child(shortage_icon)
		shortage_quantity = Label.new()
		shortage_quantity.position = Vector2(22, 0)
		shortage_quantity.size = Vector2(22, 20)
		shortage_quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shortage_quantity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		shortage_quantity.add_theme_font_size_override("font_size", 14)
		shortage_quantity.add_theme_color_override("font_color", Color("#263337"))
		shortage_quantity.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shortage_icon.add_child(shortage_quantity)
	var with_quantity := not amounts.is_empty()
	shortage_quantity.visible = with_quantity
	shortage_bubble.size = Vector2(56 if with_quantity else 32, 34)
	shortage_bubble.pivot_offset.x = shortage_bubble.size.x / 2
	shortage_icon.pivot_offset.x = 22 if with_quantity else 10
	if changed_items: shortage_icon.scale = Vector2.ONE
	show_shortage_item(items[0] if changed_items else shortage_item)
	shortage_bubble.show()
	position_shortage(get_viewport().get_camera_2d().zoom.x)

func show_shortage_item(item) -> void:
	if not is_same(shortage_item, item):
		shortage_item = item
		shortage_icon.texture = Art.item_texture(item)
	shortage_quantity.text = str(shortage_amounts[item]) if shortage_amounts.has(item) else ""

func _process(delta: float) -> void:
	delta /= Engine.time_scale
	shortage_age += delta
	var cycle := int(shortage_age / SHORTAGE_INTERVAL)
	var index := cycle % shortage_items.size()
	var phase := fmod(shortage_age, SHORTAGE_INTERVAL)
	shortage_icon.scale.x = 1.0
	if shortage_items.size() > 1 and cycle > 0 and phase < SHORTAGE_FLIP_SECONDS:
		# Swap textures edge-on; only the centered icon turns, never the bubble shell.
		var turn := phase / SHORTAGE_FLIP_SECONDS
		shortage_icon.scale.x = absf(cos(turn * PI))
		if turn < 0.5: index = (cycle - 1) % shortage_items.size()
	show_shortage_item(shortage_items[index])
	position_shortage(get_viewport().get_camera_2d().zoom.x)

func position_shortage(zoom: float) -> void:
	if shortage_bubble == null or not shortage_bubble.visible: return
	var breath := (1.0 - cos(shortage_age * TAU / SHORTAGE_INTERVAL)) * 0.5
	shortage_bubble.scale = Vector2.ONE * (1.0 + 0.045 * breath) / maxf(zoom, 0.1)
	shortage_bubble.modulate.a = 0.92 + 0.08 * breath
	shortage_bubble.position = Vector2(visual_size.x / 2 - shortage_bubble.pivot_offset.x, -36)
