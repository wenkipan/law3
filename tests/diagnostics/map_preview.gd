extends RefCounted

func run(t) -> void:
	for seed_value in [0, 1020, 4294967295]:
		await check_generated_map_seed(t, seed_value)

func check_generated_map_seed(t, seed_value: int) -> void:
	var g = t.game
	# An already explored generated world catches rendering/picking mismatches for every material.
	t.fixtures.scenario("Generated materials retain their rendered and clicked identity: %d" % seed_value, 0, true, seed_value)
	var overview := Rect2i(-64, -64, 256, 192)
	g.ensure_region(overview)
	g.world_view.rebuild(g)
	var samples: Dictionary = {}
	for cell in g.terrain:
		if not overview.has_point(cell):
			continue
		g.explored[cell] = true
		g.visible_tiles[cell] = true
		if cell.x < 10 or cell.y < 10 or Vector2(cell).distance_to(Vector2(g.BASE)) < 10:
			continue
		var material: int = g.MapGenerator.WATER if g.water_sources.has(cell) else g.terrain[cell]
		if material > 0 and not samples.has(material):
			samples[material] = cell
	g.world_view.sync_fog()
	for width in [1440, 960]:
		t.tree.root.size = Vector2i(width, 900 if width == 1440 else 640)
		g.camera.position = g.tile_corner(overview.position) + Vector2(overview.size) * g.CELL / 2.0
		g.camera.zoom = Vector2.ONE * minf((width - 80.0) / (overview.size.x * g.CELL), (t.tree.root.size.y - 160.0) / (overview.size.y * g.CELL))
		await t.input.settle()
		if t.native:
			await RenderingServer.frame_post_draw
			t.tree.root.get_texture().get_image().save_png("/tmp/law3-generated-map-%d-%d.png" % [seed_value, width])
			if seed_value == 1020:
				t.tree.root.get_texture().get_image().save_png("/tmp/law3-generated-map-%d.png" % width)
	t.tree.root.size = Vector2i(1440, 900)
	g.camera.zoom = Vector2.ONE
	g.set_tool("cancel")
	for material in range(1, 8):
		t.check(samples.has(material), "Map preview includes material category %d" % material)
	for material in samples:
		g.camera.position = g.tile_center(samples[material])
		await t.input.settle()
		await t.input.click_world(g.tile_center(samples[material]))
		var title: String = "水源" if material == g.MapGenerator.WATER else g.ORES[material].name
		t.check(g.entity_panel.visible and g.entity_title.text == title, "Clicking generated terrain identifies " + title)
		if material == g.MapGenerator.WATER:
			t.check(g.designate(samples[material], samples[material]) == 0, "Generated water remains unmineable rather than behaving as empty ground")
