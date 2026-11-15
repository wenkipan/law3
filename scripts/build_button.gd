extends Button

const Art = preload("res://scripts/view/art.gd")
const UITheme = preload("res://assets/ui_theme.tres")
var game: Node
var kind := "bed"

func _make_custom_tooltip(_for_text: String) -> Object:
	var card := PanelContainer.new()
	card.theme = UITheme
	card.theme_type_variation = "BuildingTooltip"
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	card.add_child(content)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	content.add_child(heading)
	var image := TextureRect.new()
	image.texture = icon
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(48, 36)
	heading.add_child(image)
	heading.add_child(game.hud.make_label(game.building_name(kind), 20))
	content.add_child(HSeparator.new())
	var requirements := RichTextLabel.new()
	requirements.name = "Requirements"
	requirements.fit_content = true
	requirements.scroll_active = false
	requirements.custom_minimum_size.x = 240
	requirements.add_theme_font_size_override("normal_font_size", 14)
	content.add_child(requirements)
	var recipe: Dictionary = game.building_materials(kind)
	var available: Dictionary = game.player_inventory()
	for item in recipe:
		var stock := int(maxf(0.0, available.get(item, 0.0)))
		requirements.add_image(Art.item_texture(item), 22, 22)
		requirements.push_color(Color("#A9D9B5") if stock >= recipe[item] else Color("#ED9C89"))
		requirements.add_text("  " + game.material_requirement_line(item, recipe[item], stock))
		requirements.pop()
		requirements.newline()
	var hours: float = game.building_hours(kind)
	requirements.add_text("工时  %s 小时\n工资  %s 货币" % [String.num(hours, 2), String.num(hours * game.WAGE_PER_HOUR, 2)])
	var effects_text: String = game.building_effects_text(kind)
	if effects_text != "":
		content.add_child(HSeparator.new())
		var effects: Label = game.hud.make_label(effects_text, 14)
		effects.name = "Effects"
		content.add_child(effects)
	return card
