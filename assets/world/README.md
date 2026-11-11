# World Art

Original, editable SVG game assets. No remote assets or runtime downloads.

- `terrain-atlas.svg`: ten 40px tiles (background, sandstone, copper, coal,
  granite, dense copper, dense coal, timber, iron and mineable water), used by
  TileMapLayer atlas resources. Mineable water is distinct from `water-source.svg`.
- `fog-atlas.svg`: one opaque tile for all ground outside current sight; no explored-map tint.
- `miner-parts.svg`: 32px rig-part atlas; head, clothing, boots, arms, pickaxe,
  bread, hammer, carried ore. The arm cell is cropped into upper arm and forearm
  sprites, connected by shoulder/elbow nodes and persistent hand grips.
- `worker-motion.tres` and `worker-actions.tres`: shared, editor-editable
  AnimationLibrary resources. Separate AnimationPlayers own gait and upper-body
  tracks; neither controls the entity's position, collision shape or facing.
  Props and carried goods follow hand grips. Every action includes neutral tracks
  for unused joints so transitions cannot retain the preceding action's pose.
- `building-motion.tres`, `sheep-motion.tres`: shared
  transform/property animations. World animation players inherit Pausable mode;
  the door uses a hinge-bound Tween for its dynamically selected open/close target.
- A single global software cursor lives on its own CanvasLayer above the HUD
  and embedded windows. It uses cached 32px icon/item textures and the editable
  `work-cursor-motion.tres` transform animation; system cursors are hidden.
  Default interface shapes live in `assets/cursors/`. Native picking remains
  independent of this visual layer.
- `portal.svg`: portal illustration.
- `../icons/recruitment_board.svg` and its blueprint: a one-cell wooden hiring
  notice with a resident pictogram, shared by the build tray and world entity.
- `wall-atlas.svg`, `fence-atlas.svg` and their blueprint atlases: sixteen
  single-cell joins shared by persistent enclosure sprites and previews.
  `door-frame.svg` and `door-leaf.svg` keep the opening gate on a separate hinge;
  automatic opening animates only the hinge transform, never pathfinding state.
- `selection.svg`, `order.svg`, `shadow.svg`: world interaction and shading art.
- `material-shortage.svg`: shared production/blueprint shortage bubble; blueprints
  add the missing on-site quantity beside the cycling item icon, then show the
  construction tools icon without a quantity once supplied. The shell breathes
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

The surface-economy revision adds `surface-resources.svg`, a transparent tile
atlas of low deposits and timber, and `wild-animal.svg` for stationary wildlife
resource cells. `wild-berries.svg` and `wild-grain.svg` show single-portion ground
resources; consumed cells disappear. `gathering-basket.svg` and `hunting-bow.svg`
give gathering and hunting distinct transform-driven poses. Eating and item use
show the actual item, while a second persistent hand prop shows settled trades.
These resources do not imply blocked navigation. The market (120x80) and mine (80x80)
have authored solid and blueprint SVGs under `assets/icons/`, alongside currency,
berries and the inspect tool. No portal is instantiated in the world view.

Time is owned by Godot: SceneTree.paused suspends the simulation tick and world
animation branches; Engine.time_scale applies 1x/2x/4x exactly once. Pickable
Area2D roots and the camera/HUD remain Always. PhysicsServer2D remains active for
paused native picking; it does not advance the data-driven economic simulation.
Feedback, shortage hints and camera movement use unscaled time. Construction
reveal and conveyor cargo remain driven by real simulation progress, not clips.
