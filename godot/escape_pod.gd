extends RigidBody3D
## Physical rescue pod. Mission eligibility and passenger transfer belong to tools.
var tools: Node
var radius := 0.08
func _ready() -> void:
	gravity_scale = 0; mass = 2.0; linear_damp = 3.0; angular_damp = 4.0
	collision_layer = 8; collision_mask = 1 | 8
	contact_monitor = true; max_contacts_reported = 8; continuous_cd = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	body_entered.connect(func(body: Node) -> void: tools.call_deferred("_attach_pod",body))
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if tools == null or not is_instance_valid(tools.equipment.pilot): return
	var pilot: RigidBody3D = tools.equipment.pilot
	var desired: Vector3 = tools.pod_socket() + pilot.global_basis * Vector3.DOWN * tools.pod_deployment
	var relative: Vector3 = state.linear_velocity - pilot.linear_velocity
	state.linear_velocity += ((desired-state.transform.origin) * 24.0 - relative * 7.0) * state.step
