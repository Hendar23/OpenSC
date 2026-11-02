extends "res://mission_creature.gd"
## Nursery jellyfish retain normal hull collision, repulsion and death effects.
var player: Node3D
var prey: Node3D
var provoked := false
var queen := false
var queen_held := false
var probe_clock := 0.0
var queen_motion_shape: SphereShape3D

func repel_from(point: Vector3, duration: float) -> void:
	if queen: return
	super.repel_from(point,duration)

func take_weapon_damage(strength: float, source: Vector3 = Vector3.ZERO) -> void:
	provoked = true; super.take_weapon_damage(strength,source)

func _physics_process(delta: float) -> void:
	if dead or delta <= 0: return
	animation_time += delta*animation_speed*ANIMATION_SPEED
	var victim: Node3D = prey if is_instance_valid(prey) and not prey.get("dead") else player
	var engaged := provoked or repulsion_remaining > 0 or (is_instance_valid(player) and global_position.distance_to(player.global_position) < 3)
	if not engaged:
		velocity = Vector3.ZERO; _update_orientation(); return
	var desired := direction
	if is_instance_valid(victim): desired = global_position.direction_to(victim.global_position)
	fleeing = repulsion_remaining > 0
	if fleeing:
		repulsion_remaining = maxf(0,repulsion_remaining-delta); desired = repulsion_point.direction_to(global_position)
	probe_clock -= delta
	if probe_clock <= 0:
		probe_clock = 0.2
		var query := PhysicsRayQueryParameters3D.create(global_position,global_position+desired*(radius+0.6),1)
		query.hit_back_faces = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		avoidance = Vector3(hit.normal) if not hit.is_empty() else Vector3.ZERO
	var previous_direction := direction
	desired = (desired+avoidance).normalized(); _steer(desired,delta)
	velocity = direction*swim_speed*(1.6 if fleeing else 1.0)+pushed_velocity
	pushed_velocity = pushed_velocity.move_toward(Vector3.ZERO,delta*8)
	if queen: _move_queen(delta,previous_direction)
	else: move_and_slide()
	global_position.y = minf(global_position.y,surface_height-radius-0.02)
	_update_orientation()
	combat.target = victim; combat.bite_timer = maxf(0,combat.bite_timer-delta)
	# Repulsion protects the player, while a restrained queen can still strike
	# the tethering ships as she struggles away from the repeller.
	var repelled := fleeing
	if queen and victim != player: fleeing = false
	combat.attack(delta); fleeing = repelled

func _move_queen(delta: float, previous_direction: Vector3) -> void:
	# Sweep the queen's full bounding radius, not just her centre. A sphere
	# avoids costly rotating-convex recovery while keeping her out of walls.
	# The fitted hull remains available for weapons and submarine contacts.
	var start := global_position
	var finish := start+velocity*delta
	if start.is_equal_approx(finish): return
	if queen_motion_shape == null: queen_motion_shape = SphereShape3D.new()
	queen_motion_shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = queen_motion_shape; query.transform.origin = start
	query.motion = finish-start; query.collision_mask = 1; query.exclude = [get_rid()]
	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	if fractions[0] >= 1.0:
		global_position = finish
	else:
		global_position = start.lerp(finish,fractions[0]*0.9)
		velocity = Vector3.ZERO
		direction = previous_direction
