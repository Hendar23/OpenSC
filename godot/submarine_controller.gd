extends RigidBody3D

const Movement = preload("res://movement_model.gd")
const Controls = preload("res://pilot_input.gd")
const Bubbles = preload("res://propeller_bubbles.gd")
const SubAudio = preload("res://submarine_audio.gd")
const Rumble = preload("res://impact_rumble.gd")
const HullCollision = preload("res://submarine_collision.gd")
const VISUAL_SCALE := 0.8
const COLLIDER_RADIUS := 0.54
# The legacy radius remains the docking manoeuvre/inertia reference.
# Physical contact follows the smaller rendered hull and side pods.
const COLLIDER_SIZE := Vector3(0.60, 0.44, 0.78)
const COLLIDER_CENTER := Vector3(0.0, 0.02, 0.04)
var movement := Movement.new()
var active := false:
	set(value):
		active = value
		freeze = not value
		if not value and impact_rumble != null: impact_rumble.stop()
var controls_enabled := true
var visual: Node3D
var angles := Vector3.ZERO
var propeller_speeds := Vector3.ZERO
var pod_rotation_power := 0.0
var last_pod_tilt := 0.0
var bubbles: Node3D
var submarine_audio: Node
var impact_rumble: Node
var spawn := Vector3.ZERO
var surface_height := INF
var remember_settings := true
var safe_margin := 0.01
var velocity: Vector3:
	get: return linear_velocity
	set(value): linear_velocity = value
var pending_reset := false
var reset_transform := Transform3D.IDENTITY
var previous_contacts := {}
var previous_velocity := Vector3.ZERO
var collision_parts: Array[Dictionary] = []

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	custom_integrator = true
	gravity_scale = 0.0
	can_sleep = false
	continuous_cd = true
	max_contacts_reported = 16
	freeze = not active
	collision_layer = 2
	collision_mask = 5
	_build_collision(HullCollision.fallback())
	movement.load_settings(remember_settings)
	mass = float(movement.settings.mass)
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.2
	physics_material_override.bounce = 0.0
	bubbles = Bubbles.new()
	bubbles.name = "PropellerBubbles"
	add_child(bubbles)
	submarine_audio = SubAudio.new()
	submarine_audio.name = "SubmarineAudio"
	add_child(submarine_audio)
	impact_rumble = Rumble.new()
	impact_rumble.pilot = self
	add_child(impact_rumble)
	submarine_audio.impact_accepted.connect(impact_rumble.impact)

func fit_collision_to_visual() -> void:
	var fitted := HullCollision.fit(visual,self)
	if not fitted.is_empty(): _build_collision(fitted)

func _build_collision(parts: Array[Dictionary]) -> void:
	for part in collision_parts: part.collider.free()
	collision_parts = parts
	for part in collision_parts:
		var shape := ConvexPolygonShape3D.new()
		shape.points = part.points
		shape.margin = 0.005
		var collider := CollisionShape3D.new()
		collider.name = part.name
		collider.shape = shape
		add_child(collider)
		part["collider"] = collider

func _sync_pod_collisions() -> void:
	for part in collision_parts:
		if part.has("source") and is_instance_valid(part.source):
			part.collider.transform = global_transform.affine_inverse() * part.source.global_transform * part.rest_pose.affine_inverse()

func collision_height() -> float:
	return surface_clearance(Basis.IDENTITY) + surface_clearance(Basis(Vector3.RIGHT,PI))

func _process(delta: float) -> void:
	submarine_audio.update(delta)

func reset_at(point: Vector3) -> void:
	spawn = Vector3(point.x, minf(point.y, surface_height - surface_clearance(Basis.IDENTITY) - safe_margin), point.z)
	position = spawn
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	movement.reset_motion()
	angles = Vector3.ZERO
	propeller_speeds = Vector3.ZERO
	pod_rotation_power = 0.0
	last_pod_tilt = 0.0
	if bubbles != null: bubbles.clear()
	if submarine_audio != null: submarine_audio.silence()
	if impact_rumble != null: impact_rumble.stop()
	angular_velocity = Vector3.ZERO
	reset_transform = global_transform
	pending_reset = true
	previous_contacts.clear()
	previous_velocity = Vector3.ZERO
	force_update_transform()
	get_global_transform_interpolated()
	reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	if not active: return
	mass = maxf(1.0, float(movement.settings.mass))
	_update_animation(delta)
	_sync_pod_collisions()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not active: return
	if pending_reset:
		state.transform = reset_transform
		pending_reset = false
		previous_contacts.clear()
		previous_velocity = Vector3.ZERO
	var impact_speed := _contact_impact(state)
	var controls := Controls.read() if controls_enabled else Vector4.ZERO
	movement.velocity = state.linear_velocity
	movement.angular_velocity = state.angular_velocity
	movement.step(state.step, state.transform.basis, controls.x, controls.y, controls.z, controls.w)
	state.linear_velocity = movement.velocity
	state.angular_velocity = movement.angular_velocity
	var pose := state.transform
	var forward := -pose.basis.z
	var elevation := asin(clampf(forward.y, -1.0, 1.0))
	if absf(elevation) > Movement.PITCH_LIMIT:
		var right := forward.cross(Vector3.UP).normalized()
		pose.basis = (Basis(right, clampf(elevation, -Movement.PITCH_LIMIT, Movement.PITCH_LIMIT) - elevation) * pose.basis).orthonormalized()
		var spin := state.angular_velocity.dot(right)
		if spin * elevation > 0.0: state.angular_velocity -= right * spin
	var pitch_axis := (-pose.basis.z).cross(Vector3.UP).normalized()
	elevation = asin(clampf(-pose.basis.z.y, -1.0, 1.0))
	var pitch_rate := state.angular_velocity.dot(pitch_axis)
	var limited_rate := clampf(pitch_rate, (-Movement.PITCH_LIMIT - elevation) / state.step, (Movement.PITCH_LIMIT - elevation) / state.step)
	state.angular_velocity += pitch_axis * (limited_rate - pitch_rate)
	# Guard both the current location and the next integration step at the surface.
	# Rotating the fitted hull changes how much room it needs below the surface.
	var ceiling := surface_height - surface_clearance(pose.basis) - safe_margin
	pose.origin.y = minf(pose.origin.y, ceiling)
	if pose.origin.y + state.linear_velocity.y * state.step >= ceiling:
		state.linear_velocity.y = minf(state.linear_velocity.y, maxf(0.0, (ceiling - pose.origin.y) / state.step))
	state.transform = pose
	movement.velocity = state.linear_velocity
	movement.angular_velocity = state.angular_velocity
	previous_velocity = state.linear_velocity
	if impact_speed > 0.0: submarine_audio.call_deferred("impact", impact_speed)

func receive_explosion(source: Vector3, damage: float, impulse: float) -> void:
	if not active or not controls_enabled: return
	var direction := global_position - source
	if direction.length_squared() < 0.00001: direction = Vector3.UP
	if impulse > 0.0: apply_central_impulse(direction.normalized() * impulse)
	if impact_rumble != null: impact_rumble.damage(damage)

func surface_clearance(orientation: Basis) -> float:
	var highest := -INF
	for part in collision_parts:
		var pose: Transform3D = part.collider.transform
		for point in part.points: highest = maxf(highest,(orientation * (pose * point)).y)
	return highest

func _contact_impact(state: PhysicsDirectBodyState3D) -> float:
	var contacts := {}
	var strongest := 0.0
	for index in range(state.get_contact_count()):
		var body := state.get_contact_collider_object(index) as CollisionObject3D
		# The water ceiling still blocks motion, but is not a solid hull impact.
		if body != null and body.collision_layer & 4 != 0 and body.collision_layer & 1 == 0: continue
		var collider := state.get_contact_collider_id(index)
		var normal := state.get_contact_local_normal(index)
		if not contacts.has(collider): contacts[collider] = []
		contacts[collider].append(normal)
		var previous_normals: Array = previous_contacts.get(collider, [])
		# Terrain may be one body: touching its floor must not suppress a
		# later impact against a different face of that same terrain.
		if previous_normals.any(func(old: Vector3) -> bool: return old.dot(normal) > 0.9): continue
		var relative := previous_velocity - state.get_contact_collider_velocity_at_position(index)
		var closing := maxf(0.0, -relative.dot(normal))
		var impulse_speed := state.get_contact_impulse(index).length() / maxf(1.0, mass)
		strongest = maxf(strongest, maxf(closing, impulse_speed))
	previous_contacts = contacts
	return strongest

func _update_animation(delta: float) -> void:
	if visual == null: return
	pod_rotation_power = clampf(absf(movement.tilt - last_pod_tilt) / maxf(delta, 0.0001) / maxf(0.01, deg_to_rad(float(movement.settings.tilt_speed))), 0.0, 1.0)
	last_pod_tilt = movement.tilt
	# Roles describe physical left/right after the +Z source faces Godot -Z.
	var parts: Dictionary = visual.get_meta("submarine_parts", {"left_pod": "Hull/RightPod", "right_pod": "Hull/LeftPod", "main_propeller": "Hull/RearPropeller", "left_propeller": "Hull/RightPod/RightPropeller", "right_propeller": "Hull/LeftPod/LeftPropeller"})
	for role in ["left_pod", "right_pod"]:
		if not parts.has(role): continue
		var pod := visual.get_node_or_null(NodePath(str(parts[role]))) as Node3D
		if pod == null: continue
		var rest: Basis = pod.get_meta("rest_basis", pod.basis)
		var pose := pod.transform
		pose.basis = rest * Basis(Vector3.RIGHT, movement.tilt * float(visual.get_meta("pod_tilt_sign", -1.0)))
		pod.transform = pose
	var targets := Vector3(movement.main_power, movement.left_power, movement.right_power)
	var stop_time := float(movement.settings.propeller_spin_down)
	for i in range(3):
		if i > 0 and not movement.pods_aligned:
			targets[i] = 0.0
		var slowing := absf(targets[i]) < absf(propeller_speeds[i]) or targets[i] * propeller_speeds[i] < 0.0
		var response := stop_time if slowing else 0.15
		propeller_speeds[i] = targets[i] if response <= 0.0 else move_toward(propeller_speeds[i], targets[i], delta / response)
	angles += propeller_speeds * delta * TAU * 5.0
	var roles := ["main_propeller", "left_propeller", "right_propeller"]
	for i in range(roles.size()):
		angles[i] = fmod(angles[i], TAU)
		if not parts.has(roles[i]): continue
		var propeller := visual.get_node_or_null(NodePath(str(parts[roles[i]]))) as Node3D
		if propeller == null: continue
		var rest: Basis = propeller.get_meta("rest_basis", propeller.basis)
		var pose := propeller.transform
		pose.basis = rest * Basis(Vector3.BACK, angles[i])
		propeller.transform = pose
		if bubbles != null and visual.is_visible_in_tree():
			bubbles.surface_height = surface_height
			var direction := global_basis.z if i == 0 else global_basis * Vector3(0.0, -sin(movement.tilt), cos(movement.tilt))
			bubbles.emit_from(i, propeller.global_position + direction * signf(propeller_speeds[i]) * 0.05,
				direction, propeller_speeds[i], float(movement.settings.bubble_rate), delta)
