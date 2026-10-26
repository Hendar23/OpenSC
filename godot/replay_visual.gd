extends RefCounted
## A visual-only history. Resources are retained, never gameplay nodes/scripts.
const CAPACITY := 602
const MATERIAL_FIELDS := ["opacity","albedo_texture","emission_texture","albedo_color","emission_color","uv_offset","strength","beam_length","beam_width","seed","light_color","propeller_bend","drift_distance","cloud_center"]
var source: WeakRef
var kind := ""
var stride := 14
var data := PackedFloat32Array()
var stamps := PackedInt64Array()
var versions: Array[Dictionary] = []
var previous: Array = []
var proxy: Node3D
var last_seen := 0.0
var born := 0.0
var mutable_mesh := false
static var shader_fields := {}
var multimesh_copy: MultiMesh
var material_templates := {}
var material_values := {}

func setup(node: Node3D, time: float) -> void:
	source = weakref(node); born = time; last_seen = time
	if node is CPUParticles3D:
		var age: Variant = node.get_parent().get("age")
		if age is float or age is int: born -= float(age)
	kind = "mesh" if node is MeshInstance3D else "sprite" if node is Sprite3D else "light" if node is Light3D else "multi" if node is MultiMeshInstance3D else "burst"
	if node is MeshInstance3D and node.mesh is ArrayMesh: stride += node.mesh.get_blend_shape_count()
	mutable_mesh = node.get_meta("replay_mutable_mesh",false)
	data.resize(CAPACITY*stride); stamps.resize(CAPACITY); stamps.fill(-1)

func record(tick: int, time: float, appearances: Dictionary = {}) -> void:
	var node: Node3D = source.get_ref()
	var slot := tick%CAPACITY; var offset := slot*stride
	stamps[slot] = tick
	data[offset+12] = 0
	while versions.size() > 1 and versions[1].tick <= tick-CAPACITY+1: versions.pop_front()
	if node == null or not node.is_inside_tree() or not node.is_visible_in_tree(): return
	# Procedural beams acquire this flag on their first geometry build, which
	# can happen after replay discovers the initially hidden mesh.
	mutable_mesh = mutable_mesh or node.get_meta("replay_mutable_mesh",false)
	last_seen = time
	var pose := node.global_transform
	# Avoid nested Variant indexing/loops for every recorded visual at20Hz.
	var x := pose.basis.x; var y := pose.basis.y; var z := pose.basis.z; var p := pose.origin
	data[offset] = x.x; data[offset+1] = x.y; data[offset+2] = x.z
	data[offset+3] = y.x; data[offset+4] = y.y; data[offset+5] = y.z
	data[offset+6] = z.x; data[offset+7] = z.y; data[offset+8] = z.z
	data[offset+9] = p.x; data[offset+10] = p.y; data[offset+11] = p.z
	data[offset+12] = 1
	var values := _values(node,appearances)
	if versions.is_empty() or values != previous or mutable_mesh:
		previous = values
		versions.append({"tick":tick,"state":_state(node)})
	data[offset+13] = versions.back().tick
	if node is MeshInstance3D:
		for index in range(stride-14): data[offset+14+index] = node.get_blend_shape_value(index)
	# Keep one preceding appearance for interpolation across the buffer edge.
	while versions.size() > 1 and versions[1].tick <= tick-CAPACITY+1: versions.pop_front()

func _values(node: Node3D, appearances: Dictionary) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		result = [node.mesh,node.material_override,node.layers,node.transparency]
		if node.mesh != null:
			for surface in node.mesh.get_surface_count():
				var surface_material: Material = node.get_surface_override_material(surface)
				result.append(surface_material); result.append(_material_values(surface_material,appearances))
	elif node is Sprite3D: result = [node.texture,node.modulate,node.pixel_size,node.material_override]
	elif node is MultiMeshInstance3D: result = [node.multimesh,node.multimesh.instance_count,node.multimesh.mesh,node.material_override]
	elif node is Light3D: return [node.light_color,node.light_energy,node.omni_range if node is OmniLight3D else node.spot_range]
	var material: Material = node.material_override if node is GeometryInstance3D else null
	result.append(_material_values(material,appearances))
	return result

func _fields(material: ShaderMaterial) -> Array:
	var id: int = material.shader.get_instance_id() if material.shader != null else 0
	if not shader_fields.has(id):
		shader_fields[id] = []
		if material.shader != null:
			for field in material.shader.get_shader_uniform_list():
				if field.name in MATERIAL_FIELDS: shader_fields[id].append(field.name)
		# The dummy renderer has no reflected shader-uniform list. Explicit
		# parameter values still exist and can be recorded/verified headlessly.
		if shader_fields[id].is_empty(): shader_fields[id] = MATERIAL_FIELDS.duplicate()
	return shader_fields[id]

func _material_values(material: Material, appearances: Dictionary) -> Array:
	var values: Array = []
	if material == null: return values
	var id := material.get_instance_id()
	# Many hull parts/fish share a material. Read its uniforms once per sample,
	# without carrying the snapshot into the next frame or missing animation.
	if appearances.has(id):
		material_values[id] = appearances[id]; return appearances[id]
	if material is ShaderMaterial:
		for field in _fields(material): values.append(material.get_shader_parameter(field))
	elif material is StandardMaterial3D: values = [material.albedo_color,material.albedo_texture,material.emission_texture]
	appearances[id] = values; material_values[id] = values
	return values

func _state(node: Node3D) -> Dictionary:
	var state := {}
	if node is GeometryInstance3D:
		state = {"layers":node.layers,"shadow":node.cast_shadow,"transparency":node.transparency,"material":_material(node.material_override)}
	if node is MeshInstance3D:
		state["mesh"] = _mesh_copy(node.mesh) if mutable_mesh and node.mesh != null else node.mesh
		state["bounds"] = node.custom_aabb
		state["surfaces"] = []
		if node.mesh != null:
			for index in node.mesh.get_surface_count(): state.surfaces.append(_material(node.get_surface_override_material(index)))
	elif node is Sprite3D:
		state.merge({"texture":node.texture,"modulate":node.modulate,"pixel_size":node.pixel_size,"billboard":node.billboard,"double_sided":node.double_sided,"no_depth_test":node.no_depth_test})
	elif node is MultiMeshInstance3D:
		# Water specks use an immutable instance buffer and animated uniforms.
		# Share one buffer copy across all samples, rather than copying it at20Hz.
		if multimesh_copy == null or multimesh_copy.instance_count != node.multimesh.instance_count or multimesh_copy.mesh != node.multimesh.mesh:
			var original: MultiMesh = node.multimesh
			multimesh_copy = MultiMesh.new(); multimesh_copy.transform_format = original.transform_format
			multimesh_copy.use_colors = original.use_colors; multimesh_copy.use_custom_data = original.use_custom_data
			multimesh_copy.mesh = original.mesh; multimesh_copy.instance_count = original.instance_count
			multimesh_copy.visible_instance_count = original.visible_instance_count
			var buffer := original.buffer
			if not buffer.is_empty(): multimesh_copy.buffer = buffer
		state["multimesh"] = multimesh_copy
		state["cloud"] = node.get_script() == preload("res://water_particles.gd")
	elif node is Light3D:
		state = {"color":node.light_color,"energy":node.light_energy,"range":node.omni_range if node is OmniLight3D else node.spot_range,"spot":node is SpotLight3D,"angle":node.spot_angle if node is SpotLight3D else 45.0}
	elif node is CPUParticles3D:
		# Only death bursts use CPU emitters. Keep an analytical visual burst
		# that can seek in either direction without restarting live particles.
		state = {"mesh":node.mesh,"count":node.amount,"lifetime":node.lifetime,"radius":node.emission_sphere_radius if node.emission_shape == CPUParticles3D.EMISSION_SHAPE_SPHERE else 0.0,"speed_min":node.initial_velocity_min,"speed_max":node.initial_velocity_max,"gravity":node.gravity,"size_min":node.scale_amount_min,"size_max":node.scale_amount_max,"spread":node.spread,"seed":node.get_instance_id()}
	return state

func _material(material: Material) -> Dictionary:
	if material == null: return {}
	var id := material.get_instance_id()
	if not material_templates.has(id): material_templates[id] = material.duplicate()
	return {"base":material_templates[id],"fields":_fields(material) if material is ShaderMaterial else ["albedo_color","albedo_texture","emission_texture"],"values":material_values.get(id,[]),"shader":material is ShaderMaterial}

func _apply_material(state: Dictionary, current: Material) -> Material:
	if state.is_empty(): return null
	if current == null or current.get_meta("replay_base",0) != state.base.get_instance_id():
		current = state.base.duplicate(); current.set_meta("replay_base",state.base.get_instance_id())
	for index in state.values.size():
		if state.shader: current.set_shader_parameter(state.fields[index],state.values[index])
		else: current.set(state.fields[index],state.values[index])
	return current

func _mesh_copy(mesh: Mesh) -> Mesh:
	var result := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		# Mutable ribbons/tracers in this game are triangle lists, including
		# ImmediateMesh, which does not expose surface_get_primitive_type.
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.surface_get_arrays(surface))
		result.surface_set_material(surface,mesh.surface_get_material(surface))
	return result

func _pose(offset: int) -> Transform3D:
	return Transform3D(Basis(Vector3(data[offset],data[offset+1],data[offset+2]),Vector3(data[offset+3],data[offset+4],data[offset+5]),Vector3(data[offset+6],data[offset+7],data[offset+8])),Vector3(data[offset+9],data[offset+10],data[offset+11]))

func show_at(root: Node3D, tick: int, fraction: float, time: float) -> void:
	var slot := tick%CAPACITY; var offset := slot*stride
	if stamps[slot] != tick or data[offset+12] == 0:
		if proxy != null: proxy.hide()
		return
	var version: Dictionary = {}
	for entry in versions:
		if entry.tick > tick: break
		version = entry
	if version.is_empty(): return
	if proxy == null:
		match kind:
			"mesh": proxy = MeshInstance3D.new()
			"sprite": proxy = Sprite3D.new()
			"light": proxy = SpotLight3D.new() if version.state.spot else OmniLight3D.new()
			"multi": proxy = MultiMeshInstance3D.new()
			"burst": proxy = MultiMeshInstance3D.new()
		proxy.process_mode = Node.PROCESS_MODE_DISABLED
		proxy.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		root.add_child(proxy)
	if proxy.get_meta("version",-1) != version.tick:
		_apply(version.state); proxy.set_meta("version",version.tick)
	proxy.show()
	var pose := _pose(offset)
	var next := ((tick+1)%CAPACITY)*stride
	var interpolate := stamps[(tick+1)%CAPACITY] == tick+1 and data[next+12] != 0
	# Zero scale is used by a few effects; do not decompose a singular basis.
	if interpolate and absf(pose.basis.determinant()) > 0.000001 and absf(_pose(next).basis.determinant()) > 0.000001: pose = pose.interpolate_with(_pose(next),fraction)
	proxy.global_transform = pose
	if proxy is MeshInstance3D:
		for index in range(stride-14): proxy.set_blend_shape_value(index,lerpf(data[offset+14+index],data[next+14+index],fraction) if interpolate else data[offset+14+index])
	elif kind == "burst": _burst(version.state,time-born)
	elif kind == "multi": refresh_view(root.get_viewport().get_camera_3d())

func _apply(state: Dictionary) -> void:
	if proxy is GeometryInstance3D and kind != "burst":
		proxy.layers = state.layers; proxy.cast_shadow = state.shadow; proxy.transparency = state.transparency
		proxy.material_override = _apply_material(state.material,proxy.material_override)
	if proxy is MeshInstance3D:
		proxy.mesh = state.mesh
		proxy.custom_aabb = state.get("bounds",AABB())
		for index in state.surfaces.size(): proxy.set_surface_override_material(index,_apply_material(state.surfaces[index],proxy.get_surface_override_material(index)))
	elif proxy is Sprite3D:
		proxy.texture = state.texture; proxy.modulate = state.modulate; proxy.pixel_size = state.pixel_size
		proxy.billboard = state.billboard; proxy.double_sided = state.double_sided; proxy.no_depth_test = state.no_depth_test
	elif proxy is Light3D:
		proxy.light_color = state.color; proxy.light_energy = state.energy; proxy.shadow_enabled = false
		if proxy is OmniLight3D: proxy.omni_range = state.range
		else: proxy.spot_range = state.range; proxy.spot_angle = state.angle
	elif kind == "multi": proxy.multimesh = state.multimesh; proxy.set_meta("camera_cloud",state.cloud)
	elif kind == "burst":
		proxy.multimesh = MultiMesh.new(); proxy.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		proxy.multimesh.mesh = state.mesh; proxy.multimesh.instance_count = state.count
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _burst(state: Dictionary, age: float) -> void:
	if age < 0 or age >= float(state.lifetime): proxy.hide(); return
	var rng := RandomNumberGenerator.new(); rng.seed = state.seed
	for index in state.count:
		var direction := Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
		if state.spread < 100: direction.y = absf(direction.y)
		var point: Vector3 = direction*float(state.radius)+direction*rng.randf_range(state.speed_min,state.speed_max)*age+state.gravity*age*age*0.5
		var size := rng.randf_range(state.size_min,state.size_max)
		proxy.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size),point))

func refresh_view(camera: Camera3D) -> void:
	if proxy == null or not proxy.get_meta("camera_cloud",false): return
	# Ambient specks surround the free camera, using the recorded drift.
	proxy.global_position = camera.global_position
	proxy.material_override.set_shader_parameter("cloud_center",proxy.global_position)

func dispose() -> void:
	if is_instance_valid(proxy): proxy.free()
	proxy = null; versions.clear(); data.clear(); stamps.clear(); multimesh_copy = null; material_templates.clear(); material_values.clear()
