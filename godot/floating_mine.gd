extends StaticBody3D
signal exploded(position: Vector3, damage: float, radius: float)
var health := 0.5
var dead := false
var stats := {}
var player: Node3D
var armed := true
var home := Vector3.ZERO
var age := 0.0
var phase := 0.0
var explosion_sound: AudioStream
var explosion_frames: Array[Texture2D] = []
func setup(definition: Dictionary, appearance: Node3D, sound: AudioStream, enabled: bool) -> void:
	stats = definition.duplicate(true); health = float(stats.health); armed = enabled; explosion_sound = sound
	set_meta("damage_sustain",float(stats.get("damage_sustain",0.1)))
	collision_layer = 8; collision_mask = 0
	add_child(appearance)
	var collider := CollisionShape3D.new(); var sphere := SphereShape3D.new()
	sphere.radius = float(stats.size) * 0.5; collider.shape = sphere; add_child(collider)
func _physics_process(delta: float) -> void:
	if dead or not armed: return
	age += delta
	position = home + Vector3(0,sin(age * 1.4 + phase) * minf(0.06,float(stats.size) * 0.06),0)
	if is_instance_valid(player) and bool(player.get("active")) and bool(player.get("controls_enabled")):
		if float(stats.trigger_distance) > 0.0 and global_position.distance_to(player.global_position) <= float(stats.trigger_distance):
			detonate()
		elif bool(stats.get("trigger_on_contact",true)):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = get_child(1).shape; query.transform = global_transform
			query.collision_mask = player.collision_layer; query.exclude = [get_rid()]
			for hit in get_world_3d().direct_space_state.intersect_shape(query,64):
				if hit.collider == player:
					detonate(); break
func take_damage(amount: float, _source: Vector3 = Vector3.ZERO) -> void:
	if dead or not armed or amount <= 0.0: return
	health -= amount
	if health < 0.0: detonate()
func detonate() -> void:
	if dead or not armed: return
	dead = true; collision_layer = 0; hide()
	var point := global_position
	var burst := preload("res://mine_explosion.gd").new(); get_parent().add_child(burst); burst.global_position = point
	burst.setup(explosion_frames,float(stats.size) * 3.0,explosion_sound)
	exploded.emit(point,float(stats.damage),float(stats.explosion_radius))
