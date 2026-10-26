extends Node3D
const Assets = preload("res://clump_loader.gd")
var frames: Array[Texture2D] = []
var sprite: Sprite3D
var material: ShaderMaterial
var audio: AudioStreamPlayer3D
var age := 0.0
static var effect_shader: Shader
static var enhanced_enabled := true
static var smoke_frames: Array[Texture2D] = []
var enhanced := false
var lobes: Array[Dictionary] = []
var clouds: Array[Dictionary] = []
var size := 1.0
var spill_over := false
const FRAME_RATE := 24.0
static func load_frames(folder: String, cache: Dictionary = {}) -> Array[Texture2D]:
	smoke_frames.clear()
	for index in range(1,4):
		smoke_frames.append(Assets._load_texture(folder,"SMOKE%d" % index,"SMOKE%dM" % index,cache))
	var result: Array[Texture2D] = []
	for index in range(1,13):
		var texture := Assets._load_texture(folder,"EX%d" % index,"EX%dM" % index,cache)
		if texture != null: result.append(texture)
	return result
func setup(animation: Array[Texture2D], diameter: float, sound: AudioStream) -> void:
	name = "MineExplosion"; frames = animation; enhanced = enhanced_enabled and get_tree().get_nodes_in_group("enhanced_explosions").size() < 12; size = maxf(0.1,diameter)
	if not frames.is_empty():
		sprite = Sprite3D.new(); sprite.texture = frames[0]; sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.pixel_size = maxf(0.1,diameter) / maxf(frames[0].get_width(),frames[0].get_height())
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		material = preload("res://natural_light.gd").billboard_material(frames[0])
		material.set_shader_parameter("emission_color",Color.WHITE); material.set_shader_parameter("has_emission_texture",true); material.set_shader_parameter("emission_texture",frames[0])
		sprite.material_override = material; add_child(sprite)
	if enhanced:
		add_to_group("enhanced_explosions"); _build_layers()
	for receiver in get_tree().get_nodes_in_group("explosion_camera_shake"):
		receiver.blast(global_position,size)
	var light := OmniLight3D.new(); light.light_color = Color(1,0.65,0.2); light.light_energy = 3.0; light.omni_range = maxf(1.0,diameter * 1.5); add_child(light)
	var tween := create_tween(); tween.tween_property(light,"light_energy",0.0,0.5)
	if sound != null:
		audio = AudioStreamPlayer3D.new(); audio.stream = sound; audio.max_distance = 60; add_child(audio); preload("res://explosion_audio.gd").apply(audio); audio.play()
func _process(delta: float) -> void:
	preload("res://explosion_audio.gd").apply(audio)
	age += delta
	if sprite != null:
		var index := int(age * FRAME_RATE)
		if index >= frames.size(): sprite.hide()
		else:
			sprite.texture = frames[index]; material.set_shader_parameter("albedo_texture",frames[index]); material.set_shader_parameter("emission_texture",frames[index])
	if enhanced: _animate_layers()
	if age >= (4.5 if enhanced else 3.0): queue_free()

func _quad(texture: Texture2D, glow: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.mesh = QuadMesh.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := preload("res://natural_light.gd").billboard_material(texture)
	if effect_shader == null:
		effect_shader = Shader.new()
		effect_shader.code = preload("res://natural_light.gd").alpha_shader().code.replace("filter_nearest","filter_linear")
	mat.shader = effect_shader
	if glow:
		mat.set_shader_parameter("emission_color",Color(1.0,0.65,0.28))
		mat.set_shader_parameter("has_emission_texture",true); mat.set_shader_parameter("emission_texture",texture)
	else: mat.set_shader_parameter("albedo_color",Color(0.48,0.53,0.55))
	node.material_override = mat; node.hide(); add_child(node)
	return node

func _build_layers() -> void:
	# Fixed budgets: eight staggered bursts and twelve smoke billboards,
	# no particle collisions or shadow-casting lights.
	if not frames.is_empty():
		for index in range(8):
			var angle := float(index) * TAU / 8.0
			var direction := Vector3(cos(angle),0.25 + float(index % 3) * 0.2,sin(angle))
			var upward := spill_over and index < 2
			if spill_over:
				angle = float(index-2)*TAU/6.0
				direction = Vector3.UP if upward else Vector3(cos(angle),0,sin(angle))
			var node := _quad(frames[0],true)
			if upward: node.material_override.render_priority = 1
			lobes.append({"node":node,"direction":direction,"upward":upward,"delay":float(index % 4) * 0.055,"scale":size * (0.7 if upward else 0.45 + float(index % 3) * 0.12)})
	for index in range(12):
		var texture: Texture2D = smoke_frames[index % smoke_frames.size()] if not smoke_frames.is_empty() else null
		if texture == null: continue
		var angle := float(index) * 2.39996
		clouds.append({"node":_quad(texture,false),"direction":Vector3(cos(angle),0.3 + float(index % 4) * 0.18,sin(angle)),"delay":0.4 + float(index % 3) * 0.08})

func _animate_layers() -> void:
	if sprite != null: sprite.scale = Vector3.ONE * (1.0 + minf(age,0.5) * 1.2)
	for lobe in lobes:
		var time: float = age - lobe.delay
		var index := int(time * 18.0)
		var node: MeshInstance3D = lobe.node
		node.visible = time >= 0 and index < frames.size()
		if not node.visible: continue
		node.position = lobe.direction * size * (0.12 + time * 0.7)
		if spill_over:
			var reach := size*(0.3+time*1.4)
			node.position = Vector3.UP*size*(0.15+time*2.8) if lobe.upward else Vector3(lobe.direction.x*reach,size*(0.12+time*0.9-time*time*1.9),lobe.direction.z*reach)
		node.scale = Vector3.ONE * lobe.scale * (0.7 + time * 1.5)
		if spill_over and lobe.upward: node.scale.y *= 1.8
		node.material_override.set_shader_parameter("albedo_texture",frames[index])
		node.material_override.set_shader_parameter("emission_texture",frames[index])
	for cloud in clouds:
		var time: float = age - cloud.delay
		var fraction := clampf(time / 3.7,0,1)
		var node: MeshInstance3D = cloud.node
		node.visible = time > 0 and fraction < 1
		node.position = cloud.direction * size * (0.15 + (1.0 - exp(-time * 1.6)) * 0.7) + Vector3.UP * maxf(0,time) * size * 0.12
		node.scale = Vector3.ONE * size * (0.35 + fraction * 1.1)
		node.material_override.set_shader_parameter("opacity",minf(fraction * 12.0,0.52) * (1.0 - fraction) * (1.0 - fraction))
