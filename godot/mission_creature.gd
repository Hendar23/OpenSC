extends "res://fish_controller.gd"
## Scripted fish retain ordinary swimming, collision, animation and combat.
var route := PackedVector3Array()
var route_index := 0
var route_finished := false
var contact_victim: Node3D
var contact_clock := 0.0
var giant_eel := false
var giant_player: Node3D
var giant_impact_cooldown := 0.0

func receive_sub_push(sub_velocity: Vector3, sub_radius: float) -> void:
	if not giant_eel: super.receive_sub_push(sub_velocity,sub_radius)

func submarine_contact_damage(sub_velocity: Vector3, normal: Vector3) -> float:
	if not giant_eel: return super.submarine_contact_damage(sub_velocity,normal)
	if dead or giant_impact_cooldown > 0: return 0.0
	var closing_speed := maxf(0,-(sub_velocity-velocity).dot(normal))
	if closing_speed < 0.35: return 0.0
	giant_impact_cooldown = 0.75
	# Owner-requested heavy-body impact damage, in displayed shield points.
	# take_damage applies the player's current hull protection once.
	return minf(20.0,closing_speed*5.0)

func _choose_goal() -> void:
	if route.is_empty(): super._choose_goal(); return
	goal = route[mini(route_index,route.size()-1)]; turn_timer = 60.0

func _physics_process(delta: float) -> void:
	if giant_eel:
		_step_giant_eel(delta); return
	if not route.is_empty() and not route_finished:
		if global_position.distance_to(route[route_index]) < 0.7:
			if route_index < route.size()-1: route_index += 1
			else: route_finished = true
		goal = route[route_index]; turn_timer = 60
		# The shared fish controller applies a home-radius leash after steering.
		# Advance that home with the route so it cannot turn the specimen back.
		home = goal
	super._physics_process(delta)
	contact_clock = maxf(0,contact_clock-delta)
	# The original eel can damage the mine by striking it. Generic wildlife
	# combat selects submarines; preserve this separate scenery contact damage.
	if is_instance_valid(contact_victim) and not dead and contact_clock <= 0:
		for index in range(get_slide_collision_count()):
			if get_slide_collision(index).get_collider() == contact_victim:
				contact_clock = 1.0; contact_victim.take_weapon_damage(maxf(0.5,swim_speed),global_position); break

func _step_giant_eel(delta: float) -> void:
	if dead or delta <= 0: return
	giant_impact_cooldown = maxf(0,giant_impact_cooldown-delta)
	# Released HUGEEEL controller 0046b540: head for the mine marker,
	# pursuing a player within eight units and in the forward cone.
	var desired := (home-global_position).normalized()
	var pursuing := false
	if is_instance_valid(giant_player) and giant_player.active and not giant_player.dead and giant_player.controls_enabled:
		var offset: Vector3 = giant_player.global_position-global_position
		if global_position.distance_to(home) < 8.0 and offset.length() < 8.0 and direction.dot(offset.normalized()) > 0.4:
			desired = offset.normalized(); pursuing = true
		# Original damage is continuous at close range, independent of facing.
		if offset.length() < 1.5: giant_player.take_weapon_damage(0.3*25.0*delta,global_position)
	_steer(desired,delta)
	velocity = direction*swim_speed*(1.0 if pursuing else 0.5)
	global_position += velocity*delta
	playback_rate = animation_speed*ANIMATION_SPEED
	animation_time += delta*playback_rate
	_update_orientation()
