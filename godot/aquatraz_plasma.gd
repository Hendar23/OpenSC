extends Node3D
## PLASMA0043b1d0/0043af50: animated globe, swept impacts,100-tick life.
var game: Node
var frames: Array[Texture2D] = []
var exclusions: Array[RID] = []
var velocity := Vector3.ZERO
var heading := Vector3.FORWARD
var age := 0.0
var sprite: Sprite3D

func setup(context: Node, textures: Array[Texture2D], point: Vector3, direction: Vector3, ignore: Array[RID]) -> void:
	game = context; frames = textures; heading = direction.normalized(); exclusions = ignore
	add_to_group("aquatraz_plasma")
	game.events.session_started.connect(_session_started)
	global_position = point
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	sprite = Sprite3D.new(); sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	if not frames.is_empty():
		sprite.texture = frames[0]; sprite.pixel_size = 0.4/maxf(1,frames[0].get_width())
		sprite.material_override = preload("res://natural_light.gd").billboard_material(frames[0])
		sprite.material_override.set_shader_parameter("emission_texture",frames[0])
		sprite.material_override.set_shader_parameter("has_emission_texture",true)
		sprite.material_override.set_shader_parameter("emission_color",Color.WHITE)
	add_child(sprite); reset_physics_interpolation()

func _session_started(_restored: bool) -> void:
	queue_free()

func _physics_process(delta: float) -> void:
	age += delta
	if age >= 4.0: queue_free(); return
	# Original .0025 impulse on a .1-mass projectile at25Hz.
	velocity = (velocity+heading*(0.0025/0.1*625.0)*delta)*pow(0.9090909,delta*25.0)
	var next := global_position+velocity*delta
	var query := PhysicsRayQueryParameters3D.create(global_position,next,15,exclusions)
	query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		preload("res://original_damage.gd").weapon(hit.collider,0.2,hit.position,null)
		var effect := preload("res://mine_explosion.gd").new(); get_parent().add_child(effect)
		effect.global_position = hit.position
		effect.setup(game.submarine_traffic.explosion_frames,0.5,game.submarine_traffic.explosion_sound)
		queue_free(); return
	global_position = next
	if frames.is_empty(): return
	sprite.texture = frames[posmod(int(age*25),frames.size())]
	sprite.material_override.set_shader_parameter("albedo_texture",sprite.texture)
	sprite.material_override.set_shader_parameter("emission_texture",sprite.texture)
