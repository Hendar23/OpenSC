extends Node3D
const Damage = preload("res://original_damage.gd")
const LIFETIME := 133.333333 / Damage.TICKS_PER_SECOND
const DAMPING := 0.857142857
# Gameplay feedback: a terminal-speed hit nudges a 100 kg hull by 0.5 units/s.
const HIT_IMPULSE := 50.0
var source: Node3D
var target: Node3D
var homing := false
var inflict := 2.5
var age := 0.0
var clock := 0.0
var velocity := Vector3.ZERO
var direction := Vector3.FORWARD
var bubbles: Node3D
var source_exclusions: Array[RID] = []

func setup(owner_turret: Node3D, template: Node3D, point: Vector3, heading: Vector3, victim: Node3D, guided: bool) -> void:
	source = owner_turret; target = victim; homing = guided; direction = heading.normalized()
	bubbles = owner_turret.bubble_trail
	add_to_group("turret_missiles")
	add_child(template.duplicate()); global_position = point
	global_basis = heading_basis(direction)

static func heading_basis(heading: Vector3) -> Basis:
	var up := Vector3.RIGHT if absf(heading.dot(Vector3.UP)) > 0.999 else Vector3.UP
	return Basis.looking_at(heading,up,true)

func _physics_process(delta: float) -> void:
	age += delta
	if age >= LIFETIME: queue_free(); return
	clock += delta * Damage.TICKS_PER_SECOND
	while clock >= 1.0:
		clock -= 1.0
		if homing and is_instance_valid(target) and not target.dead:
			var desired := (target.global_position - global_position).normalized()
			if not desired.is_zero_approx():
				# Preserve the original steering strength; the Godot integrator
				# uses a bounded turn rather than the old angular-momentum solver.
				var angle := direction.angle_to(desired)
				if angle > 0.000001: direction = direction.slerp(desired,minf(1.0,0.1 / angle)).normalized()
		velocity = (velocity + direction * (0.0025 / 0.1 * Damage.TICKS_PER_SECOND)) * DAMPING
		var next := global_position + velocity / Damage.TICKS_PER_SECOND
		var exclusions: Array[RID] = source_exclusions.duplicate()
		if is_instance_valid(source) and source.hitbox != null: exclusions.append(source.hitbox.get_rid())
		var query := PhysicsRayQueryParameters3D.create(global_position,next,15,exclusions)
		query.hit_back_faces = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var body: Node3D = hit.collider
			var relative_velocity := velocity
			if body is RigidBody3D: relative_velocity -= body.linear_velocity
			var closing := maxf(0,relative_velocity.dot(direction))
			var strength := (2.0 if homing else inflict) * 10.0 * closing / Damage.TICKS_PER_SECOND
			if body.has_method("receive_projectile_hit"):
				body.receive_projectile_hit(strength,hit.position,velocity.normalized() * HIT_IMPULSE * clampf(closing / 3.75,0,1))
			else: Damage.weapon(body,strength,hit.position,source)
			if is_instance_valid(source): source.burst(hit.position,0.5)
			queue_free(); return
		global_position = next
		if is_instance_valid(bubbles): bubbles.emit_from(0,global_position - direction * 0.18,-direction,1.0,25.0,1.0 / Damage.TICKS_PER_SECOND)
		if not velocity.is_zero_approx(): global_basis = heading_basis(velocity.normalized())
