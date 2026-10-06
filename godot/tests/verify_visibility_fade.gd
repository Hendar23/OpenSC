extends SceneTree
const Natural = preload("res://natural_light.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(0); return
	Natural.ensure_globals()
	RenderingServer.global_shader_parameter_set("osc_natural_fog",Vector3(18,1.5,1))
	var view := SubViewport.new(); view.size = Vector2i(64,64); view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var camera := Camera3D.new(); camera.current = true; camera.fov = 90; view.add_child(camera)
	var mesh := MeshInstance3D.new(); mesh.mesh = QuadMesh.new(); mesh.mesh.size = Vector2(20,20); view.add_child(mesh)
	var material := ShaderMaterial.new(); var shader := Shader.new()
	shader.code = 'shader_type spatial; render_mode unshaded, fog_disabled;\n#include "res://natural_light.gdshaderinc"\nvoid fragment() { ALBEDO = vec3(1.0 - natural_fog_amount(length(VERTEX))); }'
	material.shader = shader; mesh.material_override = material
	var samples: Array[float] = []
	var strip := Image.create(64 * 9,64,false,Image.FORMAT_RGB8)
	for progress in [0.0,0.25,0.5,0.75,0.9,0.95,0.99,1.0,1.1]:
		mesh.position.z = -(1.5 + float(progress) * 16.5)
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		var pixels := view.get_texture().get_image()
		pixels.convert(Image.FORMAT_RGB8)
		strip.blit_rect(pixels,Rect2i(0,0,64,64),Vector2i(samples.size() * 64,0))
		samples.append(pixels.get_pixel(32,32).r)
	check(samples[0] > 0.99 and samples[7] < 0.001 and samples[8] < 0.001,"Clear range and complete fog limit remain unchanged")
	var monotonic := true
	for index in range(1,samples.size()): monotonic = monotonic and samples[index] <= samples[index - 1]
	check(monotonic and samples[2] > samples[4],"Actual rendered shader fades continuously with distance")
	check(samples[5] - samples[6] < 0.025 and samples[6] - samples[7] < 0.005,"Contrast emerges gently at the visibility boundary")
	strip.save_png("res://tests/visibility-fade-preview.png")
	print("Visibility fade samples: ",samples)
	print("Visibility fade: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
