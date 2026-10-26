extends Node2D

const Art = preload("res://scripts/view/art.gd")
const WorkerScene = preload("res://scenes/worker.tscn")
const BedScene = preload("res://scenes/bed.tscn")
const BeltArt = preload("res://scripts/view/belt_art.gd")
var game: Node
var initialized := false
var worker_nodes: Dictionary = {}
var building_nodes: Dictionary = {}
var cargo_nodes: Dictionary = {}
var belt_previews: Array[Node2D] = []
var building_previews: Array[Sprite2D] = []
var fog_cells: Dictionary = {}
var order_cells: Dictionary = {}
var cell_updates := 0
var portal: Area2D
var hovered: Area2D
var hover_frame: NinePatchRect
var selection_frame: NinePatchRect
var drag_frame: NinePatchRect
var preview: Sprite2D

func _ready() -> void:
	var tiles := Art.tile_set("res://assets/world/terrain-atlas.svg", 5)
	$TerrainBackground.tile_set = tiles
	$Blocks.tile_set = tiles
	$Fog.tile_set = Art.tile_set("res://assets/world/fog-atlas.svg", 2)
	$Overlays/Orders.tile_set = Art.tile_set("res://assets/world/order.svg", 1)
	portal = Area2D.new()
	portal.name = "Portal"
	portal.z_index = 20
	portal.z_as_relative = false
	portal.collision_layer = 1
	portal.collision_mask = 0
	portal.monitoring = false
	portal.monitorable = false
	var sprite := Sprite2D.new()
	sprite.texture = Art.texture("res://assets/world/portal.svg")
	portal.add_child(sprite)
	var shape := CollisionShape2D.new()
	shape.name = "PickShape"
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(64, 80)
	portal.add_child(shape)
	$Buildings.add_child(portal)
	hover_frame = make_frame("Hover")
	selection_frame = make_frame("Selection")
	drag_frame = make_frame("DragSelection")
	preview = Sprite2D.new()
	preview.name = "BedPreview"
	preview.texture = Art.texture("res://assets/icons/bed-blueprint.svg")
	preview.centered = false
	preview.scale = Vector2(80, 40) / preview.texture.get_size()
	preview.modulate.a = 0.5
	$Overlays.add_child(preview)

func make_frame(node_name: String) -> NinePatchRect:
	var frame := NinePatchRect.new()
	frame.name = node_name
	frame.texture = Art.texture("res://assets/world/selection.svg")
	frame.patch_margin_left = 12
	frame.patch_margin_right = 12
	frame.patch_margin_top = 12
	frame.patch_margin_bottom = 12
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw_center = false
	$Overlays.add_child(frame)
	return frame

func rebuild(controller: Node) -> void:
	game = controller
	hovered = null
	$GroundInput/PickShape.shape.size = Vector2(game.SIZE) * game.CELL
	$GroundInput/PickShape.position = $GroundInput/PickShape.shape.size / 2
	if not $GroundInput.input_event.is_connected(_on_pick_input.bind($GroundInput)):
		connect_pick($GroundInput, -1, Vector2i(-1, -1))
		connect_pick(portal, -1, game.BASE)
	initialized = false
	for layer in [$TerrainBackground, $Blocks, $Fog, $Overlays/Orders]:
		layer.clear()
	for node in worker_nodes.values() + building_nodes.values() + cargo_nodes.values():
		node.free()
	worker_nodes.clear()
	building_nodes.clear()
	cargo_nodes.clear()
	fog_cells.clear()
	order_cells.clear()
	for node in $WaterSources.get_children():
		node.free()
	for p in game.water_sources:
		var source := Sprite2D.new()
		source.texture = Art.texture("res://assets/world/water-source.svg")
		source.position = game.tile_center(p)
		$WaterSources.add_child(source)
	for p in game.terrain:
		$TerrainBackground.set_cell(p, 0, Vector2i.ZERO)
		if game.terrain[p] != 0:
			$Blocks.set_cell(p, 0, Vector2i(game.terrain[p], 0))
		$Fog.set_cell(p, 0, Vector2i.ZERO)
		fog_cells[p] = 0
	portal.position = game.tile_center(game.BASE) + Vector2(0, -4)
	initialized = true
	sync_fog()
	sync_orders()
	sync_dynamic()

func block_changed(p: Vector2i) -> void:
	if not initialized:
		return
	if game.terrain[p] == 0:
		$Blocks.erase_cell(p)
	else:
		$Blocks.set_cell(p, 0, Vector2i(game.terrain[p], 0))
	cell_updates += 1

func sync_fog() -> void:
	if not initialized:
		return
	# Only explored cells can change; untouched fog tiles never get resubmitted.
	for p in game.explored:
		var next := -1 if game.visible_tiles.has(p) else 1
		if fog_cells.get(p, 0) == next:
			continue
		fog_cells[p] = next
		if next == -1:
			$Fog.erase_cell(p)
		else:
			$Fog.set_cell(p, 0, Vector2i(next, 0))
		cell_updates += 1

func sync_orders() -> void:
	if not initialized:
		return
	for p in order_cells.keys():
		if not game.jobs.has(p):
			$Overlays/Orders.erase_cell(p)
			order_cells.erase(p)
			cell_updates += 1
	for p in game.jobs:
		if not order_cells.has(p):
			$Overlays/Orders.set_cell(p, 0, Vector2i.ZERO)
			order_cells[p] = true
			cell_updates += 1

func sync_buildings() -> void:
	for p in building_nodes.keys():
		if not game.sites.has(p) and not game.beds.has(p) and not game.benches.has(p) and not game.banks.has(p) and not game.belts.has(p):
			building_nodes[p].free()
			building_nodes.erase(p)
	for p in game.sites.keys() + game.beds.keys() + game.benches.keys() + game.banks.keys() + game.belts.keys():
		if not building_nodes.has(p):
			var bed := BedScene.instantiate()
			bed.name = "Bed_%d_%d" % [p.x, p.y]
			$Buildings.add_child(bed)
			bed.set_kind(game.building_kind(p))
			bed.position = Vector2(p) * game.CELL
			connect_pick(bed, -1, p)
			building_nodes[p] = bed
		var progress: float = game.sites[p].progress / game.sites[p].seconds if game.sites.has(p) else 1.0
		building_nodes[p].set_progress(progress)
		if game.building_kind(p) == "belt":
			building_nodes[p].set_belt_connections(game.belt_connections(p), game.belt_direction_at(p))
		building_nodes[p].input_pickable = game.explored.has(p)

func sync_belt_cargo() -> void:
	for id in cargo_nodes.keys():
		if not game.belt_cargo.has(id):
			cargo_nodes[id].free()
			cargo_nodes.erase(id)
	for id in game.belt_cargo:
		var cargo: Dictionary = game.belt_cargo[id]
		if not cargo_nodes.has(id):
			var sprite := Sprite2D.new()
			sprite.texture = Art.item_texture(cargo.delivery.item)
			sprite.scale = Vector2.ONE * (22.0 / maxf(sprite.texture.get_width(), sprite.texture.get_height()))
			sprite.z_index = 1
			$Buildings.add_child(sprite)
			cargo_nodes[id] = sprite
		cargo_nodes[id].position = game.tile_center(Vector2(cargo.from).lerp(Vector2(cargo.to), clampf(cargo.progress, 0, 1)))

func sync_dynamic() -> void:
	if not initialized:
		return
	sync_buildings()
	sync_belt_cargo()
	for w in game.workers:
		if not worker_nodes.has(w.id):
			var worker := WorkerScene.instantiate()
			worker.name = "Worker_%d" % w.id
			$Characters.add_child(worker)
			worker.configure(w, game.font)
			connect_pick(worker, w.id, Vector2i(-1, -1))
			worker_nodes[w.id] = worker
		worker_nodes[w.id].sync(w, game.animation_time, game.CELL)
		worker_nodes[w.id].input_pickable = game.explored.has(Vector2i(w.pos.round()))
	# Native picking uses tree order for equal Z; match the workers' Y-sort order.
	var ordered: Array = worker_nodes.keys()
	ordered.sort_custom(func(a, b):
		var ay: float = worker_nodes[a].position.y
		var by: float = worker_nodes[b].position.y
		return a < b if is_equal_approx(ay, by) else ay < by)
	for i in ordered.size():
		var worker: Area2D = worker_nodes[ordered[i]]
		if worker.get_index() != i:
			$Characters.move_child(worker, i)
	portal.modulate = Color.WHITE * (0.95 + sin(game.animation_time * 2) * 0.05)
	var p: Vector2i = game.selected_entity
	selection_frame.visible = true
	if game.selected_worker >= 0:
		var bounds := pick_bounds(worker_nodes[game.selected_worker])
		selection_frame.position = bounds.position
		selection_frame.size = bounds.size
	elif p == game.BASE:
		selection_frame.position = portal.position - Vector2(32, 40)
		selection_frame.size = Vector2(64, 80)
	elif game.beds.has(p) or game.sites.has(p) or game.benches.has(p) or game.banks.has(p) or game.belts.has(p):
		selection_frame.position = Vector2(p) * game.CELL
		selection_frame.size = Vector2(40, 40) if game.building_kind(p) == "belt" else Vector2(80, 40)
	elif game.explored.has(game.selected_tile):
		selection_frame.position = Vector2(game.selected_tile) * game.CELL
		selection_frame.size = Vector2.ONE * game.CELL
	else:
		selection_frame.hide()
	var hover: Vector2i = game.mouse_tile()
	hover_frame.visible = game.explored.has(hover)
	hover_frame.position = Vector2(hover) * game.CELL
	hover_frame.size = Vector2.ONE * game.CELL
	if is_instance_valid(hovered) and hovered != $GroundInput and hovered.input_pickable:
		var bounds := pick_bounds(hovered)
		hover_frame.show()
		hover_frame.position = bounds.position
		hover_frame.size = bounds.size
	if get_viewport().gui_get_hovered_control() != null:
		hover_frame.hide()
		hovered = null
	preview.visible = game.tool in game.BUILDING_KINDS and game.can_afford_building(game.tool) and game.explored.has(hover) and get_viewport().gui_get_hovered_control() == null
	if preview.visible:
		preview.texture = Art.texture("res://assets/icons/%s-blueprint.svg" % game.tool)
	var preview_size := Vector2(40, 40) if game.tool == "belt" else Vector2(80, 40)
	preview.scale = preview_size / preview.texture.get_size()
	preview.modulate = Color(1, 1, 1, 0.5) if game.building_space_valid(hover, game.tool) else Color(1, 0.4, 0.3, 0.5)
	preview.centered = false
	preview.rotation = 0.0
	preview.position = Vector2(hover) * game.CELL
	if game.belt_drawing or game.building_drawing or game.tool == "belt":
		preview.hide()
	sync_belt_preview()
	sync_building_preview()
	drag_frame.visible = game.dragging
	if game.dragging:
		drag_frame.position = Vector2(game.selection_start.min(game.selection_end)) * game.CELL
		drag_frame.size = Vector2((game.selection_start - game.selection_end).abs() + Vector2i.ONE) * game.CELL
		drag_frame.modulate = Color("#e39d90") if game.tool == "cancel" else Color("#e3d29d")

func sync_belt_preview() -> void:
	var path: Array[Vector2i] = []
	if game.belt_drawing:
		path.assign(game.belt_path)
	if not game.belt_drawing and game.tool == "belt" and game.explored.has(game.mouse_tile()) and get_viewport().gui_get_hovered_control() == null:
		path.append(game.mouse_tile())
	var plan: Dictionary = game.belt_path_plan(path)
	var cells: Array = plan.keys()
	# Preview changed joins on neighboring existing tracks as well as new tiles.
	for p in plan:
		for direction in game.DIRS:
			var neighbor: Vector2i = p + direction
			if not cells.has(neighbor) and not game.belt_data(neighbor).is_empty():
				cells.append(neighbor)
	while belt_previews.size() < cells.size():
		var art := BeltArt.new()
		$Overlays.add_child(art)
		belt_previews.append(art)
	var valid: bool = game.belt_plan_valid(path)
	for i in belt_previews.size():
		var art := belt_previews[i]
		art.visible = i < cells.size()
		if not art.visible:
			continue
		var p: Vector2i = cells[i]
		art.position = game.tile_center(p)
		art.configure(game.belt_connections(p, plan), game.belt_data(p, plan).direction, 0.0)
		art.modulate = Color(0.7, 1, 0.85, 0.8) if valid else Color(1, 0.4, 0.3, 0.8)

func sync_building_preview() -> void:
	var positions: Array[Vector2i] = []
	if game.building_drawing:
		positions.assign(game.building_row())
	while building_previews.size() < positions.size():
		var sprite := Sprite2D.new()
		sprite.centered = false
		$Overlays.add_child(sprite)
		building_previews.append(sprite)
	var valid: bool = game.building_batch_valid(positions, game.tool) if game.building_drawing else false
	for i in building_previews.size():
		var sprite := building_previews[i]
		sprite.visible = i < positions.size()
		if sprite.visible:
			sprite.texture = Art.texture("res://assets/icons/%s-blueprint.svg" % game.tool)
			sprite.scale = Vector2(80, 40) / sprite.texture.get_size()
			sprite.position = Vector2(positions[i]) * game.CELL
			sprite.modulate = Color(0.7, 1, 0.85, 0.8) if valid else Color(1, 0.4, 0.3, 0.8)

func pick_bounds(area: Area2D) -> Rect2:
	var shape: CollisionShape2D = area.get_node("PickShape")
	return shape.global_transform * shape.shape.get_rect()

func connect_pick(area: Area2D, worker_id: int, entity: Vector2i) -> void:
	area.set_meta("worker_id", worker_id)
	area.set_meta("entity", entity)
	area.input_event.connect(_on_pick_input.bind(area))
	area.mouse_exited.connect(func():
		if hovered == area:
			hovered = null)

func _on_pick_input(_viewport: Node, event: InputEvent, _shape: int, area: Area2D) -> void:
	hovered = area
	game.handle_world_input(event, area.get_meta("worker_id"), area.get_meta("entity"))
