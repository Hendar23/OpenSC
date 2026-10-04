extends SceneTree
const Display = preload("res://hud_display.gd")
const Map = preload("res://hud_map.gd")
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(128,80)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var pilot := Node3D.new()
	view.add_child(pilot)
	pilot.position = Vector3(50,5,50)
	var map := Map.new()
	map.bounds = AABB(Vector3.ZERO,Vector3(100,10,100))
	map.initialize_exploration()
	var terrain := Image.create(128,128,false,Image.FORMAT_RGB8)
	terrain.fill(Color.WHITE)
	map.texture = ImageTexture.create_from_image(terrain)
	var display := Display.new()
	display.screen_only = true
	display.size = Vector2(128,80)
	display.pilot = pilot
	display.map_data = map
	view.add_child(display)
	for revealed in [false,true]:
		map.explored.fill(Color.WHITE if revealed else Color.BLACK)
		map.exploration_texture.update(map.explored)
		for frame in range(3): await process_frame
		await RenderingServer.frame_post_draw
		var picture := view.get_texture().get_image()
		var orange := picture.get_pixel(64,39)
		if orange.r < 0.95 or orange.g < 0.20 or orange.g > 0.30 or orange.b > 0.10:
			failures += 1
			push_error("Player marker must stay orange with revealed=%s: %s" % [revealed,orange])
		var background := picture.get_pixel(10,10)
		if (revealed and background.r < 0.95) or (not revealed and background.r > 0.02):
			failures += 1
			push_error("Terrain must still respect exploration")
	pilot.rotation.y = PI / 2.0
	pilot.reset_physics_interpolation()
	await physics_frame
	await process_frame
	display._process(0.0)
	if not is_equal_approx(display.player_marker.rotation,-PI / 2.0):
		failures += 1
		push_error("Player marker must still follow heading: %s" % display.player_marker.rotation)
	view.queue_free()
	await process_frame
	print("Minimap marker: 5 checks, %d failures" % failures)
	quit(1 if failures else 0)
