extends SceneTree
const Game = preload("res://game.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("_run")
func capture(name: String) -> void:
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/" + name + ".png")
func _run() -> void:
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1800):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Game loads with shelter atlas")
	if not game.startup_complete: quit(1); return
	game._resume_game(); game.day_night.hour = 12; game.day_night.enabled = false; game.pilot.set_physics_process(false)
	game.natural_light.configure(Game.NaturalLight.DEFAULTS)
	check(game.natural_light.image != null and game.natural_light.image.get_width() == 512,"World builds one shared overhead atlas")
	print("World surface=",game.natural_light.surface," player=",game.pilot.global_position," visibility=",game.natural_light.visibility(game.pilot.global_position))
	var deepest := INF; var cell := Vector2i.ZERO
	var image: Image = game.natural_light.image
	for z in range(image.get_height()):
		for x in range(image.get_width()):
			var height := image.get_pixel(x,z).r
			if height >= game.natural_light.bounds.position.y - 0.1 and height < deepest: deepest = height; cell = Vector2i(x,z)
	var box: AABB = game.natural_light.bounds
	var point := Vector3(box.position.x + (cell.x + 0.5) * box.size.x / image.get_width(),deepest + 2,box.position.z + (cell.y + 0.5) * box.size.z / image.get_height())
	check(game.natural_light.visibility(point) == 0,"Real trench bottom is below the default sunlight reach")
	if DisplayServer.get_name() != "headless":
		game._update_daylight(); await capture("natural-world-day")
		game.pilot.global_position = point; game.pilot.reset_physics_interpolation(); game._set_camera_mode(true); game._update_follow_camera(0,true); game._update_daylight()
		await capture("natural-world-deep")
		game.equipment.mounted[0].enabled = true; game.equipment.apply_settings()
		await capture("natural-world-deep-headlight")
	game.queue_free(); await process_frame
	print("Natural world: 3 checks, %d failures" % failures); quit(1 if failures else 0)
