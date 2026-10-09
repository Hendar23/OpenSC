extends StaticBody3D
const Definitions = preload("res://object_definitions.gd")
var stats := {}
var enabled := true
var player: Node3D
var pearl: RigidBody3D
var population: Node3D
var angle := 0.0
var remaining := 0.0
var lid: Node3D
var rest := Basis.IDENTITY
var colliders: Array[Dictionary] = []

func setup(definition: Dictionary, visual: Node3D, running: bool, delay: float) -> void:
	stats = definition.duplicate(true); enabled = running; remaining = delay
	collision_layer = 1; collision_mask = 0
	add_child(visual)
	lid = visual.find_child("Frame_1",true,false) as Node3D
	if lid != null: rest = lid.basis
	for mesh in visual.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null: continue
		var collider := CollisionShape3D.new(); collider.shape = mesh.mesh.create_trimesh_shape(); add_child(collider)
		colliders.append({"mesh":mesh,"shape":collider})
	_update_shell()

func fully_open() -> bool:
	return is_instance_valid(pearl) and angle >= float(stats.open_angle) - 0.01

func _physics_process(delta: float) -> void:
	if not enabled: return
	if not is_instance_valid(pearl):
		remaining = maxf(0,remaining - delta)
		if remaining <= 0: _grow_pearl()
	var frightened := is_instance_valid(player) and global_position.distance_to(player.global_position) < float(stats.close_distance)
	var opening := is_instance_valid(pearl) and not frightened
	angle = move_toward(angle,float(stats.open_angle if opening else stats.closed_angle),float(stats.opening_speed if opening else stats.closing_speed) * delta)
	if not opening and is_instance_valid(pearl): pearl.global_position = to_global(Vector3(0,float(stats.pearl_height),0))
	_update_shell()

func _update_shell() -> void:
	if lid != null: lid.basis = rest * Basis(Vector3.RIGHT,deg_to_rad(angle))
	for entry in colliders:
		entry.shape.transform = global_transform.affine_inverse() * entry.mesh.global_transform if is_inside_tree() else entry.mesh.transform

func _grow_pearl() -> void:
	if not is_instance_valid(population): return
	var definition: Dictionary = population.pearl_types.get(str(stats.pearl_type),Definitions.PEARL)
	pearl = population._create_thorium(definition,0,Transform3D(Basis.IDENTITY,position + basis * Vector3(0,float(stats.pearl_height),0)))
	if pearl != null:
		pearl.clam = self; pearl.freeze = true; pearl.add_collision_exception_with(self)

func release_pearl() -> void:
	if not is_instance_valid(pearl): return
	pearl.clam = null; pearl.freeze = not enabled
	pearl = null; remaining = float(stats.regrowth_seconds)

func state() -> Dictionary:
	return {"angle":angle,"remaining":remaining,"pearl_offset":preload("res://map_document.gd").array(to_local(pearl.global_position)) if is_instance_valid(pearl) and not pearl.is_queued_for_deletion() else []}

func restore_state(value: Dictionary) -> void:
	angle = float(value.angle); remaining = float(value.remaining)
	if value.pearl_offset.size() == 3:
		_grow_pearl()
		if is_instance_valid(pearl): pearl.global_position = to_global(preload("res://map_document.gd").vector(value.pearl_offset))
	_update_shell()

func _exit_tree() -> void:
	if is_instance_valid(pearl): pearl.queue_free()
