extends Node3D
signal destroyed(entity_id: String, attacker_id: String)
var mission_owner := ""
var damage_attacker: Node3D
var report_player_attack := true
## Original turret callback 0x4051f0; shields/sustain from OBJECTS.CSV.
const Damage = preload("res://original_damage.gd")
const DEFAULTS := {"turret_health":8.0,"turret_sustain":0.3,"turret_homing":false,"turret_armed":false,"turret_faction":0,"turret_range":20.0,"turret_turn_speed":12.5}
var tuning := DEFAULTS.duplicate()
var health := 8.0
var dead := false
var player: Node3D
var hostile: Callable
var missile_template: Node3D
var bubble_trail: Node3D
var bubble_texture: Texture2D
var explosion_frames: Array[Texture2D] = []
var explosion_sound: AudioStream
var head: Node3D
var rest_head := Transform3D.IDENTITY
var hitbox: StaticBody3D
var cooldown := 0.0
var retaliation := 0.0
var shots := 0
var local_simulation := true
var visibility_radius := 1.0
var collision_meshes: Array[MeshInstance3D] = []
var collision_shapes: Array[CollisionShape3D] = []

static func install(model: Node3D, values: Dictionary = {}) -> Node3D:
	var controller := model.get_node_or_null("GunTurret")
	if controller == null:
		controller = load("res://gun_turret.gd").new()
		controller.name = "GunTurret"; model.add_child(controller)
	var model_head := model.find_child("Frame_1",true,false) as Node3D
	if model_head == null:
		# Replacement models can provide an explicit articulated gun socket.
		model_head = model.find_child("TurretHead",true,false) as Node3D
	if controller.head != model_head:
		controller.head = model_head
		if model_head != null: controller.rest_head = model_head.transform
	controller.hitbox = model.get_node_or_null("SceneryCollision")
	var rebuild: bool = controller.collision_meshes.is_empty() or controller.collision_meshes.any(func(mesh: MeshInstance3D) -> bool: return not model.is_ancestor_of(mesh))
	if controller.hitbox != null and (rebuild or controller.hitbox.get_script() != load("res://turret_hitbox.gd")):
		controller.hitbox.set_script(load("res://turret_hitbox.gd"))
		var meshes: Array[MeshInstance3D] = []
		var shapes: Array[CollisionShape3D] = []
		controller.collision_meshes = meshes; controller.collision_shapes = shapes
		# Separate articulated surfaces so head collisions follow the barrel.
		for shape in controller.hitbox.get_children(): shape.free()
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh == null: continue
			var collider := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new(); shape.backface_collision = true; shape.set_faces(mesh.mesh.get_faces())
			collider.shape = shape; controller.hitbox.add_child(collider)
			controller.collision_meshes.append(mesh); controller.collision_shapes.append(collider)
		controller.sync_collision()
	controller.configure(values)
	controller.visibility_radius = 1.0
	for mesh in controller.collision_meshes:
		for corner in range(8):
			var point: Vector3 = mesh.global_transform * mesh.mesh.get_aabb().get_endpoint(corner)
			controller.visibility_radius = maxf(controller.visibility_radius,controller.global_position.distance_to(point))
	preload("res://entity_identity.gd").actor(model,controller,controller.hitbox)
	return controller

func configure(values: Dictionary) -> void:
	for key in DEFAULTS: tuning[key] = values.get(key,tuning[key])
	if not has_meta("initialized"):
		health = float(tuning.turret_health); set_meta("initialized",true)
	if hitbox != null: hitbox.set_meta("damage_sustain",float(tuning.turret_sustain))

func reset() -> void:
	health = float(tuning.turret_health); dead = false; cooldown = 0; retaliation = 0; shots = 0
	get_parent().show()
	if head != null: head.transform = rest_head
	sync_collision()
	if hitbox != null: hitbox.collision_layer = 1

func take_weapon_damage(strength: float, _source: Vector3 = Vector3.ZERO) -> void:
	if dead or not is_finite(strength) or strength <= 0: return
	health = maxf(0,health - strength * float(tuning.turret_sustain))
	if report_player_attack: activate(60.0)
	if health <= 0:
		dead = true; get_parent().hide()
		destroyed.emit(preload("res://entity_identity.gd").of(self),preload("res://entity_identity.gd").of(damage_attacker) if is_instance_valid(damage_attacker) else "")
		if hitbox != null: hitbox.collision_layer = 0
		var wreck := preload("res://submarine_death.gd").new()
		get_parent().get_parent().add_child(wreck); wreck.global_position = global_position
		wreck.setup_machine(get_parent(),get_parent(),bubble_texture)
		wreck.name = "TurretWreck"; wreck.add_to_group("turret_wrecks")
		burst(global_position,1.0)

func activate(seconds: float) -> void:
	if retaliation <= 0: cooldown = 0
	retaliation = maxf(retaliation,seconds)

func take_weapon_damage_from(strength: float, source: Vector3, attacker: Node3D) -> void:
	var previous := report_player_attack
	var previous_attacker := damage_attacker
	damage_attacker = attacker; report_player_attack = is_instance_valid(attacker) and attacker == player
	take_weapon_damage(strength,source)
	report_player_attack = previous; damage_attacker = previous_attacker

func armed() -> bool:
	return bool(tuning.turret_armed) or retaliation > 0 or (hostile.is_valid() and hostile.call(int(tuning.turret_faction)))

func set_local_simulation(enabled: bool) -> void:
	local_simulation = enabled
	set_physics_process(enabled)

static func intercept(relative: Vector3, velocity: Vector3) -> Vector3:
	# 0x47eb40 predicts against 0.15 units/tick, with a 96-tick horizon.
	var speed := 0.15 * Damage.TICKS_PER_SECOND
	var a := velocity.length_squared() - speed * speed
	var b := 2.0 * relative.dot(velocity)
	var c := relative.length_squared()
	var time := -1.0
	if absf(a) < 0.000001:
		if absf(b) > 0.000001: time = -c / b
	else:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0:
			var first := (-b - sqrt(discriminant)) / (2.0 * a)
			var second := (-b + sqrt(discriminant)) / (2.0 * a)
			if first > 0: time = first
			if second > 0 and (time < 0 or second < time): time = second
	return relative + velocity * time if time >= 0 and time < 96.0 / Damage.TICKS_PER_SECOND else relative

func muzzle_position() -> Vector3:
	return head.to_global(Vector3(0,0,0.7)) if head != null else global_position

func _physics_process(delta: float) -> void:
	if not local_simulation: return
	if dead or head == null or not is_instance_valid(player): return
	if not player.active or not player.controls_enabled or player.dead: return
	if player.get_meta("bubble_screened",false): return
	cooldown = maxf(0,cooldown - delta); retaliation = maxf(0,retaliation - delta)
	var relative := player.global_position - head.global_position
	if relative.length_squared() > float(tuning.turret_range) * float(tuning.turret_range): return
	var aim := intercept(relative,player.velocity).normalized()
	if aim.is_zero_approx(): return
	var forward := head.global_basis.z.normalized()
	# Original turns 0.5 degrees/tick. Only the gun head moves, not its base.
	var angle := forward.angle_to(aim)
	if angle > 0.000001:
		var up: Vector3 = get_parent().global_basis.y.normalized()
		var desired := Basis.looking_at(-aim,up) if absf(aim.dot(up)) < 0.995 else head.global_basis.orthonormalized()
		var fraction := minf(1.0,deg_to_rad(float(tuning.turret_turn_speed)) * delta / maxf(0.000001,head.global_basis.orthonormalized().get_rotation_quaternion().angle_to(desired.get_rotation_quaternion())))
		head.global_basis = head.global_basis.orthonormalized().slerp(desired,fraction).scaled_local(head.global_basis.get_scale())
		sync_collision()
	forward = head.global_basis.z.normalized()
	var tolerance := asin(sqrt(0.001 if retaliation > 0 else 0.0003))
	if cooldown > 0 or not armed() or forward.angle_to(aim) > tolerance: return
	if missile_template == null: return
	var muzzle := muzzle_position()
	var exclusions: Array[RID] = []
	if hitbox != null: exclusions.append(hitbox.get_rid())
	var query := PhysicsRayQueryParameters3D.create(muzzle,player.global_position,1,exclusions)
	query.hit_back_faces = true
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return
	var missile := preload("res://turret_missile.gd").new()
	get_parent().get_parent().add_child(missile)
	missile.inflict = 8.0 # 004051f0 launches MISSILE (0x99), or HMISSILE (0x9a).
	missile.setup(self,missile_template,muzzle,forward,player,bool(tuning.turret_homing))
	# Counter resets to 40/30 and fires on the next zero: 41/31 ticks.
	cooldown = (31.0 if retaliation > 0 else 41.0) / Damage.TICKS_PER_SECOND
	shots += 1

func sync_collision() -> void:
	if hitbox == null: return
	for index in range(collision_meshes.size()):
		collision_shapes[index].transform = hitbox.global_transform.affine_inverse() * collision_meshes[index].global_transform

func burst(point: Vector3, diameter: float) -> void:
	var effect := preload("res://mine_explosion.gd").new()
	get_parent().get_parent().add_child(effect); effect.global_position = point
	effect.setup(explosion_frames,diameter,explosion_sound)
