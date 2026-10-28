extends RefCounted

const P := Vector2i(28, 11)

func run(t) -> void:
	var g = t.game
	var ui = g.get_node("UI")
	if t.native:
		await t.settle()
		await RenderingServer.frame_post_draw
		t.root.get_texture().get_image().save_png("/tmp/law3-resource-start.png")
	await check_generated_map(t)
	if "--generated-map" in OS.get_cmdline_user_args():
		return
	await check_unbounded_picking(t)
	t.scenario("Real viewport clicks select the displayed object")
	t.bed(P)
	t.bank(Vector2i(31, 11))
	t.materials(100)
	for zoom in [0.65, 1.0, 1.6]:
		g.camera.zoom = Vector2.ONE * zoom
		await t.settle()
		for mode in ["dig", "cancel", "bed", "bank"]:
			g.set_tool(mode)
			await t.click_world(g.tile_center(P + Vector2i.RIGHT))
			t.check(g.entity_panel.visible and g.entity_title.text == "床", "Either footprint remains inspectable across tools and zoom")
			if t.native:
				t.check(g.world_view.hover_frame.visible and g.world_view.hover_frame.size.x > g.CELL, "Native hover outlines the building, not one ground tile")
			await t.click_world(g.tile_center(Vector2i(32, 11)))
			t.check(g.entity_title.text == "银行" and not ui.production_controls.visible, "Bank is selectable across tools and zoom without production controls")
		await t.click_world(g.tile_center(g.BASE) + Vector2(0, -32))
		t.check(g.selected_entity == g.BASE, "Upper portal artwork responds to clicks")
	g.camera.zoom = Vector2.ONE
	g.set_tool("dig")
	# These are layout fixtures, not simulated movement or fabricated task states.
	g.workers[0].pos = Vector2(P)
	g.workers[1].pos = Vector2(P) + Vector2(0, 0.1)
	await t.settle()
	var overlap: Vector2 = g.tile_center(P) + Vector2(0, -7)
	await t.click_world(overlap)
	t.check(g.entity_title.text == g.workers[1].name, "Frontmost worker wins over another worker and a building")
	g.workers[0].pos.y += 0.2
	await t.settle()
	await t.click_world(overlap)
	t.check(g.entity_title.text == g.workers[0].name, "Click ordering follows visible depth")
	g.workers[0].pos = Vector2(34, 15)
	g.workers[1].pos = Vector2(35, 15)
	await t.settle()
	if t.native:
		t.check(g.world_view.hover_frame.size.x > g.CELL, "Stationary native mouse reveals the building after workers move")
	await t.click_world(overlap)
	t.check(g.entity_title.text == "床", "Moving workers away makes the underlying bed selectable")
	await t.click(g.pause_button.get_global_rect().get_center())
	t.check(g.simulation_paused and g.entity_title.text == "床", "Toolbar click pauses without selecting the world underneath")
	t.check(not g.world_view.hover_frame.visible, "UI suppresses world hover")

	t.scenario("Ground orders, cancellation, and rapid clicks")
	t.materials(6, 2)
	await t.settle()
	await t.click(g.furniture_button.get_global_rect().get_center())
	await t.click(g.tool_buttons.bed.get_global_rect().get_center())
	t.check(g.tool_buttons.bed.disabled and g.tool != "bed", "Clicking a disabled recipe cannot spend the wrong mineral")
	t.materials(6)
	g.set_tool("bed")
	await t.settle()
	await t.click_world(g.tile_center(P))
	g.set_tool("cancel")
	await t.click_world(g.tile_center(P + Vector2i.RIGHT))
	t.check(g.player_blocks == 6, "Cancel click refunds the blueprint through either cell")
	g.set_tool("dig")
	var rapid := InputEventMouseButton.new()
	rapid.position = g.get_global_transform_with_canvas() * g.tile_center(Vector2i(37, 13))
	rapid.button_index = MOUSE_BUTTON_LEFT
	rapid.pressed = true
	t.root.push_input(rapid, true)
	rapid = rapid.duplicate()
	rapid.pressed = false
	t.root.push_input(rapid, true)
	await t.settle()
	g.simulate(30)
	t.check(g.delivered == 1, "Press and release in one tick still orders a real excavation")

	for kind in ["bench", "workbench", "bank"]:
		t.scenario("Blueprint completes without losing the inspected building: " + kind, 1)
		t.building_materials(kind)
		g.set_tool(kind)
		await t.settle()
		await t.click_world(g.tile_center(P))
		t.check(g.player_blocks == 0, "Ground click places a paid blueprint")
		await t.click_world(g.tile_center(P + Vector2i.RIGHT))
		t.check(g.entity_title.text == g.building_name(kind) + " · 建造中", "Blueprint opens live construction details")
		g.simulate(90)
		await t.settle()
		t.check(g.entity_title.text == g.building_name(kind) and ui.production_controls.visible == (kind != "bank"), "Selected details become the completed building without reselection")
		await t.click_world(g.tile_center(P + Vector2i.RIGHT))
		t.check(g.entity_title.text == g.building_name(kind), "Completed building remains clickable")

	for kind in ["bench", "workbench", "pump", "purifier", "printer", "farm"]:
		t.scenario("Production controls: " + kind)
		t.station(kind, P)
		await t.settle()
		await t.click_world(g.tile_center(P + Vector2i.RIGHT))
		await t.click(ui.add_order.get_global_rect().get_center())
		var amount: int = g.PRODUCTS[kind].get("amount", 1)
		var expected := "待制  1" if kind == "printer" else "每日产出 %d%s" % [amount, g.PRODUCTS[kind].unit]
		t.check(ui.queue_count.text == expected, "Plus edits the displayed quota in the right units")
		await t.click(ui.remove_order.get_global_rect().get_center())
		t.check(ui.remove_order.disabled, "Minus reaches zero and disables further subtraction")

	t.scenario("Printed worker appears in selection, bed choices, and an open report")
	t.station("printer", P)
	t.bed(Vector2i(31, 11))
	t.materials(10)
	g.adjust_production(P, 1)
	g.open_report()
	g.report_window.hide()
	g.simulate(40)
	g.report_window.refresh()
	t.check(g.report_window.people.item_count == 5 and g.report_window.people.get_item_text(4) == g.workers[3].name, "Existing report adds the newborn to its people filter")
	await t.settle()
	await t.click_world(g.tile_center(g.workers[3].pos) + Vector2(0, -7))
	t.check(g.entity_title.text == g.workers[3].name, "Newborn is clickable without rebuilding the world")
	g.select_entity(Vector2i(31, 11))
	t.check(ui.bed_assignment.item_count == 5, "Newborn can be chosen for a bed")

	for size in [Vector2i(1440, 900), Vector2i(960, 640)]:
		t.root.size = size
		g.select_entity(P)
		await t.settle()
		t.check(t.root.get_visible_rect().encloses(g.entity_panel.get_global_rect()), "Inspector fits inside the window")
		t.check(g.entity_panel.get_global_rect().encloses(ui.production_controls.get_global_rect()), "Production controls fit inside the inspector")
		t.check(ui.queue_count.size.x >= ui.queue_count.get_minimum_size().x, "Quantity label is not clipped")
		if t.native:
			await RenderingServer.frame_post_draw
			t.root.get_texture().get_image().save_png("/tmp/law3-behaviors-%d.png" % size.x)

	# Bank terms and receipts must fit without exposing internal spending forecasts.
	t.scenario("Bank toolbar, receipts, and compact layout", 1)
	t.bank(P)
	g.workers[0].bread = 9.03
	g.designate(Vector2i(37, 11), Vector2i(37, 15))
	t.advance_until(func(): return g.banks[P].interest_received >= 0.194 - 0.000001, 90, "Bank has an actual collected interest receipt")
	for size in [Vector2i(1440, 900), Vector2i(960, 640)]:
		t.root.size = size
		await t.settle()
		if not g.build_tray.visible:
			await t.click(g.furniture_button.get_global_rect().get_center())
		t.check(g.build_tray.visible and g.tool_buttons.bank.disabled, "Bank is listed but unavailable without materials")
		t.check(t.root.get_visible_rect().encloses(g.build_tray.get_global_rect()), "Expanded building list fits the window")
		await t.click_world(g.tile_center(P + Vector2i.RIGHT))
		t.check(g.entity_title.text == "银行" and g.entity_details.text.contains("已收利息  0.19"), "Selected bank shows real collected interest")
		t.check(not g.entity_details.text.contains("预算") and not g.entity_details.text.contains("待支付"), "Bank keeps internal forecasts out of player details")
		t.check(t.root.get_visible_rect().encloses(g.entity_panel.get_global_rect()), "Bank inspector fits the viewport")
		t.check(g.entity_panel.get_global_rect().encloses(g.entity_details.get_global_rect()), "Bank terms are not clipped")
		if t.native:
			await RenderingServer.frame_post_draw
			t.root.get_texture().get_image().save_png("/tmp/law3-behaviors-bank-%d.png" % size.x)
		await t.click(g.furniture_button.get_global_rect().get_center())

	# The report must refresh the same metric for dates and people, including zero results.
	t.scenario("Daily report excavation counts and filters", 2)
	var report_item: int = g.terrain[Vector2i(37, 13)]
	g.workers[0].pos = Vector2(36, 13)
	g.workers[1].pos = Vector2(28, 11)
	g.designate(Vector2i(37, 13), Vector2i(37, 13))
	t.advance_until(func(): return g.mined == 1, 20, "A completed excavation is available in the report")
	await t.settle()
	for button in ui.find_children("*", "Button", true, false):
		if button.tooltip_text == "每日报告":
			await t.click(button.get_global_rect().get_center())
	var report = g.report_window
	t.check(is_instance_valid(report) and report.visible, "Toolbar opens the daily report")
	if not is_instance_valid(report):
		return
	t.check(report.summary.text.contains("挖掘方块  1 块"), "Report displays completed blocks, not delivered blocks")
	await choose_report_filter(t, report, report.people, 2)
	t.check(report.summary.text.contains("挖掘方块  0 块"), "Worker without excavations displays zero")
	await choose_report_filter(t, report, report.people, 1)
	t.check(report.summary.text.contains("挖掘方块  1 块"), "Worker filter displays that miner's count")
	g.simulate(g.DAY_SECONDS - g.day_elapsed + 1)
	report.refresh()
	await choose_report_filter(t, report, report.days, 1)
	t.check(report.summary.text.contains("挖掘方块  0 块"), "New day starts with zero excavations")
	await choose_report_filter(t, report, report.days, 0)
	await choose_report_filter(t, report, report.people, 0)
	t.check(report.summary.text.contains("已结算") and report.summary.text.contains("挖掘方块  1 块"), "Historical all-worker count remains available")
	for report_size in [Vector2i(680, 600), Vector2i(560, 550)]:
		report.size = report_size
		await t.settle()
		t.check(report.get_visible_rect().encloses(report.summary.get_global_rect()), "Excavation summary fits the report")
		for row in report.rows.values():
			t.check(report.get_visible_rect().encloses(row[2].get_global_rect()), "Action rows remain inside the report")
		if t.native:
			await RenderingServer.frame_post_draw
			report.get_texture().get_image().save_png("/tmp/law3-behaviors-report-%d.png" % report_size.x)
	# Tabs share one report window; the resource page expands an item, not a date selector.
	await t.click(Vector2(report.position) + report.tabs.global_position + report.tabs.get_tab_rect(1).get_center())
	t.check(report.resources.visible and not report.days.is_visible_in_tree(), "Top tab switches to inventory without historical date controls")
	t.check(report.resources.day_labels[0].text == "1" and report.resources.day_labels[1].text == "2" and not report.resources.day_labels[2].visible, "Inventory axis labels elapsed game days rather than stretching an unlabeled time range")
	t.check(not report.resources.details.visible and report.resources.rows[report_item][3].is_visible_in_tree(), "Inventory curves appear in the third column before any row is expanded")
	await t.click(Vector2(report.position) + report.resources.rows[report_item][1].get_global_rect().get_center())
	t.check(report.resources.details.visible and report.resources.yesterday.text == "昨日产出  1    昨日消耗  0", "Clicking an item expands yesterday's actual mining output and consumption")
	t.check(report.resources.rows[report_item][2].text == "1", "Resource row displays current total inventory")
	var selected_before: int = g.selected_worker
	for report_size in [Vector2i(680, 600), Vector2i(560, 550)]:
		report.size = report_size
		await t.settle()
		t.check(report.get_visible_rect().encloses(report.resources.rows[report_item][3].get_global_rect()), "Third-column inventory curve fits the report at both sizes")
		t.check(report.resources.rows[report_item][2].get_global_rect().end.x <= report.resources.rows[report_item][3].get_global_rect().position.x, "Total count and inventory curve occupy separate non-overlapping columns")
		t.near(report.resources.day_axis.get_global_rect().position.x, report.resources.rows[report_item][3].get_global_rect().position.x, "Shared day axis aligns with every inventory chart")
		for label in report.resources.day_labels:
			if label.visible:
				t.check(report.resources.day_axis.get_global_rect().encloses(label.get_global_rect()), "Day labels stay within the chart column at both report sizes")
		t.check(report.get_visible_rect().encloses(report.resources.yesterday.get_global_rect()), "Yesterday's flows fit without clipping")
		if t.native:
			await RenderingServer.frame_post_draw
			report.get_texture().get_image().save_png("/tmp/law3-resources-%d.png" % report_size.x)
	t.check(g.selected_worker == selected_before, "Report interactions do not select world objects behind it")
	await t.click(Vector2(report.position) + report.resources.rows[report_item][2].get_global_rect().get_center())
	t.check(not report.resources.details.visible and report.resources.rows[report_item][3].is_visible_in_tree(), "Clicking the total collapses yesterday's totals but keeps the row's curve visible")
	await t.click(Vector2(report.position) + report.resources.rows[report_item][3].get_global_rect().get_center())
	t.check(report.resources.details.visible, "Clicking the curve also expands its row's yesterday totals")
	g.simulate(g.DAY_SECONDS * 4)
	report.refresh()
	await t.settle()
	t.check(report.resources.day_labels[0].text == "2" and report.resources.day_labels[4].text == "6" and report.resources.day_labels[4].visible, "The day axis rolls forward to the latest five days at midnight")
	g.simulate(g.DAY_SECONDS * 0.5)
	report.refresh()
	await t.settle()
	t.check(report.resources.day_labels[0].text == "2" and report.resources.day_labels[4].text == "6", "Day divisions remain fixed as the current day progresses")
	if t.native:
		await RenderingServer.frame_post_draw
		report.get_texture().get_image().save_png("/tmp/law3-resources-daily-axis.png")
	await t.click(Vector2(report.position) + report.tabs.global_position + report.tabs.get_tab_rect(0).get_center())
	t.check(report.labor.visible and report.days.is_visible_in_tree(), "Worker report retains its existing filters when switching back")
	report.hide()
	await check_material_delivery(t)
	await check_building_rows(t)
	await check_tracks(t)
	await check_track_receivers(t)
	await check_tile_details(t)
	await check_power_interactions(t)

func check_power_interactions(t) -> void:
	var g = t.game
	t.root.size = Vector2i(1440, 900)
	# Line blueprints retain the same clicked inspector through completion and crossings.
	for kind in g.LINE_KINDS:
		for axis in [Vector2i.RIGHT, Vector2i.DOWN]:
			t.scenario("Cable row, completion and live inspection: %s %s" % [kind, axis], 1)
			t.clear_area(Rect2i(27, 10, 10, 6))
			t.building_materials(kind, 3)
			g.world_view.rebuild(g)
			await choose_building(t, kind)
			var stroke: Array[Vector2i] = [P, P + axis * 2]
			var orientation := "horizontal" if axis == Vector2i.RIGHT else "vertical"
			await t.drag_world(stroke, false, false, "/tmp/law3-power-%s-%s-preview.png" % [kind, orientation])
			t.check(g.player_blocks == 0, "Each of three cable lengths charges exactly once")
			var far_cell: Vector2i = P + (Vector2i(axis.y, axis.x) if kind == "high_line" else Vector2i.ZERO)
			await t.click_world(g.tile_center(far_cell))
			t.check(g.entity_title.text == g.building_name(kind) + " · 建造中", "Cable footprint opens its construction details")
			# Capture the reveal mid-build using the work hours shown in the inspector.
			t.advance_until(func():
				g.update_ui()
				var hours: float = g.entity_details.text.get_slice("工时  ", 1).get_slice(" /", 0).to_float()
				return g.entity_details.text.contains("工时  ") and hours >= g.building_hours(kind) * 0.4,
				30, "Selected cable reports real construction underway")
			await t.settle()
			if t.native:
				await RenderingServer.frame_post_draw
				t.root.get_texture().get_image().save_png("/tmp/law3-power-%s-%s-building.png" % [kind, orientation])
			t.advance_until(func(): return g.power_lines.size() == 3, 45, "Cable row completes through normal material transport and labor")
			await t.settle()
			t.check(g.entity_title.text == g.building_name(kind), "Selected cable details survive blueprint completion")
			for width in [1440, 960]:
				t.root.size = Vector2i(width, 900 if width == 1440 else 640)
				g.camera.zoom = Vector2.ONE * (1.4 if width == 1440 else 0.8)
				await t.settle()
				await t.click_world(g.tile_center(P + axis))
				t.check(g.entity_title.text == g.building_name(kind), "Finished cable remains inspectable at both zooms and window sizes")
				if t.native:
					await RenderingServer.frame_post_draw
					t.root.get_texture().get_image().save_png("/tmp/law3-power-%s-%s-%d.png" % [kind, orientation, width])
			g.camera.zoom = Vector2.ONE
			t.root.size = Vector2i(1440, 900)
			t.building_materials(kind)
			await choose_building(t, kind)
			stroke = [P, P + axis * 3]
			await t.drag_world(stroke)
			t.check(g.player_blocks == 0, "Extending a same-type line charges only its new length")
			if t.native and kind == "high_line" and axis == Vector2i.DOWN:
				await RenderingServer.frame_post_draw
				t.root.get_texture().get_image().save_png("/tmp/law3-power-vertical.png")
			# A turn/branch must stay clickable, and removing it must not remove the trunk.
			var branch: Vector2i = P + axis + Vector2i(axis.y, axis.x) * (2 if kind == "high_line" else 1)
			t.building_materials(kind)
			await choose_building(t, kind)
			await t.click_world(g.tile_center(branch))
			t.advance_until(func(): return g.power_lines.has(branch), 30, "Perpendicular cable branch completes normally")
			g.set_tool("dig")
			await t.click_world(g.tile_center(branch) + Vector2(0, 17))
			t.check(g.entity_title.text == g.building_name(kind), "Cable branch opens its own details")
			if t.native:
				await RenderingServer.frame_post_draw
				t.root.get_texture().get_image().save_png("/tmp/law3-power-%s-%s-branch.png" % [kind, orientation])
			g.set_tool("cancel")
			await t.click_world(g.tile_center(branch) + Vector2(0, 17))
			t.check(not g.power_lines.has(branch) and g.power_lines.has(P + axis), "Dismantling a branch preserves the neighboring trunk")

	t.scenario("High-voltage corridor permits belt crossing but blocks buildings", 0)
	t.clear_area(Rect2i(27, 9, 10, 7))
	for x in range(28, 33): t.cable(Vector2i(x, 11), "high_line")
	t.materials(5)
	g.world_view.rebuild(g)
	await choose_building(t, "belt")
	var crossing: Array[Vector2i] = [Vector2i(30, 10), Vector2i(30, 14)]
	await t.drag_world(crossing)
	t.check(g.player_blocks == 0, "A belt can cross both corridor cells without duplicating cable cost")
	t.building_materials("bed")
	t.check(not g.place_building(Vector2i(28, 12), "bed"), "The full two-cell corridor rejects buildings")
	t.check(not g.route(Vector2i(29, 10), Vector2i(29, 14)).is_empty(), "People can walk across the corridor")
	await t.click_world(g.tile_center(Vector2i(30, 11)))
	t.check(g.entity_title.text.begins_with("矿道"), "The visible belt wins native picking over the cable beneath it")
	if t.native:
		await RenderingServer.frame_post_draw
		t.root.get_texture().get_image().save_png("/tmp/law3-power-crossing.png")

	# Selected ranges and relocation must use real viewport events, including zoom and UI interception.
	t.scenario("Power effects, dense ore and drill movement", 0)
	t.power_facilities(1, 1)
	t.station("fountain", Vector2i(35, 9))
	g.add_stock(Vector2i(35, 9), "raw_water", 10)
	var drill := Vector2i(38, 9)
	t.station("drill", drill)
	var additions := {Vector2i(32, 12): "spotlight", Vector2i(35, 12): "daylight", Vector2i(28, 12): "canteen", Vector2i(25, 11): "manual_generator"}
	for p in additions:
		t.station(additions[p], p)
	g.terrain[Vector2i(39, 11)] = 5
	g.navigation.set_point_solid(Vector2i(39, 11), true)
	g.world_view.rebuild(g)
	g.simulate(3)
	if g.build_tray.visible:
		await t.click(g.furniture_button.get_global_rect().get_center())
	for width in [1440, 960]:
		t.root.size = Vector2i(width, 900 if width == 1440 else 640)
		g.camera.position = g.tile_center(Vector2i(34, 10))
		g.camera.zoom = Vector2.ONE * (1.1 if width == 1440 else 0.8)
		for p in [Vector2i(32, 9), Vector2i(35, 9), drill] + additions.keys():
			await t.settle()
			await t.click_world(g.tile_center(p))
			t.check(g.entity_title.text == g.building_name(g.building_kind(p)), "Facility %s at width %d opens its live details, got %s" % [g.building_kind(p), width, g.entity_title.text])
			t.check(g.world_view.effect_frame.visible == (g.building_kind(p) not in ["manual_generator", "canteen"]), "Only area-effect facilities reveal a range when clicked")
			t.check(t.root.get_visible_rect().encloses(g.entity_panel.get_global_rect()), "Inspector %s at width %d fits the viewport: %s" % [g.building_kind(p), width, g.entity_panel.get_global_rect()])
			if t.native:
				await RenderingServer.frame_post_draw
				t.root.get_texture().get_image().save_png("/tmp/law3-power-%s-%d.png" % [g.building_kind(p), width])
	await t.click_world(g.tile_center(Vector2i(39, 11)))
	t.check(g.entity_title.text == "致密铜矿" and g.entity_details.text.contains("矿钻"), "Dense terrain shows its distinct repeatable extraction rule")
	t.check(not g.world_view.effect_frame.visible, "Selecting terrain clears the previous building range")
	await t.click_world(g.tile_center(drill))
	await t.click(g.get_node("UI").move_drill.get_global_rect().get_center())
	var destination := Vector2i(38, 13)
	await t.click_world(g.tile_center(destination))
	t.check(g.entity_title.text == "矿钻" and g.selected_entity == destination, "Move icon relocates the drill through native ground input")
	t.check(g.entity_details.text.contains("未供电"), "Moved drill immediately reports its lost power connection")
	await t.click(g.pause_button.get_global_rect().get_center())
	t.check(g.selected_entity == destination, "Toolbar click does not place or select through the HUD")
	t.root.size = Vector2i(1440, 900)

func check_generated_map(t) -> void:
	for seed_value in [0, 1020, 4294967295]:
		await check_generated_map_seed(t, seed_value)

func check_generated_map_seed(t, seed_value: int) -> void:
	var g = t.game
	# An already explored generated world catches rendering/picking mismatches for every material.
	t.scenario("Generated materials retain their rendered and clicked identity: %d" % seed_value, 0, true, seed_value)
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
		t.root.size = Vector2i(width, 900 if width == 1440 else 640)
		g.camera.position = g.tile_corner(overview.position) + Vector2(overview.size) * g.CELL / 2.0
		g.camera.zoom = Vector2.ONE * minf((width - 80.0) / (overview.size.x * g.CELL), (t.root.size.y - 160.0) / (overview.size.y * g.CELL))
		await t.settle()
		if t.native:
			await RenderingServer.frame_post_draw
			t.root.get_texture().get_image().save_png("/tmp/law3-generated-map-%d-%d.png" % [seed_value, width])
			if seed_value == 1020:
				t.root.get_texture().get_image().save_png("/tmp/law3-generated-map-%d.png" % width)
	t.root.size = Vector2i(1440, 900)
	g.camera.zoom = Vector2.ONE
	g.set_tool("cancel")
	for material in range(1, 8):
		t.check(samples.has(material), "Map preview includes material category %d" % material)
	for material in samples:
		g.camera.position = g.tile_center(samples[material])
		await t.settle()
		await t.click_world(g.tile_center(samples[material]))
		var title: String = "水源" if material == g.MapGenerator.WATER else g.ORES[material].name
		t.check(g.entity_panel.visible and g.entity_title.text == title, "Clicking generated terrain identifies " + title)
		if material == g.MapGenerator.WATER:
			t.check(g.designate(samples[material], samples[material]) == 0, "Generated water remains unmineable rather than behaving as empty ground")

func check_unbounded_picking(t) -> void:
	var g = t.game
	# Prevent negative cells being treated as no selection and distant tiles wrapping.
	for cell in [Vector2i(-1, -1), Vector2i(-33, -32), Vector2i(160, 96), Vector2i(65536, -65536)]:
		t.scenario("Native picking in streamed regions: " + str(cell), 0, true)
		g.ensure_region(Rect2i(cell - Vector2i.ONE * 5, Vector2i.ONE * 12))
		t.clear_area(Rect2i(cell - Vector2i.ONE * 4, Vector2i.ONE * 10))
		g.terrain[cell] = 2
		g.navigation.set_point_solid(cell, true)
		var bed: Vector2i = cell + Vector2i(2, 0)
		t.bed(bed)
		var worker: Dictionary = g.create_worker(cell + Vector2i(-2, 0))
		t.building_materials("bed", 2)
		g.simulation_paused = true
		g.set_tool("cancel")
		g.world_view.rebuild(g)
		for width in [1440, 960]:
			t.root.size = Vector2i(width, 900 if width == 1440 else 640)
			for zoom in [0.65, 1.6]:
				g.camera.zoom = Vector2.ONE * zoom
				g.camera.position = g.tile_center(cell)
				g._process(0.0)
				await t.settle()
				await t.click_world(g.tile_center(cell))
				t.check(g.entity_panel.visible and g.selected_tile == cell and g.entity_title.text == "铜矿", "Streamed ground selects its actual world cell at both zoom levels and viewport sizes")
				if t.native:
					t.check(g.world_view.hover_frame.visible, "Native stationary hover survives display-origin shifts")
				await t.click_world(g.tile_center(bed))
				t.check(g.selected_entity == bed and g.entity_title.text == "床", "Building picking uses the same shifted coordinates as its visible artwork")
				await t.click_world(g.tile_center(worker.pos) + Vector2(0, -7))
				t.check(g.selected_worker == worker.id, "Worker picking survives a distant display origin")
			await t.click(g.pause_button.get_global_rect().get_center())
			t.check(g.selected_worker == worker.id, "HUD still intercepts clicks over distant terrain")
			g.simulation_paused = true
			if t.native and cell.x == 65536:
				await RenderingServer.frame_post_draw
				t.root.get_texture().get_image().save_png("/tmp/law3-streamed-map-%d.png" % width)
		g.camera.position = g.tile_center(g.BASE)
		g._process(0.0)
		await t.settle()
		g.camera.position = g.tile_center(cell)
		g._process(0.0)
		await t.settle()
		g.set_tool("dig")
		var stroke: Array[Vector2i] = [cell, cell + Vector2i.RIGHT]
		await t.drag_world(stroke)
		g.select_tile(cell)
		t.check(g.entity_details.text.contains("等待挖掘"), "Returning to an unloaded view preserves terrain and allows a real mining drag")
		g.set_tool("bed")
		await t.click_world(g.tile_center(cell + Vector2i(0, 2)))
		t.check(g.building_at(cell + Vector2i(0, 2)), "Blueprint placement uses world coordinates after rebasing")
		var hidden: Vector2i = cell + Vector2i(80, 0)
		g.camera.position = g.tile_center(hidden)
		g._process(0.0)
		await t.settle()
		await t.click_world(g.tile_center(hidden))
		t.check(g.tile_details(hidden).is_empty() and not g.building_at(hidden), "Panning into fog neither reveals geology nor permits building")
	t.root.size = Vector2i(1440, 900)
	g.camera.zoom = Vector2.ONE

func check_tile_details(t) -> void:
	var g = t.game
	var ore := Vector2i(37, 13)
	# Inspecting terrain must retain both single-cell orders and live excavation results.
	for mineral in range(1, 5):
		t.scenario("Click terrain information: " + g.ORES[mineral].name, 0)
		g.terrain[ore] = mineral
		g.world_view.block_changed(ore)
		g.set_tool("cancel")
		for zoom in [0.65, 1.0, 1.6]:
			g.camera.zoom = Vector2.ONE * zoom
			await t.settle()
			await t.click_world(g.tile_center(ore))
			t.check(g.entity_panel.visible and g.entity_title.text == g.ORES[mineral].name, "Clicking an explored block opens its own material information at every zoom")
			t.check(g.entity_details.text.contains("未标记挖掘") and g.entity_details.text.contains("开采工时") and g.entity_details.text.contains("产物  " + g.ORES[mineral].name), "Terrain details show current designation, work time and actual yield")
		g.set_tool("dig")
		await t.click_world(g.tile_center(ore))
		t.check(g.entity_details.text.contains("等待挖掘"), "Single click still places an excavation order while displaying the block")
		for width in [1440, 960]:
			t.root.size = Vector2i(width, 900 if width == 1440 else 640)
			g.camera.position = g.tile_center(ore)
			await t.settle()
			t.check(t.root.get_visible_rect().encloses(g.entity_panel.get_global_rect()), "Block information fits both viewport sizes")
			if t.native and mineral == 2:
				await RenderingServer.frame_post_draw
				t.root.get_texture().get_image().save_png("/tmp/law3-block-details-%d.png" % width)
		g.create_worker(Vector2i(36, 13))
		t.advance_until(func():
			g.update_entity_panel()
			return g.entity_details.text.contains("挖掘中") and g.entity_details.text.contains("%"), 10, "An open block inspector updates as a worker excavates")
		t.advance_until(func(): return g.mined == 1, 20, "Inspection does not interfere with actual excavation")
		await t.settle()
		t.check(g.entity_title.text == "空地" and g.entity_details.text == "可通行", "After excavation the same selected cell updates to empty ground without stale ore information")
		t.root.size = Vector2i(1440, 900)

	t.scenario("Terrain selection respects water, fog, UI and drag orders", 0)
	var water: Vector2i = g.water_sources.keys()[0]
	g.camera.position = g.tile_center(water)
	await t.settle()
	await t.click_world(g.tile_center(water))
	t.check(g.entity_title.text == "水源" and g.entity_details.text.contains("不可通行"), "Water is identified as a source, not empty walkable ground")
	await t.click(g.pause_button.get_global_rect().get_center())
	t.check(g.entity_title.text == "水源", "Toolbar clicks do not replace the selected terrain")
	var close: Button
	for button in g.entity_panel.find_children("*", "Button", true, false):
		if button.tooltip_text == "关闭属性（Esc）":
			close = button
	await t.click(close.get_global_rect().get_center())
	t.check(not g.entity_panel.visible, "Closing the terrain inspector does not click through to the world")
	g.camera.position = g.tile_center(Vector2i(60, 40))
	await t.settle()
	await t.click_world(g.tile_center(Vector2i(60, 40)))
	t.check(not g.entity_panel.visible, "Unexplored terrain never reveals its mineral through the inspector")
	g.camera.position = g.tile_center(g.BASE)
	await t.settle()
	var stroke: Array[Vector2i] = [ore, ore + Vector2i.DOWN]
	await t.drag_world(stroke)
	t.check(not g.entity_panel.visible, "Area designation remains a drag operation rather than opening an arbitrary tile")
	g.create_worker(Vector2i(36, 13))
	t.advance_until(func(): return g.mined == 2, 30, "Dragging still designates and excavates both blocks")

func check_material_delivery(t) -> void:
	var g = t.game
	# Inspect real moving cargo and both warehouses; screenshots verify each material's artwork.
	for entry in preload("res://tests/production_behaviors.gd").INPUT_ROUTES:
		t.scenario("Material icons and live delivery details: " + entry.target, 1)
		var source: Vector2i = g.BASE if entry.source == "" else P
		var target := Vector2i(34, 11)
		if entry.source != "":
			t.station(entry.source, source)
		t.station(entry.target, target)
		g.add_stock(source, entry.item, entry.amount)
		g.adjust_production(target, 1)
		var carried := "搬运  %s × %s" % [g.item_name(entry.item), String.num(entry.amount, 1)]
		t.advance_until(func():
			g.select_worker(0)
			return g.entity_details.text.contains(carried) and g.workers[0].pos.distance_to(Vector2(source)) > 0.8, 15, "Worker picks up the requested material and leaves its source")
		for width in [1440, 960]:
			t.root.size = Vector2i(width, 900 if width == 1440 else 640)
			g.camera.zoom = Vector2.ONE * 2.0
			g.camera.position = g.tile_center(g.workers[0].pos)
			await t.settle()
			await t.click_world(g.tile_center(g.workers[0].pos) + Vector2(0, -7))
			t.check(g.entity_details.text.contains(carried), "Clicking the visible carrier shows the correct item and quantity")
			t.check(t.root.get_visible_rect().encloses(g.entity_panel.get_global_rect()), "Cargo details stay within the viewport")
			if t.native:
				await RenderingServer.frame_post_draw
				t.root.get_texture().get_image().save_png("/tmp/law3-material-%s-%d.png" % [entry.target, width])
		g.camera.zoom = Vector2.ONE
		g.camera.position = g.tile_center(g.BASE)
		g.adjust_production(target, -1)
		t.advance_until(func(): return g.stock_at(target, entry.item) == entry.amount, 10, "Carried material reaches the destination without being consumed by a stopped order")
		await t.settle()
		await t.click_world(g.tile_center(target + Vector2i.RIGHT) + Vector2(0, 16))
		t.check(g.entity_title.text == g.building_name(entry.target) and g.entity_details.text.contains(g.item_name(entry.item)), "Destination inspector shows the material in its own warehouse")
		t.root.size = Vector2i(1440, 900)

func check_building_rows(t) -> void:
	var g = t.game
	t.root.size = Vector2i(1440, 900)
	# A row spanning open ground and ore must remain pickable while workers clear it.
	t.scenario("Ore-covered row remains inspectable through excavation", 1)
	t.materials(g.BED_BLOCKS * 2)
	var covered_row: Array[Vector2i] = [Vector2i(36, 13), Vector2i(38, 13)]
	await choose_building(t, "bed")
	await t.drag_world(covered_row)
	t.check(g.player_blocks == 0, "Dragging over ore places both funded blueprints")
	for width in [1440, 960]:
		t.root.size = Vector2i(width, 900 if width == 1440 else 640)
		g.camera.zoom = Vector2.ONE * (1.0 if width == 1440 else 0.65)
		await t.settle()
		await t.click_world(g.tile_center(Vector2i(39, 13)))
		t.check(g.entity_title.text == "床 · 建造中", "Clicking the far cell over ore opens the blueprint at either viewport size")
		if t.native:
			t.check(g.world_view.hover_frame.visible and g.world_view.hover_frame.size.x > g.CELL, "Native hover finds the blueprint above its unmined blocks")
			await RenderingServer.frame_post_draw
			t.root.get_texture().get_image().save_png("/tmp/law3-behaviors-ore-blueprint-%d.png" % width)
	t.advance_until(func(): return g.beds.has(covered_row[0]) and g.beds.has(covered_row[1]) and g.delivered == 3, 240, "Worker clears and completes both beds, including normal rest breaks")
	await t.settle()
	t.check(g.entity_title.text == "床" and g.delivered == 3 and g.player_blocks == 3, "Selected blueprint becomes a bed after clearing the entire row, retaining all mined ore")
	g.camera.zoom = Vector2.ONE
	t.root.size = Vector2i(1440, 900)

	# All blueprints share the same drag, footprint spacing, payment and completion contract.
	for kind in g.BUILDING_KINDS:
		if kind in g.BELT_KINDS or kind in g.LINE_KINDS:
			continue
		t.scenario("Mouse-only building row: " + kind)
		for worker in g.workers:
			worker.pos = Vector2(34 + worker.id, 15)
		if kind == "pump":
			for source in [Vector2i(31, 10), Vector2i(33, 10)]:
				g.water_sources[source] = true
				g.terrain[source] = 0
				g.navigation.set_point_solid(source, true)
		var cost: int = g.building_blocks(kind)
		t.building_materials(kind, 3)
		await choose_building(t, kind)
		var stroke: Array[Vector2i] = [P, P + Vector2i(4, 0)]
		await t.drag_world(stroke, false, false, "/tmp/law3-behaviors-row-preview.png" if kind == "bed" else "")
		t.check(g.player_blocks == 0 and g.tool_buttons[kind].disabled, "Fast drag fills the row at footprint spacing and charges once")
		for i in 3:
			await t.click_world(g.tile_center(P + Vector2i(i * 2 + 1, 0)))
			t.check(g.entity_title.text == g.building_name(kind) + " · 建造中", "Every building's far footprint cell opens its blueprint")
		g.simulate(150)
		await t.settle()
		for i in 3:
			await t.click_world(g.tile_center(P + Vector2i(i * 2 + 1, 0)) + Vector2(0, 16))
			t.check(g.entity_title.text == g.building_name(kind), "All row blueprints complete with empty inventory")
		t.check(g.player_blocks == 0, "Batch construction does not charge again")

	# Axis locking must not jump rows due to small perpendicular mouse movement.
	for endpoint in [Vector2i(28, 15), Vector2i(28, 11)]:
		t.scenario("Vertical building row in either drag direction", 0)
		t.materials(g.BED_BLOCKS * 5)
		await choose_building(t, "bed")
		var start := Vector2i(28, 11) if endpoint.y == 15 else Vector2i(28, 15)
		var stroke: Array[Vector2i] = [start, start + Vector2i(0, signi(endpoint.y - start.y)), endpoint + Vector2i.RIGHT]
		await t.drag_world(stroke)
		t.check(g.player_blocks == 0, "Vertical drag follows the first axis and uses one-row spacing")
		for y in range(11, 16):
			await t.click_world(g.tile_center(Vector2i(29, y)))
			t.check(g.entity_title.text == "床 · 建造中", "Reverse or drifting drag leaves a straight complete column")

	t.scenario("Invalid row and canceled gestures never spend materials", 0)
	t.bed(Vector2i(30, 11))
	t.materials(g.BED_BLOCKS * 3)
	await choose_building(t, "bed")
	var row: Array[Vector2i] = [P, Vector2i(32, 11)]
	await t.drag_world(row)
	t.check(g.player_blocks == g.BED_BLOCKS * 3, "Occupied middle footprint rejects the row without partial charges")
	var safe_row: Array[Vector2i] = [Vector2i(28, 15), Vector2i(32, 15)]
	await t.drag_world(safe_row, true)
	t.check(g.player_blocks == g.BED_BLOCKS * 3, "Releasing a building drag over UI cancels the whole preview")
	await t.drag_world(safe_row, false, true)
	t.check(g.player_blocks == g.BED_BLOCKS * 3, "Right-click cancels a building row without a keyboard")
	await t.click_world(g.tile_center(Vector2i(28, 15)))
	t.check(g.player_blocks == g.BED_BLOCKS * 2, "Canceled gesture does not leak into the next single placement")

func choose_building(t, kind: String) -> void:
	await t.settle()
	if not t.game.build_tray.visible:
		await t.click(t.game.furniture_button.get_global_rect().get_center())
	await t.click(t.game.tool_buttons[kind].get_global_rect().get_center())

func check_tracks(t) -> void:
	var g = t.game
	var ui = g.get_node("UI")
	t.root.size = Vector2i(1440, 900)
	# Track gestures must use the same ore-overlay rule as individual building placement.
	t.scenario("Drag and cancel track blueprints over ore", 1)
	t.materials(3)
	await choose_building(t, "belt")
	var covered_path: Array[Vector2i] = [Vector2i(38, 13), Vector2i(36, 13)]
	await t.drag_world(covered_path)
	t.check(g.player_blocks == 0, "Track drag reserves materials for every crossed ore cell")
	g.set_tool("cancel")
	await t.click_world(g.tile_center(Vector2i(38, 13)))
	t.check(g.player_blocks == 1, "Cancel click over solid terrain refunds the covered track cell")
	g.simulate(45)
	g.set_tool("dig")
	await t.click_world(g.tile_center(Vector2i(37, 13)) + Vector2(0, 16))
	t.check(g.entity_title.text == "矿道" and g.delivered == 1 and g.player_blocks == 2, "Remaining track excavates and completes without the canceled cell")
	t.check(g.terrain[Vector2i(38, 13)] != 0, "Canceled track leaves its underlying ore untouched")

	t.scenario("Drag track corners, reuse, reverse, and dismantle", 1)
	g.workers[0].pos = Vector2(P)
	t.materials(7)
	await t.settle()
	if not g.build_tray.visible:
		await t.click(g.furniture_button.get_global_rect().get_center())
	await t.click(g.tool_buttons.belt.get_global_rect().get_center())
	var path: Array[Vector2i] = [Vector2i(36, 15), Vector2i(35, 15), Vector2i(35, 14), Vector2i(35, 13), Vector2i(34, 13), Vector2i(33, 13), g.BASE]
	await t.drag_world(path)
	t.check(g.player_blocks == 1, "Drag charges every new cell once")
	await t.click_world(g.tile_center(path[0]))
	t.check(g.entity_title.text == "矿道 · 建造中", "Single-cell track blueprint can be inspected")
	g.simulate(45)
	await t.settle()
	t.check(g.entity_title.text == "矿道" and g.entity_details.text.contains("通往传送门"), "Dragged corners complete into a connected route without losing selection")
	for zoom in [0.65, 1.0, 1.6]:
		g.camera.zoom = Vector2.ONE * zoom
		await t.settle()
		await t.click_world(g.tile_center(path[0]))
		t.check(g.entity_title.text == "矿道" and ui.belt_controls.visible, "Track remains clickable across zoom levels")
		if t.native:
			t.near(g.world_view.hover_frame.size.x, g.CELL, "Native track hover covers exactly one cell")
	g.camera.zoom = Vector2.ONE
	await t.settle()
	await choose_building(t, "belt")
	var reverse: Array[Vector2i] = [Vector2i(35, 15), Vector2i(36, 15)]
	await t.drag_world(reverse)
	await t.click_world(g.tile_center(path[0]))
	t.check(g.entity_details.text.contains("未连接传送门") and g.player_blocks == 1, "Reverse dragging rewires empty tracks without charging twice")
	var restore: Array[Vector2i] = [Vector2i(36, 15), Vector2i(35, 15), Vector2i(35, 14)]
	await t.drag_world(restore)
	await t.click_world(g.tile_center(path[0]))
	t.check(g.entity_details.text.contains("通往传送门"), "Dragging back into the main line preserves its outgoing direction")
	if t.native:
		await RenderingServer.frame_post_draw
		t.root.get_texture().get_image().save_png("/tmp/law3-behaviors-belt-corners.png")
	await t.click(ui.remove_track.get_global_rect().get_center())
	t.advance_until(func(): return g.player_blocks == 2, 20, "Dismantled track is carried back to storage")
	await t.settle()
	t.check(g.player_blocks == 2 and not g.entity_panel.visible, "Dismantle control refunds the empty track and closes its details")

	# UI release must cancel a stroke, not place behind a panel or retain pointer capture.
	t.materials(10)
	g.set_tool("belt")
	var short_path: Array[Vector2i] = [Vector2i(36, 15), Vector2i(36, 14)]
	await t.drag_world(short_path, true)
	t.check(g.player_blocks == 10, "Releasing a track stroke over UI spends nothing")
	await t.click_world(g.tile_center(Vector2i(36, 15)))
	t.check(g.player_blocks == 9, "Next click places only one tile after canceled UI drag")
	g.set_tool("cancel")
	await t.click_world(g.tile_center(Vector2i(36, 15)))
	t.check(g.player_blocks == 10, "Cancel tool refunds the track blueprint")
	t.materials(1)
	g.set_tool("belt")
	await t.drag_world(short_path)
	t.check(g.player_blocks == 1, "An unaffordable drag does not place a partial line")
	await t.click_world(g.tile_center(Vector2i(36, 15)))
	t.check(g.player_blocks == 0, "Single-tile placement still works after a rejected stroke")

	# Missing intermediate mouse events must not produce an X-first detour or holes.
	t.scenario("Fast diagonal track stroke follows crossed grid cells", 0)
	t.materials(6)
	await choose_building(t, "belt")
	var diagonal: Array[Vector2i] = [Vector2i(34, 15), Vector2i(35, 11)]
	await t.drag_world(diagonal)
	t.check(g.player_blocks == 0, "Fast diagonal gesture places a continuous six-cell stroke")
	for cell in [Vector2i(34, 14), Vector2i(35, 12)]:
		await t.click_world(g.tile_center(cell))
		t.check(g.entity_title.text == "矿道 · 建造中", "Cells crossed by the pointer, not an arbitrary horizontal-first detour, receive blueprints")

	t.scenario("Track backtracking and right-click cancel", 0)
	t.materials(5)
	await choose_building(t, "belt")
	var backtrack: Array[Vector2i] = [Vector2i(36, 15), Vector2i(33, 15), Vector2i(35, 15)]
	await t.drag_world(backtrack, false, true)
	t.check(g.player_blocks == 5, "Right-click discards a track preview without charging")
	await t.drag_world(backtrack)
	t.check(g.player_blocks == 3, "Dragging back retracts pending cells rather than reversing the preview")

	# Occupied tracks protect ore while worker-over-track picking and nearby buildings stay correct.
	t.scenario("Loaded track inspector and visible freight", 1)
	t.bed(P)
	for x in range(33, 37):
		t.belt(Vector2i(x, 13), Vector2i.LEFT)
	g.workers[0].pos = Vector2(36, 13)
	g.designate(Vector2i(37, 13), Vector2i(37, 13))
	t.advance_until(func(): return not g.belt_cargo.is_empty(), 20, "Miner has left ore on the track")
	g.set_tool("dig")
	for size in [Vector2i(1440, 900), Vector2i(960, 640)]:
		t.root.size = size
		await t.settle()
		await t.click_world(g.tile_center(Vector2i(36, 13)) + Vector2(16, 16))
		t.check(g.entity_title.text == "矿道" and g.entity_details.text.contains(g.workers[0].name), "Loaded track details identify the ore owner")
		t.check(ui.remove_track.disabled, "Occupied track disables destructive controls")
		t.check(t.root.get_visible_rect().encloses(g.entity_panel.get_global_rect()) and g.entity_panel.get_global_rect().encloses(ui.belt_controls.get_global_rect()), "Track details and controls fit both window sizes")
		if t.native:
			await RenderingServer.frame_post_draw
			t.root.get_texture().get_image().save_png("/tmp/law3-behaviors-belt-%d.png" % size.x)
		await t.click_world(g.tile_center(Vector2i(36, 13)) + Vector2(0, -7))
		t.check(g.entity_title.text == g.workers[0].name, "Worker remains the first picked object over a track")
		await t.click_world(g.tile_center(P + Vector2i.RIGHT))
		t.check(g.entity_title.text == "床", "Adding single-cell tracks preserves existing two-cell building picking")
	g.simulate(0.25)
	await t.settle()
	if t.native:
		await RenderingServer.frame_post_draw
		t.root.get_texture().get_image().save_png("/tmp/law3-behaviors-belt-moving.png")
	t.advance_until(func(): return g.delivered == 1, 5, "Visible cargo completes delivery")

func check_track_receivers(t) -> void:
	var g = t.game
	var production = preload("res://tests/production_behaviors.gd").new()
	# Native picking must allow a stroke to end on either half of a receiver, not build over it.
	for entry in production.INPUT_ROUTES:
		t.scenario("Drag track into production building: " + entry.target, 1)
		t.root.size = Vector2i(1440, 900)
		var source: Vector2i = g.BASE if entry.source == "" else P
		var target := Vector2i(34, 11)
		if entry.source != "":
			t.station(entry.source, source)
		t.station(entry.target, target)
		t.materials(1)
		g.add_stock(source, entry.item, entry.amount)
		g.workers[0].pos = Vector2(source)
		var endpoint := target + (Vector2i.RIGHT if entry.item is String else Vector2i.ZERO)
		for x in range(29, endpoint.x + 1):
			t.belt(Vector2i(x, 12), Vector2i.RIGHT if x < endpoint.x else Vector2i.ZERO)
		await choose_building(t, "belt")
		var path: Array[Vector2i] = [endpoint + Vector2i.DOWN, endpoint]
		var blocks: int = g.player_blocks
		await t.drag_world(path)
		t.check(g.player_blocks == blocks, "Dropping an existing track onto a building does not spend materials")
		g.set_tool("dig")
		await t.click_world(g.tile_center(path[0]))
		t.check(g.entity_title.text == "矿道" and g.entity_details.text.contains("通往" + g.building_name(entry.target)), "Mouse stroke connects the existing track to the chosen building")
		g.adjust_production(target, 1)
		t.advance_until(func(): return production.track_shows_item(g, entry.item), 10, "Track inspector exposes the actual ingredient and batch quantity")
		g.adjust_production(target, -1)
		var loaded := endpoint + Vector2i.DOWN
		t.advance_until(func():
			g.select_entity(loaded)
			return g.entity_details.text.contains(g.item_name(entry.item) + " ×"), 5, "Cargo travels away from its carrier to the receiving end of the track")
		for width in [1440, 960]:
			t.root.size = Vector2i(width, 900 if width == 1440 else 640)
			g.camera.zoom = Vector2.ONE * 2.0
			g.camera.position = g.tile_center(loaded)
			await t.settle()
			await t.click_world(g.tile_center(loaded) + Vector2(16, 16))
			t.check(g.entity_title.text == "矿道" and g.entity_details.text.contains(g.item_name(entry.item) + " ×"), "Clicking loaded track shows the matching material at both viewport sizes")
			t.check(g.get_node("UI").remove_track.disabled, "Track carrying production materials cannot be dismantled")
			t.check(t.root.get_visible_rect().encloses(g.entity_panel.get_global_rect()), "Generic freight details fit the viewport")
			if t.native:
				await RenderingServer.frame_post_draw
				t.root.get_texture().get_image().save_png("/tmp/law3-track-%s-%d.png" % [entry.target, width])
		t.advance_until(func(): return g.stock_at(target, entry.item) == entry.amount, 5, "Visible cargo unloads into the connected building")
		g.camera.zoom = Vector2.ONE
		g.camera.position = g.tile_center(g.BASE)
		await t.settle()
		await t.click_world(g.tile_center(endpoint) + Vector2(0, 16))
		t.check(g.entity_title.text == g.building_name(entry.target) and g.entity_details.text.contains(g.item_name(entry.item)), "Clicking the receiving footprint shows the delivered goods in its warehouse")
		t.root.size = Vector2i(1440, 900)

func choose_report_filter(t, report: Window, button: OptionButton, index: int) -> void:
	await t.click(Vector2(report.position) + button.get_global_rect().get_center())
	var popup := button.get_popup()
	t.check(popup.visible, "Click opens the report filter menu")
	var keys := [KEY_HOME]
	for i in index + 1:
		keys.append(KEY_DOWN)
	keys.append(KEY_ENTER)
	for key in keys:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = true
		t.root.push_input(event, true)
		event = event.duplicate()
		event.pressed = false
		t.root.push_input(event, true)
		await t.settle()
	t.check(button.selected == index, "Report filter selects requested row %d (got %d)" % [index, button.selected])
