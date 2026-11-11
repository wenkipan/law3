extends CanvasLayer

const Art = preload("res://scripts/view/art.gd")

@onready var game: Node = get_parent()
@onready var world_view: Node = game.get_node("World")
@onready var hud: CanvasLayer = game.get_node("UI")
@onready var pointer: Node2D = $Pointer
@onready var icon: Sprite2D = $Pointer/Icon
@onready var motion: AnimationPlayer = $Pointer/AnimationPlayer
var previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var inside_window := true

func _ready() -> void:
	previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	get_window().mouse_entered.connect(func(): inside_window = true)
	get_window().mouse_exited.connect(func(): inside_window = false)
	sync_cursor()

func _exit_tree() -> void:
	Input.mouse_mode = previous_mouse_mode

func _process(_delta: float) -> void:
	sync_cursor()

func sync_cursor() -> void:
	var mouse := get_viewport().get_mouse_position()
	pointer.visible = inside_window and get_viewport().get_visible_rect().has_point(mouse)
	pointer.position = mouse
	var texture: Texture2D
	var hotspot := Vector2(16, 16)
	var working := false
	var control := get_viewport().gui_get_hovered_control()
	if not game.world.player_cargo.is_empty():
		texture = Art.item_texture(game.world.player_cargo.item)
	elif control != null or hud.blocks_simulation():
		var shape: int = control.get_cursor_shape(control.get_local_mouse_position()) if control != null else Input.get_current_cursor_shape()
		match shape:
			Input.CURSOR_IBEAM:
				texture = Art.texture("res://assets/cursors/ibeam.svg")
			Input.CURSOR_POINTING_HAND, Input.CURSOR_DRAG, Input.CURSOR_CAN_DROP:
				texture = Art.texture("res://assets/cursors/hand.svg")
				hotspot = Vector2(11, 3)
			Input.CURSOR_FORBIDDEN:
				texture = Art.texture("res://assets/cursors/forbidden.svg")
			Input.CURSOR_VSIZE, Input.CURSOR_HSIZE, Input.CURSOR_BDIAGSIZE, Input.CURSOR_FDIAGSIZE, Input.CURSOR_MOVE, Input.CURSOR_VSPLIT, Input.CURSOR_HSPLIT:
				texture = Art.texture("res://assets/icons/move.svg")
	else:
		texture = world_view.pointer_texture()
		if texture == Art.texture("res://assets/cursors/hand.svg"): hotspot = Vector2(11, 3)
		working = texture != null and not game.player_work.is_empty() and not get_tree().paused
	if texture == null:
		texture = Art.texture("res://assets/cursors/arrow.svg")
		hotspot = Vector2(3, 2)
	icon.texture = texture
	icon.scale = Vector2.ONE * 32.0 / maxf(texture.get_width(), texture.get_height())
	icon.position = -hotspot
	# The clip only animates the pointer transform, never input or labor progress.
	motion.speed_scale = 1.0 / Engine.time_scale
	if working and pointer.visible:
		if not motion.is_playing(): motion.play(&"work")
	else:
		if motion.is_playing(): motion.stop()
		pointer.rotation = 0.0
