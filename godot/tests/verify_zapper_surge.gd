extends SceneTree

const Surge = preload("res://zapper_surge.gd")
const ReplayVisual = preload("res://replay_visual.gd")

var checks := 0
var failures := 0

class Target extends CharacterBody3D:
	func take_damage(_amount: float, _source: Vector3 = Vector3.ZERO) -> void: pass

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var model := Node3D.new()
	model.set_meta("asset_source","test hull")
	root.add_child(model)
	var target := Target.new()
	model.add_child(target)
	var mesh := MeshInstance3D.new()
	var hull := SphereMesh.new()
	hull.radius = 0.65
	hull.height = 1.3
	mesh.mesh = hull
	mesh.scale = Vector3(1.6,0.8,1.0)
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color(0.13,0.21,0.24)
	mesh.material_override = paint
	model.add_child(mesh)
	var pod := MeshInstance3D.new()
	pod.mesh = hull
	pod.material_override = paint
	pod.scale = Vector3(0.45,0.45,0.6)
	pod.position = Vector3(0.75,-0.32,0.4)
	model.add_child(pod)
	var original := StandardMaterial3D.new()
	original.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	original.albedo_color.a = 0.0
	pod.material_overlay = original
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0.2,0.8,3.9)
	camera.look_at(model.position)
	camera.make_current()
	var native := DisplayServer.get_name() != "headless"
	var baseline: Image
	if native:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(720,480)
		await process_frame
		await RenderingServer.frame_post_draw
		baseline = root.get_texture().get_image()
	var track := ReplayVisual.new()
	track.setup(mesh,0.0)
	track.record(0,0.0)
	Surge.strike(target)
	var effect := model.get_node_or_null(Surge.NODE_NAME)
	check(effect != null and mesh.material_overlay is ShaderMaterial and pod.material_overlay is ShaderMaterial,"A collision-child hit covers both hull and pod")
	if effect == null or mesh.material_overlay == null:
		quit(1)
		return
	effect.set_process(false)
	check(pod.material_overlay.next_pass == original,"A model's existing pass is retained during the surge")
	check(is_equal_approx(float(mesh.material_overlay.get_shader_parameter("arc_strength")),1.0),"The hull opens at full surge strength")
	track.record(1,0.01)
	if native:
		await RenderingServer.frame_post_draw
		var energized := root.get_texture().get_image()
		var left := 0
		var right := 0
		for y in range(0,energized.get_height(),2):
			for x in range(0,energized.get_width(),2):
				if energized.get_pixel(x,y).b - baseline.get_pixel(x,y).b <= 0.12: continue
				if x < energized.get_width() / 2.0: left += 1
				else: right += 1
		check(left > 150 and right > 150,"Visible blue filaments cover both sides of the hull")
		var paths := OS.get_cmdline_user_args()
		if not paths.is_empty(): energized.save_png(paths[0])
	# Simulate sustained contact followed by release and recontact.
	for step in range(20):
		effect._process(0.02)
		Surge.strike(target)
	check(absf(float(mesh.material_overlay.get_shader_parameter("arc_strength")) - Surge.HOLD_STRENGTH) < 0.01,"Continuous hits retain one crawling effect")
	for step in range(20): effect._process(0.02)
	var fading: float = mesh.material_overlay.get_shader_parameter("arc_strength")
	check(fading > 0.0 and fading < Surge.HOLD_STRENGTH,"Electrical energy decays after contact ends")
	track.record(2,0.41)
	Surge.strike(target)
	effect._process(0.01)
	var recovered: float = mesh.material_overlay.get_shader_parameter("arc_strength")
	check(recovered > fading and recovered < Surge.HOLD_STRENGTH,"Recontact ramps the same overlay up smoothly")
	effect._process(Surge.FADE_TIME)
	check(mesh.material_overlay == null and pod.material_overlay == original,"The completed fade restores the original passes")
	track.record(3,1.12)
	var preview := Node3D.new()
	root.add_child(preview)
	track.show_at(preview,1,0.0,0.01)
	check(is_equal_approx(float(track.proxy.material_overlay.get_shader_parameter("arc_strength")),1.0),"Replay restores the opening surge")
	track.show_at(preview,2,0.0,0.41)
	check(is_equal_approx(float(track.proxy.material_overlay.get_shader_parameter("arc_strength")),fading),"Replay restores a fading frame")
	track.show_at(preview,3,0.0,1.12)
	check(track.proxy.material_overlay == null,"Replay clears the pass at expiration")
	await process_frame
	Surge.strike(target)
	root.remove_child(model)
	check(mesh.material_overlay == null and pod.material_overlay == original,"Early cleanup restores original materials")
	root.add_child(model)
	check(mesh.material_overlay == null and model.get_node(Surge.NODE_NAME).is_queued_for_deletion(),"Reused models do not inherit an earlier contact")
	print("Zapper hull surge: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
