extends Node3D
const Assets = preload("res://clump_loader.gd")
var frames: Array[Texture2D] = []
var sprite: Sprite3D
var material: ShaderMaterial
var audio: AudioStreamPlayer3D
var age := 0.0
const FRAME_RATE := 24.0
static func load_frames(folder: String, cache: Dictionary = {}) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for index in range(1,13):
		var texture := Assets._load_texture(folder,"EX%d" % index,"EX%dM" % index,cache)
		if texture != null: result.append(texture)
	return result
func setup(animation: Array[Texture2D], diameter: float, sound: AudioStream) -> void:
	name = "MineExplosion"; frames = animation
	if not frames.is_empty():
		sprite = Sprite3D.new(); sprite.texture = frames[0]; sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.pixel_size = maxf(0.1,diameter) / maxf(frames[0].get_width(),frames[0].get_height())
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		material = preload("res://natural_light.gd").billboard_material(frames[0])
		material.set_shader_parameter("emission_color",Color.WHITE); material.set_shader_parameter("has_emission_texture",true); material.set_shader_parameter("emission_texture",frames[0])
		sprite.material_override = material; add_child(sprite)
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
	if age >= 3.0: queue_free()
