extends StaticBody3D
## The retail multi-state switch can be held by the parked ROV or the sub.
var iris: Node3D
var shape: CollisionShape3D
var meshes: Array[MeshInstance3D] = []
var pressed_for := 0.0
var poll := 0.0

func setup(model: Node3D, hatch: Node3D) -> void:
	iris = hatch; add_child(model); collision_layer = 1; collision_mask = 0
	shape = CollisionShape3D.new(); shape.shape = preload("res://model_hitbox.gd").fitted_hull(model); add_child(shape)
	preload("res://morph_animation.gd").collect(model,meshes)

func activate() -> void:
	pressed_for = 0.4
	if is_instance_valid(iris): iris.activate()

func _physics_process(delta: float) -> void:
	pressed_for = maxf(0,pressed_for-delta); poll -= delta
	if poll <= 0:
		poll = 0.1
		var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape.shape
		query.transform = shape.global_transform; query.margin = 0.06; query.collision_mask = 2|8
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): activate()
	for mesh in meshes: mesh.set_blend_shape_value(0,1.0 if pressed_for > 0 else 0.0)
