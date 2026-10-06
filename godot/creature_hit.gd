extends Node3D
## Small, bounded blood puffs for nonlethal weapon feedback.
const NaturalLight = preload("res://natural_light.gd")
var particles: Array[Dictionary] = []
var random := RandomNumberGenerator.new()

func _ready() -> void:
	name = "CreatureHitBlood"
	top_level = true
	global_transform = Transform3D.IDENTITY
	random.randomize()

func emit_hit(point: Vector3, normal: Vector3, frames: Array[Texture2D], amount: float, lifetime: float, settle_speed: float) -> void:
	if frames.is_empty() or amount <= 0.0: return
	# A hit is a small puff rather than the full death burst. Respect the gore slider.
	var count := clampi(int(ceil(amount * 0.15)),1,6)
	for index in range(mini(count,32 - particles.size())):
		var sprite := Sprite3D.new()
		sprite.texture = frames[mini(2,frames.size() - 1)]
		sprite.material_override = NaturalLight.billboard_material(sprite.texture)
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.pixel_size = random.randf_range(0.002,0.0035)
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sprite); sprite.global_position = point + normal * 0.02
		var spread := Vector3(random.randf_range(-1,1),random.randf_range(-1,1),random.randf_range(-1,1))
		particles.append({"node":sprite,"velocity":normal * 0.35 + spread * 0.3,"age":0.0,"lifetime":clampf(lifetime,0.2,0.75),"settle":settle_speed,"frames":frames})

func _process(delta: float) -> void:
	for index in range(particles.size() - 1,-1,-1):
		var particle := particles[index]
		particle.age += delta
		if particle.age >= particle.lifetime:
			particle.node.queue_free(); particles.remove_at(index); continue
		particle.velocity *= exp(-2.0 * delta * particle.settle)
		particle.velocity.y -= delta * 0.15 * particle.settle
		particle.node.position += particle.velocity * delta
		particle.node.texture = particle.frames[mini(2 + int(particle.age * 12.0),particle.frames.size() - 1)]
		particle.node.material_override.set_shader_parameter("albedo_texture",particle.node.texture)
		particle.node.material_override.set_shader_parameter("opacity",clampf((particle.lifetime - particle.age) / 0.3,0.0,1.0))
