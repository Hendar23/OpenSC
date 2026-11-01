extends Node3D
const Damage = preload("res://original_damage.gd")
const Drift = preload("res://torpedo_drift.gd")
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
var out_of_fuel := false
var spent := false
var tumble_axis := Vector3(0.7,0.4,0.25).normalized()
var explosion_frames: Array[Texture2D] = []
var explosion_sound: AudioStream

func setup(owner_turret: Node3D, template: Node3D, point: Vector3, heading: Vector3, victim: Node3D, guided: bool) -> void:
	source = owner_turret; target = victim; homing = guided; direction = heading.normalized()
	bubbles = owner_turret.bubble_trail
	var effects: Node = owner_turret
	if owner_turret.get("system") is Node: effects = owner_turret.get("system")
	elif owner_turret.get("game") is Node: effects = owner_turret.get("game").submarine_traffic
	var animation = effects.get("explosion_frames")
	if animation is Array: explosion_frames.assign(animation)
	explosion_sound = effects.get("explosion_sound")
	tumble_axis.x *= -1.0 if get_instance_id() % 2 else 1.0
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_to_group("turret_missiles")
	add_child(template.duplicate()); global_position = point
	global_basis = heading_basis(direction)
	reset_physics_interpolation()

static func heading_basis(heading: Vector3) -> Basis:
	var up := Vector3.RIGHT if absf(heading.dot(Vector3.UP)) > 0.999 else Vector3.UP
	return Basis.looking_at(heading,up,true)

func _physics_process(delta: float) -> void:
	if spent: return
	age += delta
	# Keep the existing NPC powered-flight duration, then coast and sink.
	if not out_of_fuel and age >= LIFETIME: _run_out_of_fuel()
	clock += delta * Damage.TICKS_PER_SECOND
	while clock >= 1.0:
		clock -= 1.0
		if out_of_fuel:
			_sink_tick()
			if spent: return
			continue
		if homing and is_instance_valid(target) and not target.dead and not target.get_meta("bubble_screened",false):
			var desired := (target.global_position - global_position).normalized()
			if not desired.is_zero_approx():
				# Preserve the original steering strength; the Godot integrator
				# uses a bounded turn rather than the old angular-momentum solver.
				var angle := direction.angle_to(desired)
				if angle > 0.000001: direction = direction.slerp(desired,minf(1.0,0.1 / angle)).normalized()
		velocity = (velocity + direction * (0.0025 / 0.1 * Damage.TICKS_PER_SECOND)) * DAMPING
		var next := global_position + velocity / Damage.TICKS_PER_SECOND
		var hit := _impact(next)
		if not hit.is_empty():
			var body: Node3D = hit.collider
			var relative_velocity := velocity
			if body is RigidBody3D: relative_velocity -= body.linear_velocity
			elif body is CharacterBody3D: relative_velocity -= body.velocity
			var closing := maxf(0,relative_velocity.dot(direction))
			var strength := (2.0 if homing else inflict) * 10.0 * closing / Damage.TICKS_PER_SECOND
			if body.has_method("receive_projectile_hit"):
				body.receive_projectile_hit(strength,hit.position,velocity.normalized() * HIT_IMPULSE * clampf(closing / 3.75,0,1))
			else: Damage.weapon(body,strength,global_position if body.has_method("take_typed_weapon_damage") else hit.position,source if is_instance_valid(source) else null,"homers" if homing else "missile" if is_equal_approx(inflict,8.0) else "",hit)
			_finish(hit.position); return
		global_position = next
		if is_instance_valid(bubbles): bubbles.emit_from(get_instance_id(),global_position - direction * 0.18,-direction,1.0,25.0,1.0 / Damage.TICKS_PER_SECOND)
		if not velocity.is_zero_approx(): global_basis = heading_basis(velocity.normalized())

func _run_out_of_fuel() -> void:
	out_of_fuel = true; target = null
	if is_instance_valid(bubbles): bubbles.credits.erase(get_instance_id())

func _impact(next: Vector3, inside: bool = false) -> Dictionary:
	var exclusions: Array[RID] = source_exclusions.duplicate()
	if is_instance_valid(source) and source.hitbox != null: exclusions.append(source.hitbox.get_rid())
	var query := PhysicsRayQueryParameters3D.create(global_position,next,15,exclusions)
	query.hit_back_faces = true; query.hit_from_inside = inside
	return get_world_3d().direct_space_state.intersect_ray(query)

func _sink_tick() -> void:
	var step := 1.0/Damage.TICKS_PER_SECOND
	velocity = Drift.velocity_after_tick(velocity,step)
	var next := global_position+velocity*step
	var hit := _impact(next,true)
	if not hit.is_empty(): _finish(hit.position); return
	global_position = next
	global_basis = Drift.tumble(global_basis,tumble_axis,step)

func _finish(point: Vector3) -> void:
	if spent: return
	spent = true; global_position = point
	if is_instance_valid(source): source.burst(point,0.5)
	else:
		var effect := preload("res://mine_explosion.gd").new()
		get_parent().add_child(effect); effect.global_position = point
		effect.setup(explosion_frames,0.5,explosion_sound)
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(bubbles): bubbles.credits.erase(get_instance_id())
