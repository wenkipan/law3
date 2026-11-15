extends RefCounted

static var textures: Dictionary = {}
const SURFACE_ATLAS := "res://assets/world/surface-resources.svg"
const SURFACE_TILE_SIZE := 40
const WORLD_BUILDINGS := ["farm", "power_plant", "chemical_plant", "barn", "smelter", "sawmill",
	"brewery", "hospital", "bathhouse", "soapworks", "pharmacy", "bank",
	"mill", "weaver", "smithy", "laundry", "canteen"]

static func building_texture(kind: String, blueprint := false) -> Texture2D:
	var folder := "world/buildings" if kind in WORLD_BUILDINGS else "icons"
	return texture("res://assets/%s/%s%s.svg" % [folder, kind, "-blueprint" if blueprint else ""])

static func item_texture(item) -> Texture2D:
	if item in ["money", "berries"]: return texture("res://assets/icons/%s.svg" % item)
	var icons := {0: "blocks", "wheat": "wheat",
		"clean_water": "water", "bench": "mining-gun", "workbench": "backpack",
		"wool": "wool", "cloth": "cloth", "clothes": "clothes", "ale": "ale",
		"iron": "iron", "planks": "planks", "tools": "tools", "meat": "meat", "loan": "loan",
		"chemicals": "chemicals", "cleaner": "cleaner", "medical": "medical", "wastewater": "wastewater"}
	if icons.has(item):
		return texture("res://assets/icons/%s.svg" % icons[item])
	var key := "item:" + str(item)
	if not textures.has(key):
		var atlas := AtlasTexture.new()
		if item is int or item == "raw_water":
			var column: int = item if item is int else 9
			atlas.atlas = texture(SURFACE_ATLAS)
			atlas.region = Rect2(column * SURFACE_TILE_SIZE, 0, SURFACE_TILE_SIZE, SURFACE_TILE_SIZE)
			atlas.filter_clip = true
		elif item == "bread":
			atlas.atlas = texture("res://assets/world/miner-parts.svg")
			atlas.region = Rect2(160, 0, 32, 32)
		else:
			return texture("res://assets/icons/freight.svg")
		textures[key] = atlas
	return textures[key]

static func texture(path: String) -> Texture2D:
	if not textures.has(path):
		var resource := ResourceLoader.load(path, "Texture2D") as Texture2D
		assert(resource != null, "Cannot load art: " + path)
		textures[path] = resource
	return textures[path]

static func tile_set(path: String, columns: int) -> TileSet:
	var result := TileSet.new()
	result.tile_size = Vector2i.ONE * SURFACE_TILE_SIZE
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture(path)
	atlas.texture_region_size = result.tile_size
	for x in columns:
		atlas.create_tile(Vector2i(x, 0))
	result.add_source(atlas, 0)
	return result
