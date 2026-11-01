extends Area2D

const Art = preload("res://scripts/view/art.gd")
var last_state := ""
var animation_updates := 0
var last_clock := -1.0
var last_position := Vector2.INF
var last_carry := -1
var last_facing := 0.0
var last_walking := false
var last_in_bed := false
var last_gun := false
var last_backpack := false
var last_cargo_item = null
var last_work_active := true
var last_origin := Vector2i.ZERO
var last_used_item := ""

func _ready() -> void:
	$Shadow.texture = Art.texture("res://assets/world/shadow.svg")
	for part in $Puppet.get_children():
		part.texture = Art.texture("res://assets/world/miner-parts.svg")
		part.region_enabled = true
		part.region_filter_clip_enabled = true
	set_part($Puppet/Head, Vector2i(0, 0))
	set_part($Puppet/Torso, Vector2i(1, 0))
	set_part($Puppet/LeftBoot, Vector2i(2, 0))
	set_part($Puppet/RightBoot, Vector2i(2, 0))
	set_part($Puppet/LeftArm, Vector2i(3, 0))
	set_part($Puppet/RightArm, Vector2i(3, 0))
	set_part($Puppet/Cargo, Vector2i(1, 1))
	$Puppet/Backpack.texture = Art.texture("res://assets/icons/backpack.svg")
	$Puppet/Backpack.region_enabled = false

func set_part(sprite: Sprite2D, cell: Vector2i) -> void:
	sprite.region_rect = Rect2(Vector2(cell) * 32, Vector2(32, 32))

func configure(w: Dictionary, font: Font) -> void:
	$Name.text = w.name
	$Name.add_theme_font_override("font", font)
	$Puppet/Torso.modulate = w.color.lightened(0.2)
	$Puppet/LeftArm.modulate = w.color.lightened(0.2)
	$Puppet/RightArm.modulate = w.color.lightened(0.2)

func sync(w: Dictionary, clock: float, cell_size: float, work_active := true, origin := Vector2i.ZERO) -> void:
	var walking: bool = w.state in ["walk", "haul", "to_build", "to_bed", "to_meal", "to_work", "to_shop", "freight_pickup", "freight_dropoff", "to_payroll", "to_bank", "to_bath"] or (w.state == "rest" and not w.path.is_empty())
	var gun: bool = w.state == "dig" and w.gun_uses > 0
	var backpack: bool = w.backpack_uses > 0
	var in_bed: bool = w.state == "sleep" and w.bed != null
	var freight: bool = not w.freight.is_empty() and w.freight.picked
	var cargo_item = w.freight.item if freight else (w.carry if w.carry > 0 else null)
	$Puppet/Torso.modulate = Color("#888c87").lerp(Color("#d8a8c8"), w.clothes_cleanliness / 100.0) if w.equipment.get("clothes", 0) > 0 else w.color.lightened(0.2)
	if last_origin == origin and last_clock == clock and last_position == w.pos and last_state == w.state and last_carry == w.carry and last_facing == w.facing and last_walking == walking and last_in_bed == in_bed and last_gun == gun and last_backpack == backpack and last_work_active == work_active and is_same(last_cargo_item, cargo_item):
		return
	last_origin = origin
	last_work_active = work_active
	last_clock = clock
	if last_state != w.state or last_in_bed != in_bed:
		$PickShape.shape.size = Vector2(46, 24) if w.state == "sleep" else Vector2(28, 42)
		$PickShape.position = Vector2(cell_size * 0.5, -2) if in_bed else (Vector2(0, 8) if w.state == "sleep" else Vector2(0, -7))
	last_position = w.pos
	last_carry = w.carry
	last_facing = w.facing
	last_walking = walking
	last_in_bed = in_bed
	last_backpack = backpack
	$Puppet/Backpack.visible = backpack and not in_bed
	position = (w.pos - Vector2(origin) + Vector2(0.5, 0.5)) * cell_size
	var phase: float = clock * (5.0 if w.state == "rest" else 11.0) + w.id
	var stride := sin(phase) if walking else 0.0
	$Puppet.position = Vector2(0, absf(stride) * -1.6)
	$Puppet.rotation = PI / 2 if w.state == "sleep" else 0.0
	$Puppet.scale = Vector2(w.facing, 1)
	if w.state == "sleep":
		$Puppet.position = Vector2(0, 8)
		$Puppet.scale = Vector2(0.85, 0.85 + sin(clock * 2) * 0.015)
		if in_bed:
			$Puppet.position = Vector2(cell_size * 0.5, -2)
			$Puppet.rotation = -PI / 2
	elif not walking:
		$Puppet.position.y = sin(clock * 2 + w.id) * 0.6
	$Puppet/LeftBoot.rotation = stride * 0.25
	$Puppet/RightBoot.rotation = -stride * 0.25
	$Puppet/LeftArm.rotation = -stride * 0.3
	$Puppet/RightArm.rotation = stride * 0.3
	$Puppet/Tool.visible = w.state in ["dig", "build", "work", "eat", "drink", "use_item", "bathe"] and (w.state != "work" or work_active)
	$Puppet/Cargo.visible = (w.carry > 0 or freight) and not in_bed
	if not is_same(last_cargo_item, cargo_item):
		last_cargo_item = cargo_item
		if cargo_item != null:
			$Puppet/Cargo.texture = Art.item_texture(cargo_item)
			$Puppet/Cargo.region_enabled = false
			$Puppet/Cargo.scale = Vector2.ONE * 28.0 / $Puppet/Cargo.texture.get_width()
	$Shadow.visible = not in_bed
	$Puppet/Head.rotation = 0.0
	if last_state != w.state or last_gun != gun or last_used_item != w.get("item", ""):
		last_state = w.state
		last_gun = gun
		last_used_item = w.get("item", "")
		$Puppet/Tool.texture = Art.texture("res://assets/icons/mining-gun.svg") if gun else Art.texture("res://assets/world/miner-parts.svg")
		$Puppet/Tool.region_enabled = not gun
		if w.state == "drink":
			$Puppet/Tool.texture = Art.texture("res://assets/icons/water.svg")
			$Puppet/Tool.region_enabled = false
		if w.state == "use_item":
			$Puppet/Tool.texture = Art.item_texture(w.item)
			$Puppet/Tool.region_enabled = false
		if w.state == "bathe":
			$Puppet/Tool.texture = Art.texture("res://assets/icons/bath.svg")
			$Puppet/Tool.region_enabled = false
		set_part($Puppet/Tool, Vector2i(5, 0) if w.state == "eat" else (Vector2i(4, 0) if w.state == "dig" else Vector2i(0, 1)))
	$Puppet/Tool.position = Vector2(17, -5)
	$Puppet/Tool.rotation = 0.0
	if w.state in ["dig", "build"] or (w.state == "work" and work_active):
		var swing := sin(clock * 9) * 0.65
		$Puppet/RightArm.rotation = swing - 0.5
		$Puppet/Tool.rotation = swing
		if gun:
			$Puppet/Tool.rotation = 0.0
			$Puppet/Tool.position.x += sin(clock * 35) * 1.5
			$Puppet/RightArm.rotation = -0.5
	elif w.state == "bathe" or (w.state == "use_item" and w.item == "cleaner"):
		$Puppet/Tool.position = Vector2(9 + sin(clock * 8) * 3, 2)
		$Puppet/RightArm.rotation = -0.5 + sin(clock * 8) * 0.25
		$Puppet/LeftArm.rotation = 0.4 - sin(clock * 8) * 0.25
	elif w.state in ["eat", "drink", "use_item"]:
		$Puppet/Tool.position = Vector2(12, -9 + sin(clock * 7) * 3)
		$Puppet/RightArm.rotation = -0.8
		if w.state == "drink":
			$Puppet/Tool.rotation = -0.4 + sin(clock * 4) * 0.15
	elif w.state == "deposit":
		$Puppet/RightArm.rotation = -0.9 + sin(clock * 8) * 0.2
	elif w.state in ["idle", "rest"] and not walking:
		$Puppet/Head.rotation = sin(clock * 1.3 + w.id) * 0.08
	animation_updates += 1
