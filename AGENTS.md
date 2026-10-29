# Design
read file README.md,扩大系统设计.md, they are how game iterated

# UI conventions

- Simulation changes do not authorize new UI fields. Keep internal budgets,
  payment forecasts, and decision diagnostics out of player-facing panels and
  tooltips unless explicitly requested. Do not display daily budget or amount due.
- Do not show intrusive error dialogs. Material shortages do not disable building
  tools or prevent legal blueprint placement. Blueprints publish supply demand
  without charging or reserving stock; workers deliver actual materials through
  the same StateTree, Utility Selection and Smart Objects flow as production.
  Construction requires a clear footprint and all materials on site, consumes
  them once on completion, and never charges remote stock during construction.
  Cancellation recovers only actual goods, never the unfilled recipe.
- Keep the world view free of text labels and attribute/progress bars.
- The only world-text exception is a worker's name, centered below their feet.
- Show descriptions, numeric attributes, status text, and progress bars only in
  toolbars, their hover tooltips, or windows/panels opened by clicking.
- Clicking a worker or building opens live details in the bottom-right inspector.
- Do not restore overhead daily-income progress, hunger/fatigue bars, building
  captions, or floating action text. Communicate world actions through animation.
- Toolbar actions and building/category choices show icons only, without names,
  section headings, or repeated property summaries. Names belong in hover or
  clicked details. Numeric clock and speed controls remain readable.
- Present each fact once per information surface. Omit explanatory filler such
  as wage funding, footprint (shown by blueprint), single occupancy, and early
  wake conditions. Keep material, labor, price/duration, and recovery concise.
- Share property text generation rather than duplicating templates. Simplify
  presentation without removing material, occupancy, pathfinding or accounting
  safeguards, and do not change gameplay rules to reduce UI complexity.

# Rendering architecture

- Keep simulation/input in `scripts/game.gd`, world display in `scripts/view/`,
  and HUD layout in `scripts/view/hud.gd` on its own CanvasLayer.
- Preserve separate terrain-background, block, building, character, fog, and
  interaction layers in `scenes/world.tscn`. Keep fog above world entities and
  interaction markers above fog.
- Use persistent TileMapLayer/Sprite2D/Control nodes and authored assets. Do not
  restore world rendering through `_draw()` or per-frame `queue_redraw()`.
- Update tile cells only when their data changes. Cache textures. Reuse worker
  and building scenes; animate transforms or shader parameters, not new images.

# World input

- Use native Viewport object picking with sorting and first-only enabled. Entity
  roots are Area2D nodes with explicit absolute Z (buildings 20, workers 30),
  CollisionShape2D, input_pickable, and a nonzero collision layer.
- Route entity input_event signals to the existing game script; do not add a
  separate interaction controller or restore rectangle-based mouse hit tests.
- GroundInput receives otherwise unobstructed world clicks. Do not consume world
  left presses in _input or _unhandled_input before native picking runs.
- Keep hover and selection on the native picking path. UI blocks world clicks;
  decorative controls ignore mouse input. No implicit overlap click cycling.
- Keep equal-Z worker tree order consistent with Y-sort. Preserve the building
  node and identity through blueprint completion; test real viewport events,
  including native-window hover, zoom, overlapping objects, and UI interception.

# Behavioral tests

- Follow `tests/README.md`. Extend an existing behavior suite; do not add a test
  script or visual smoke script for every building, item, or implementation change.
- Arrange a valid starting world, issue player commands, advance bounded game
  time, then check observable results: inventory, payments, population, recovery,
  reports, selected details, or actual viewport interaction.
- Do not assert private budgets, task ownership/progress, state-machine labels,
  paths, cache counters, node classes/IDs, signal counts, or texture filenames.
  Do not write those internals to force an action to complete or resume.
- Share one parameterized contract for equivalent buildings/products. Add a
  separate case only for a distinct player-visible rule or concrete regression;
  each case must explain what incorrect outcome it prevents.
- Keep fixtures separate from actions; fixtures may set initial resources,
  equipment, needs, positions, and completed facilities. Do not change gameplay
  or add production abstractions solely to make tests convenient.
- Use real viewport events for picking/UI behavior. Headless tests do not prove
  OS-window hover or rendered appearance; run the same interaction suite with
  `--native` for input/rendering changes, and inspect its screenshots.
- Architectural constraints above remain code-review requirements.
