extends Node3D
const Assets = preload("res://clump_loader.gd")
const NaturalLight = preload("res://natural_light.gd")
const RemasterShader = preload("res://underwater_explosion.gdshader")
const RemasterNoise = preload("res://game_assets/effects/blast-noise.res")
const RemasterSound = preload("res://game_assets/audio/underwater-explosion.mp3")
const REMASTER_RATE := 2.0 * 1.40
const REMASTER_END := 5.70
const OPENING_END := 0.26
const OPENING_HOLD := 0.045
const EXPANSION_RATE := 4.0
const COLLAPSE_START := 0.81
const COLLAPSE_END := 1.20
const OPENING_END_TIME := OPENING_END / REMASTER_RATE + OPENING_HOLD
const COLLAPSE_START_TIME := OPENING_END_TIME + (COLLAPSE_START - OPENING_END) / EXPANSION_RATE
const COLLAPSE_END_TIME := COLLAPSE_START_TIME + (COLLAPSE_END - COLLAPSE_START) / REMASTER_RATE
const VISUAL_DURATION := COLLAPSE_END_TIME + (REMASTER_END - COLLAPSE_END) / REMASTER_RATE
const RUPTURE := 1.17
const BUBBLE_END := 3.65
const EXPLOSION_DIAMETER := 2.34
const REMASTER_SIZE_SCALE := 1.40
const RUPTURE_OFFSET := Vector3(-0.14,0.095,-0.025)
const REMASTER_GAIN := 10.0
const REMASTER_NEAR_DISTANCE := 4.5
const PITCH_VARIATION := 0.04
var frames: Array[Texture2D] = []
var sprite: Sprite3D
var material: ShaderMaterial
var audio: AudioStreamPlayer3D
var age := 0.0
var lifetime := 3.0
static var effect_shader: Shader
static var enhanced_enabled := true
static var classic_enabled := false
static var smoke_frames: Array[Texture2D] = []
var enhanced := false
var remastered := false
var volume: MeshInstance3D
var volume_material: ShaderMaterial
var remaster_light: OmniLight3D
var full_volume := false
var emit_bubbles := false
var lobes: Array[Dictionary] = []
var clouds: Array[Dictionary] = []
var size := 1.0
var spill_over := false
const FRAME_RATE := 24.0
static var volume_mesh: QuadMesh
static var audio_random := RandomNumberGenerator.new()

static func remaster_unit(diameter: float) -> float:
	return maxf(0.1,diameter) * REMASTER_SIZE_SCALE / EXPLOSION_DIAMETER

static func warm_up(world: Node3D, camera: Camera3D) -> void:
	if DisplayServer.get_name() == "headless" or camera == null: return
	var probe := new()
	world.add_child(probe)
	probe.set_process(false)
	probe.global_position = camera.global_position - camera.global_basis.z * 3.0
	probe._setup_volume(false)
	probe.volume_material.set_shader_parameter("blast_age",REMASTER_END)
	await world.get_tree().process_frame
	await world.get_tree().process_frame
	probe.queue_free()

static func remaster_phase(elapsed: float) -> float:
	if elapsed < OPENING_END_TIME:
		return elapsed * OPENING_END / OPENING_END_TIME
	if elapsed < COLLAPSE_START_TIME:
		return OPENING_END + (elapsed - OPENING_END_TIME) * EXPANSION_RATE
	return COLLAPSE_START + (elapsed - COLLAPSE_START_TIME) * REMASTER_RATE

func _short_phase() -> float:
	var opening_end := minf(OPENING_END_TIME,lifetime * 0.4)
	if age < opening_end: return age * OPENING_END / opening_end
	return lerpf(OPENING_END,REMASTER_END,inverse_lerp(opening_end,lifetime,age))
static func load_frames(folder: String, cache: Dictionary = {}) -> Array[Texture2D]:
	smoke_frames.clear()
	for index in range(1,4):
		smoke_frames.append(Assets._load_texture(folder,"SMOKE%d" % index,"SMOKE%dM" % index,cache))
	var result: Array[Texture2D] = []
	for index in range(1,13):
		var texture := Assets._load_texture(folder,"EX%d" % index,"EX%dM" % index,cache)
		if texture != null: result.append(texture)
	return result
func setup(animation: Array[Texture2D], diameter: float, sound: AudioStream, full_effect: bool = true) -> void:
	name = "MineExplosion"; frames = animation; size = maxf(0.1,diameter)
	remastered = not classic_enabled
	if remastered:
		_setup_volume(full_effect)
	else:
		_setup_classic(full_effect)
	if not full_effect: return
	for receiver in get_tree().get_nodes_in_group("explosion_camera_shake"):
		receiver.blast(global_position,size)
	var light := OmniLight3D.new(); light.light_color = Color(1,0.65,0.2); light.light_energy = 3.0; light.omni_range = maxf(1.0,diameter * 1.5); add_child(light)
	if remastered:
		light.omni_range *= REMASTER_SIZE_SCALE
		remaster_light = light
		_update_remaster_light(0.0)
	else:
		var tween := create_tween(); tween.tween_property(light,"light_energy",0.0,0.5)
	if sound != null:
		audio = AudioStreamPlayer3D.new()
		audio.stream = RemasterSound if remastered else sound
		if remastered: audio.pitch_scale = audio_random.randf_range(1.0 - PITCH_VARIATION,1.0 + PITCH_VARIATION)
		add_child(audio)
		_update_audio()
		audio.play()
		if remastered: lifetime = maxf(lifetime,audio.stream.get_length() / audio.pitch_scale + 0.15)

func _setup_volume(full_effect: bool) -> void:
	NaturalLight.ensure_globals()
	full_volume = full_effect
	lifetime = VISUAL_DURATION if full_effect else maxf(0.1,frames.size() / FRAME_RATE)
	if full_effect:
		add_to_group("enhanced_explosions")
		emit_bubbles = true
	if volume_mesh == null:
		volume_mesh = QuadMesh.new()
		volume_mesh.size = Vector2(2.0,2.0)
	volume = MeshInstance3D.new()
	volume.mesh = volume_mesh
	var unit := remaster_unit(size)
	var extent := Vector3.ONE * (4.2 * unit)
	volume.custom_aabb = AABB(-extent,extent * 2.0)
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	volume.set_meta("replay_blast_phase",true)
	volume_material = ShaderMaterial.new()
	volume_material.shader = RemasterShader
	volume_material.set_shader_parameter("blast_noise",RemasterNoise)
	volume_material.set_shader_parameter("blast_age",0.0)
	volume_material.set_shader_parameter("blast_unit",unit)
	volume_material.set_shader_parameter("spill_over",spill_over)
	volume.material_override = volume_material
	add_child(volume)

func _setup_classic(full_effect: bool) -> void:
	enhanced = full_effect and enhanced_enabled and get_tree().get_nodes_in_group("enhanced_explosions").size() < 12
	if not frames.is_empty():
		sprite = Sprite3D.new(); sprite.texture = frames[0]; sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.pixel_size = size / maxf(frames[0].get_width(),frames[0].get_height())
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		material = preload("res://natural_light.gd").billboard_material(frames[0])
		material.set_shader_parameter("emission_color",Color.WHITE); material.set_shader_parameter("has_emission_texture",true); material.set_shader_parameter("emission_texture",frames[0])
		sprite.material_override = material; add_child(sprite)
	if not full_effect:
		lifetime = maxf(0.1,frames.size() / FRAME_RATE)
		return
	if enhanced:
		lifetime = 4.5
		add_to_group("enhanced_explosions"); _build_layers()

func _update_audio() -> void:
	if remastered:
		preload("res://explosion_audio.gd").apply(audio,REMASTER_GAIN,"explosion_volume",REMASTER_NEAR_DISTANCE)
	else:
		preload("res://explosion_audio.gd").apply(audio)

func _process(delta: float) -> void:
	_update_audio()
	age += delta
	if remastered:
		_advance_volume()
	else:
		_advance_classic()
	if age >= lifetime: queue_free()

func _advance_volume() -> void:
	if not volume.visible: return
	var time := remaster_phase(age) if full_volume else _short_phase()
	volume_material.set_shader_parameter("blast_age",time)
	if remaster_light != null: _update_remaster_light(time)
	if emit_bubbles and time >= RUPTURE:
		emit_bubbles = false
		var emitter := get_tree().get_first_node_in_group("blast_bubble_emitter")
		if emitter != null:
			var point := global_position + RUPTURE_OFFSET * remaster_unit(size)
			emitter.emit_blast_cloud(point,size * REMASTER_SIZE_SCALE,(BUBBLE_END - RUPTURE) / REMASTER_RATE,REMASTER_RATE)
	if time >= REMASTER_END and volume.visible:
		volume.hide()
		if is_in_group("enhanced_explosions"): remove_from_group("enhanced_explosions")

func _update_remaster_light(time: float) -> void:
	var flash := smoothstep(0.0,0.026,time) * (1.0 - smoothstep(0.055,0.16,time))
	var first_fire := (time - 0.19) / 0.13
	var reignition := (time - 1.115) / 0.085
	remaster_light.light_energy = 3.0 * flash + 0.70 * exp(-first_fire * first_fire) + exp(-reignition * reignition)

func _advance_classic() -> void:
	if sprite != null:
		var index := int(age * FRAME_RATE)
		if index >= frames.size(): sprite.hide()
		else:
			sprite.texture = frames[index]; material.set_shader_parameter("albedo_texture",frames[index]); material.set_shader_parameter("emission_texture",frames[index])
	if enhanced: _animate_layers()

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
