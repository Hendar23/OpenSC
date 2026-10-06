extends SceneTree
const Mods = preload("res://mod_registry.gd")
const Population = preload("res://object_population.gd")
const Definitions = preload("res://object_definitions.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Mods.initialize(false); Mods.apply(["sea-mine-model"],[],false)
	var descriptor: Dictionary = Mods.candidates("model.mine")[0]
	check(descriptor.get("trigger_distance","") == "model_radius","Mine mod requests a model-sized trigger")
	var pack := {}
	for candidate in Mods.packs:
		if candidate.id == "sea-mine-model": pack = candidate
	check(pack.valid and pack.description.contains('"sea mine" (https://skfb.ly/onJQC) by AbsoluteMadLadd is licensed under Creative Commons Attribution (http://creativecommons.org/licenses/by/4.0/).'),"Mod validates and retains the exact attribution")
	var definition := Definitions.FLOATING_MINE.duplicate(true); definition.size = 2.0
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var model := Population.appearance(definition,folder)
	check(model != null,"Supplied self-contained sea-mine GLB loads")
	if model == null: quit(1); return
	var boxes: Array[AABB] = []; preload("res://creature_loader.gd")._collect_bounds(model,model.transform,boxes)
	var bounds := boxes[0]
	for box in boxes: bounds = bounds.merge(box)
	check(is_equal_approx(maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z)),2.0) and bounds.get_center().length() < 0.001,"Model is centred and fitted to the configured diameter")
	check(is_equal_approx(float(model.get_meta("trigger_distance")),1.0),"Trigger radius matches displayed model radius")
	model.free()
	var data := {"seed":42,"object_types":[definition],"object_groups":[{"id":"mine_test","type":"floating_mine","position":[0,0,0],"count":1,"radius":0}]}
	var world := Node3D.new(); root.add_child(world)
	var pop := Population.new(); world.add_child(pop); pop.setup(folder,data,false)
	check(is_equal_approx(pop.get_child(0).stats.trigger_distance,1.0) and definition.trigger_distance == 0.75,"Runtime uses the mod trigger without altering map stats")
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED; root.size = Vector2i(960,720)
		var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.015,0.1,0.13); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_energy = 0.6; world.add_child(env)
		var sun := DirectionalLight3D.new(); world.add_child(sun); sun.rotation_degrees = Vector3(-35,-30,0)
		var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(3,2,4); camera.look_at(Vector3.ZERO); camera.current = true
		for frame in range(6): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/sea-mine-mod-preview.png")
	pop.free(); definition.size = 3.0
	pop = Population.new(); world.add_child(pop); pop.setup(folder,data,false)
	check(is_equal_approx(pop.get_child(0).stats.trigger_distance,1.5),"Resizing mines automatically updates the trigger radius")
	pop.free(); Mods.apply([],[],false)
	pop = Population.new(); world.add_child(pop); pop.setup(folder,data,false)
	check(is_equal_approx(pop.get_child(0).stats.trigger_distance,0.75) and pop.get_child(0).get_child(0) is Sprite3D,"Disabling the mod restores the bitmap and map trigger")
	world.queue_free(); await process_frame
	print("Sea mine mod: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
