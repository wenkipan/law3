extends Node2D

const Art = preload("res://scripts/view/art.gd")
const InspectorIcons = preload("res://scripts/view/inspector_icons.gd")
const LIFETIME := 2.4
const MERGE_SECONDS := 0.5
const POOL_SIZE := 32
const WORKER_LIMIT := 3
var game: Node
var rows: Array[FeedbackRow] = []
var known_effects: Dictionary = {}

class FeedbackRow extends Control:
	var icon := TextureRect.new()
	var label := Label.new()
	var worker := -1
	var kind := ""
	var item := ""
	var effect := ""
	var amount := 0.0
	var motion: Tween
	var rise := 0.0
	var age: float:
		get: return motion.get_total_elapsed_time() if motion != null else 0.0
	var last_event := 0.0

	func configure(font: Font) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(224, 28)
		icon.position = Vector2(0, 2)
		icon.size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
		label.position = Vector2(28, 0)
		label.size = Vector2(196, 28)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_outline_color", Color("#172021"))
		label.add_theme_constant_override("outline_size", 5)
		add_child(label)
		hide()

	func dismiss() -> void:
		if motion != null:
			motion.kill()
			motion = null
		hide()

	func start() -> void:
		dismiss()
		rise = 0.0
		modulate = Color.WHITE
		show()
		motion = create_tween().set_ignore_time_scale(true).set_parallel(true)
		motion.tween_property(self, "rise", 12.0, 1.0)
		motion.tween_property(self, "modulate:a", 0.0, 0.45).set_delay(LIFETIME - 0.45)
		motion.chain().tween_callback(hide)

func rebuild(controller: Node) -> void:
	game = controller
	if not game.personal_item_event.is_connected(on_item_event):
		game.personal_item_event.connect(on_item_event)
	if rows.is_empty():
		for i in POOL_SIZE:
			var row := FeedbackRow.new()
			row.configure(game.hud.font)
			add_child(row)
			rows.append(row)
	for row in rows:
		row.dismiss()
	known_effects.clear()

func forget_effects(worker_id: int) -> void:
	known_effects.erase(worker_id)

func effect_keys(w: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for effect in w.buffs.display_effects(game, w):
		result[effect.id + ":" + effect.name] = effect
	return result

func observe_effects(w: Dictionary) -> void:
	var current := effect_keys(w)
	if known_effects.has(w.id):
		for key in current:
			if not known_effects[w.id].has(key):
				on_effect(w.id, current[key])
	known_effects[w.id] = current

func can_show(worker_id: int) -> bool:
	if not is_instance_valid(game) or not game.world_view.initialized or game.world.worker(worker_id).is_empty():
		return false
	var w: Dictionary = game.world.worker(worker_id)
	if not game.cache.visible_tiles.has(Vector2i(w.pos.round())):
		return false
	var point: Vector2 = get_global_transform_with_canvas() * game.tile_center(w.pos)
	return get_viewport_rect().grow(-32).has_point(point)

func on_item_event(worker_id: int, kind: String, item: String, amount: float) -> void:
	if amount <= 0.000001 or not can_show(worker_id):
		return
	var row := find_recent(worker_id, kind, item)
	if row == null:
		row = claim_row(worker_id)
		row.kind = kind
		row.item = item
		row.icon.texture = Art.item_texture(item)
	row.amount += amount
	row.last_event = row.age
	refresh_text(row)

func on_effect(worker_id: int, effect: Dictionary) -> void:
	if not can_show(worker_id):
		return
	var item: String = effect.get("item", "")
	var row := find_recent(worker_id, "use", item) if item != "" else null
	if row == null:
		row = claim_row(worker_id)
		row.kind = "effect"
		row.item = item
		row.icon.texture = Art.item_texture(item) if item != "" else Art.texture("res://assets/icons/%s.svg" % effect.icon)
	row.effect = "生效" if effect.id in ["gun", "backpack", "clothes", "tools", "hydrated"] else effect.name
	row.label.modulate = Color("#edb7a6") if effect.id == "pollution" or effect.get("icon", "") == "mood-low" else (Color("#dbcfab") if effect.id == "loan" else Color("#b8e2ed"))
	if row.kind == "effect":
		row.label.text = effect.name + " · 生效"
	else:
		refresh_text(row)

func find_recent(worker_id: int, kind: String, item: String) -> FeedbackRow:
	for row in rows:
		if row.visible and row.worker == worker_id and row.kind == kind and row.item == item and row.age - row.last_event <= MERGE_SECONDS:
			return row
	return null

func claim_row(worker_id: int) -> FeedbackRow:
	var available: FeedbackRow
	var oldest: FeedbackRow
	var owned := 0
	for row in rows:
		if not row.visible:
			available = row
		elif row.worker == worker_id:
			owned += 1
			if oldest == null or row.age > oldest.age:
				oldest = row
	if owned >= WORKER_LIMIT:
		available = oldest
	if available == null:
		available = rows[0]
		for row in rows:
			if row.age > available.age:
				available = row
	available.worker = worker_id
	available.kind = ""
	available.item = ""
	available.effect = ""
	available.amount = 0
	available.last_event = 0
	available.label.modulate = Color("#bde8b4")
	available.start()
	return available

func refresh_text(row: FeedbackRow) -> void:
	var title: String = game.item_name(row.item)
	if row.kind in ["gain", "borrow"]:
		row.label.text = "+%s %s" % [InspectorIcons.quantity_text(row.amount), title] + (" · 借入" if row.kind == "borrow" else "")
		if row.kind == "borrow": row.label.modulate = Color("#dbcfab")
	else:
		var verb := "使用"
		if game.FOOD_RECOVERY.has(row.item): verb = "食用"
		elif row.item in ["clean_water", "ale"]: verb = "饮用"
		elif row.item == "clothes": verb = "穿上"
		elif game.ITEM_USES.has(row.item): verb = "装备"
		row.label.text = verb + " " + title + (" · " + row.effect if row.effect != "" else "")
		if row.effect == "": row.label.modulate = Color("#f4dbad")

func _process(_delta: float) -> void:
	if not is_instance_valid(game): return
	var active: Array[FeedbackRow] = []
	for row in rows:
		if not row.visible: continue
		if not can_show(row.worker):
			row.dismiss()
		else:
			active.append(row)
	active.sort_custom(func(a: FeedbackRow, b: FeedbackRow): return a.age < b.age)
	var lanes: Dictionary = {}
	var occupied: Array[Rect2] = []
	var zoom: float = game.world_view.camera.zoom.x
	for row in active:
		var lane: int = lanes.get(row.worker, 0)
		lanes[row.worker] = lane + 1
		var width: float = 28 + row.label.get_minimum_size().x
		row.scale = Vector2.ONE / zoom
		var height := maxf(40.0, 36.0 * zoom) + 30.0
		row.position = game.tile_center(game.world.worker(row.worker).pos) + Vector2(-width / 2, -height - lane * 30 - row.rise) / zoom
		# Nearby workers share screen space; discard excess rather than stack unreadable text.
		for attempt in 5:
			var screen_rect := Rect2(get_global_transform_with_canvas() * row.position, Vector2(width, 28))
			var blocked := false
			for rect in occupied:
				if rect.grow(2).intersects(screen_rect):
					blocked = true
					break
			if not blocked and get_viewport_rect().encloses(screen_rect):
				occupied.append(screen_rect)
				break
			if attempt == 4 or not get_viewport_rect().encloses(screen_rect):
				row.dismiss()
				break
			row.position.y -= 30.0 / zoom
