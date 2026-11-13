extends Area2D

const Art = preload("res://scripts/view/art.gd")
const WALK_STATES := ["walk", "haul", "to_build", "to_bed", "to_meal", "to_work", "to_shop",
	"freight_pickup", "freight_dropoff", "to_payroll", "to_bank", "to_service"]
const FOOD := ["berries", "meat", "wheat", "bread"]
var trading := false
var trade_item = null
var trade_buying := false
var action: StringName = &""
var motion: StringName = &""
var prop_signature: Array = []
var initialized := false
var action_context: Array = []
var previous_progress := 0.0
@onready var body: Node2D = $Puppet/Gait/Body
@onready var tool: Sprite2D = $Puppet/Gait/Body/RightArm/Elbow/Hand/Grip/Prop
@onready var exchange: Sprite2D = $Puppet/Gait/Body/LeftArm/Elbow/Hand/Grip/Prop
@onready var cargo: Sprite2D = $Puppet/Gait/Body/LeftArm/Elbow/Hand/Grip/Cargo
@onready var actions: AnimationPlayer = $Puppet/Actions
@onready var locomotion: AnimationPlayer = $Puppet/Motion

func _ready() -> void:
	$Shadow.texture = Art.texture("res://assets/world/shadow.svg")
	set_region(body.get_node("Head"), Rect2(0, 0, 32, 32))
	set_region(body.get_node("Torso"), Rect2(32, 0, 32, 32))
	for side in ["Left", "Right"]:
		set_region($Puppet/Gait.get_node(side + "Leg/Boot"), Rect2(64, 0, 32, 32))
		set_region(body.get_node(side + "Arm/Upper"), Rect2(102, 8, 16, 12))
		set_region(body.get_node(side + "Arm/Elbow/Forearm"), Rect2(102, 19, 16, 13))
	body.get_node("Backpack").texture = Art.texture("res://assets/icons/backpack.svg")

func set_region(sprite: Sprite2D, region: Rect2) -> void:
	sprite.texture = Art.texture("res://assets/world/miner-parts.svg")
	sprite.region_enabled = true
	sprite.region_filter_clip_enabled = true
	sprite.region_rect = region
	sprite.scale = Vector2.ONE

func set_prop(sprite: Sprite2D, texture: Texture2D, size: float) -> void:
	sprite.texture = texture
	sprite.region_enabled = false
	sprite.offset = Vector2.ZERO
	sprite.scale = Vector2.ONE * size / maxf(texture.get_width(), texture.get_height())

func configure(w: Dictionary, font: Font) -> void:
	$Name.text = w.name
	$Name.add_theme_font_override("font", font)

func show_transaction(item, buying: bool) -> void:
	trade_item = item
	trade_buying = buying
	trading = true
	action = &""
	prop_signature.clear()

func cancel_transaction() -> void:
	trading = false

func _on_action_finished(finished: StringName) -> void:
	if finished in [&"trade_buy", &"trade_sell"]:
		trading = false

func select_action(w: Dictionary, work_active: bool, walking: bool) -> StringName:
	if trading: return &"trade_buy" if trade_buying else &"trade_sell"
	match w.state:
		"sleep": return &"sleep"
		"build": return &"build"
		"work":
			if not work_active: return &"idle"
			match w.get("work_kind", ""):
				"mine": return &"gun" if w.gun_uses > 0 else &"mine"
				"hunting_ground": return &"hunt"
				"gathering_garden": return &"gather"
				"market", "bank": return &"market"
				"drill", "power_plant", "manual_generator", "transformer": return &"operate"
			return &"craft"
		"eat": return &"eat"
		"drink": return &"drink"
		"use_item":
			if w.get("item", "") in FOOD: return &"eat"
			return &"drink" if w.get("item", "") in ["ale", "clean_water"] else &"equip"
		"service":
			return &"medical" if w.service == "hospital" else (&"bath" if w.service == "bathhouse" else &"wash")
		"deposit": return &"deposit"
	if w.cargo_item != null: return &"carry"
	return &"walk" if walking else &"idle"

func sync(w: Dictionary, cell_size: float, work_active := true, origin := Vector2i.ZERO) -> void:
	var walking: bool = w.state in WALK_STATES or (w.state == "rest" and not w.path.is_empty())
	var in_bed: bool = w.state == "sleep" and w.bed != null
	$PickShape.shape.size = Vector2(46, 24) if w.state == "sleep" else Vector2(28, 42)
	$PickShape.position = Vector2(cell_size * 0.5, -2) if in_bed else (Vector2(0, 8) if w.state == "sleep" else Vector2(0, -7))
	position = (w.pos - Vector2(origin) + Vector2(0.5, 0.5)) * cell_size
	$Puppet.position = (Vector2(cell_size * 0.5, -2) if in_bed else Vector2(0, 8)) if w.state == "sleep" else Vector2.ZERO
	$Puppet.rotation = (-PI / 2 if in_bed else PI / 2) if w.state == "sleep" else 0.0
	$Puppet.scale = Vector2.ONE * 0.85 if w.state == "sleep" else Vector2(w.facing, 1)
	$Shadow.visible = not in_bed
	body.get_node("Backpack").visible = w.backpack_uses > 0 and not in_bed
	var color: Color = Color("#d8a8c8").lerp(Color("#888c87"), w.clothes_pollution / 50.0) if w.equipment.get("clothes", 0) > 0 else w.color.lightened(0.2)
	body.get_node("Torso").modulate = color
	for side in ["Left", "Right"]:
		body.get_node(side + "Arm/Upper").modulate = color
		body.get_node(side + "Arm/Elbow/Forearm").modulate = color
	body.get_node("Head").modulate = Color("#b6cfaa") if w.pollution >= 70 else Color.WHITE
	cargo.visible = w.cargo_item != null and not in_bed and not trading
	if cargo.visible: set_prop(cargo, Art.item_texture(w.cargo_item), 28)
	var next_motion: StringName = &"sleep" if w.state == "sleep" else (&"walk" if walking else &"idle")
	if next_motion != motion:
		motion = next_motion
		locomotion.play(motion, 0.08 if initialized else 0.0)
		locomotion.advance(0)
	var next_action := select_action(w, work_active, walking)
	var item = trade_item if trading else ("clean_water" if w.state == "drink" else w.get("item", ""))
	var context := [next_action, item] if trading else [next_action, w.state, item, w.get("station"), w.get("job"), w.get("work_kind", "")]
	var elapsed: float = w.get("drink_progress", 0.0) if w.state == "drink" else w.get("progress", 0.0)
	var new_use := next_action in [&"eat", &"drink", &"equip"] and elapsed + 0.000001 < previous_progress
	if next_action != action or context != action_context or new_use:
		action = next_action
		action_context = context
		actions.play(action, 0.1 if initialized else 0.0)
		# Initial/load poses can be sampled while paused; ongoing playback is engine-owned.
		if not initialized and not trading:
			var clip := actions.get_animation(action)
			actions.seek(minf(elapsed, clip.length) if clip.loop_mode == Animation.LOOP_NONE else fmod(elapsed, clip.length), true)
		actions.advance(0)
	previous_progress = elapsed
	var signature := [action, item]
	if signature != prop_signature:
		prop_signature = signature
		configure_props(item)
	initialized = true

func configure_props(item) -> void:
	tool.visible = action in [&"mine", &"gun", &"build", &"craft", &"market", &"gather", &"hunt",
		&"eat", &"drink", &"equip", &"medical", &"wash", &"bath", &"trade_buy", &"trade_sell"]
	exchange.visible = action in [&"gather", &"trade_buy", &"trade_sell"]
	if not tool.visible: return
	match action:
		&"mine", &"build", &"craft":
			set_region(tool, Rect2(128, 0, 32, 32) if action == &"mine" else Rect2(0, 32, 32, 32))
			tool.offset = Vector2(9, -13) if action == &"mine" else Vector2(7, -12)
		&"gun": set_prop(tool, Art.texture("res://assets/icons/mining-gun.svg"), 32)
		&"market": set_prop(tool, Art.item_texture("money"), 17)
		&"gather":
			set_prop(tool, Art.item_texture("berries"), 15)
			set_prop(exchange, Art.texture("res://assets/world/gathering-basket.svg"), 23)
		&"hunt": set_prop(tool, Art.texture("res://assets/world/hunting-bow.svg"), 34)
		&"eat", &"drink": set_prop(tool, Art.item_texture("clean_water" if item == "" else item), 18)
		&"equip": set_prop(tool, Art.item_texture(item), 25)
		&"medical": set_prop(tool, Art.item_texture("medical"), 25)
		&"wash": set_prop(tool, Art.item_texture("clothes"), 25)
		&"bath": set_prop(tool, Art.texture("res://assets/icons/bath.svg"), 25)
		&"trade_buy", &"trade_sell":
			set_prop(tool, Art.item_texture(item), 22)
			set_prop(exchange, Art.item_texture("money"), 15)
