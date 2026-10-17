extends Node3D
var kind := "listening"
var velocity := Vector3.ZERO
var age := 0.0
var tools: Node
var attached := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _physics_process(delta: float) -> void:
	if attached: return
	age += delta
	if kind == "depth": velocity.y -= 1.2 * delta
	var next := global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position,next,15,[tools.equipment.pilot.get_rid()]); query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		if kind == "depth": detonate(); return
		var body: Node3D = hit.collider
		var runtime: Node = tools.runtime()
		if runtime != null: runtime.side_jobs.attach_listening_device(body)
		if body.is_in_group("npc_submarines"):
			reparent(body,true); attached = true; return
		queue_free(); return
	global_position = next
	if age >= (1.2 if kind == "depth" else 5.0):
		if kind == "depth": detonate()
		else: queue_free()

func detonate() -> void:
	if attached: return
	attached = true
	var pilot: Node3D = tools.equipment.pilot
	var world: Node3D = pilot.get_parent()
	var shape := SphereShape3D.new(); shape.radius = 3.0
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape; query.transform.origin = global_position; query.collision_mask = 15
	var hit_ids := {}
	for hit in get_world_3d().direct_space_state.intersect_shape(query,128):
		var body: Node3D = hit.collider
		if hit_ids.has(body.get_instance_id()): continue
		hit_ids[body.get_instance_id()] = true
		if body.has_method("depth_charge"): body.depth_charge(3.0)
		else: preload("res://original_damage.gd").weapon(body,3.0 / maxf(0.5,global_position.distance_to(body.global_position)),global_position,pilot)
	var effect := preload("res://mine_explosion.gd").new(); world.add_child(effect); effect.global_position = global_position
	effect.setup(tools.explosion_frames,2.0,tools.explosion_sound)
	queue_free()
