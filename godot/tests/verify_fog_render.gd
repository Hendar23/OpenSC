extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var scene := Node3D.new(); root.add_child(scene)
	var view := SubViewport.new(); view.size = Vector2i(900, 300); view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	var fog := environment.environment
	fog.background_mode = Environment.BG_COLOR; fog.background_color = Color(0, 0.48, 0.56)
	fog.fog_enabled = true; fog.fog_mode = Environment.FOG_MODE_DEPTH; fog.fog_density = 1.0
	fog.fog_depth_begin = 5; fog.fog_depth_end = 24; fog.fog_depth_curve = 1.8; fog.fog_light_color = fog.background_color
	view.add_child(environment)
	var camera := Camera3D.new(); camera.fov = 90; camera.current = true; view.add_child(camera)
	for point in [Vector3(-2, 0, -2), Vector3(0, 0, -12), Vector3(30, 0, -30)]:
		var mesh := MeshInstance3D.new(); mesh.mesh = QuadMesh.new(); mesh.mesh.size = Vector2.ONE * -point.z * 0.3
		var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = Color.RED
		mesh.material_override = material; mesh.position = point; view.add_child(mesh)
	for frame in range(20): await process_frame
	await RenderingServer.frame_post_draw
	var pixels := view.get_texture().get_image()
	var near := pixels.get_pixel(300, 150); var middle := pixels.get_pixel(450, 150); var far := pixels.get_pixel(600, 150)
	print("Fog pixels near/mid/far: ", near, " / ", middle, " / ", far)
	if near.r < 0.95 or near.g > 0.05: failures += 1; push_error("Near texture is tinted")
	if middle.r >= near.r or middle.g <= near.g: failures += 1; push_error("Fog fails to build with distance")
	if far.r > 0.05 or far.g < 0.4: failures += 1; push_error("Distant object is not obscured")
	pixels.save_png("res://tests/fog-distance-preview.png")
	print("Fog render verification: 3 checks, %d failures" % failures)
	quit(1 if failures else 0)
