extends RigidBody3D
## SC.EXE 0046a930 -> 0044a420 / 0044a100, blast callback 0044a2d0.
const TICK_RATE := 25.0
const SINK_ACCELERATION := 0.0002 / 0.05 * TICK_RATE * TICK_RATE
# The original starts at 30, tests the old value < 0, then decrements it.
const FUSE_SECONDS := 32.0 / TICK_RATE
const BLAST_RADIUS := 3.0
const BLAST_STRENGTH := 4.0
const BLAST_IMPULSE := 0.03 * TICK_RATE
var tools: Node
var age := 0.0
var spent := false
var impact_velocity := Vector3.ZERO
var entered_vent: StaticBody3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mass = 0.05; gravity_scale = 0.0; custom_integrator = true
	contact_monitor = true; max_contacts_reported = 8; continuous_cd = true
	collision_layer = 8; collision_mask = 15
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	var collider := CollisionShape3D.new(); collider.shape = SphereShape3D.new()
	collider.shape.radius = 0.1; add_child(collider)
	body_entered.connect(func(_body: Node) -> void: detonate.call_deferred())

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if spent: return
	age += state.step
	state.linear_velocity += Vector3.DOWN * SINK_ACCELERATION * state.step
	state.angular_velocity *= pow(0.9,TICK_RATE * state.step)
	impact_velocity = state.linear_velocity
	sleeping = false

func _physics_process(delta: float) -> void:
	if spent: return
	prepare_aperture(delta)
	if is_instance_valid(tools):
		var mission: Node = tools.runtime()
		if mission != null and is_instance_valid(mission.game.submarine_traffic.bubbles):
			mission.game.submarine_traffic.bubbles.emit_from(get_instance_id(),global_position,Vector3.UP,1.0,12.5,delta)
	if is_instance_valid(entered_vent) and entered_vent.charge_at_target(global_position):
		detonate(); return
	if age >= FUSE_SECONDS:
		# Once admitted, let a correctly dropped charge reach the shaft floor.
		# Keep misses on the ordinary fuse and bound the extra travel time.
		if is_instance_valid(entered_vent) and entered_vent.contains_charge(global_position) and age < FUSE_SECONDS+2.0: return
		detonate()

func prepare_aperture(step: float = 0.0) -> void:
	if is_instance_valid(entered_vent): return
	for vent: StaticBody3D in get_tree().get_nodes_in_group("depth_charge_vents"):
		if not vent.accepts_charge(global_position,linear_velocity,step): continue
		entered_vent = vent
		add_collision_exception_with(vent)
		if is_instance_valid(vent.shell): add_collision_exception_with(vent.shell)
		return

static func damage_at(distance: float) -> float:
	return BLAST_STRENGTH / maxf(0.1,distance)

func detonate() -> void:
	if spent or is_queued_for_deletion(): return
	spent = true
	var shooter: Node3D = tools.equipment.pilot if is_instance_valid(tools) else null
	var point := global_position
	if is_instance_valid(entered_vent) and entered_vent.charge_at_target(point):
		point = entered_vent.global_position + Vector3.DOWN*entered_vent.INTERNAL_DEPTH
		global_position = point
	var shape := SphereShape3D.new(); shape.radius = BLAST_RADIUS
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape
	query.transform.origin = point; query.collision_mask = 15; query.exclude = [get_rid()]
	var struck := {}
	# Query mission internals by their actual target position, independently of
	# the hatch collider (which may lie outside the blast sphere).
	for vent: StaticBody3D in get_tree().get_nodes_in_group("depth_charge_vents"):
		vent.depth_charge_from(0.0,point,impact_velocity)
	for hit in get_world_3d().direct_space_state.intersect_shape(query,512):
		var body: Node3D = hit.collider
		if body == shooter or struck.has(body.get_instance_id()) or body.get("dead") == true: continue
		struck[body.get_instance_id()] = true
		var displacement := body.global_position - point
		var distance := maxf(0.1,displacement.length())
		if body.has_method("depth_charge_from"): continue # Already handled above.
		preload("res://original_damage.gd").weapon(body,damage_at(distance),point,shooter)
		var impulse := displacement * BLAST_IMPULSE / (distance * distance)
		if body.has_method("apply_weapon_impulse"): body.apply_weapon_impulse(impulse)
		elif body is RigidBody3D and not body.freeze: body.apply_central_impulse(impulse)
		elif body is CharacterBody3D: body.velocity += impulse
	if is_instance_valid(tools):
		var effect := preload("res://mine_explosion.gd").new(); get_parent().add_child(effect)
		effect.global_position = point; effect.setup(tools.explosion_frames,1.0,tools.explosion_sound)
	queue_free()

func _exit_tree() -> void:
	if not is_instance_valid(tools): return
	var mission: Node = tools.runtime()
	if mission != null and is_instance_valid(mission.game.submarine_traffic.bubbles):
		mission.game.submarine_traffic.bubbles.credits.erase(get_instance_id())
