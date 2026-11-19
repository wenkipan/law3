extends RefCounted

const P := Vector2i(28, 11)

func run(t) -> void:
	t.game.reset_world(1020)
	await t.input.click_exposed_building(t.game.BASE, "储物箱")
	await t.input.screenshot("/tmp/law3-input-opening.png")
	await check_tactical_pause(t)
	await check_selection_and_market(t)
	await check_blueprints(t)
	await check_demolition_input(t)
	await check_fog(t)
	await check_planning_only(t)
	await check_migration_details(t)

# Native commands still reach the right overlapping facility after mouse labor is removed.
func check_demolition_input(t) -> void:
	var g = t.game
	t.fixtures.scenario("Demolition is commissioned through native picking and performed only by residents")
	t.fixtures.station("mill", P)
	t.fixtures.stock_recipe(P, {"bread": 3})
	t.fixtures.resident("building_logistics", P + Vector2i(0, 3))
	g.update_fog()
	await t.input.press_key(KEY_X)
	await t.input.click_world(g.tile_center(P + Vector2i.RIGHT) + Vector2(10, 12))
	g.set_tool("dig")
	await t.input.click_exposed_building(P, "磨房 · 待拆除")
	t.check(g.hud.entity_title.text.contains("待拆除"), "Native demolition designation opens live pending details")
	await t.input.screenshot("/tmp/law3-input-demolition.png")
	await t.input.press_key(KEY_C)
	await t.input.click_world(g.tile_center(P + Vector2i.RIGHT))
	t.check(g.world.has_building(P, "station"), "Cancellation withdraws demolition before any actual labor")
	await t.input.press_key(KEY_X)
	await t.input.click_world(g.tile_center(P + Vector2i.RIGHT))
	g.set_wage(P, 0)
	g.set_tool("dig")
	await t.input.hold_world(g.tile_center(P + Vector2i.RIGHT), g.building_hours("mill") * g.HOUR_SECONDS)
	t.check(g.world.has_building(P), "Holding cannot dismantle a closed job")
	t.check(g.cancel_site(P), "Mouse holding has not started irreversible demolition")
	g.demolish_building(P)
	t.advance_until(func(): return not g.world.has_building(P), 150, "A qualified resident completes the commissioned dismantling")
	t.near(g.stock_at(P, "bread"), 3, "Contents remain on the actual demolition site")
	t.near(g.resource_inventory().money, g.STARTING_MONEY, "Demolition transfers the actual resident wage")

	t.fixtures.scenario("Crossed cables and conveyors keep independent demolition commands")
	t.fixtures.belt(P, Vector2i.RIGHT)
	t.fixtures.cable(P, "high_line")
	t.fixtures.resident("building_logistics", P + Vector2i(0, 3))
	g.update_fog()
	await t.input.press_key(KEY_X)
	await t.input.click_world(g.tile_center(P + Vector2i.DOWN))
	g.set_tool("dig")
	await t.input.click_world(g.tile_center(P + Vector2i.DOWN))
	t.check(g.hud.entity_title.text.contains("待拆除"), "The exposed cable receives its own demolition command")
	t.advance_until(func(): return not g.world.has_building(P, "line"), 90, "A resident dismantles only the commissioned cable")
	t.check(g.world.has_building(P, "belt"), "Cable demolition preserves the crossing conveyor")
	await t.input.press_key(KEY_X)
	await t.input.click_world(g.tile_center(P))
	t.advance_until(func(): return not g.world.has_building(P), 90, "The conveyor accepts its separate demolition command")
	for item in g.building_materials("high_line"):
		t.near(g.player_inventory()[item], g.building_materials("high_line")[item] + g.building_materials("belt").get(item, 0), "Crossed demolition recovers the actual materials once")

func check_tactical_pause(t) -> void:
	var g = t.game
	t.fixtures.scenario("Tactical pause preserves planning and picking without advancing residents or producing goods")
	t.fixtures.station("market", g.BASE)
	var person: Dictionary = t.fixtures.resident("building_logistics", g.BASE + Vector2i(1, 1))
	g.update_fog()
	g.get_node("SimulationTick").set_physics_process(true)
	await t.input.press_key(KEY_SPACE)
	var before: Dictionary = t.world_observations()
	await t.tree.create_timer(0.3, true, false, true).timeout
	t.check(t.world_observations() == before, "Paused real frames do not move residents, consume goods, pay wages or advance the calendar")
	await t.input.click_world(g.tile_center(person.pos) + Vector2(0, -7))
	t.check(g.interaction.selected_worker == person.id, "Paused native picking still selects a resident over a building")
	if t.native: t.check(g.world_view.hover_frame.visible, "Paused native-window hover still reaches the resident")
	await t.input.choose_building("bed")
	var row: Array[Vector2i] = [P, P + Vector2i(4, 0)]
	await t.input.drag_world(row)
	t.check(g.world.building_positions("site").size() == 3 and g.world.has_building(P + Vector2i(4, 0), "site"), "Paused toolbar drag places the full blueprint row even with no materials (placed %s)" % str(g.world.building_positions("site")))
	t.near(g.player_inventory()[1], 0, "Planning an unfunded row does not create or charge physical materials")
	await t.input.close_build_tray()
	# Closing the selected category must also exit placement, not leave a hidden tool active.
	var empty_cell := P + Vector2i(0, 3)
	await t.input.click_world(g.tile_center(empty_cell))
	t.check(not g.world.has_building(empty_cell, "site") and g.interaction.selected_tile == empty_cell,
		"Closing the selected building category restores ordinary ground selection while paused")
	await t.input.click(g.hud.save_button.get_global_rect().get_center())
	t.check(g.hud.save_menu.visible, "The authored save toolbar opens the modal planning window")
	g.hud.save_menu.hide()
	var paused_time: float = g.world.day_elapsed
	await t.tree.create_timer(0.2, true, false, true).timeout
	t.near(g.world.day_elapsed, paused_time, "Closing a modal window does not release the player's tactical pause")
	await t.input.click(g.hud.speed_buttons[4].get_global_rect().get_center())
	var snapshot: Dictionary = g.capture_snapshot()
	g.set_speed(1)
	g.world_view.camera.zoom = Vector2.ONE * 0.45
	g.world_view.camera.position = g.tile_center(g.BASE + Vector2i(96, 32))
	g.interaction.pollution_visible = true
	var other_view: Dictionary = g.capture_snapshot()
	t.check(snapshot.ok and other_view.ok and snapshot.data == other_view.data,
		"Changing the camera, overlay and speed while paused leaves the serialized world identical")
	var restored: Dictionary = g.restore_snapshot(snapshot.data)
	t.check(restored.ok, "A paused planning snapshot restores without replaying work or transactions")
	paused_time = g.world.day_elapsed
	await t.tree.create_timer(0.2, true, false, true).timeout
	t.near(g.world.day_elapsed, paused_time, "Loading does not release the current session's tactical pause")
	await t.input.press_key(KEY_SPACE)
	var elapsed_before: float = g.world.day_elapsed
	await t.tree.create_timer(0.25, true, false, true).timeout
	var advanced: float = g.world.day_elapsed - elapsed_before
	t.check(advanced > 0.10 and advanced < 0.55, "Resuming uses the current session's 1x speed, not the speed at the checkpoint")
	g.get_node("SimulationTick").set_physics_process(false)
	g.set_speed(1)

	t.fixtures.scenario("Engine speed controls advance the game calendar once, while modal windows suspend it")
	g.get_node("SimulationTick").set_physics_process(true)
	for speed in [1, 2, 4]:
		await t.input.click(g.hud.speed_buttons[speed].get_global_rect().get_center())
		var started := Time.get_ticks_usec()
		var calendar: float = g.world.day_elapsed
		await t.tree.create_timer(0.4, true, false, true).timeout
		var real_seconds := (Time.get_ticks_usec() - started) / 1000000.0
		t.near(g.world.day_elapsed - calendar, real_seconds * speed, "The %dx control advances the calendar at its displayed speed, not squared speed" % speed, 0.12 * speed)
	g.hud.show_save_menu(true)
	paused_time = g.world.day_elapsed
	await t.tree.create_timer(0.2, true, false, true).timeout
	t.near(g.world.day_elapsed, paused_time, "A save window suspends a running accelerated world")
	g.hud.save_menu.hide()
	await t.tree.create_timer(0.2, true, false, true).timeout
	t.check(g.world.day_elapsed > paused_time, "Closing the window resumes a game that was not manually paused")
	g.get_node("SimulationTick").set_physics_process(false)
	g.set_speed(1)

# Protect the removal itself: clicks inspect, holds and drags never create free work or transport.
func check_planning_only(t) -> void:
	var g = t.game
	t.fixtures.scenario("World and inspector input cannot mine, build, operate, or transport items")
	# Keep the pump open without funding an operator who could work during a held click.
	g.add_stock(g.BASE, "money", -g.STARTING_MONEY)
	var source := P + Vector2i(-3, 0)
	var drop := P + Vector2i(0, 3)
	t.fixtures.deposit(source, 7, 4)
	t.fixtures.stock_recipe(drop, {7: 5})
	t.fixtures.stock_recipe(P, g.building_materials("storage_box"))
	t.fixtures.station("pump", P + Vector2i(4, 0))
	g.update_fog()
	await t.input.choose_building("storage_box")
	await t.input.click_world(g.tile_center(P))
	t.check(g.world.has_building(P, "site"), "Planning still places a real blueprint")
	g.set_tool("dig")
	await t.input.close_build_tray()
	await t.input.hold_world(g.tile_center(source), 65)
	t.near(g.world.deposits[source], 4, "Holding an ordinary deposit cannot mine it")
	await t.input.hold_world(g.tile_center(P), 65)
	t.check(g.world.has_building(P, "site"), "Holding a supplied blueprint cannot construct it")
	await t.input.hold_world(g.tile_center(P + Vector2i(4, 0)), 35)
	t.near(g.stock_at(P + Vector2i(4, 0), "raw_water"), 0, "Holding a production facility cannot operate it")
	var route: Array[Vector2i] = [drop, drop + Vector2i.RIGHT]
	await t.input.drag_world(route)
	t.near(g.stock_at(drop, 7), 5, "Dragging a world stack cannot transport it")
	t.near(g.stock_at(drop + Vector2i.RIGHT, 7), 0, "Dragging cannot create goods at its destination")
	await t.input.click_world(g.tile_center(drop))
	await t.input.press(g.hud.inventory_icons.entries[7].get_global_rect().get_center())
	await t.input.move_to(g.get_global_transform_with_canvas() * g.tile_center(drop + Vector2i.RIGHT))
	await t.input.release()
	t.near(g.stock_at(drop, 7), 5, "Inspector inventory icons cannot pick up goods")
	await t.input.screenshot("/tmp/law3-input-planning.png")

func check_selection_and_market(t) -> void:
	var g = t.game
	t.fixtures.scenario("Viewport routes residents, market prices and zero-wage closure")
	t.fixtures.station("market", P)
	var resident: Dictionary = t.fixtures.resident("operations", P + Vector2i(1, 1), "fruit")
	var source := P + Vector2i(0, 3)
	var belt := source + Vector2i.UP
	t.fixtures.stock_recipe(source, {"berries": 4})
	t.fixtures.belt(belt, Vector2i.UP)
	g.update_fog()
	g.world_view.camera.zoom = Vector2.ONE * 1.25
	await t.input.settle()
	await t.input.click_world(g.tile_center(resident.pos) + Vector2(0, -7))
	t.check(g.interaction.selected_worker == resident.id, "The front resident receives the native click over a building")
	t.check(g.hud.entity_details.text.contains("机械与操作") and not g.hud.entity_details.text.contains("水果"), "The clicked inspector shows skill without an obsolete food category")
	if t.native: t.check(g.world_view.hover_frame.visible, "Native-window hover reaches the visible resident")
	await t.input.click(g.hud.speed_buttons[2].get_global_rect().get_center())
	t.check(g.interaction.selected_worker == resident.id, "HUD input does not select world content behind it")
	await t.input.click_exposed_building(P, "市场")
	t.check(g.interaction.selected_entity == P, "An exposed market opens its live inspector")
	var route: Array[Vector2i] = [source, P]
	await t.input.drag_world(route)
	t.near(g.stock_at(P, "berries"), 0, "A world drag cannot put items on sale")
	t.near(g.stock_at(source, "berries"), 4, "The source retains actual stock until a resident picks it up")
	await t.input.click_exposed_building(P, "市场")
	t.check(g.hud.market_inputs.berries.visible and not g.hud.market_inputs.clothes.visible, "The price table lists owned items and hides unowned products")
	var quote: SpinBox = g.hud.market_inputs.berries
	var quote_rect := quote.get_global_rect()
	await t.input.click(Vector2(quote_rect.end.x - 5, quote_rect.position.y + 7))
	t.near(g.market_price(P, "berries"), 1, "A real price control enables sales from the zero default")
	t.near(g.stock_at(P, "berries"), 0, "Enabling a price cannot transfer distant goods immediately")
	await t.input.click(Vector2(quote_rect.end.x - 5, quote_rect.end.y - 7))
	t.near(g.market_price(P, "berries"), 0, "The price control can disable sales with zero")
	await t.input.click(Vector2(quote_rect.end.x - 5, quote_rect.position.y + 7))
	await t.input.click(g.hud.wage_selector.buttons[0].get_global_rect().get_center())
	t.check(g.hud.entity_details.text.contains("已关闭"), "The zero employment price visibly closes the market")
	await t.input.screenshot("/tmp/law3-input-market.png")
	if t.native:
		t.tree.root.size = Vector2i(960, 640)
		await t.input.settle()
		await t.input.screenshot("/tmp/law3-input-market-960.png")
		t.tree.root.size = Vector2i(1440, 900)
		await t.input.settle()
	await t.input.click(g.hud.wage_selector.buttons[2].get_global_rect().get_center())
	t.check(not g.hud.entity_details.text.contains("已关闭"), "A positive employment price reopens recruitment")
	# A keyboard-selected brush must issue the same command as its toolbar equivalent.
	await t.input.press_key(KEY_P)
	await t.input.press_key(KEY_KP_3)
	await t.input.click_world(g.tile_center(P + Vector2i(2, 0)) + Vector2(10, 16))
	t.near(g.world.building_state(P, "station").wage, 3, "Mapped tool and keypad actions paint the actual building wage")
	await t.input.press_key(KEY_G)
	await t.input.press_key(KEY_ESCAPE)
	t.check(not g.hud.entity_panel.visible, "Escape closes the selected inspector")
	await t.input.click(g.hud.get_node("%ReportButton").get_global_rect().get_center())
	t.check(is_instance_valid(g.hud.report_window) and g.hud.report_window.visible,
		"The authored report toolbar opens the live daily report")
	g.hud.report_window.hide()

func check_blueprints(t) -> void:
	var g = t.game
	t.fixtures.scenario("The first market is built through physical supply and keeps native entity identity", 0, false, 1020, false)
	t.fixtures.fund_carrier(t.fixtures.resident("building_logistics", g.BASE + Vector2i.DOWN))
	t.fixtures.building_materials("market")
	t.fixtures.stock_recipe(P, {"berries": 3})
	g.update_fog()
	await t.input.settle()
	await t.input.choose_building("market")
	await t.input.click_world(g.tile_center(P) + Vector2(17, 0))
	t.check(g.world.has_building(P, "site"), "The building icon and ground click create a real blueprint")
	if not g.world.has_building(P, "site"): return
	g.set_tool("dig")
	await t.input.click_world(g.tile_center(P + Vector2i.RIGHT))
	t.check(g.interaction.selected_entity == P, "A blueprint is selected through its complete footprint")
	t.check(not g.hud.market_controls.visible and not g.set_market_price(P, "berries", 3), "A market blueprint has construction controls, not operating prices")
	var wood_needed: int = g.building_materials("market")[7]
	# Capture a real shipment before its first arrival so the bubble can be
	# checked for the regression where claiming alone clears the displayed need.
	t.advance_until(func(): return g.stock_at(g.BASE, 7) < wood_needed or g.stock_at(P, 7) > 0, 100, "Building materials actually leave the source")
	await t.input.screenshot("/tmp/law3-input-blueprint.png")
	t.advance_until(func(): return g.stock_at(P, 7) > 0, 100, "Construction materials must actually reach the market blueprint")
	await t.input.settle()
	await t.input.screenshot("/tmp/law3-input-blueprint-delivery.png")
	t.advance_until(func(): return g.site_supplied(P), 150, "The complete recipe reaches the construction site")
	await t.input.settle()
	await t.input.screenshot("/tmp/law3-input-blueprint-ready.png")
	t.advance_until(func(): return g.world.has_building(P, "station"), 200, "The first market completes through ordinary supply and labor without an existing market")
	for item in g.building_materials("market"):
		t.near(g.player_inventory()[item], 0, "The market consumes its actual construction materials exactly once")
	t.near(g.stock_at(P, "berries"), 0, "Construction over a ground stack does not automatically put it on the shelf")
	t.near(g.player_inventory().berries, 3, "Goods under the new market are not lost")
	await t.input.settle()
	await t.input.click_exposed_building(P, "市场")
	t.check(g.interaction.selected_entity == P and g.hud.entity_title.text == "市场", "Completion preserves the selectable market at its original footprint")
	g.set_tool("demolish")
	await t.input.click_world(g.tile_center(P + Vector2i.RIGHT) + Vector2(10, 12))
	t.check(not g.world.has_building(P, "station"), "The demolition tool reaches the selected building through native input")

	# A moved entity must keep its goods without retaining a pick target at its old location.
	t.fixtures.scenario("Relocating a stocked drill updates native picking without copying its inventory")
	t.fixtures.station("market", g.BASE)
	t.fixtures.station("drill", P)
	t.fixtures.stock_recipe(P, {2: 3, "raw_water": 2})
	var target := Vector2i(35, 11)
	g.update_fog()
	g.set_tool("dig")
	await t.input.click_exposed_building(P, "矿钻")
	await t.input.click(g.hud.move_drill.get_global_rect().get_center())
	await t.input.click_world(g.tile_center(target))
	t.near(g.stock_at(target, 2), 3, "The move control keeps the drill's actual output at its new position")
	t.near(g.stock_at(target, "raw_water"), 2, "Relocation keeps other goods in the same building container")
	t.near(g.stock_at(P, 2), 0, "The old position does not retain a duplicate warehouse")
	await t.input.click_world(g.tile_center(P))
	t.check(g.interaction.selected_entity != P, "The old footprint no longer selects a relocated building")
	await t.input.click_exposed_building(target, "矿钻")
	t.check(g.interaction.selected_entity == target and g.hud.entity_title.text == "矿钻", "The moved native pick target opens the live building details")

func check_fog(t) -> void:
	var g = t.game
	t.fixtures.scenario("Losing sight hides terrain, goods and neutral residents without explored-map memory")
	t.fixtures.station("market", g.BASE)
	var far := Vector2i(55, 13)
	t.fixtures.resident("building_logistics", far, "fruit")
	t.fixtures.wild(far + Vector2i.DOWN, "berries")
	t.fixtures.stock_recipe(far + Vector2i.LEFT, {1: 1})
	g.update_fog()
	g.world_view.camera.position = g.tile_center(far)
	g.world_view.camera.zoom = Vector2.ONE
	g.set_tool("dig")
	await t.input.settle()
	await t.input.click_world(g.tile_center(far) + Vector2(0, -7))
	t.check(g.interaction.selected_worker < 0, "A neutral resident outside current sight cannot be picked")
	t.fixtures.station("storage_box", far)
	g.update_fog()
	await t.input.settle()
	await t.input.click_world(g.tile_center(far) + Vector2(0, -7))
	t.check(g.interaction.selected_worker >= 0, "A new player building reveals the existing resident rather than generating a replacement")
	var selected: int = g.interaction.selected_worker
	g.world_view.camera.position = g.tile_center(g.BASE + Vector2i(96, 32))
	await t.input.settle()
	g.world_view.camera.position = g.tile_center(far)
	await t.input.click_world(g.tile_center(far) + Vector2(0, -7))
	t.check(selected >= 0 and g.interaction.selected_worker == selected, "Returning to a previously offscreen area can pick the same resident")
	await t.input.click_world(g.tile_center(far + Vector2i.DOWN))
	t.check(g.interaction.selected_tile == far + Vector2i.DOWN and not g.tile_details(far + Vector2i.DOWN).is_empty(), "A visible resource opens its live terrain details")
	await t.input.screenshot("/tmp/law3-input-world.png")
	t.check(g.demolish_building(far), "Removing the sight source accepts the normal demolition command")
	g.update_fog()
	t.check(not g.tile_details(far + Vector2i.DOWN).is_empty(), "Pending demolition retains sight so the player can dismantle a remote facility")
	t.advance_until(func(): return not g.world.has_building(far), 150, "The resident dismantles the remote sight source")
	g.update_fog()
	g.update_ui()
	await t.input.settle()
	t.check(not g.hud.entity_panel.visible and g.tile_details(far + Vector2i.DOWN).is_empty(), "Lost sight closes the selected terrain inspector rather than exposing remembered information")
	await t.input.click_world(g.tile_center(far) + Vector2(0, -7))
	t.check(g.interaction.selected_worker < 0 and g.interaction.selected_entity == null, "Previously seen residents and buildings cannot be picked through fog")
	await t.input.click_world(g.tile_center(far + Vector2i.LEFT))
	t.check(g.interaction.selected_tile == null, "Previously seen loose goods and ground cannot be selected through fog")
	t.check(not g.place_building(far + Vector2i(0, 3), "bed"), "Blueprint placement cannot use remembered terrain outside current sight")
	var hidden: Dictionary = g.capture_snapshot()
	t.check(hidden.ok and g.restore_snapshot(hidden.data).ok and g.tile_details(far + Vector2i.DOWN).is_empty(), "Saving and loading cannot turn lost sight into explored-map visibility")
	await t.input.screenshot("/tmp/law3-input-fog.png")

# A departing resident keeps ordinary native picking and live details, and loading
# an actual walk cannot turn departure into death or leave a stale selected person.
func check_migration_details(t) -> void:
	var g = t.game
	t.fixtures.scenario("A departing resident remains selectable and resumes the walk after loading")
	t.fixtures.station("market", P)
	var resident: Dictionary = t.fixtures.resident("operations", P + Vector2i.DOWN, "grain", {"bread": 24})
	resident.pollution = 100.0
	g.update_fog()
	await t.input.click_world(g.tile_center(resident.pos) + Vector2(0, -7))
	t.check(g.interaction.selected_worker == resident.id, "Native picking opens the resident's live details")
	t.advance_until(func():
		g.update_ui()
		return g.hud.entity_details.text.contains("离开地区"), g.DAY_SECONDS * 4,
		"Persistent hardship appears as the actual departure action in existing details")
	if not g.hud.entity_details.text.contains("离开地区"): return
	var before: Vector2 = resident.pos
	var saved: Dictionary = g.capture_snapshot()
	t.check(saved.ok and g.restore_snapshot(saved.data).ok, "The resident's actual departure walk survives loading")
	var person: Dictionary = g.world.workers[0]
	await t.input.click_world(g.tile_center(person.pos) + Vector2(0, -7))
	t.check(g.hud.entity_details.text.contains("离开地区"), "Loading preserves the departing action in the clicked inspector")
	await t.input.screenshot("/tmp/law3-input-migration.png")
	g.simulate(0.1)
	t.check(g.world.workers.is_empty() or g.world.workers[0].pos != before, "The restored resident continues physically walking toward the fixed exit")
	t.advance_until(func(): return g.world.workers.is_empty(), 60, "The resident leaves only after reaching the exit")
	g.update_ui()
	t.check(not g.hud.entity_panel.visible, "Departure closes the removed resident's selected details")
