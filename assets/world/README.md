# World Art

Original, editable SVG game assets. No remote assets or runtime downloads.

- `terrain-atlas.svg`: five 40px tiles (background, sandstone, copper, coal,
  granite), used by TileMapLayer atlas resources.
- `fog-atlas.svg`: opaque unexplored and translucent explored fog tiles.
- `miner-parts.svg`: 32px rig-part atlas; head, clothing, boots, arms, pickaxe,
  bread, hammer, carried ore. Worker scenes animate sprite transforms.
- `portal.svg`: portal illustration.
- `selection.svg`, `order.svg`, `shadow.svg`: world interaction and shading art.
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

Bed and toolbar illustrations remain under `assets/icons/`. Textures are loaded
once through `scripts/view/art.gd` and shared by all instances.
