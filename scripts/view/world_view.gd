extends Node2D

const Art = preload("res://scripts/view/art.gd")
const WorkerScene = preload("res://scenes/worker.tscn")
const BedScene = preload("res://scenes/bed.tscn")
const BeltArt = preload("res://scripts/view/belt_art.gd")
var game: Node
var initialized := false
var worker_nodes: Dictionary = {}
var building_nodes: Dictionary = {}
var line_nodes: Dictionary = {}
var cargo_nodes: Dictionary = {}
var belt_previews: Array[Node2D] = []
var building_previews: Array[Sprite2D] = []
var line_previews: Array[Node2D] = []
var fog_cells: Dictionary = {}
var order_cells: Dictionary = {}
var cell_updates := 0
var portal: Area2D
var hovered: Area2D
var hover_frame: NinePatchRect
var selection_frame: NinePatchRect
var drag_frame: NinePatchRect
var preview: Sprite2D
var effect_frame: NinePatchRect
var chunks: Dictionary = {}
var chunk_pool: Array[Dictionary] = []
var view_chunks := Rect2i()

func _ready() -> void:
	var tiles := Art.tile_set("res://assets/world/terrain-atlas.svg", 9)
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
	effect_frame = make_frame("EffectRange")
	effect_frame.modulate = Color("#81e0bf")
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
	if not $GroundInput.input_event.is_connected(_on_pick_input.bind($GroundInput)):
		connect_pick($GroundInput, -1, null)
		connect_pick(portal, -1, game.BASE)
	initialized = false
	for index in chunks.keys():
		release_chunk(index)
	view_chunks = Rect2i()
	for layer in [$TerrainBackground, $Blocks, $Fog, $Overlays/Orders]:
		layer.clear()
	for node in worker_nodes.values() + building_nodes.values() + cargo_nodes.values() + line_nodes.values():
		node.free()
	worker_nodes.clear()
	building_nodes.clear()
	line_nodes.clear()
	cargo_nodes.clear()
	fog_cells.clear()
	order_cells.clear()
	portal.position = game.tile_center(game.BASE) + Vector2(0, -4)
	initialized = true
	sync_chunks()
	sync_fog()
	sync_orders()
	sync_dynamic()

func block_changed(p: Vector2i) -> void:
	if not initialized or not chunks.has(game.MapGenerator.chunk_at(p)):
		return
	var chunk: Dictionary = chunks[game.MapGenerator.chunk_at(p)]
	var local: Vector2i = p - game.MapGenerator.chunk_at(p) * game.MapGenerator.CHUNK_SIZE
	if game.terrain[p] == 0:
		chunk.blocks.erase_cell(local)
	else:
		chunk.blocks.set_cell(local, 0, Vector2i(game.terrain[p], 0))
	cell_updates += 1

func make_chunk() -> Dictionary:
	var chunk: Dictionary = {}
	for entry in [["background", $TerrainBackground], ["blocks", $Blocks], ["fog", $Fog], ["orders", $Overlays/Orders]]:
		var layer := TileMapLayer.new()
		layer.tile_set = entry[1].tile_set
		entry[1].add_child(layer)
		chunk[entry[0]] = layer
	var water := Node2D.new()
	$WaterSources.add_child(water)
	chunk.water = water
	return chunk

func release_chunk(index: Vector2i) -> void:
	var chunk: Dictionary = chunks[index]
	for key in ["background", "blocks", "fog", "orders"]:
		chunk[key].clear()
		chunk[key].hide()
	chunk.water.hide()
	var origin: Vector2i = index * game.MapGenerator.CHUNK_SIZE
	for y in game.MapGenerator.CHUNK_SIZE:
		for x in game.MapGenerator.CHUNK_SIZE:
			fog_cells.erase(origin + Vector2i(x, y))
			order_cells.erase(origin + Vector2i(x, y))
	chunk_pool.append(chunk)
	chunks.erase(index)

func refresh_chunk(index: Vector2i) -> void:
	if not initialized or not chunks.has(index):
		return
	var chunk: Dictionary = chunks[index]
	var origin: Vector2i = index * game.MapGenerator.CHUNK_SIZE
	var water_count := 0
	for y in game.MapGenerator.CHUNK_SIZE:
		for x in game.MapGenerator.CHUNK_SIZE:
			var local := Vector2i(x, y)
			var cell := origin + local
			chunk.background.set_cell(local, 0, Vector2i.ZERO)
			var material: int = game.terrain.get(cell, 0)
			if material != 0:
				chunk.blocks.set_cell(local, 0, Vector2i(material, 0))
			else:
				chunk.blocks.erase_cell(local)
			var fog := -1 if game.visible_tiles.has(cell) else (1 if game.explored.has(cell) else 0)
			fog_cells[cell] = fog
			if fog < 0:
				chunk.fog.erase_cell(local)
			else:
				chunk.fog.set_cell(local, 0, Vector2i(fog, 0))
			if game.water_sources.has(cell):
				if water_count == chunk.water.get_child_count():
					var sprite := Sprite2D.new()
					sprite.texture = Art.texture("res://assets/world/water-source.svg")
					chunk.water.add_child(sprite)
				var sprite: Sprite2D = chunk.water.get_child(water_count)
				sprite.position = (Vector2(local) + Vector2.ONE * 0.5) * game.CELL
				sprite.show()
				water_count += 1
	for i in range(water_count, chunk.water.get_child_count()):
		chunk.water.get_child(i).hide()

func sync_chunks() -> void:
	if not initialized:
		return
	var half: Vector2 = get_viewport_rect().size / game.camera.zoom / 2
	var first: Vector2i = game.MapGenerator.chunk_at(game.world_cell(game.camera.position - half)) - Vector2i.ONE
	var last: Vector2i = game.MapGenerator.chunk_at(game.world_cell(game.camera.position + half)) + Vector2i.ONE
	var wanted := Rect2i(first, last - first + Vector2i.ONE)
	$GroundInput/PickShape.shape.size = half * 2 + Vector2.ONE * game.CELL * 4
	$GroundInput/PickShape.position = game.camera.position
	if wanted == view_chunks:
		return
	view_chunks = wanted
	for index in chunks.keys():
		if not wanted.has_point(index):
			release_chunk(index)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var index := Vector2i(x, y)
			if chunks.has(index):
				continue
			chunks[index] = chunk_pool.pop_back() if not chunk_pool.is_empty() else make_chunk()
			for node in chunks[index].values():
				node.position = game.tile_corner(index * game.MapGenerator.CHUNK_SIZE)
				node.show()
			refresh_chunk(index)
	sync_orders()

func reposition() -> void:
	if not initialized:
		return
	for index in chunks:
		for node in chunks[index].values():
			node.position = game.tile_corner(index * game.MapGenerator.CHUNK_SIZE)
	for p in building_nodes:
		building_nodes[p].position = game.tile_corner(p)
	for p in line_nodes:
		line_nodes[p].position = game.tile_corner(p)
	portal.position = game.tile_center(game.BASE) + Vector2(0, -4)

func sync_fog(changed: Dictionary = {}) -> void:
	if not initialized:
		return
	# Only explored cells can change; untouched fog tiles never get resubmitted.
	for p in (game.explored if changed.is_empty() else changed):
		if not fog_cells.has(p):
			continue
		var next := -1 if game.visible_tiles.has(p) else 1
		if fog_cells.get(p, 0) == next:
			continue
		fog_cells[p] = next
		var index: Vector2i = game.MapGenerator.chunk_at(p)
		var layer: TileMapLayer = chunks[index].fog
		var local: Vector2i = p - index * game.MapGenerator.CHUNK_SIZE
		if next == -1:
			layer.erase_cell(local)
		else:
			layer.set_cell(local, 0, Vector2i(next, 0))
		cell_updates += 1

func sync_orders() -> void:
	if not initialized:
		return
	for p in order_cells.keys():
		if not game.jobs.has(p):
			var index: Vector2i = game.MapGenerator.chunk_at(p)
			if chunks.has(index):
				chunks[index].orders.erase_cell(p - index * game.MapGenerator.CHUNK_SIZE)
			order_cells.erase(p)
			cell_updates += 1
	for p in game.jobs:
		var index: Vector2i = game.MapGenerator.chunk_at(p)
		if not order_cells.has(p) and chunks.has(index):
			chunks[index].orders.set_cell(p - index * game.MapGenerator.CHUNK_SIZE, 0, Vector2i.ZERO)
			order_cells[p] = true
			cell_updates += 1

func sync_buildings() -> void:
	var line_positions: Dictionary = game.power_lines.duplicate()
	for p in game.sites:
		if game.sites[p].kind in game.LINE_KINDS:
			line_positions[p] = game.sites[p]
	for p in line_nodes.keys():
		if not line_positions.has(p):
			line_nodes[p].free()
			line_nodes.erase(p)
	var cells := line_cell_map(line_positions)
	var ports := line_port_map() if not line_positions.is_empty() else {}
	for p in line_positions:
		var kind: String = line_positions[p].kind
		if not line_nodes.has(p):
			var node := BedScene.instantiate()
			$Buildings.add_child(node)
			$Buildings.move_child(node, 0)
			node.set_kind(kind)
			node.position = game.tile_corner(p)
			connect_pick(node, -1, p)
			node.set_meta("line", true)
			line_nodes[p] = node
		line_nodes[p].set_size(game.building_size(p, kind))
		line_nodes[p].set_progress(line_positions[p].progress / line_positions[p].seconds if line_positions[p].has("progress") else 1.0)
		line_nodes[p].set_line_connections(line_connection_masks(p, line_positions[p], cells, ports))
		line_nodes[p].input_pickable = game.explored.has(p)
	for p in building_nodes.keys():
		if not game.sites.has(p) and not game.beds.has(p) and not game.benches.has(p) and not game.banks.has(p) and not game.belts.has(p):
			building_nodes[p].free()
			building_nodes.erase(p)
	for p in game.sites.keys() + game.beds.keys() + game.benches.keys() + game.banks.keys() + game.belts.keys():
		var kind: String = game.building_kind(p)
		if kind in game.LINE_KINDS:
			if not game.belts.has(p):
				continue
			kind = game.belts[p].get("kind", "belt")
		if not building_nodes.has(p):
			var bed := BedScene.instantiate()
			bed.name = "Bed_%d_%d" % [p.x, p.y]
			$Buildings.add_child(bed)
			bed.set_kind(kind)
			bed.position = game.tile_corner(p)
			connect_pick(bed, -1, p)
			building_nodes[p] = bed
		var progress: float = game.sites[p].progress / game.sites[p].seconds if game.sites.has(p) and game.sites[p].kind == kind else 1.0
		building_nodes[p].set_progress(progress)
		building_nodes[p].set_size(game.building_size(p, kind))
		building_nodes[p].animate(game.powered_devices.has(p) or game.power_output.get(p, 0.0) > 0, game.animation_time)
		if kind == "barn":
			building_nodes[p].sync_sheep(game.benches.get(p, {}).get("sheep", 0), game.animation_time)
		if kind in game.BELT_KINDS:
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
	sync_chunks()
	sync_buildings()
	sync_belt_cargo()
	for w in game.workers:
		if not worker_nodes.has(w.id):
			var worker := WorkerScene.instantiate()
			worker.name = "Worker_%d" % w.id
			$Characters.add_child(worker)
			worker.configure(w, game.font)
			connect_pick(worker, w.id, null)
			worker_nodes[w.id] = worker
		worker_nodes[w.id].sync(game.worker_display(w), game.animation_time, game.CELL, game.action_for(w) != "等待", game.view_origin)
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
	var p = game.selected_entity
	effect_frame.visible = game.selected_worker < 0 and not game.selected_line and game.building_kind(p) in ["grow_light", "fountain", "drill", "spotlight", "daylight"]
	if effect_frame.visible:
		effect_frame.position = game.tile_corner(p - Vector2i.ONE * game.EFFECT_RADIUS)
		effect_frame.size = Vector2.ONE * (game.EFFECT_RADIUS * 2 + 1) * game.CELL
	selection_frame.visible = true
	if game.selected_worker >= 0:
		var bounds := pick_bounds(worker_nodes[game.selected_worker])
		selection_frame.position = bounds.position
		selection_frame.size = bounds.size
	elif p == game.BASE:
		selection_frame.position = portal.position - Vector2(32, 40)
		selection_frame.size = Vector2(64, 80)
	elif game.selected_line and line_nodes.has(p):
		selection_frame.position = game.tile_corner(p)
		selection_frame.size = game.building_size(p, game.power_lines.get(p, game.sites.get(p, {})).kind)
	elif game.beds.has(p) or game.sites.has(p) or game.benches.has(p) or game.banks.has(p) or game.belts.has(p):
		selection_frame.position = game.tile_corner(p)
		selection_frame.size = game.building_size(p, game.building_kind(p))
	elif game.explored.has(game.selected_tile):
		selection_frame.position = game.tile_corner(game.selected_tile)
		selection_frame.size = Vector2.ONE * game.CELL
	else:
		selection_frame.hide()
	var hover: Vector2i = game.mouse_tile()
	hover_frame.visible = game.explored.has(hover)
	hover_frame.position = game.tile_corner(hover)
	hover_frame.size = Vector2.ONE * game.CELL
	if is_instance_valid(hovered) and hovered != $GroundInput and hovered.input_pickable:
		var bounds := pick_bounds(hovered)
		hover_frame.show()
		hover_frame.position = bounds.position
		hover_frame.size = bounds.size
	if get_viewport().gui_get_hovered_control() != null:
		hover_frame.hide()
		hovered = null
	var preview_kind: String = "drill" if game.tool == "move_drill" else game.tool
	preview.visible = (game.tool == "move_drill" or game.tool in game.BUILDING_KINDS) and game.explored.has(hover) and get_viewport().gui_get_hovered_control() == null
	if preview.visible:
		configure_blueprint(preview, hover, preview_kind)
	preview.modulate = Color(1, 1, 1, 0.5) if game.building_space_valid(hover, preview_kind) else Color(1, 0.4, 0.3, 0.5)
	if game.belt_drawing or game.building_drawing or game.tool in game.BELT_KINDS or game.tool in game.LINE_KINDS:
		preview.hide()
	sync_belt_preview()
	sync_building_preview()
	sync_line_preview()
	drag_frame.visible = game.dragging
	if game.dragging:
		drag_frame.position = game.tile_corner(game.selection_start.min(game.selection_end))
		drag_frame.size = Vector2((game.selection_start - game.selection_end).abs() + Vector2i.ONE) * game.CELL
		drag_frame.modulate = Color("#e39d90") if game.tool == "cancel" else Color("#e3d29d")

func sync_belt_preview() -> void:
	var path: Array[Vector2i] = []
	if game.belt_drawing:
		path.assign(game.belt_path)
	if not game.belt_drawing and game.tool in game.BELT_KINDS and game.explored.has(game.mouse_tile()) and get_viewport().gui_get_hovered_control() == null:
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
	if game.building_drawing and game.tool not in game.LINE_KINDS:
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
			configure_blueprint(sprite, positions[i], game.tool)
			sprite.modulate = Color(0.7, 1, 0.85, 0.8) if valid else Color(1, 0.4, 0.3, 0.8)

func line_cell_map(positions: Dictionary) -> Dictionary:
	var cells := {"high_line": {}, "low_line": {}}
	for p in positions:
		for cell in game.building_cells(p, positions[p].kind):
			if not cells[positions[p].kind].has(cell):
				cells[positions[p].kind][cell] = []
			cells[positions[p].kind][cell].append(p)
	return cells

func line_port_map() -> Dictionary:
	var ports := {"high_line": {}, "low_line": {}}
	for p in game.benches.keys() + game.belts.keys():
		var kind: String = game.building_kind(p)
		if kind == "transformer":
			for wire in game.LINE_KINDS:
				ports[wire][p + Vector2i.LEFT] = ports[wire].get(p + Vector2i.LEFT, 0) | 2
				ports[wire][p + Vector2i.RIGHT * 2] = ports[wire].get(p + Vector2i.RIGHT * 2, 0) | 1
		elif kind in ["power_plant", "manual_generator", "grow_light", "fountain", "drill", "electric_belt", "spotlight", "daylight"]:
			for wire in game.LINE_KINDS:
				for cell in game.building_cells(p, kind):
					for i in game.DIRS.size():
						var neighbor: Vector2i = cell - game.DIRS[i]
						ports[wire][neighbor] = ports[wire].get(neighbor, 0) | (1 << i)
	return ports

func line_connection_masks(p: Vector2i, data: Dictionary, cells: Dictionary, ports: Dictionary) -> Dictionary:
	var connections: Dictionary = {}
	var vertical: bool = data.get("axis", game.building_axis) == Vector2i.DOWN
	var bridge := false
	for cell in game.building_cells(p, data.kind):
		var mask: int = ports[data.kind].get(cell, 0)
		for i in game.DIRS.size():
			var neighbors: Array = cells.high_line.get(cell + game.DIRS[i], []) + cells.low_line.get(cell + game.DIRS[i], [])
			# The two cells of one high-voltage segment are parallel conductors.
			if not neighbors.is_empty() and (neighbors.size() > 1 or neighbors[0] != p):
				mask |= 1 << i
		bridge = bridge or (mask & (3 if vertical else 12)) != 0
		if mask == 0 and data.kind == "high_line":
			mask = 12 if vertical else 3
		connections[cell - p] = mask
	# Side-fed high-voltage segments must visibly join both corridor lanes.
	if data.kind == "high_line" and bridge:
		var across := Vector2i.RIGHT if vertical else Vector2i.DOWN
		for offset in connections:
			if connections.has(offset + across):
				connections[offset] |= 2 if vertical else 8
			if connections.has(offset - across):
				connections[offset] |= 1 if vertical else 4
	return connections

func sync_line_preview() -> void:
	var positions: Array[Vector2i] = []
	if game.tool in game.LINE_KINDS:
		if game.building_drawing:
			positions.assign(game.building_row())
		elif game.explored.has(game.mouse_tile()) and get_viewport().gui_get_hovered_control() == null:
			positions.append(game.mouse_tile())
	var plan: Dictionary = game.power_lines.duplicate()
	for p in game.sites:
		if game.sites[p].kind in game.LINE_KINDS:
			plan[p] = game.sites[p]
	for p in positions:
		if not plan.has(p) or plan[p].kind != game.tool:
			plan[p] = {"kind": game.tool, "axis": game.building_axis}
	var cells := line_cell_map(plan) if not positions.is_empty() else {}
	var ports := line_port_map() if not positions.is_empty() else {}
	var affected: Array = positions.duplicate()
	for p in positions:
		for cell in game.building_cells(p, game.tool):
			for direction in [Vector2i.ZERO] + game.DIRS:
				for neighbor in cells[game.tool].get(cell + direction, []):
					if neighbor not in affected:
						affected.append(neighbor)
	var index := 0
	var valid: bool = game.building_batch_valid(positions, game.tool) if not positions.is_empty() else false
	for p in affected:
		var masks := line_connection_masks(p, plan[p], cells, ports)
		for offset in masks:
			if index == line_previews.size():
				var art := BeltArt.new(plan[p].kind)
				$Overlays.add_child(art)
				line_previews.append(art)
			var art := line_previews[index]
			art.set_line_kind(plan[p].kind)
			art.position = game.tile_center(p + offset)
			art.configure(masks[offset], Vector2i.ZERO, 0.0)
			art.modulate = Color(0.7, 1, 0.85, 0.8) if valid else Color(1, 0.4, 0.3, 0.8)
			art.show()
			index += 1
	for i in range(index, line_previews.size()):
		line_previews[i].hide()

func configure_blueprint(sprite: Sprite2D, p: Vector2i, kind: String) -> void:
	sprite.texture = Art.texture("res://assets/icons/%s-blueprint.svg" % kind)
	var size: Vector2 = game.building_size(p, kind)
	var vertical := kind == "high_line" and size.x > size.y
	sprite.centered = false
	sprite.rotation = PI / 2 if vertical else 0.0
	sprite.scale = (Vector2(size.y, size.x) if vertical else size) / sprite.texture.get_size()
	sprite.position = game.tile_corner(p) + (Vector2(size.x, 0) if vertical else Vector2.ZERO)

func pick_bounds(area: Area2D) -> Rect2:
	var shape: CollisionShape2D = area.get_node("PickShape")
	return shape.global_transform * shape.shape.get_rect()

func connect_pick(area: Area2D, worker_id: int, entity) -> void:
	area.set_meta("worker_id", worker_id)
	# Null metadata removes the key, so the handler supplies the absent-entity default.
	if entity != null:
		area.set_meta("entity", entity)
	area.input_event.connect(_on_pick_input.bind(area))
	area.mouse_entered.connect(func(): hovered = area)
	area.mouse_exited.connect(func():
		if hovered == area:
			hovered = null)

func _on_pick_input(_viewport: Node, event: InputEvent, _shape: int, area: Area2D) -> void:
	hovered = area
	game.handle_world_input(event, area.get_meta("worker_id"), area.get_meta("entity") if area.has_meta("entity") else null, area.get_meta("line", false))
