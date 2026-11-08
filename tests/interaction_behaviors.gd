extends RefCounted

const P := Vector2i(28, 11)

func run(t) -> void:
	await check_world_commands(t)
	await check_wage_controls(t)
	await check_fee_controls(t)
	await check_demolition_commands(t)
	await check_research_controls(t)
	await check_save_controls(t)
	await check_unbounded_picking(t)
	await check_large_footprints(t)
	await check_tracks(t)
	await check_track_receivers(t)
	await check_power_interactions(t)
	await check_industry_controls(t)
	await check_alerts(t)

func check_world_commands(t) -> void:
	var g = t.game
	var ui = g.hud
	t.fixtures.scenario("Viewport selection, overlap and HUD interception")
	t.fixtures.bed(P)
	t.fixtures.materials(100)
	for sample in [{"tool": "dig", "zoom": 0.65}, {"tool": "cancel", "zoom": 1.6}, {"tool": "bed", "zoom": 1.0}]:
		g.world_view.camera.zoom = Vector2.ONE * sample.zoom
		g.set_tool(sample.tool)
		await t.input.settle()
		await t.input.click_world(g.tile_center(P + Vector2i.RIGHT))
		t.check(g.interaction.selected_entity == P and ui.entity_panel.visible, "The building footprint selects its inspector even with another tool active")
		if t.native and sample.tool == "dig":
			t.check(g.world_view.hover_frame.visible, "Native hover reaches the same building as clicking")
	g.world_view.camera.zoom = Vector2.ONE
	g.set_tool("dig")
	await t.input.click_world(g.tile_center(g.BASE) + Vector2(0, -32))
	t.check(g.interaction.selected_entity == g.BASE, "The portal artwork uses the native picking route")
	g.world.workers[0].pos = Vector2(P)
	g.world.workers[1].pos = Vector2(P) + Vector2(0, 0.1)
	await t.input.settle()
	var overlap: Vector2 = g.tile_center(P) + Vector2(0, -7)
	await t.input.click_world(overlap)
	t.check(g.interaction.selected_worker == 1, "The visible front worker wins over a worker and building behind it")
	g.world.workers[0].pos.y += 0.2
	await t.input.settle()
	await t.input.click_world(overlap)
	t.check(g.interaction.selected_worker == 0, "Picking follows the changed visible depth")
	g.world.workers[0].pos = Vector2(34, 15)
	g.world.workers[1].pos = Vector2(35, 15)
	await t.input.settle()
	await t.input.click_world(overlap)
	t.check(g.interaction.selected_entity == P, "Moving workers exposes the building underneath")
	await t.input.click(ui.pollution_button.get_global_rect().get_center())
	await t.input.click_world(g.tile_center(g.world.workers[0].pos) + Vector2(0, -7))
	t.check(g.interaction.pollution_visible and g.interaction.selected_worker == 0, "The overlay does not intercept worker picking")
	await t.input.click(ui.pollution_button.get_global_rect().get_center())
	await t.input.click(ui.speed_buttons[2].get_global_rect().get_center())
	t.check(g.interaction.speed == 2 and g.interaction.selected_worker == 0, "Speed controls change simulation speed without clicking through")
	await t.input.click(ui.pause_button.get_global_rect().get_center())
	t.check(g.interaction.simulation_paused and g.interaction.selected_worker == 0, "Pause does not replace the selected world object")
	t.check(not g.world_view.hover_frame.visible, "The HUD blocks world hover")
	await t.input.press_key(KEY_SPACE)
	t.check(not g.interaction.simulation_paused, "The keyboard command resumes simulation")
	await t.input.screenshot("/tmp/law3-input-world.png")

	t.fixtures.scenario("Building eligibility, cancellation and a rapid mining click")
	t.fixtures.materials(6, 2)
	await t.input.settle()
	await t.input.click(ui.category_buttons.life.get_global_rect().get_center())
	await t.input.click(ui.tool_buttons.bed.get_global_rect().get_center())
	t.check(ui.tool_buttons.bed.disabled and g.interaction.tool == "dig", "A material shortage blocks selecting the building tool")
	await t.input.click_world(g.tile_center(P))
	t.check(not g.building_at(P) and g.stock_at(g.BASE, 2) == 6, "A rejected placement neither creates a blueprint nor spends other materials")
	t.fixtures.building_materials("bed")
	await t.input.choose_building("bed")
	await t.input.click_world(g.tile_center(P))
	t.check(g.building_at(P) and ui.tool_buttons.bed.disabled, "A placement immediately exhausts its material allowance")
	await t.input.click_world(g.tile_center(P + Vector2i(2, 0)))
	t.check(not g.building_at(P + Vector2i(2, 0)), "The selected tool cannot place beyond the affordable prefix")
	await t.input.click(ui.tool_buttons.cancel.get_global_rect().get_center())
	await t.input.click_world(g.tile_center(P + Vector2i.RIGHT))
	t.check(not g.building_at(P) and not ui.tool_buttons.bed.disabled, "Cancellation through the footprint releases the blueprint and its allowance")
	await t.input.choose_building("bed")
	await t.input.click(g.get_global_transform_with_canvas() * g.tile_center(P), MOUSE_BUTTON_RIGHT)
	t.check(g.interaction.tool == "dig" and not g.building_at(P), "Right-click exits an armed building tool even before dragging a preview")
	await t.input.click(ui.tool_buttons.dig.get_global_rect().get_center())
	var rapid := InputEventMouseButton.new()
	rapid.position = g.get_global_transform_with_canvas() * g.tile_center(Vector2i(37, 13))
	await t.input.move_to(rapid.position)
	rapid.button_index = MOUSE_BUTTON_LEFT
	rapid.pressed = true
	t.tree.root.push_input(rapid, true)
	rapid = rapid.duplicate()
	rapid.pressed = false
	t.tree.root.push_input(rapid, true)
	await t.input.settle()
	g.simulate(30)
	t.check(g.world.delivered == 1, "Press and release in one tick still issues an actual excavation")

	t.fixtures.scenario("Selected blueprint survives completion", 1)
	t.fixtures.building_materials("farm")
	await t.input.choose_building("farm")
	await t.input.click_world(g.tile_center(P))
	var corner: Vector2i = g.building_cells(P, "farm").back()
	await t.input.click_world(g.tile_center(corner))
	t.check(g.interaction.selected_entity == P, "The far footprint corner selects the blueprint")
	await t.input.screenshot("/tmp/law3-input-blueprint.png")
	t.advance_until(func(): return not g.world.sites.has(P), g.HOUR_SECONDS * 12, "The ordered blueprint completes using actual deliveries and labor")
	await t.input.settle()
	t.check(g.interaction.selected_entity == P and ui.entity_panel.visible and g.building_kind_at(corner) == "farm", "Completion preserves the selected building without reselection")

	# Daily output and a finite queue are two different player commands, not two content entries.
	for kind in ["pump", "printer"]:
		t.fixtures.scenario("Production order controls: " + kind, 0)
		t.fixtures.station(kind, P)
		await t.input.settle()
		await t.input.click_world(g.tile_center(P + Vector2i.RIGHT))
		await t.input.click(ui.add_order.get_global_rect().get_center())
		var setting := "queue" if kind == "printer" else "daily_output"
		var amount: int = 1 if kind == "printer" else g.PRODUCTS[kind].amount
		t.check(g.world.benches[P][setting] == amount, "Plus issues the actual production command in its proper units")
		await t.input.click(ui.remove_order.get_global_rect().get_center())
		t.check(g.world.benches[P][setting] == 0, "Minus cancels the production setting")

func check_wage_controls(t) -> void:
	var g = t.game
	var ui = g.hud
	t.fixtures.scenario("Direct wage selection and filtered brush commands do not leak into world actions", 0)
	var other := Vector2i(31, 11)
	var site := Vector2i(34, 11)
	var ore := Vector2i(37, 13)
	t.fixtures.station("pump", P)
	t.fixtures.station("mill", other)
	t.fixtures.building_materials("bed")
	g.place_building(site, "bed")
	g.designate(ore, ore)
	# Entity inspection and terrain inspection are distinct native input paths.
	for target in [{"p": P, "point": P + Vector2i.RIGHT, "mining": false},
			{"p": site, "point": site + Vector2i.RIGHT, "mining": false},
			{"p": ore, "point": ore, "mining": true}]:
		await t.input.click_world(g.tile_center(target.point))
		t.check(ui.wage_controls.visible, "The selected labor target exposes direct wage choices")
		await t.input.click(ui.wage_selector.buttons[3].get_global_rect().get_center())
		t.near(g.wage_settings(target.p, target.mining).get("wage", 0), 3, "Clicking a wage digit changes this target without clicking through")
		await t.input.click(ui.wage_selector.buttons[3].get_global_rect().get_center())
		t.check(ui.wage_selector.buttons[3].button_pressed, "Repeating the selected wage leaves a single visible current value")
	await t.input.screenshot("/tmp/law3-input-wage-details.png")
	await t.input.click(ui.tool_buttons.wage.get_global_rect().get_center())
	await t.input.press_key(KEY_8)
	await t.input.click_world(g.tile_center(P + Vector2i.RIGHT))
	await t.input.click_world(g.tile_center(other + Vector2i.RIGHT))
	t.check(g.interaction.tool == "wage" and not ui.entity_panel.visible, "Painting stays in tool mode instead of opening an inspector")
	t.near(g.wage_settings(P).get("wage", 0), 8, "A native building click applies the chosen brush wage")
	t.near(g.wage_settings(other).get("wage", 0), 8, "The same brush can continue onto another building")
	await t.input.click(ui.wage_filters.build.get_global_rect().get_center())
	await t.input.click(ui.brush_selector.buttons[4].get_global_rect().get_center())
	var area: Array[Vector2i] = [P, ore]
	await t.input.drag_world(area)
	t.check(g.wage_settings(site).get("wage", 0) == 4 and g.wage_settings(P).get("wage", 0) == 8 and g.wage_settings(ore, true).get("wage", 0) == 3,
		"A construction-only stroke changes blueprints but not mining or operating wages")
	await t.input.click(ui.wage_filters.mine.get_global_rect().get_center())
	await t.input.press_key(KEY_2)
	var mining_area: Array[Vector2i] = [ore, ore + Vector2i.DOWN]
	await t.input.drag_world(mining_area)
	t.check(g.wage_settings(ore, true).get("wage", 0) == 2 and not g.world.mining_contracts.has(ore + Vector2i.DOWN), "A mining wage stroke edits existing orders without designating new ore")
	await t.input.click(ui.wage_filters.all.get_global_rect().get_center())
	await t.input.press_key(KEY_9)
	await t.input.drag_world(area, true)
	t.check(g.wage_settings(site).get("wage", 0) == 4 and g.wage_settings(ore, true).get("wage", 0) == 2, "Releasing over the HUD cancels the wage stroke")
	await t.input.screenshot("/tmp/law3-input-wages-1440.png")
	if t.native:
		t.tree.root.size = Vector2i(960, 640)
		g.world_view.camera.position = g.tile_center(Vector2i(34, 13))
		await t.input.settle()
		await t.input.screenshot("/tmp/law3-input-wages-960.png")
		t.tree.root.size = Vector2i(1440, 900)
		g.world_view.camera.position = g.tile_center(g.BASE)
		await t.input.settle()
	await t.input.drag_world(area)
	t.check(g.wage_settings(P).get("wage", 0) == 9 and g.wage_settings(site).get("wage", 0) == 9 and g.wage_settings(ore, true).get("wage", 0) == 9,
		"An all-target stroke applies one wage across the existing labor opportunities")
	await t.input.press_key(KEY_ESCAPE)
	await t.input.click_world(g.tile_center(P + Vector2i.RIGHT))
	t.check(ui.entity_panel.visible and ui.wage_selector.buttons[9].button_pressed, "Leaving the brush restores normal picking and shows the actual edited wage")
	t.check(g.world.benches[P].daily_output == 0 and g.world.sites.has(site), "Wage controls neither start production nor cancel construction")

func check_fee_controls(t) -> void:
	var g = t.game
	var ui = g.hud
	t.fixtures.fee_controls_world()
	var shop := Vector2i(31, 11)
	var service := Vector2i(34, 11)
	var site := Vector2i(37, 13)
	g.place_building(site, "bed")
	g.set_wage(shop, 6)
	await t.input.click_world(g.tile_center(P + Vector2i.RIGHT))
	await t.input.click(ui.fee_selector.buttons[3].get_global_rect().get_center())
	t.near(g.base_fee(P), 3, "The bottom fee selector changes the inspected bed's actual price")
	await t.input.click(ui.tool_buttons.fee.get_global_rect().get_center())
	await t.input.press_key(KEY_7)
	await t.input.click_world(g.tile_center(shop + Vector2i.RIGHT))
	t.check(g.base_fee(shop) == 7 and g.wage_settings(shop).get("wage", 0) == 6, "The fee brush changes price without changing a building's wage")
	await t.input.click(ui.fee_filters.bed.get_global_rect().get_center())
	await t.input.press_key(KEY_2)
	var area: Array[Vector2i] = [P, site + Vector2i.RIGHT]
	await t.input.drag_world(area)
	t.check(g.base_fee(P) == 2 and g.base_fee(site) == 2 and g.base_fee(shop) == 7 and g.base_fee(service) == g.SERVICES.hospital.price,
		"A bed-only fee stroke edits completed beds and blueprint settings without repricing goods or services")
	await t.input.press_key(KEY_9)
	await t.input.drag_world(area, true)
	t.near(g.base_fee(P), 2, "A fee stroke released over the HUD makes no price change")
	await t.input.click(ui.fee_filters.all.get_global_rect().get_center())
	await t.input.screenshot("/tmp/law3-input-fees-1440.png")
	if t.native:
		t.tree.root.size = Vector2i(960, 640)
		g.world_view.camera.position = g.tile_center(Vector2i(34, 13))
		await t.input.settle()
		await t.input.screenshot("/tmp/law3-input-fees-960.png")
		t.tree.root.size = Vector2i(1440, 900)
		g.world_view.camera.position = g.tile_center(g.BASE)
		await t.input.settle()
	await t.input.press_key(KEY_4)
	await t.input.drag_world(area)
	t.check(g.base_fee(P) == 4 and g.base_fee(shop) == 4 and g.base_fee(service) == 4 and g.base_fee(site) == 4,
		"The independent all-fees brush applies one price across chargeable targets")
	await t.input.press_key(KEY_P)
	await t.input.press_key(KEY_8)
	await t.input.click_world(g.tile_center(shop + Vector2i.RIGHT))
	t.check(g.wage_settings(shop).get("wage", 0) == 8 and g.base_fee(shop) == 4, "Switching back to wages does not overwrite a building's fee")
	await t.input.press_key(KEY_F)
	t.check(g.interaction.brush_fee == 4, "The fee brush retains its own chosen value when switching modes")
	var saved: Dictionary = g.capture_snapshot()
	t.check(saved.ok and g.restore_snapshot(saved.data).ok and g.base_fee(P) == 4 and g.base_fee(site) == 4 and g.interaction.brush_fee == 4,
		"Saving preserves actual building prices, blueprint prices and the separate fee brush")
	await t.input.click_world(g.tile_center(shop + Vector2i.RIGHT))
	t.check(ui.fee_selector.buttons[4].button_pressed and ui.wage_selector.buttons[8].button_pressed, "The bottom selectors independently reflect the inspected price and wage")
	await t.input.screenshot("/tmp/law3-input-fee-details.png")

func check_demolition_commands(t) -> void:
	var g = t.game
	var ui = g.hud
	t.fixtures.scenario("Cancel and demolition are separate commands; right-click does not issue either", 0)
	t.fixtures.bed(P)
	var storage := Vector2i(32, 11)
	var blueprint := Vector2i(34, 13)
	var ore := Vector2i(37, 13)
	t.fixtures.station("storage_box", storage)
	t.fixtures.building_materials("bed")
	g.place_building(blueprint, "bed")
	g.designate(ore, ore)
	await t.input.press_key(KEY_C)
	await t.input.click_world(g.tile_center(P + Vector2i.RIGHT))
	t.check(g.world.beds.has(P) and ui.entity_panel.visible, "C inspects an existing building rather than demolishing it")
	await t.input.click(g.get_global_transform_with_canvas() * g.tile_center(blueprint), MOUSE_BUTTON_RIGHT)
	t.check(g.interaction.tool == "cancel" and g.building_at(blueprint), "Right-click neither switches tools nor cancels the object underneath")
	await t.input.press_key(KEY_X)
	await t.input.click(g.get_global_transform_with_canvas() * g.tile_center(P), MOUSE_BUTTON_RIGHT)
	t.check(g.interaction.tool == "demolish" and g.world.beds.has(P), "Right-click does not leave demolition mode or remove buildings")
	await t.input.click_world(g.tile_center(blueprint))
	await t.input.click_world(g.tile_center(ore))
	t.check(g.building_at(blueprint) and g.world.mining_contracts.has(ore), "X cannot cancel a blueprint or a mining order")
	await t.input.click(ui.tool_buttons.cancel.get_global_rect().get_center())
	await t.input.click_world(g.tile_center(blueprint + Vector2i.RIGHT))
	await t.input.click_world(g.tile_center(ore))
	t.check(not g.building_at(blueprint) and not g.world.mining_contracts.has(ore), "The cancel toolbar command removes blueprints and mining orders")
	await t.input.click(ui.tool_buttons.demolish.get_global_rect().get_center())
	var stroke: Array[Vector2i] = [P + Vector2i.RIGHT, storage]
	await t.input.drag_world(stroke, true)
	t.check(g.world.beds.has(P) and g.world.benches.has(storage), "Releasing a demolition stroke over the HUD removes nothing")
	await t.input.move_to(g.get_global_transform_with_canvas() * g.tile_center(P + Vector2i.RIGHT))
	await t.input.screenshot("/tmp/law3-input-tools.png")
	await t.input.click_world(g.tile_center(P + Vector2i.RIGHT))
	t.check(not g.world.beds.has(P) and g.world.benches.has(storage), "X removes the whole building through its far footprint cell")
	var storage_stroke: Array[Vector2i] = [storage, storage + Vector2i.DOWN]
	await t.input.drag_world(storage_stroke)
	t.check(not g.world.benches.has(storage), "The same demolition tool supports a ground stroke")
	await t.input.press_key(KEY_G)
	await t.input.click_world(g.tile_center(g.BASE))
	t.check(g.interaction.selected_entity == g.BASE, "The portal remains available after demolition")

func check_research_controls(t) -> void:
	var g = t.game
	var ui = g.hud
	var other := Vector2i(31, 11)
	t.fixtures.research_world("Research commands through technology tiles and an individual inspector", ["tools", "logistics"], 1, {"tools": g.Technology.PROJECTS.tools.points - 1})
	t.fixtures.research_materials(P, "tools")
	t.fixtures.research_materials(other, "logistics")
	t.fixtures.building_materials("bench")
	await t.input.settle()
	await t.input.click(ui.research_button.get_global_rect().get_center())
	var panel = ui.research_panel
	var inventory: Dictionary = g.resource_inventory()
	var orders: int = g.world.mining_contracts.size()
	await t.input.choose_technology("finance")
	t.check(g.world.benches[P].research == "" and g.world.benches[other].research == "", "A locked project cannot issue a research order")
	await t.input.choose_technology("population")
	t.check(g.world.benches[P].research == "population" and g.world.benches[other].research == "population", "Population can be ordered before tools is complete")
	await t.input.choose_technology("tools")
	t.check(g.world.benches[P].research == "tools" and g.world.benches[other].research == "tools", "The first tile click starts research on both benches")
	await t.input.choose_technology("tools")
	t.check(g.world.benches[P].research == "" and g.world.benches[other].research == "", "The second tile click pauses the assigned project")
	await t.input.choose_technology("logistics")
	await t.input.choose_technology("finance")
	t.check(g.world.benches[P].research == "logistics" and g.world.benches[other].research == "logistics", "Inspecting a locked project cannot replace the active research order")
	await t.input.choose_technology("tools")
	t.check(g.resource_inventory() == inventory and g.world.mining_contracts.size() == orders, "Project controls neither consume goods without labor nor click through to excavation")
	var zoom: Vector2 = g.world_view.camera.zoom
	await t.input.choose_technology("hygiene")
	t.check(panel.selected == "hygiene" and g.world_view.camera.zoom == zoom, "Tree scrolling reaches another project without zooming the world")
	await t.input.screenshot("/tmp/law3-input-research.png")
	await t.input.press_key(KEY_ESCAPE)
	await t.input.click_world(g.tile_center(P + Vector2i.RIGHT))
	await t.input.click(ui.research_choice.get_global_rect().get_center())
	await t.input.press_key(KEY_DOWN)
	await t.input.press_key(KEY_ENTER)
	t.check(g.world.benches[P].research == "" and g.world.benches[other].research == "tools", "The inspector can pause one bench without affecting the other")
	await t.input.click(ui.research_button.get_global_rect().get_center())
	await t.input.choose_technology("tools")
	t.check(g.world.benches[P].research == "" and g.world.benches[other].research == "", "A tile click pauses a partially assigned project")
	await t.input.choose_technology("tools")
	t.advance_until(func(): return g.is_building_unlocked("bench"), 120, "The UI research order completes through actual labor")
	await t.input.choose_technology("logistics")
	await t.input.choose_technology("tools")
	t.check(g.world.benches[P].research == "logistics", "Completed technology cannot replace an active research order")
	await t.input.press_key(KEY_ESCAPE)
	var notice: Button = t.alert_button("研究完成：工具制造")
	t.check(notice != null, "Completing research offers a notification in the existing alert rail")
	if notice != null:
		await t.input.screenshot("/tmp/law3-input-research-complete.png")
		await t.input.click(notice.get_global_rect().get_center())
		t.check(panel.visible and panel.selected == "tools" and g.world.mining_contracts.size() == orders,
			"The completion notification opens its technology without ordering excavation behind the HUD")
		t.check(t.alert_button("研究完成：工具制造") == null, "Reading a completion notification dismisses it")
		await t.input.press_key(KEY_ESCAPE)
	await t.input.choose_building("bench")
	t.check(g.interaction.tool == "bench", "The newly unlocked building becomes selectable through its toolbar")

func check_save_controls(t) -> void:
	var g = t.game
	var ui = g.hud
	t.fixtures.scenario("Save/load controls preserve the world and native picking", 1)
	var original_directory: String = ui.save_directory
	ui.save_directory = "/tmp/law3-ui-save-%d" % OS.get_process_id()
	ui.last_save_slot = -1
	var ore := Vector2i(37, 13)
	g.designate(ore, ore)
	g.simulate(0.2)
	var before: Dictionary = t.world_observations()
	var was_paused: bool = g.interaction.simulation_paused
	await t.input.press_key(KEY_F9)
	t.check(ui.save_menu.visible and ui.save_action.disabled and ui.backup_action.disabled, "Quick load opens the menu with empty saves unavailable before any slot is chosen")
	await t.input.press_key(KEY_ESCAPE)
	t.check(not ui.save_menu.visible and t.world_observations() == before and g.interaction.simulation_paused == was_paused, "Cancelling the menu leaves the current colony and pause preference intact")
	await t.input.click(ui.save_button.get_global_rect().get_center())
	t.check(ui.save_menu.visible, "The save icon opens the slot menu without world click-through")
	g._process(0.1)
	t.check(t.world_observations() == before, "Opening the save menu suspends simulation without changing the saved pause preference")
	await t.input.choose_save_slot(ui.save_menu, ui.save_slots, 1)
	await t.input.click(Vector2(ui.save_menu.position) + ui.save_action.get_global_rect().get_center())
	t.check(not ui.save_menu.visible and ui.save_status.text == "已保存：存档 2", "Saving to an empty slot closes the menu and reports its player-facing name")
	g.simulate(30)
	var newer: Dictionary = t.world_observations()
	await t.input.click(ui.save_button.get_global_rect().get_center())
	await t.input.click(Vector2(ui.save_menu.position) + ui.save_action.get_global_rect().get_center())
	t.check(ui.save_menu.visible and ui.save_hint.text.contains("覆盖"), "An occupied slot requires confirmation before replacing the saved colony")
	await t.input.press_key(KEY_ESCAPE)
	await t.input.click(ui.load_button.get_global_rect().get_center())
	t.check(ui.save_menu.visible, "The load icon opens the existing-save menu")
	await t.input.click(Vector2(ui.save_menu.position) + ui.save_action.get_global_rect().get_center())
	t.check(ui.save_status.text == "已读取：存档 2" and t.world_observations() == before, "Cancelling overwrite preserves the saved inventory, people and reports")
	g.simulate(30)
	await t.input.click(ui.save_button.get_global_rect().get_center())
	for click in 2:
		await t.input.click(Vector2(ui.save_menu.position) + ui.save_action.get_global_rect().get_center())
	t.check(not ui.save_menu.visible and ui.save_status.text == "已保存：存档 2", "Confirming overwrite updates the selected save")
	g.simulate(5)
	await t.input.press_key(KEY_F9)
	t.check(t.world_observations() == newer, "Quick load uses the selected slot and restores its replacement")
	await t.input.click(ui.load_button.get_global_rect().get_center())
	await t.input.click(Vector2(ui.save_menu.position) + ui.backup_action.get_global_rect().get_center())
	t.check(ui.save_status.text == "已读取：存档 2 · 上一版" and t.world_observations() == before, "The menu restores the previous version without exposing backup files")
	await t.input.click(ui.save_button.get_global_rect().get_center())
	await t.input.choose_save_slot(ui.save_menu, ui.save_slots, 0)
	await t.input.click(Vector2(ui.save_menu.position) + ui.save_action.get_global_rect().get_center())
	await t.input.click(ui.load_button.get_global_rect().get_center())
	await t.input.choose_save_slot(ui.save_menu, ui.save_slots, 1)
	await t.input.click(Vector2(ui.save_menu.position) + ui.save_action.get_global_rect().get_center())
	t.check(t.world_observations() == newer, "Saving another slot does not replace the independently selected colony")
	g.set_tool("cancel")
	await t.input.click_world(g.tile_center(g.world.workers[0].pos) + Vector2(0, -8))
	t.check(g.interaction.selected_worker == 0 and ui.entity_title.text == g.world.workers[0].name, "The reconstructed worker remains inspectable through native picking")
	await t.input.press_key(KEY_F5)
	await t.input.click(ui.load_button.get_global_rect().get_center())
	await t.input.press_key(KEY_ESCAPE)
	var path: String = ui.SaveStore.slot_path(1, ui.save_directory)
	var damaged := FileAccess.open(path, FileAccess.WRITE)
	damaged.store_string("damaged save")
	damaged.close()
	var intact: Dictionary = t.world_observations()
	await t.input.press_key(KEY_F9)
	t.check(ui.save_status.text.begins_with("读取失败") and g.interaction.selected_worker == 0 and t.world_observations() == intact, "A damaged quick load leaves the selected world intact and reports inline instead of opening an error dialog")
	await t.input.click(ui.load_button.get_global_rect().get_center())
	await t.input.click(Vector2(ui.save_menu.position) + ui.save_action.get_global_rect().get_center())
	t.check(ui.save_menu.visible and ui.save_hint.text.begins_with("读取失败") and t.world_observations() == intact, "A failed menu load stays in the menu without replacing the running colony")
	await t.input.click(Vector2(ui.save_menu.position) + ui.backup_action.get_global_rect().get_center())
	t.check(not ui.save_menu.visible and t.world_observations() == intact, "The previous version remains recoverable from the menu after primary corruption")
	await t.input.press_key(KEY_F5)
	await t.input.press_key(KEY_F9)
	t.check(ui.save_status.text.begins_with("已读取") and g.world.workers.size() == 1, "Quick load works again after a failure: " + ui.save_status.text)
	t.tree.root.size = Vector2i(1440, 900)
	for slot in ui.SaveStore.SLOT_COUNT:
		var slot_path: String = ui.SaveStore.slot_path(slot, ui.save_directory)
		for suffix in ["", ".bak"]: DirAccess.remove_absolute(slot_path + suffix)
	DirAccess.remove_absolute(ui.save_directory)
	ui.save_directory = original_directory
	ui.last_save_slot = -1


func check_unbounded_picking(t) -> void:
	var g = t.game
	for sample in [{"cell": Vector2i(-1, -1), "zoom": 0.65, "size": Vector2i(1440, 900)},
			{"cell": Vector2i(65536, -65536), "zoom": 1.6, "size": Vector2i(960, 640)}]:
		var cell: Vector2i = sample.cell
		t.fixtures.scenario("Native input after coordinate rebasing: " + str(cell), 0, true)
		g.ensure_region(Rect2i(cell - Vector2i.ONE * 5, Vector2i.ONE * 12))
		t.fixtures.clear_area(Rect2i(cell - Vector2i.ONE * 4, Vector2i.ONE * 10))
		g.world.terrain[cell] = 2
		g.cache.navigation.set_point_solid(cell, true)
		var bed: Vector2i = cell + Vector2i(2, 0)
		t.fixtures.bed(bed)
		var worker: Dictionary = t.fixtures.hungry_worker(cell + Vector2i(-2, 0))
		t.fixtures.building_materials("bed", 2)
		g.interaction.simulation_paused = true
		g.set_tool("cancel")
		g.world_view.rebuild(g)
		t.tree.root.size = sample.size
		g.world_view.camera.zoom = Vector2.ONE * sample.zoom
		g.world_view.camera.position = g.tile_center(cell)
		g._process(0.0)
		await t.input.settle()
		await t.input.click_world(g.tile_center(cell))
		t.check(g.interaction.selected_tile == cell, "The rebased ground click selects its actual world coordinate")
		if t.native: t.check(g.world_view.hover_frame.visible, "Native hover survives a distant display origin")
		await t.input.click_world(g.tile_center(bed))
		t.check(g.interaction.selected_entity == bed, "Building picking uses the same rebased coordinate as its artwork")
		await t.input.click_world(g.tile_center(worker.pos) + Vector2(0, -7))
		t.check(g.interaction.selected_worker == worker.id, "Worker picking survives rebasing")
		await t.input.click(g.hud.pause_button.get_global_rect().get_center())
		t.check(g.interaction.selected_worker == worker.id, "The HUD intercepts clicks over distant terrain")
		g.interaction.simulation_paused = true
		await t.input.screenshot("/tmp/law3-input-rebased-%d.png" % sample.size.x)
		g.set_tool("dig")
		var stroke: Array[Vector2i] = [cell, cell + Vector2i.RIGHT]
		await t.input.drag_world(stroke)
		t.check(g.world.mining_contracts.has(cell), "A mining drag still targets the rebased world cell")
		g.set_tool("bed")
		await t.input.click_world(g.tile_center(cell + Vector2i(0, 2)))
		t.check(g.building_at(cell + Vector2i(0, 2)), "A blueprint command uses rebased coordinates")
		var hidden: Vector2i = cell + Vector2i(80, 0)
		g.world_view.camera.position = g.tile_center(hidden)
		g._process(0.0)
		await t.input.settle()
		await t.input.click_world(g.tile_center(hidden))
		t.check(g.interaction.selected_tile != hidden and not g.building_at(hidden), "Panning into fog cannot reveal or build on unexplored ground")
	t.tree.root.size = Vector2i(1440, 900)

func check_large_footprints(t) -> void:
	var g = t.game
	for axis in [Vector2i.RIGHT, Vector2i.DOWN]:
		t.fixtures.scenario("Multi-row drag spacing and affordable prefix: " + str(axis), 0)
		t.fixtures.clear_area(Rect2i(27, 6, 16, 13))
		t.fixtures.building_materials("farm", 2)
		var start := Vector2i(28, 7)
		var stride := 4 if axis == Vector2i.RIGHT else 3
		await t.input.choose_building("farm")
		var stroke: Array[Vector2i] = [start, start + axis * stride * 2]
		await t.input.drag_world(stroke)
		t.check(g.building_kind(start) == "farm" and g.building_kind(start + axis * stride) == "farm", "Dragging spaces buildings by the footprint in the chosen direction")
		t.check(not g.building_at(start + axis * stride * 2) and g.hud.tool_buttons.farm.disabled, "The unaffordable remainder creates no blueprints")
		g.set_tool("cancel")
		await t.input.click_world(g.tile_center(start + Vector2i(3, 2)))
		t.check(not g.building_at(start) and g.building_kind(start + axis * stride) == "farm", "Canceling through the far corner removes only its own blueprint")

	t.fixtures.scenario("Rejected and cancelled gestures create no blueprints", 0)
	t.fixtures.bed(Vector2i(30, 11))
	t.fixtures.materials(g.BED_BLOCKS * 3)
	await t.input.choose_building("bed")
	var row: Array[Vector2i] = [P, Vector2i(32, 11)]
	await t.input.drag_world(row)
	t.check(not g.building_at(P) and g.building_at(Vector2i(30, 11)), "An obstructed row does not partly place new buildings")
	var safe_row: Array[Vector2i] = [Vector2i(28, 15), Vector2i(32, 15)]
	await t.input.drag_world(safe_row, true)
	t.check(not g.building_at(safe_row[0]), "Releasing over the HUD cancels the preview")
	await t.input.drag_world(safe_row, false, true)
	t.check(not g.building_at(safe_row[0]) and g.interaction.tool == "dig", "Right-click discards the uncommitted preview and exits blueprint mode")
	await t.input.choose_building("bed")
	await t.input.click_world(g.tile_center(safe_row[0]))
	t.check(g.building_at(safe_row[0]) and not g.building_at(Vector2i(30, 15)), "A cancelled gesture does not leak into the next single placement")

func check_tracks(t) -> void:
	var g = t.game
	var ui = g.hud

	t.fixtures.scenario("Drag track corners, reuse, reverse, and dismantle", 1)
	g.world.workers[0].pos = Vector2(P)
	t.fixtures.materials(7)
	await t.input.settle()
	await t.input.choose_building("belt")
	var path: Array[Vector2i] = [Vector2i(36, 15), Vector2i(35, 15), Vector2i(35, 14), Vector2i(35, 13), Vector2i(34, 13), Vector2i(33, 13), g.BASE]
	await t.input.drag_world(path)
	t.check(g.player_blocks == 7, "Dragging a route leaves construction materials in storage")
	await t.input.click_world(g.tile_center(path[0]))
	t.check(g.hud.entity_title.text == "矿道 · 建造中", "Single-cell track blueprint can be inspected")
	t.advance_until(func(): return g.world.sites.is_empty(), 120, "The dragged route completes through actual delivery and construction, with room for need responses")
	await t.input.settle()
	t.check(g.hud.entity_title.text == "矿道" and g.belt_destination(path[0]) == g.BASE, "Dragged corners complete into a connected route without losing selection")
	await t.input.choose_building("belt")
	var reverse: Array[Vector2i] = [Vector2i(35, 15), Vector2i(36, 15)]
	await t.input.drag_world(reverse, false, false, Vector2(0, 16))
	await t.input.click_exposed_building(path[0], "矿道")
	t.check(g.belt_destination(path[0]) == null and g.player_blocks == 1, "Reverse dragging rewires empty tracks without charging twice")
	var restore: Array[Vector2i] = [Vector2i(36, 15), Vector2i(35, 15), Vector2i(35, 14)]
	await t.input.drag_world(restore, false, false, Vector2(0, 16))
	await t.input.click_exposed_building(path[0], "矿道")
	t.check(g.belt_destination(path[0]) == g.BASE, "Dragging back into the main line preserves its outgoing direction")
	await t.input.press_key(KEY_X)
	await t.input.click_world(g.tile_center(path[0]) + Vector2(0, 16))
	t.advance_until(func(): return g.player_blocks == 2, 20, "Dismantled track is carried back to storage")
	await t.input.settle()
	t.check(g.player_blocks == 2 and not g.hud.entity_panel.visible, "The unified demolition tool refunds the empty track and closes its details")

	# UI release must cancel a stroke, not place behind a panel or retain pointer capture.
	t.fixtures.materials(10)
	g.set_tool("belt")
	var short_path: Array[Vector2i] = [Vector2i(36, 15), Vector2i(36, 14)]
	await t.input.drag_world(short_path, true)
	t.check(g.player_blocks == 10, "Releasing a track stroke over UI spends nothing")
	await t.input.click_world(g.tile_center(Vector2i(36, 15)))
	t.check(g.player_blocks == 10 and g.building_at(Vector2i(36, 15)) and not g.building_at(Vector2i(36, 14)), "Next click plans only one tile after canceled UI drag")
	g.set_tool("cancel")
	await t.input.click_world(g.tile_center(Vector2i(36, 15)))
	t.check(g.player_blocks == 10, "Cancel tool refunds the track blueprint")
	t.fixtures.materials(1)
	g.set_tool("belt")
	await t.input.drag_world(short_path)
	t.check(g.player_blocks == 1 and g.building_at(short_path[0]) and not g.building_at(short_path[1]), "One available sandstone plans only the first new track segment")
	await t.input.click_world(g.tile_center(Vector2i(36, 15)))
	t.check(g.player_blocks == 1 and g.hud.entity_title.text == "矿道 · 建造中", "Clicking an existing unfunded blueprint opens its details without a charge")

	# Missing intermediate mouse events must not produce an X-first detour or holes.
	t.fixtures.scenario("Fast diagonal track stroke follows crossed grid cells", 0)
	t.fixtures.materials(6)
	await t.input.choose_building("belt")
	var diagonal: Array[Vector2i] = [Vector2i(34, 15), Vector2i(35, 11)]
	await t.input.drag_world(diagonal)
	t.check(g.player_blocks == 6, "Fast diagonal planning leaves materials untouched")
	for cell in [Vector2i(34, 14), Vector2i(35, 12)]:
		await t.input.click_world(g.tile_center(cell))
		t.check(g.hud.entity_title.text == "矿道 · 建造中", "Cells crossed by the pointer, not an arbitrary horizontal-first detour, receive blueprints")

	t.fixtures.scenario("Right-click exits track blueprint mode without placing its preview", 0)
	t.fixtures.materials(5)
	await t.input.choose_building("belt")
	var backtrack: Array[Vector2i] = [Vector2i(36, 15), Vector2i(33, 15), Vector2i(35, 15)]
	await t.input.drag_world(backtrack, false, true)
	t.check(g.interaction.tool == "dig" and not g.building_at(backtrack[0]) and g.player_blocks == 5, "Right-click exits track placement without committing or charging the preview")
	await t.input.choose_building("belt")
	await t.input.drag_world(backtrack)
	t.check(g.player_blocks == 5 and g.building_at(Vector2i(36, 15)) and g.building_at(Vector2i(35, 15)) and not g.building_at(Vector2i(34, 15)), "Dragging back retracts preview cells without prepaying construction")


func check_track_receivers(t) -> void:
	var g = t.game
	t.fixtures.scenario("A track drag connects to the far corner of a receiving footprint", 1)
	var target := Vector2i(34, 11)
	t.fixtures.station("pump", P)
	t.fixtures.station("farm", target)
	t.fixtures.materials(1)
	g.add_stock(P, "raw_water", 4)
	g.world.workers[0].pos = Vector2(P)
	var endpoint: Vector2i = t.fixtures.receiver_track(target, "farm")
	await t.input.choose_building("belt")
	var path: Array[Vector2i] = [endpoint + Vector2i.DOWN, endpoint]
	await t.input.drag_world(path)
	t.check(g.belt_destination(path[0]) == target, "The mouse stroke connects the existing track to the requested receiver")
	g.adjust_production(target, 1)
	t.advance_until(func(): return t.track_shows_item("raw_water"), 10, "Actual material enters the newly connected track")
	g.adjust_production(target, -1)
	t.advance_until(func(): return g.stock_at(target, "raw_water") == 4, 10, "The player connection delivers its actual cargo to the stopped receiver")
	t.near(g.resource_inventory().raw_water, 4, "Connecting and delivering do not create or consume goods")

func check_power_interactions(t) -> void:
	var g = t.game
	t.tree.root.size = Vector2i(1440, 900)
	# Cover line footprints separately; completion, extension and branch removal need one journey.
	for sample in [{"kind": "low_line", "axis": Vector2i.RIGHT},
			{"kind": "high_line", "axis": Vector2i.RIGHT}, {"kind": "high_line", "axis": Vector2i.DOWN}]:
		var kind: String = sample.kind
		var axis: Vector2i = sample.axis
		t.fixtures.scenario("Cable footprint: %s %s" % [kind, axis], 1)
		t.fixtures.clear_area(Rect2i(27, 10, 10, 6))
		t.fixtures.building_materials(kind, 3)
		g.world_view.rebuild(g)
		await t.input.choose_building(kind)
		var stroke: Array[Vector2i] = [P, P + axis * 2]
		await t.input.drag_world(stroke)
		var far_cell: Vector2i = P + (Vector2i(axis.y, axis.x) if kind == "high_line" else Vector2i.ZERO)
		await t.input.click_world(g.tile_center(far_cell))
		t.check(g.hud.entity_title.text == g.building_name(kind) + " · 建造中", "Cable footprint opens its construction details")
		if kind != "high_line" or axis != Vector2i.DOWN:
			continue
		t.advance_until(func(): return g.world.power_lines.size() == 3, 45, "Cable row completes through normal material transport and labor")
		await t.input.settle()
		t.check(g.hud.entity_title.text == g.building_name(kind), "Selected cable details survive blueprint completion")
		t.fixtures.building_materials(kind)
		await t.input.choose_building(kind)
		stroke = [P, P + axis * 3]
		await t.input.drag_world(stroke, false, false, Vector2(18, -8))
		t.check(g.building_at(P + axis * 3), "Dragging from an exposed part of the cable plans the extension")
		t.advance_until(func(): return g.world.power_lines.size() == 4, 30, "The extension receives its own material and completes")
		var branch: Vector2i = P + axis + Vector2i.RIGHT * 2
		t.fixtures.building_materials(kind)
		await t.input.choose_building(kind)
		await t.input.click_world(g.tile_center(branch))
		t.advance_until(func(): return g.world.power_lines.has(branch), 30, "Perpendicular cable branch completes normally")
		g.set_tool("dig")
		await t.input.click_world(g.tile_center(branch) + Vector2(0, 17))
		t.check(g.hud.entity_title.text == g.building_name(kind), "Cable branch opens its own details")
		g.set_tool("demolish")
		await t.input.click_world(g.tile_center(branch) + Vector2(0, 17))
		t.check(not g.world.power_lines.has(branch) and g.world.power_lines.has(P + axis), "Dismantling a branch preserves the neighboring trunk")

	t.fixtures.scenario("High-voltage corridor permits belt crossing but blocks buildings", 0)
	t.fixtures.clear_area(Rect2i(27, 9, 10, 7))
	for x in range(28, 33): t.fixtures.cable(Vector2i(x, 11), "high_line")
	t.fixtures.materials(5)
	g.world_view.rebuild(g)
	await t.input.choose_building("belt")
	var crossing: Array[Vector2i] = [Vector2i(30, 10), Vector2i(30, 14)]
	await t.input.drag_world(crossing)
	t.check(g.player_blocks == 5, "Belt blueprints can cross the corridor without prepaying materials")
	t.fixtures.building_materials("bed")
	t.check(not g.place_building(Vector2i(28, 12), "bed"), "The full two-cell corridor rejects buildings")
	await t.input.click_world(g.tile_center(Vector2i(30, 11)))
	t.check(g.hud.entity_title.text.begins_with("矿道"), "The visible belt wins native picking over the cable beneath it")

	# Moving a facility is a command that must carry its actual stock.
	t.fixtures.scenario("Move a drill through the inspector", 0)
	var drill := Vector2i(34, 11)
	var destination := Vector2i(34, 14)
	t.fixtures.station("drill", drill)
	t.fixtures.clear_area(Rect2i(destination, Vector2i(2, 1)))
	g.add_stock(drill, 2, 3)
	await t.input.settle()
	await t.input.click_world(g.tile_center(drill))
	await t.input.click(g.hud.move_drill.get_global_rect().get_center())
	await t.input.click_world(g.tile_center(destination))
	t.check(g.interaction.selected_entity == destination and not g.building_at(drill), "The move control relocates the selected building")
	t.near(g.stock_at(destination, 2), 3, "Relocation carries stock without loss or duplication")


func check_industry_controls(t) -> void:
	var g = t.game
	t.fixtures.scenario("The slaughter control issues a real finite job", 1)
	t.fixtures.station("barn", P)
	await t.input.settle()
	await t.input.click_world(g.tile_center(P))
	await t.input.click(g.hud.slaughter.get_global_rect().get_center())
	t.advance_until(func(): return g.resource_activity("meat", 1).produced == g.SHEEP_MEAT, 120, "The inspector command completes its actual slaughter job")
	g.simulate(1)
	t.near(g.resource_inventory().meat + g.resource_activity("meat", 1).consumed, g.SHEEP_MEAT, "The command cannot create a duplicate batch of meat")

func check_alerts(t) -> void:
	var g = t.game
	t.fixtures.scenario("Clicking an alert targets its building without world click-through", 0)
	t.fixtures.station("farm", P)
	g.adjust_production(P, 1)
	g.simulate(g.HOUR_SECONDS * 1.1)
	await t.input.settle()
	var alert: Button = t.alert_button("1 个农田缺少原水")
	t.check(alert != null, "The ordered blocked facility offers a navigation action")
	if alert == null: return
	var orders: int = g.world.mining_contracts.size()
	await t.input.click(alert.get_global_rect().get_center())
	t.check(g.interaction.selected_entity == P and g.world.mining_contracts.size() == orders, "The alert selects its target without ordering excavation behind the HUD")
