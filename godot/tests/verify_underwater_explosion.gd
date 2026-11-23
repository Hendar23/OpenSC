extends SceneTree

const Blast = preload("res://mine_explosion.gd")
const Visual = preload("res://replay_visual.gd")
const Bubbles = preload("res://propeller_bubbles.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(960,540)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.035,0.15,0.22)
	world.add_child(environment)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0,0.67,4.0)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var emitter := Bubbles.new()
	world.add_child(emitter)
	emitter.add_to_group("blast_bubble_emitter")
	emitter.surface_height = 100.0
	emitter.set_process(false)
	emitter.set_physics_process(false)
	var old_sound := AudioStreamWAV.new()
	var image := Image.create_empty(8,8,false,Image.FORMAT_RGBA8)
	image.fill(Color.ORANGE_RED)
	var frames: Array[Texture2D] = [ImageTexture.create_from_image(image)]
	Blast.audio_random.seed = 450455
	var blast := Blast.new()
	world.add_child(blast)
	blast.set_process(false)
	blast.setup(frames,2.34,old_sound)
	check(blast.remastered and blast.volume != null and blast.sprite == null,"Remastered visuals are the default")
	check(is_equal_approx(blast.size,2.34) and is_equal_approx(float(blast.volume_material.get_shader_parameter("blast_unit")),1.4)
		and is_equal_approx(blast.volume.custom_aabb.size.x,8.4 * 1.4),"The remastered volume and its bounds scale up together")
	check(blast.audio.stream == Blast.RemasterSound and absf(blast.audio.pitch_scale - 1.0) <= Blast.PITCH_VARIATION + 0.00001 and blast.lifetime >= blast.audio.stream.get_length() / blast.audio.pitch_scale,"Remastered audio varies subtly and keeps its full tail")
	var repeat := Blast.new()
	world.add_child(repeat)
	repeat.setup(frames,1.0,old_sound)
	check(not is_equal_approx(repeat.audio.pitch_scale,blast.audio.pitch_scale),"Consecutive blasts get their own pitch")
	repeat.free()
	var collapse_start := Blast.COLLAPSE_START_TIME
	var collapse_end := Blast.COLLAPSE_END_TIME
	blast._process(collapse_start)
	check(is_equal_approx(float(blast.volume_material.get_shader_parameter("blast_age")),0.81) and emitter.particles.is_empty(),"Opening and expansion are visible before rupture")
	check(Blast.remaster_phase(1.0 / 30.0) > 0.055 and Blast.remaster_phase(2.0 / 30.0) < 0.16,"Opening flash stays readable at 30 FPS")
	check(collapse_start - Blast.OPENING_END_TIME < 0.15 and collapse_end - collapse_start < 0.15,"Bubble expansion and collapse use the faster timings")
	check(is_equal_approx(blast.audio.unit_size,4.5) and is_zero_approx(blast.audio.volume_db),"Default remastered audio is louder and reaches combat distance")
	var track := Visual.new()
	track.setup(blast.volume,0.0)
	track.record(0,0.0)
	blast._process(collapse_end - collapse_start)
	track.record(1,0.15)
	check(emitter.particles.size() == 96,"Rupture emits a single stock bubble cloud")
	blast._process(0.1)
	check(emitter.particles.size() == 96,"Rupture does not repeat")
	emitter.advance(1.0,false)
	check(emitter.particles.is_empty(),"Remastered bubbles expire after their authored fade, even far below the surface")
	track.show_at(world,0,0,0)
	check(track.proxy.visible and is_equal_approx(float(track.proxy.material_override.get_shader_parameter("blast_age")),0.81),"Photo replay restores an earlier volume phase")
	track.show_at(world,0,0.5,0.075)
	check(is_equal_approx(float(track.proxy.material_override.get_shader_parameter("blast_age")),1.005),"Photo replay interpolates the blast between recorded frames")
	check(track.versions.size() == 1,"Animating the blast phase does not duplicate material history")
	track.dispose()
	_verify_debris(world)
	var secondary_frames: Array[Texture2D] = []
	secondary_frames.resize(12)
	secondary_frames.fill(frames[0])
	var secondary := Blast.new()
	world.add_child(secondary)
	secondary.set_process(false)
	secondary.setup(secondary_frames,0.5,null,false)
	secondary._process(1.0 / 30.0)
	var small_phase: float = secondary.volume_material.get_shader_parameter("blast_age")
	check(small_phase > 0.055 and small_phase < 0.16 and is_equal_approx(secondary.lifetime,0.5),"Short wreck bursts show their opening flash and keep their original lifetime")
	secondary.free()
	if DisplayServer.get_name() != "headless":
		await _visual_check(world,blast)
	Blast.classic_enabled = true
	var classic := Blast.new()
	world.add_child(classic)
	classic.setup(frames,2.34,old_sound)
	check(not classic.remastered and classic.sprite != null and classic.lobes.size() == 8 and classic.audio.stream == old_sound,"Classic restores existing layered sprites and original audio")
	check(is_equal_approx(classic.audio.unit_size,2.0) and is_equal_approx(classic.audio.volume_db,-10.0),"Classic retains the previous gain and distance falloff")
	Blast.classic_enabled = false
	world.free()
	print("Underwater explosion: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _verify_debris(world: Node3D) -> void:
	var wreck := preload("res://submarine_death.gd").new()
	world.add_child(wreck)
	wreck.set_process(false)
	wreck.position = Vector3(10,10,10)
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	part.position = Vector3(0.5,0,0)
	wreck.add_child(part)
	var piece := {"node":part,"velocity":Vector3(3,1,0),"spin":Vector3.ZERO,"settled":false}
	wreck.pieces.append(piece)
	wreck.configure_bubble_collapse(2.34)
	wreck.age = Blast.COLLAPSE_START_TIME
	wreck._move_chunk(piece,0.01)
	var spread := part.position.length()
	wreck.age = Blast.COLLAPSE_END_TIME
	wreck._move_chunk(piece,0.01)
	check(is_equal_approx(wreck.INITIAL_SCATTER,1.80) and spread > 1.0 and part.position.length() < spread * 0.5,"Hull fragments scatter at the approved setting and retract during collapse")
	check(not piece.has("rest_position"),"Fragments return to normal sinking after the collapse")
	wreck.free()

func _visual_check(world: Node3D, blast: Node3D) -> void:
	var output := OS.get_environment("OPENSC_BLAST_TEST_OUTPUT")
	blast.volume.hide()
	var baseline := await _frame()
	blast.volume.show()
	blast.volume_material.set_shader_parameter("blast_age",0.05)
	var flash := await _frame()
	blast.volume_material.set_shader_parameter("blast_age",0.81)
	var shell := await _frame()
	blast.volume_material.set_shader_parameter("blast_age",3.2)
	var smoke := await _frame()
	var center := Vector2i(flash.get_size() / 2)
	check(flash.get_pixelv(center).r > baseline.get_pixelv(center).r + 0.3,"Opening flash is visible")
	check(_differences(shell,baseline) > 32,"Smoke-filled shell is visible")
	check(_differences(smoke,baseline) > 32,"Lingering smoke is visible")
	var wall := MeshInstance3D.new()
	var mesh := BoxMesh.new(); mesh.size = Vector3(8,8,0.4)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.14,0.43,0.31)
	mesh.material = material
	wall.mesh = mesh
	wall.position.z = 3.1
	world.add_child(wall)
	blast.volume.hide()
	var wall_baseline := await _frame()
	blast.volume.show()
	blast.volume_material.set_shader_parameter("blast_age",0.05)
	var wall_flash := await _frame()
	check(_differences(wall_baseline,wall_flash) == 0,"Opaque foreground geometry hides the blast")
	if not output.is_empty():
		flash.save_png(output.path_join("flash.png"))
		shell.save_png(output.path_join("shell.png"))
		smoke.save_png(output.path_join("smoke.png"))
	wall.free()
	await _verify_off_axis_bounds(world.get_viewport().get_camera_3d(), blast, output)

func _verify_off_axis_bounds(camera: Camera3D, blast: Node3D, output: String) -> void:
	camera.global_transform = Transform3D.IDENTITY
	var normal: ShaderMaterial = blast.volume_material
	var reference := normal.duplicate() as ShaderMaterial
	var shader := Shader.new()
	var code := normal.shader.code
	var start := code.find("void vertex()")
	var finish := code.find("void fragment()",start)
	shader.code = code.substr(0,start) + """
void vertex() {
	blast_center = MODEL_MATRIX[3].xyz;
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}
""" + code.substr(finish)
	reference.shader = shader
	reference.set_shader_parameter("blast_noise",Blast.RemasterNoise)
	reference.set_shader_parameter("blast_unit",normal.get_shader_parameter("blast_unit"))
	for sample in [
		[Vector3(1.8,-4.6,-8.0),0.81,"shell below centre"],
		[Vector3(1.8,-4.6,-8.0),2.4,"smoke below centre"],
		[Vector3(-3.2,4.3,-8.0),2.4,"smoke above centre"],
		[Vector3(2.0,-0.8,-1.8),0.81,"shell near camera"],
	]:
		blast.global_position = sample[0]
		normal.set_shader_parameter("blast_age",sample[1])
		reference.set_shader_parameter("blast_age",sample[1])
		blast.volume.material_override = normal
		var bounded := await _frame()
		blast.volume.material_override = reference
		await RenderingServer.frame_post_draw
		var uncropped := await _frame()
		var differences := _differences(bounded,uncropped)
		check(differences == 0,"%s matches an unbounded projection (%d differing samples)" % [sample[2],differences])
		if not output.is_empty() and sample[2] == "smoke below centre":
			bounded.save_png(output.path_join("off-axis-smoke.png"))
			uncropped.save_png(output.path_join("off-axis-reference.png"))
		if not output.is_empty() and sample[2] == "shell near camera" and differences > 0:
			bounded.save_png(output.path_join("near-shell.png"))
			uncropped.save_png(output.path_join("near-reference.png"))
	blast.volume.material_override = normal

func _frame() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _differences(first: Image, second: Image) -> int:
	var count := 0
	for y in range(16,first.get_height()-16,6):
		for x in range(16,first.get_width()-16,6):
			var a := first.get_pixel(x,y)
			var b := second.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.035:
				count += 1
	return count
