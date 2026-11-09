extends StaticBody3D
## ENDGAMEIRIS00469f60: the contact switch renews its500-tick open latch.
var visual: Node3D
var meshes: Array[MeshInstance3D] = []
var shapes: Array[CollisionShape3D] = []
var poses: Array[Array] = []
var latch := 0.0
var openness := 0.0
var collision_open := false

func setup(model: Node3D) -> void:
	visual = model; add_child(model)
	collision_layer = 1; collision_mask = 0
	for mesh in visual.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null: continue
		meshes.append(mesh)
		var collider := CollisionShape3D.new(); add_child(collider); shapes.append(collider)
		collider.transform = global_transform.affine_inverse()*mesh.global_transform
		var surfaces: Array = []
		for phase in [0,1]:
			var faces := PackedVector3Array()
			for surface in mesh.mesh.get_surface_count():
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				if phase == 1 and mesh.mesh.get_blend_shape_count() > 0:
					arrays = mesh.mesh.surface_get_blend_shape_arrays(surface)[0]
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
				if indices.is_empty(): faces.append_array(vertices)
				else:
					for index in indices: faces.append(vertices[index])
			var shape := ConcavePolygonShape3D.new(); shape.backface_collision = true; shape.set_faces(faces); surfaces.append(shape)
		poses.append(surfaces); collider.shape = surfaces[0]

func activate() -> void:
	latch = 20.0

func _physics_process(delta: float) -> void:
	latch = maxf(0,latch-delta)
	openness = move_toward(openness,1.0 if latch > 0 else 0.0,delta*2.5)
	for mesh in meshes:
		if mesh.mesh.get_blend_shape_count() > 0: mesh.set_blend_shape_value(0,openness)
	var opened := openness >= 0.999
	if opened == collision_open: return
	collision_open = opened
	for index in shapes.size(): shapes[index].set_deferred("shape",poses[index][1 if opened else 0])
