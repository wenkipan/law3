extends SceneTree

const SUITES := {
	"world": preload("res://tests/world_behaviors.gd"),
	"production": preload("res://tests/production_behaviors.gd"),
	"equipment": preload("res://tests/equipment_behaviors.gd"),
	"interaction": preload("res://tests/interaction_behaviors.gd"),
}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var native := "--native" in args
	var selected := ""
	var preview_map := "--generated-map" in args
	for arg in args:
		if arg.begins_with("--suite="):
			selected = arg.trim_prefix("--suite=")
		elif (arg not in ["--native", "--generated-map", "--trace-ai"]
				and not arg.begins_with("--trace-ai=")
				and not arg.begins_with("--trace-ai-file=")
				and not arg.begins_with("--trace-ai-max-mib=")):
			printerr("Unknown test option: ", arg)
			quit(2)
			return
	if selected != "" and not SUITES.has(selected):
		printerr("Use --suite=world|production|equipment|interaction; --generated-map runs only the map preview.")
		quit(2)
		return
	if native and DisplayServer.get_name() == "headless":
		printerr("--native requires a window.")
		quit(2)
		return
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	var context := preload("res://tests/support/context.gd").new(self, game, native)
	if native:
		root.grab_focus()
		await create_timer(0.25).timeout
	if preview_map:
		await preload("res://tests/diagnostics/map_preview.gd").new().run(context)
	else:
		for suite in SUITES:
			if selected == "" or selected == suite:
				await SUITES[suite].new().run(context)
	print("%s: %d checks, %d failures" % ["PASS" if context.failures == 0 else "FAIL", context.checks, context.failures])
	game.free()
	quit(0 if context.failures == 0 else 1)
