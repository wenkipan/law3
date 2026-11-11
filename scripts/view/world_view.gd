extends Node2D

const Art = preload("res://scripts/view/art.gd")
const WorkerScene = preload("res://scenes/worker.tscn")
const BedScene = preload("res://scenes/bed.tscn")
const ItemScene = preload("res://scenes/item.tscn")
const BeltArt = preload("res://scripts/view/belt_art.gd")
const BarrierArt = preload("res://scripts/view/barrier_art.gd")
const RateSelector = preload("res://scripts/view/rate_selector.gd")
var game: Node
var camera := Camera2D.new()
var initialized := false
var worker_nodes: Dictionary = {}
var building_nodes: Dictionary = {}
var line_nodes: Dictionary = {}
var cargo_nodes: Dictionary = {}
var belt_previews: Array[Node2D] = []
var building_previews: Array[Sprite2D] = []
var barrier_previews: Array[Node2D] = []
var line_previews: Array[Node2D] = []
var fog_cells: Dictionary = {}
var order_cells: Dictionary = {}
var pollution_cells: Dictionary = {}
var pollution_revision := -1
var cell_updates := 0
var hovered: Area2D
var hover_frame: NinePatchRect
var selection_frame: NinePatchRect
var drag_frame: NinePatchRect
var preview: Sprite2D
var effect_frame: NinePatchRect
var chunks: Dictionary = {}
var chunk_pool: Array[Dictionary] = []
var view_chunks := Rect2i()
var alert_frames: Array[NinePatchRect] = []
var alert_targets: Array = []
var alert_fade := 0.0
var wage_labels: Dictionary = {}
var item_nodes: Dictionary = {}

func pointer_texture() -> Texture2D:
	if not initialized or game == null: return null
	var tool: String = game.interaction.tool
	if tool in ["cancel", "demolish", "wage", "fee"]:
		return Art.texture("res://assets/icons/%s.svg" % tool)
	if tool != "dig" or not is_instance_valid(hovered) or not hovered.input_pickable or hovered.get_meta("worker_id", -1) >= 0 or not game.cache.visible_tiles.has(game.mouse_tile()):
		return null
	var p = hovered.get_meta("entity", game.mouse_tile())
	var kind: String = game.building_kind(p)
	if item_nodes.get(p) == hovered:
		return Art.texture("res://assets/cursors/hand.svg")
	elif game.world.has_building(p, "site"):
		return null if game.world.building_state(p, "site").get("cancelled", false) else Art.texture("res://assets/icons/tools.svg")
	elif game.has_job(kind):
		var icon := "pickaxe" if kind in ["mine", "drill"] else "tools"
		return Art.texture("res://assets/icons/%s.svg" % icon)
	elif hovered == $GroundInput:
		if game.world.wild_resources.get(p, {}).get("stock", 0) > 0:
			return Art.texture("res://assets/cursors/hand.svg")
		elif game.world.deposits.get(p, 0) > 0 and game.world.terrain.get(p, 0) in game.SmartObjectDefinitions.MINERALS:
			return Art.texture("res://assets/icons/pickaxe.svg")
	return null

func _process(delta: float) -> void:
	delta /= Engine.time_scale
	if alert_fade <= 0: return
	alert_fade = maxf(0, alert_fade - delta)
	sync_alert_highlights()

func flash_alert_targets(targets: Array) -> void:
	alert_targets = targets.duplicate()
	alert_fade = 2.0
	while alert_frames.size() < targets.size():
		alert_frames.append(make_frame("AlertHighlight"))
	sync_alert_highlights()

func sync_alert_highlights() -> void:
	for i in alert_frames.size():
		var frame := alert_frames[i]
		frame.hide()
		if i >= alert_targets.size() or alert_fade <= 0 or not initialized: continue
		var target: Dictionary = alert_targets[i]
		var bounds: Rect2
		if target.has("worker"):
			if not worker_nodes.has(target.worker): continue
			var w: Dictionary = game.world.worker(target.worker)
			if w.is_empty(): continue
			if not game.cache.visible_tiles.has(Vector2i(w.pos.round())): continue
			bounds = pick_bounds(worker_nodes[target.worker])
		else:
			var p: Vector2i = target.entity
			if not game.cache.visible_tiles.has(p): continue
			var kind: String = game.building_kind(p)
			if kind.is_empty(): continue
			bounds = Rect2(game.tile_corner(p), game.building_size(p, kind))
		frame.position = bounds.position - Vector2.ONE * 3
		frame.size = bounds.size + Vector2.ONE * 6
		frame.modulate = Color(1.0, 0.77, 0.3, alert_fade / 2.0)
		frame.show()

func _ready() -> void:
	add_child(camera)
	var tiles := Art.tile_set("res://assets/world/terrain-atlas.svg", 10)
	$TerrainBackground.tile_set = tiles
	$Blocks.tile_set = Art.tile_set("res://assets/world/surface-resources.svg", 10)
	$Fog.tile_set = Art.tile_set("res://assets/world/fog-atlas.svg", 1)
	$Overlays/Orders.tile_set = Art.tile_set("res://assets/world/order.svg", 1)
	$Pollution.tile_set = Art.tile_set("res://assets/world/pollution-atlas.svg", 11)
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
	for label in wage_labels.values(): label.free()
	wage_labels.clear()
	alert_targets.clear()
	alert_fade = 0.0
	for frame in alert_frames: frame.hide()
	$Overlays/WorkerFeedback.rebuild(game)
	if not game.transaction_completed.is_connected(on_transaction):
		game.transaction_completed.connect(on_transaction)
	hovered = null
	if not $GroundInput.input_event.is_connected(_on_pick_input.bind($GroundInput)):
		connect_pick($GroundInput, -1, null)
	initialized = false
	for index in chunks.keys():
		release_chunk(index)
	view_chunks = Rect2i()
	for layer in [$TerrainBackground, $Blocks, $Fog, $Pollution, $Overlays/Orders]:
		layer.clear()
	for node in worker_nodes.values() + building_nodes.values() + cargo_nodes.values() + line_nodes.values() + item_nodes.values():
		node.free()
	worker_nodes.clear()
	building_nodes.clear()
	line_nodes.clear()
	item_nodes.clear()
	cargo_nodes.clear()
	fog_cells.clear()
	order_cells.clear()
	pollution_cells.clear()
	pollution_revision = -1
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
	if game.world.terrain[p] == 0:
		chunk.blocks.erase_cell(local)
	else:
		chunk.blocks.set_cell(local, 0, Vector2i(game.world.terrain[p], 0))
	for sprite in chunk.water.get_children():
		if sprite.get_meta("cell", null) == p and game.world.wild_resources.has(p):
			sprite.visible = game.world.wild_resources[p].stock > 0
	cell_updates += 1

func make_chunk() -> Dictionary:
	var chunk: Dictionary = {}
	for entry in [["background", $TerrainBackground], ["blocks", $Blocks], ["fog", $Fog], ["pollution", $Pollution], ["orders", $Overlays/Orders]]:
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
	for key in ["background", "blocks", "fog", "pollution", "orders"]:
		chunk[key].clear()
		chunk[key].hide()
	chunk.water.hide()
	var origin: Vector2i = index * game.MapGenerator.CHUNK_SIZE
	for y in game.MapGenerator.CHUNK_SIZE:
		for x in game.MapGenerator.CHUNK_SIZE:
			fog_cells.erase(origin + Vector2i(x, y))
			order_cells.erase(origin + Vector2i(x, y))
			pollution_cells.erase(origin + Vector2i(x, y))
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
			pollution_cells.erase(cell)
			chunk.background.set_cell(local, 0, Vector2i.ZERO)
			var material: int = game.world.terrain.get(cell, 0)
			if material != 0:
				chunk.blocks.set_cell(local, 0, Vector2i(material, 0))
			else:
				chunk.blocks.erase_cell(local)
			var fog := -1 if game.cache.visible_tiles.has(cell) else 0
			fog_cells[cell] = fog
			if fog < 0:
				chunk.fog.erase_cell(local)
			else:
				chunk.fog.set_cell(local, 0, Vector2i(fog, 0))
			if game.world.water_sources.has(cell) or game.world.wild_resources.get(cell, {}).get("stock", 0) > 0:
				if water_count == chunk.water.get_child_count():
					var sprite := Sprite2D.new()
					chunk.water.add_child(sprite)
				var sprite: Sprite2D = chunk.water.get_child(water_count)
				sprite.set_meta("cell", cell)
				sprite.modulate = Color.WHITE
				if game.world.water_sources.has(cell):
					sprite.texture = Art.texture("res://assets/world/water-source.svg")
				else:
					var resource: Dictionary = game.world.wild_resources[cell]
					sprite.texture = Art.texture("res://assets/world/%s.svg" % {"berries": "wild-berries", "wheat": "wild-grain", "meat": "wild-animal"}[resource.item])
				sprite.position = (Vector2(local) + Vector2.ONE * 0.5) * game.CELL
				sprite.show()
				water_count += 1
	for i in range(water_count, chunk.water.get_child_count()):
		chunk.water.get_child(i).hide()
	pollution_revision = -1

func sync_pollution() -> void:
	$Pollution.visible = game.interaction.pollution_visible
	if not game.interaction.pollution_visible: return
	if pollution_revision == game.cache.pollution.revision: return
	pollution_revision = game.cache.pollution.revision
	for p in game.cache.visible_tiles:
		var index: Vector2i = game.MapGenerator.chunk_at(p)
		if not chunks.has(index): continue
		var band := clampi(ceili(game.cache.pollution.at(p) / 10.0), 0, 10)
		if pollution_cells.get(p, -1) == band: continue
		pollution_cells[p] = band
		chunks[index].pollution.set_cell(p - index * game.MapGenerator.CHUNK_SIZE, 0, Vector2i(band, 0))

func sync_chunks() -> void:
	if not initialized:
		return
	var half: Vector2 = get_viewport_rect().size / camera.zoom / 2
	var first: Vector2i = game.MapGenerator.chunk_at(game.world_cell(camera.position - half)) - Vector2i.ONE
	var last: Vector2i = game.MapGenerator.chunk_at(game.world_cell(camera.position + half)) + Vector2i.ONE
	var wanted := Rect2i(first, last - first + Vector2i.ONE)
	$GroundInput/PickShape.shape.size = half * 2 + Vector2.ONE * game.CELL * 4
	$GroundInput/PickShape.position = camera.position
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
	for id in building_nodes:
		if game.world.buildings.has(id): building_nodes[id].position = game.tile_corner(game.world.building_map.origin(id))
	for id in line_nodes:
		if game.world.buildings.has(id): line_nodes[id].position = game.tile_corner(game.world.building_map.origin(id))

func sync_fog(changed: Dictionary = {}) -> void:
	if not initialized:
		return
	# Update lost sight as well as gained sight, without resubmitting unchanged cells.
	for p in (fog_cells if changed.is_empty() else changed):
		if not fog_cells.has(p):
			continue
		var next := -1 if game.cache.visible_tiles.has(p) else 0
		if fog_cells.get(p, 0) == next:
			continue
		pollution_revision = -1
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
		if not game.world.mining_contracts.has(p):
			var index: Vector2i = game.MapGenerator.chunk_at(p)
			if chunks.has(index):
				chunks[index].orders.erase_cell(p - index * game.MapGenerator.CHUNK_SIZE)
			order_cells.erase(p)
			cell_updates += 1

func sync_buildings() -> void:
	var barriers: Dictionary = {}
	for p in game.world.building_positions("station"):
		if game.world.building_state(p, "station").kind in game.BARRIER_KINDS: barriers[p] = true
	for p in game.world.building_positions("site"):
		if game.world.building_state(p, "site").kind in game.BARRIER_KINDS and not game.world.building_state(p, "site").get("cancelled", false): barriers[p] = true
	var open_doors: Dictionary = {}
	for w in game.world.workers:
		var cell := Vector2i(w.pos.round())
		for offset in [Vector2i.ZERO] + game.DIRS:
			if barriers.has(cell + offset): open_doors[cell + offset] = true
	var line_positions: Dictionary = {}
	for entity in game.world.buildings_in("line"):
		line_positions[game.world.building_map.origin(entity.id)] = entity.state
	for p in game.world.building_positions("site"):
		if game.world.building_state(p, "site").kind in game.LINE_KINDS:
			line_positions[p] = game.world.building_state(p, "site")
	for id in line_nodes.keys():
		if not game.world.buildings.has(id):
			if hovered == line_nodes[id]: hovered = null
			line_nodes[id].free()
			line_nodes.erase(id)
	var cells := line_cell_map(line_positions)
	var ports := line_port_map() if not line_positions.is_empty() else {}
	for p in line_positions:
		var kind: String = line_positions[p].kind
		var entity = game.world.building_at(p, "site") if game.world.building_state(p, "site").get("kind", "") in game.LINE_KINDS else game.world.building_at(p, "line")
		var id: int = entity.id
		if not line_nodes.has(id):
			var node := BedScene.instantiate()
			$Buildings.add_child(node)
			$Buildings.move_child(node, 0)
			node.set_kind(kind)
			node.position = game.tile_corner(p)
			connect_pick(node, -1, p)
			node.set_meta("building_id", id)
			node.set_meta("line", true)
			line_nodes[id] = node
		line_nodes[id].set_size(game.building_size(p, kind))
		line_nodes[id].set_progress(line_positions[p].progress / line_positions[p].seconds if line_positions[p].has("progress") else 1.0)
		line_nodes[id].set_line_connections(line_connection_masks(p, line_positions[p], cells, ports))
		sync_shortages(line_nodes[id], p)
		line_nodes[id].input_pickable = game.cache.visible_tiles.has(p)
	for id in building_nodes.keys():
		if not game.world.buildings.has(id):
			if hovered == building_nodes[id]: hovered = null
			building_nodes[id].free()
			building_nodes.erase(id)
	for entity in game.world.buildings.values():
		var kind: String = entity.kind
		if kind in game.LINE_KINDS: continue
		var id: int = entity.id
		var p: Vector2i = game.world.building_map.origin(id)
		if not building_nodes.has(id):
			var bed := BedScene.instantiate()
			bed.name = "Bed_%d_%d" % [p.x, p.y]
			$Buildings.add_child(bed)
			bed.set_kind(kind)
			bed.position = game.tile_corner(p)
			connect_pick(bed, -1, p)
			bed.set_meta("building_id", id)
			building_nodes[id] = bed
		var progress: float = entity.state.progress / entity.state.seconds if entity.in_group("site") else 1.0
		var node: Area2D = building_nodes[id]
		node.position = game.tile_corner(p)
		node.set_meta("entity", p)
		node.set_progress(progress)
		node.set_size(game.building_size(p, kind))
		sync_shortages(node, p)
		node.set_operating(game.cache.powered_devices.has(p) or game.cache.power_output.get(p, 0.0) > 0)
		if kind == "barn":
			node.sync_sheep(entity.state.get("sheep", 0))
		if kind in game.BELT_KINDS:
			node.set_belt_connections(game.belt_connections(p), game.belt_direction_at(p))
		if kind in game.BARRIER_KINDS:
			var mask := 0
			for i in game.DIRS.size():
				if barriers.has(p + game.DIRS[i]): mask |= 1 << i
			node.set_barrier_connections(mask, open_doors.has(p))
		node.input_pickable = game.cache.visible_tiles.has(p)

func sync_shortages(node: Area2D, p: Vector2i) -> void:
	var amounts: Dictionary = {}
	var items: Array = []
	if game.cache.visible_tiles.has(p):
		if game.world.has_building(p, "site"):
			amounts = game.alerts.blueprint_shortages(game, p)
			items = amounts.keys()
			if items.is_empty() and not game.world.building_state(p, "site").get("cancelled", false):
				items = ["tools"]
		else:
			items = game.alerts.production_shortages(game, p)
	node.set_shortages(items, amounts)
	node.position_shortage(camera.zoom.x)

func sync_belt_cargo() -> void:
	for id in cargo_nodes.keys():
		if not game.world.belt_cargo.has(id):
			cargo_nodes[id].free()
			cargo_nodes.erase(id)
	for id in game.world.belt_cargo:
		var cargo: Dictionary = game.world.belt_cargo[id]
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
	sync_pollution()
	sync_buildings()
	sync_belt_cargo()
	sync_loose_items()
	for id in worker_nodes.keys():
		if not game.world.worker(id).is_empty(): continue
		var node: Area2D = worker_nodes[id]
		if hovered == node:
			hovered = null
			hover_frame.hide()
		$Characters.remove_child(node)
		node.queue_free()
		worker_nodes.erase(id)
	for w in game.world.workers:
		$Overlays/WorkerFeedback.observe_effects(w)
		if not worker_nodes.has(w.id):
			var worker := WorkerScene.instantiate()
			worker.name = "Worker_%d" % w.id
			$Characters.add_child(worker)
			worker.configure(w, game.hud.font)
			connect_pick(worker, w.id, null)
			worker_nodes[w.id] = worker
		worker_nodes[w.id].sync(game.worker_display(w), game.CELL, game.action_for(w) != "等待", game.interaction.view_origin)
		var visible_now: bool = game.cache.visible_tiles.has(Vector2i(w.pos.round()))
		worker_nodes[w.id].visible = visible_now
		worker_nodes[w.id].input_pickable = visible_now
		if not visible_now: worker_nodes[w.id].cancel_transaction()
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
	var p = game.interaction.selected_entity
	effect_frame.visible = game.interaction.selected_worker < 0 and not game.interaction.selected_line and game.building_kind(p) in ["grow_light", "fountain", "drill", "spotlight", "daylight"]
	if effect_frame.visible:
		effect_frame.position = game.tile_corner(p - Vector2i.ONE * game.EFFECT_RADIUS)
		effect_frame.size = Vector2.ONE * (game.EFFECT_RADIUS * 2 + 1) * game.CELL
	selection_frame.visible = true
	if game.interaction.selected_worker >= 0:
		var bounds := pick_bounds(worker_nodes[game.interaction.selected_worker])
		selection_frame.position = bounds.position
		selection_frame.size = bounds.size
	elif game.interaction.selected_line and game.world.has_building(p, "line"):
		selection_frame.position = game.tile_corner(p)
		selection_frame.size = game.building_size(p, game.world.building_state(p, "line", game.world.building_state(p, "site", {})).kind)
	elif game.world.has_building(p, "bed") or game.world.has_building(p, "site") or game.world.has_building(p, "station") or game.world.has_building(p, "bank") or game.world.has_building(p, "belt"):
		selection_frame.position = game.tile_corner(p)
		selection_frame.size = game.building_size(p, game.building_kind(p))
	elif game.cache.visible_tiles.has(game.interaction.selected_tile):
		selection_frame.position = game.tile_corner(game.interaction.selected_tile)
		selection_frame.size = Vector2.ONE * game.CELL
	else:
		selection_frame.hide()
	var hover: Vector2i = game.mouse_tile()
	hover_frame.visible = game.cache.visible_tiles.has(hover)
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
	var preview_kind: String = "drill" if game.interaction.tool == "move_drill" else game.interaction.tool
	preview.visible = (game.interaction.tool == "move_drill" or game.interaction.tool in game.BUILDING_KINDS) and game.cache.visible_tiles.has(hover) and get_viewport().gui_get_hovered_control() == null
	if preview.visible:
		configure_blueprint(preview, hover, preview_kind)
	preview.modulate = Color(1, 1, 1, 0.5) if game.building_space_valid(hover, preview_kind) else Color(1, 0.4, 0.3, 0.5)
	if game.interaction.belt_drawing or game.interaction.building_drawing or game.interaction.tool in game.BELT_KINDS or game.interaction.tool in game.LINE_KINDS or game.interaction.tool in game.BARRIER_KINDS:
		preview.hide()
	sync_belt_preview()
	sync_building_preview()
	sync_barrier_preview()
	sync_line_preview()
	sync_wages()
	drag_frame.visible = game.interaction.dragging
	if game.interaction.dragging:
		drag_frame.position = game.tile_corner(game.interaction.selection_start.min(game.interaction.selection_end))
		drag_frame.size = Vector2((game.interaction.selection_start - game.interaction.selection_end).abs() + Vector2i.ONE) * game.CELL
		var value: float = game.interaction.brush_fee if game.interaction.tool == "fee" else game.interaction.brush_wage
		drag_frame.modulate = RateSelector.color_for(int(value)) if game.interaction.tool in ["wage", "fee"] else (Color("#e39d90") if game.interaction.tool in ["cancel", "demolish"] else Color("#e3d29d"))

func sync_loose_items() -> void:
	var present: Dictionary = {}
	for p in game.world.ground_items:
		if not game.building_kind_at(p).is_empty(): continue
		var item = game.first_loose_item(p)
		if item == null: continue
		present[p] = true
		if not item_nodes.has(p):
			var node := ItemScene.instantiate()
			$Buildings.add_child(node)
			connect_pick(node, -1, p)
			item_nodes[p] = node
		var node: Area2D = item_nodes[p]
		var sprite: Sprite2D = node.get_node("Sprite")
		sprite.texture = Art.item_texture(item)
		sprite.scale = Vector2.ONE * 26.0 / sprite.texture.get_width()
		node.position = game.tile_center(p)
		node.visible = game.cache.visible_tiles.has(p)
		node.input_pickable = node.visible
	for p in item_nodes.keys():
		if present.has(p): continue
		if hovered == item_nodes[p]: hovered = null
		item_nodes[p].free()
		item_nodes.erase(p)

func on_transaction(worker_id: int, item, buying: bool) -> void:
	if not initialized or not worker_nodes.has(worker_id): return
	var w: Dictionary = game.world.worker(worker_id)
	if w.is_empty() or not game.cache.visible_tiles.has(Vector2i(w.pos.round())): return
	worker_nodes[worker_id].show_transaction(item, buying)

func sync_wages() -> void:
	$Overlays/Wages.visible = game.interaction.tool in ["wage", "fee"]
	if not $Overlays/Wages.visible: return
	var active: Dictionary = {}
	var screen := get_viewport_rect().grow(48)
	var fees: bool = game.interaction.tool == "fee"
	var targets: Array = game.fee_targets() if fees else game.wage_targets()
	for target in targets:
		var p: Vector2i = target.position
		var key := "%s:%s:%s" % [game.interaction.tool, target.kind, p]
		var extent: Vector2 = game.building_size(p, game.building_kind(p))
		var bottom: Vector2 = game.tile_corner(p) + Vector2(extent.x * 0.5, extent.y)
		if not game.cache.visible_tiles.has(p) or not screen.has_point(get_global_transform_with_canvas() * bottom): continue
		active[key] = true
		if not wage_labels.has(key):
			var label := Label.new()
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_override("font", game.hud.font)
			label.add_theme_font_size_override("font_size", 18)
			label.add_theme_color_override("font_outline_color", Color("#172126"))
			label.add_theme_constant_override("outline_size", 5)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.size = Vector2(24, 24)
			$Overlays/Wages.add_child(label)
			wage_labels[key] = label
		var label: Label = wage_labels[key]
		var value: int = target.settings.get("fee", game.default_fee(game.building_kind(p))) if fees else target.settings.get("wage", game.WAGE_PER_HOUR)
		label.text = str(value)
		label.add_theme_color_override("font_color", RateSelector.color_for(value))
		label.scale = Vector2.ONE / maxf(0.8, camera.zoom.x)
		label.position = bottom - Vector2(label.size.x * label.scale.x * 0.5, label.size.y * label.scale.y + 2)
	for key in wage_labels.keys():
		if not active.has(key):
			wage_labels[key].free()
			wage_labels.erase(key)

func sync_belt_preview() -> void:
	var path: Array[Vector2i] = []
	if game.interaction.belt_drawing:
		path.assign(game.interaction.belt_path)
	if not game.interaction.belt_drawing and game.interaction.tool in game.BELT_KINDS and game.cache.visible_tiles.has(game.mouse_tile()) and get_viewport().gui_get_hovered_control() == null:
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
	var valid: bool = game.belt_plan_valid(path, game.interaction.tool)
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
	if game.interaction.building_drawing and game.interaction.tool not in game.LINE_KINDS and game.interaction.tool not in game.BARRIER_KINDS:
		positions.assign(game.building_row())
	while building_previews.size() < positions.size():
		var sprite := Sprite2D.new()
		sprite.centered = false
		$Overlays.add_child(sprite)
		building_previews.append(sprite)
	var valid: bool = game.building_batch_valid(positions, game.interaction.tool) if game.interaction.building_drawing else false
	for i in building_previews.size():
		var sprite := building_previews[i]
		sprite.visible = i < positions.size()
		if sprite.visible:
			configure_blueprint(sprite, positions[i], game.interaction.tool)
			sprite.modulate = Color(0.7, 1, 0.85, 0.8) if valid else Color(1, 0.4, 0.3, 0.8)

func sync_barrier_preview() -> void:
	var positions: Array[Vector2i] = []
	var kind: String = game.interaction.tool
	if kind in game.BARRIER_KINDS:
		if game.interaction.building_drawing:
			positions.assign(game.building_row())
		elif game.cache.visible_tiles.has(game.mouse_tile()) and get_viewport().gui_get_hovered_control() == null:
			positions.append(game.mouse_tile())
	var joined: Dictionary = {}
	for p in game.world.building_positions("station") + game.world.building_positions("site"):
		if game.building_kind(p) in game.BARRIER_KINDS and not game.world.building_state(p, "site", {}).get("cancelled", false): joined[p] = true
	for p in positions: joined[p] = true
	var valid: bool = game.building_batch_valid(positions, kind) and game.can_plan_building(kind) if not positions.is_empty() else false
	for i in positions.size():
		if i < barrier_previews.size() and barrier_previews[i].kind != kind:
			barrier_previews[i].free()
			barrier_previews[i] = BarrierArt.new(kind)
			$Overlays.add_child(barrier_previews[i])
		if i == barrier_previews.size():
			var art := BarrierArt.new(kind)
			$Overlays.add_child(art)
			barrier_previews.append(art)
		var mask := 0
		for direction in game.DIRS.size():
			if joined.has(positions[i] + game.DIRS[direction]): mask |= 1 << direction
		var art := barrier_previews[i]
		art.position = game.tile_center(positions[i])
		art.configure(mask, 0.0)
		art.modulate = Color(0.7, 1, 0.85, 0.8) if valid else Color(1, 0.4, 0.3, 0.8)
		art.show()
	for i in range(positions.size(), barrier_previews.size()): barrier_previews[i].hide()

func line_cell_map(positions: Dictionary) -> Dictionary:
	var cells := {"high_line": {}, "low_line": {}}
	for p in positions:
		for cell in game.building_cells(p, positions[p].kind, positions[p].get("axis", Vector2i.RIGHT)):
			if not cells[positions[p].kind].has(cell):
				cells[positions[p].kind][cell] = []
			cells[positions[p].kind][cell].append(p)
	return cells

func line_port_map() -> Dictionary:
	var ports := {"high_line": {}, "low_line": {}}
	for p in game.world.building_positions("station") + game.world.building_positions("belt"):
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
	var vertical: bool = data.get("axis", Vector2i.RIGHT) == Vector2i.DOWN
	var bridge := false
	for cell in game.building_cells(p, data.kind, data.get("axis", Vector2i.RIGHT)):
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
	if game.interaction.tool in game.LINE_KINDS:
		if game.interaction.building_drawing:
			positions.assign(game.building_row())
		elif game.cache.visible_tiles.has(game.mouse_tile()) and get_viewport().gui_get_hovered_control() == null:
			positions.append(game.mouse_tile())
	var plan: Dictionary = {}
	for entity in game.world.buildings_in("line"):
		plan[game.world.building_map.origin(entity.id)] = entity.state
	for p in game.world.building_positions("site"):
		if game.world.building_state(p, "site").kind in game.LINE_KINDS:
			plan[p] = game.world.building_state(p, "site")
	for p in positions:
		if not plan.has(p) or plan[p].kind != game.interaction.tool:
			plan[p] = {"kind": game.interaction.tool, "axis": game.interaction.building_axis}
	var cells := line_cell_map(plan) if not positions.is_empty() else {}
	var ports := line_port_map() if not positions.is_empty() else {}
	var affected: Array = positions.duplicate()
	for p in positions:
		for cell in game.building_cells(p, game.interaction.tool, game.interaction.building_axis):
			for direction in [Vector2i.ZERO] + game.DIRS:
				for neighbor in cells[game.interaction.tool].get(cell + direction, []):
					if neighbor not in affected:
						affected.append(neighbor)
	var index := 0
	var valid: bool = game.building_batch_valid(positions, game.interaction.tool, game.interaction.building_axis) if not positions.is_empty() else false
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
	sprite.texture = Art.building_texture(kind, true)
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
	var entity = area.get_meta("entity") if area.has_meta("entity") else null
	if area.has_meta("building_id"):
		var id: int = area.get_meta("building_id")
		if not game.world.buildings.has(id): return
		entity = game.world.building_map.origin(id)
	game.handle_world_input(event, area.get_meta("worker_id"), entity, area.get_meta("line", false))
