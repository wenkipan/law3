extends Node2D

const Art = preload("res://scripts/view/art.gd")
var items: Array = []
var amounts: Dictionary = {}
var index := 0
@onready var bubble: TextureRect = $Bubble
@onready var icon: TextureRect = $Bubble/Icon
@onready var quantity: Label = $Bubble/Icon/Quantity
@onready var breath: AnimationPlayer = $Breath
@onready var cycle: AnimationPlayer = $Cycle

func sync(next_items: Array, next_amounts: Dictionary) -> void:
	if items == next_items and amounts == next_amounts: return
	var changed_items := items != next_items
	items = next_items.duplicate()
	amounts = next_amounts.duplicate()
	if items.is_empty():
		breath.stop()
		cycle.stop()
		hide()
		return
	var with_quantity := not amounts.is_empty()
	quantity.visible = with_quantity
	bubble.size.x = 56 if with_quantity else 32
	bubble.position.x = -bubble.size.x / 2
	bubble.pivot_offset.x = bubble.size.x / 2
	icon.pivot_offset.x = 22 if with_quantity else 10
	if changed_items:
		index = 0
		cycle.stop()
		icon.scale = Vector2.ONE
		breath.play(&"breath")
		breath.seek(0, true)
		if items.size() > 1: cycle.play(&"cycle")
	show_item()
	show()

func advance_item() -> void:
	if items.is_empty(): return
	index = (index + 1) % items.size()
	show_item()

func show_item() -> void:
	var item = items[index]
	icon.texture = Art.item_texture(item)
	quantity.text = str(amounts[item]) if amounts.has(item) else ""

func sync_zoom(zoom: float) -> void:
	if not visible: return
	scale = Vector2.ONE / maxf(zoom, 0.1)
	# UI feedback uses real time, independently of simulation speed and pause.
	breath.speed_scale = 1.0 / Engine.time_scale
	cycle.speed_scale = breath.speed_scale
