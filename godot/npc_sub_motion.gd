extends RefCounted
## Inertial swimming shared by civilian, combat and mission submarines.
var velocity := Vector3.ZERO
var bank := 0.0
var turn_rate := deg_to_rad(75.0)
var thrust_scale := 1.0
func step(delta: float, direction: Vector3, desired_speed: float, cruise_speed: float, facing: Basis, aim: Vector3 = Vector3.ZERO, precise: bool = false) -> Basis:
	var forward := facing.z.normalized()
	var look := aim.normalized() if not aim.is_zero_approx() else direction.normalized()
	if look.is_zero_approx(): look = forward
	var level := Basis.looking_at(-forward,Vector3.UP) if absf(forward.y) < 0.98 else facing.orthonormalized()
	var target := Basis.looking_at(-look,Vector3.UP) if absf(look.y) < 0.98 else level
	var angle := level.get_rotation_quaternion().angle_to(target.get_rotation_quaternion())
	var fraction := minf(1.0-exp(-3.5*delta),turn_rate*delta/maxf(0.00001,angle))
	var turn := level.slerp(target,fraction)
	# Thrust follows the bow; inertia carries the old heading through a turn.
	# Close docking/boarding alignment retains fine lateral control.
	var drive := direction.normalized() if precise else turn.z.normalized()
	var alignment := clampf(forward.dot(direction.normalized()),0.0,1.0)
	var desired := drive * desired_speed * (1.0 if precise else lerpf(0.65,1.0,alignment))
	var braking := desired_speed < velocity.length() or desired_speed <= 0
	var acceleration := maxf(0.6,cruise_speed * (1.0 if braking else 0.65)) * thrust_scale
	velocity = velocity.move_toward(desired,acceleration * delta)
	var yaw_rate := forward.signed_angle_to(turn.z,Vector3.UP) / maxf(0.00001,delta)
	var lean := clampf(-yaw_rate * 0.12,-0.14,0.14) * clampf(velocity.length()/maxf(0.1,cruise_speed),0,1)
	bank = lerpf(bank,lean,1.0-exp(-3.0*delta))
	return turn * Basis(Vector3.BACK,bank)
