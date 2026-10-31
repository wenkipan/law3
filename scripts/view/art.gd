extends RefCounted

static var textures: Dictionary = {}

static func item_texture(item) -> Texture2D:
	var icons := {"raw_water": "raw-water", "wheat": "wheat", 3: "coal",
		"clean_water": "water", "bench": "mining-gun", "workbench": "backpack",
		"wool": "wool", "cloth": "cloth", "clothes": "clothes", "ale": "ale",
		"iron": "iron", "planks": "planks", "tools": "tools", "meat": "meat", "loan": "loan"}
	if icons.has(item):
		return texture("res://assets/icons/%s.svg" % icons[item])
	var key := "item:" + str(item)
	if not textures.has(key):
		var atlas := AtlasTexture.new()
		if item is int:
			atlas.atlas = texture("res://assets/world/terrain-atlas.svg")
			atlas.region = Rect2(item * 40, 0, 40, 40)
		elif item == "bread":
			atlas.atlas = texture("res://assets/world/miner-parts.svg")
			atlas.region = Rect2(160, 0, 32, 32)
		else:
			return texture("res://assets/icons/freight.svg")
		textures[key] = atlas
	return textures[key]

static func texture(path: String) -> Texture2D:
	if not textures.has(path):
		var image := Image.new()
		var error := image.load_svg_from_string(FileAccess.get_file_as_string(path))
		assert(error == OK, "Cannot load art: " + path)
		textures[path] = ImageTexture.create_from_image(image)
	return textures[path]

static func tile_set(path: String, columns: int) -> TileSet:
	var result := TileSet.new()
	result.tile_size = Vector2i(40, 40)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture(path)
	atlas.texture_region_size = Vector2i(40, 40)
	for x in columns:
		atlas.create_tile(Vector2i(x, 0))
	result.add_source(atlas, 0)
	return result
