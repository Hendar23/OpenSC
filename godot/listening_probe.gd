extends RigidBody3D
## Big Ears: SC.EXE 00432d50 launches 0041b620, updated by 0041b510.
const TICKS_PER_SECOND := 25.0
const RETENTION := 0.9
const THRUST_SECONDS := 100.0 / TICKS_PER_SECOND
# Original force .0005 / mass .01, with tick velocities converted to seconds.
const ACCELERATION := 0.0005 / 0.01 * TICKS_PER_SECOND * TICKS_PER_SECOND
const SINK_ACCELERATION := 0.001 * TICKS_PER_SECOND * TICKS_PER_SECOND
var tools: Node
var designated_target: Node3D
var attached := false
var motor_remaining := THRUST_SECONDS
var age := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mass = 0.01; gravity_scale = 0.0; custom_integrator = true
	contact_monitor = true; max_contacts_reported = 8; continuous_cd = true
	collision_layer = 8; collision_mask = 1 | 8
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	var collider := CollisionShape3D.new(); var shape := SphereShape3D.new()
	shape.radius = 0.025; collider.shape = shape; add_child(collider)
	body_entered.connect(func(body: Node) -> void: _contact.call_deferred(body))

static func flight_velocity(current: Vector3, forward: Vector3, powered: bool, delta: float) -> Vector3:
	var retention := pow(RETENTION,TICKS_PER_SECOND * delta)
	var acceleration := forward * ACCELERATION if powered else Vector3.DOWN * SINK_ACCELERATION
	# Fractional-tick form of (velocity + acceleration/25) * .9.
	return current * retention + acceleration / TICKS_PER_SECOND * RETENTION * (1.0-retention) / (1.0-RETENTION)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if attached: return
	age += state.step
	var powered := minf(motor_remaining,state.step)
	var motion := state.linear_velocity
	if powered > 0.0:
		motion = flight_velocity(motion,-state.transform.basis.z.normalized(),true,powered)
		motor_remaining = maxf(0.0,motor_remaining-powered)
	if state.step > powered: motion = flight_velocity(motion,Vector3.ZERO,false,state.step-powered)
	state.linear_velocity = motion
	state.angular_velocity *= pow(RETENTION,TICKS_PER_SECOND * state.step)
	sleeping = false

func _contact(body: Node) -> void:
	if attached or not is_instance_valid(body) or is_queued_for_deletion(): return
	# 0041b620 accepts only the target registered with the launcher (0x1b).
	if body == designated_target and is_instance_valid(tools):
		var mission: Node = tools.runtime()
		if mission != null and mission.side_jobs.attach_listening_device(body):
			attached = true; freeze = true; collision_layer = 0; collision_mask = 0
			linear_velocity = Vector3.ZERO; angular_velocity = Vector3.ZERO
			_seat_on_hull(body)
			reparent(body,true); reset_physics_interpolation()
			return
	# Other contacts stop the motor, leaving a physical device to settle.
	motor_remaining = 0.0; linear_velocity = Vector3.ZERO

func _seat_on_hull(body: Node3D) -> void:
	# Match the original contact projection + .05 stand-off, rather than
	# leaving the device floating against an oversized NPC collision capsule.
	var point := global_position; var closest := point; var distance := INF
	for mesh: MeshInstance3D in body.get_parent().find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null or not mesh.visible: continue
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for index in range(0,count-2,3):
				var a: Vector3 = mesh.to_global(vertices[indices[index] if not indices.is_empty() else index])
				var b: Vector3 = mesh.to_global(vertices[indices[index+1] if not indices.is_empty() else index+1])
				var c: Vector3 = mesh.to_global(vertices[indices[index+2] if not indices.is_empty() else index+2])
				var contact := preload("res://submarine_magnet.gd")._closest_triangle(point,a,b,c)
				if point.distance_squared_to(contact) < distance: closest = contact; distance = point.distance_squared_to(contact)
	if is_finite(distance):
		var normal := (point-closest).normalized()
		if normal.is_zero_approx(): normal = (point-body.global_position).normalized()
		global_position = closest + normal * 0.05
