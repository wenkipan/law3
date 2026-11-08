# World Art

Original, editable SVG game assets. No remote assets or runtime downloads.

- `terrain-atlas.svg`: ten 40px tiles (background, sandstone, copper, coal,
  granite, dense copper, dense coal, timber, iron and mineable water), used by
  TileMapLayer atlas resources. Mineable water is distinct from `water-source.svg`.
- `fog-atlas.svg`: opaque unexplored and translucent explored fog tiles.
- `miner-parts.svg`: 32px rig-part atlas; head, clothing, boots, arms, pickaxe,
  bread, hammer, carried ore. Worker scenes animate sprite transforms.
- `portal.svg`: portal illustration.
- `selection.svg`, `order.svg`, `shadow.svg`: world interaction and shading art.
- `material-shortage.svg`: compact production-shortage bubble; the shell breathes
  around its fixed tip while the centered item icon flips between missing inputs.
- `clock-segment.svg`: one segment instanced twelve times in the UI clock.
- `belt-atlas.svg`, `belt-blueprint-atlas.svg`: sixteen 40px connection shapes
  for points, ends, straight tracks, corners, and junctions. `belt-arrow.svg`
  marks the outgoing edge. Persistent sprites share these textures in both
  construction previews and completed tracks.
- `power-line-atlas.svg`, `power-line-blueprint-atlas.svg`: the same sixteen
  connection shapes in gold 3200W and mint 800W rows. Power lines
  reuse the track sprites and construction reveal, including connected previews;
  thick-wire corridors retain two parallel conductors and their full footprint.
  Both types connect to each other and to any power device.
- `construction.gdshader`: complementary bottom-up reveal masks for solid and
  blueprint sprites, relative to each atlas row. No custom draw calls or
  frame-by-frame image creation.

`buildings/` contains world illustrations and matching construction blueprints
for the farm and coal power plant (160x120), chemical plant (120x120), barn,
smelter and sawmill (120x80). These are authored at their actual tile footprint,
not stretched toolbar illustrations. The barn's sheep remains a separate sprite.

The second batch adds the brewery, bank, hospital, bathhouse, soapworks and
pharmacy (120x80), plus the mill, weaver, smithy, laundry and canteen (80x80).
Service buildings retain their original capacities; the canteen shows two chairs,
while the laundry uses a washbasin and clothesline rather than another bath facade.

Other buildings and compact toolbar illustrations remain under `assets/icons/`.
World building texture selection is shared by previews and persistent building
sprites through `scripts/view/art.gd`; cached textures are shared by all instances.
