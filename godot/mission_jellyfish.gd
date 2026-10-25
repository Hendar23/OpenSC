extends "res://mission_creature.gd"
## BADJELLY 004200a0/0041fe30: attack the assigned city marker or player.
var city_target := Vector3.ZERO
var player: Node3D
var city_attacker := false
var pursue_player := false
var probe_clock := 0.0
var zap_timer := 0.0
var navigation: Node
var route_clock := 0.0

func _physics_process(delta: float) -> void:
	if dead or delta <= 0: return
	var target_point := city_target
	var attacking_player := false
	if is_instance_valid(player) and player.active and not player.dead and player.controls_enabled and not player.get_meta("bubble_screened",false):
		if pursue_player or (not city_attacker and global_position.distance_to(player.global_position) < 8.0):
			target_point = player.global_position; attacking_player = true
	var desired := _pursuit_direction(target_point,attacking_player,delta)
	# Keep the horde from piling into one coincident body at the city marker.
	# Share the existing cheap wildlife separation snapshot, without letting
	# ambient fish divert these mission attackers from their assigned targets.
	shoal.refresh(group_members)
	desired = (desired+_separation()*0.6).normalized()
	var speed := swim_speed
	fleeing = repulsion_remaining > 0
	if fleeing:
		repulsion_remaining = maxf(0,repulsion_remaining-delta)
		desired = repulsion_point.direction_to(global_position); speed *= 1.6; attacking_player = false
	probe_clock -= delta
	if probe_clock <= 0:
		probe_clock = 0.2
		var query := PhysicsRayQueryParameters3D.create(global_position,global_position+direction*(radius+0.8),5)
		query.hit_back_faces = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		avoidance = (desired+Vector3(hit.normal)*2).normalized() if not hit.is_empty() else Vector3.ZERO
	if not avoidance.is_zero_approx(): desired = (desired+avoidance).normalized()
	_steer(desired,delta)
	velocity = direction*speed+pushed_velocity
	pushed_velocity = pushed_velocity.move_toward(Vector3.ZERO,delta*8)
	move_and_slide()
	global_position.y = minf(global_position.y,surface_height-radius-0.02)
	animation_time += delta*animation_speed*ANIMATION_SPEED; _update_orientation()
	combat.target = player if attacking_player else null
	combat.bite_timer = maxf(0,combat.bite_timer-delta)
	if attacking_player:
		combat.attack(delta)
	else:
		# City damage is represented by the original mission's radio sequence,
		# not an invented city-health meter or loss timer. Keep its visible arcs.
		zap_timer -= delta
		if not fleeing and global_position.distance_to(city_target) < 3 and zap_timer <= 0:
			zap_timer = rng.randf_range(0.2,0.6)
			combat._show_weapon(global_position+direction*0.5,global_position+direction*1.5)
		elif zap_timer < 0.15 or fleeing: combat._stop_weapon()

func above_seabed(point: Vector3) -> Vector3:
	# Concave terrain only reports triangle overlap, not a point buried inside
	# solid ground. The retail marker's downward offset is below this seabed.
	var clear := point
	var reach := radius+0.1
	for offset in [Vector3.ZERO,Vector3(reach,0,0),Vector3(-reach,0,0),Vector3(0,0,reach),Vector3(0,0,-reach)]:
		var floor_hit: Dictionary = population.floor_contact(point+offset)
		if not floor_hit.is_empty(): clear.y = maxf(clear.y,float(floor_hit.position.y)+radius+0.15)
	return clear

func _pursuit_direction(target: Vector3, pursuing: bool, delta: float) -> Vector3:
	var direct := global_position.direction_to(target)
	if not pursuing or not is_instance_valid(navigation): return direct
	route_clock -= delta
	if route_clock <= 0:
		route_clock = 0.75
		if navigation.segment_clear(global_position,target): route.clear()
		else: route = navigation.route(global_position,target)
	while not route.is_empty() and global_position.distance_to(route[0]) < 0.8: route.remove_at(0)
	return global_position.direction_to(route[0]) if not route.is_empty() else direct

func _separation() -> Vector3:
	var away: Vector3 = shoal.separation(position,radius)
	# The original integer spawn offsets can put several attackers at exactly
	# the same point. Ordinary separation ignores zero-distance pairs, leaving
	# identical-heading bodies visually stacked as one apparent survivor.
	for peer in group_members:
		if peer == self or not is_instance_valid(peer) or peer.dead: continue
		if position.distance_squared_to(peer.position) > 0.001: continue
		var angle := float(group_members.find(self))*2.39996323
		away += Vector3(cos(angle),0,sin(angle))
	return away
