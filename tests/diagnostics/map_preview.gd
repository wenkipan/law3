extends RefCounted

func run(t) -> void:
	for seed_value in [0, 1020, 4294967295]:
		await preview_seed(t, seed_value)

func preview_seed(t, seed_value: int) -> void:
	var g = t.game
	# This opt-in overview is for manual inspection, not content or picking assertions.
	g.reset_world(seed_value)
	t.fixtures.scenario_name = "Generated map overview: %d" % seed_value
	var overview := Rect2i(-64, -64, 256, 192)
	g.ensure_region(overview)
	for cell in g.world.terrain:
		if not overview.has_point(cell):
			continue
		g.cache.visible_tiles[cell] = true
	g.world_view.rebuild(g)
	if t.native:
		g.world_view.camera.position = g.tile_center(g.BASE)
		g.world_view.camera.zoom = Vector2.ONE * 0.5
		await t.input.settle()
		await t.input.screenshot("/tmp/law3-generated-camp-%d.png" % seed_value)
	for width in [1440, 960]:
		t.tree.root.size = Vector2i(width, 900 if width == 1440 else 640)
		g.world_view.camera.position = g.tile_corner(overview.position) + Vector2(overview.size) * g.CELL / 2.0
		g.world_view.camera.zoom = Vector2.ONE * minf((width - 80.0) / (overview.size.x * g.CELL), (t.tree.root.size.y - 160.0) / (overview.size.y * g.CELL))
		await t.input.settle()
		if t.native:
			await RenderingServer.frame_post_draw
			t.tree.root.get_texture().get_image().save_png("/tmp/law3-generated-map-%d-%d.png" % [seed_value, width])
			if seed_value == 1020:
				t.tree.root.get_texture().get_image().save_png("/tmp/law3-generated-map-%d.png" % width)
	t.tree.root.size = Vector2i(1440, 900)
	g.world_view.camera.zoom = Vector2.ONE
