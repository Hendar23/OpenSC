extends SceneTree
const Display = preload("res://hud_display.gd")
const Map = preload("res://hud_map.gd")
var failures := 0
var checks := 6
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
	terrain.fill_rect(Rect2i(40,48,8,8),Color(1.0,0.25,0.05))
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
		if (revealed and (background.b < 0.95 or background.r > 0.5 or background.g < 0.65)) or (not revealed and background.r > 0.02):
			failures += 1
			push_error("Terrain must be blue while respecting exploration")
		if revealed:
			var border := picture.get_pixel(35,22)
			if border.r < 0.95 or border.g < 0.20 or border.g > 0.30 or border.b > 0.10:
				failures += 1
				push_error("Blue map tint must preserve orange impassable borders")
	map.markers = [{"position":Vector3(32,5,50),"name":"Touka Reef"}]
	for full in [false,true]:
		display.full_world = full
		for discovered in [false,true,false]:
			map.reset_exploration()
			if discovered:
				var cell := Vector2i(map.uv(map.markers[0].position) * (Map.RESOLUTION - 1))
				map.explored.fill_rect(Rect2i(cell - Vector2i.ONE,Vector2i(3,3)),Color.WHITE)
				map.exploration_texture.update(map.explored)
			for frame in range(3): await process_frame
			await RenderingServer.frame_post_draw
			var image := view.get_texture().get_image()
			var label_x := int(64.0 - 18.0 / display.map_span * 128.0 + 5.0)
			var green_pixels := 0
			for y in range(26,40):
				for x in range(label_x,mini(label_x + 55,128)):
					var pixel := image.get_pixel(x,y)
					if pixel.g > 0.4 and pixel.g > pixel.r * 2 and pixel.g > pixel.b * 2: green_pixels += 1
			checks += 1
			if (green_pixels > 0) != discovered:
				failures += 1; push_error("Discovered city names must render over fog, full=%s discovered=%s pixels=%d" % [full,discovered,green_pixels])
	map.reveal_all()
	checks += 1
	if not map.is_explored(Vector3(0,0,0)) or not map.is_explored(Vector3(99,0,99)):
		failures += 1; push_error("Reveal whole map must uncover both ends of the map")
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
	print("Minimap marker: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
