extends RefCounted
## Shared unpowered movement for player and NPC torpedoes.
const ACCELERATION := 0.65
const SPEED := 1.2

static func velocity_after_tick(velocity: Vector3, step: float) -> Vector3:
	velocity.x *= 0.94; velocity.z *= 0.94
	if velocity.y > 0: velocity.y *= 0.94
	velocity.y = maxf(-SPEED,velocity.y-ACCELERATION*step)
	return velocity

static func tumble(basis: Basis, axis: Vector3, step: float) -> Basis:
	return (basis*Basis(axis,0.7*step)).orthonormalized()
