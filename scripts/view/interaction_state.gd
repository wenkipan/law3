extends RefCounted

# View coordinates and player gestures are not world coordinates or commands.
var view_origin := Vector2i.ZERO
var pollution_visible := false
var selected_line := false
var moving_drill_from = null
var belt_drawing := false
var belt_path: Array[Vector2i] = []
var belt_pointer := Vector2.ZERO
var building_drawing := false
var building_start := Vector2i.ZERO
var building_end := Vector2i.ZERO
var building_axis := Vector2i.ZERO
var building_pick = null
var speed := 1.0
var paused_by_player := false
var tool := "dig"
var brush_wage := 1.0
var wage_filter := "all"
var wage_pick: Dictionary = {}
var brush_fee := 1.0
var fee_filter := "all"
var dragging := false
var panning := false
var selection_start := Vector2i.ZERO
var selection_end := Vector2i.ZERO
var selected_entity = null
var selected_tile = null
var selected_worker := -1
var demolition_pick: Dictionary = {}

func reset() -> void:
	view_origin = Vector2i.ZERO
	pollution_visible = false
	selected_line = false
	moving_drill_from = null
	belt_drawing = false
	belt_path.clear()
	belt_pointer = Vector2.ZERO
	building_drawing = false
	building_start = Vector2i.ZERO
	building_end = Vector2i.ZERO
	building_axis = Vector2i.ZERO
	building_pick = null
	# Speed is a player preference, retained when starting a new world.
	paused_by_player = false
	tool = "dig"
	brush_wage = 1.0
	wage_filter = "all"
	wage_pick.clear()
	brush_fee = 1.0
	fee_filter = "all"
	dragging = false
	panning = false
	selection_start = Vector2i.ZERO
	selection_end = Vector2i.ZERO
	selected_entity = null
	selected_tile = null
	selected_worker = -1
	demolition_pick.clear()
