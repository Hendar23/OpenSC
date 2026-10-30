extends "res://mission_vessel.gd"
const Mine = preload("res://floating_mine.gd")
## CARAVAN 00432160: blind vector following, not autonomous route finding.
var tracking := false
var held_by_boarders := false
var secured := false

func set_local_simulation(_on: bool) -> void:
	# One mission hull retains physical collision even beyond the camera. An
	# abstract navigation route would silently steer this blind ship past mines.
	super.set_local_simulation(true)

func _advance_motion(delta: float) -> void:
	if secured or dock_destination > 0: super._advance_motion(delta); return
	if not tracking or held_by_boarders or not is_instance_valid(system.player): _coast(delta); return
	var offset: Vector3 = system.player.global_position-global_position
	# Retail keeps two units under the surface and coasts within three units.
	if global_position.y > system.map.surface_height-2:
		offset.y -= global_position.y-(system.map.surface_height-2)
	var desired := float(tuning.npc_speed) if offset.length() > 3.0 else 0.0
	_flow_move(delta,offset.normalized(),desired)

func _precise_motion() -> bool:
	return super._precise_motion() if secured or retiring else false

func _flow_move(delta: float, direction: Vector3, desired_speed: float, aim: Vector3 = Vector3.ZERO) -> KinematicCollision3D:
	var before: float = motion.velocity.length()
	var hit := super._flow_move(delta,direction,desired_speed,aim)
	if hit != null and not secured:
		var obstacle := hit.get_collider()
		if obstacle is Mine: obstacle.detonate.call_deferred()
		elif before > 0.5:
			# Original 00466620: closing tick velocity / mass * hull sustain.
			var closing: float = maxf(0.0,-direction.dot(hit.get_normal()))*before
			if closing > 0.5: take_weapon_damage(closing/25.0,hit.get_position())
	return hit
