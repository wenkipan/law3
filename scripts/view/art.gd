extends RefCounted

static var textures: Dictionary = {}

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
