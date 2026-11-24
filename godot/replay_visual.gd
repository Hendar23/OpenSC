extends RefCounted
## A visual-only history. Resources are retained, never gameplay nodes/scripts.
const CAPACITY := 602
const NO_MATERIAL_VALUES: Array = []
const MATERIAL_FIELDS := ["opacity","albedo_texture","emission_texture","albedo_color","emission_color","uv_offset","strength","beam_length","beam_width","seed","light_color","propeller_bend","drift_distance","cloud_center","flare_color","brightness","reach","diameter","cone_cosine","forward_sign","solar","lunar","blast_unit","spill_over","arc_scale","arc_phase","arc_strength"]
var source: WeakRef
var detached := false
var kind := ""
var transforms := PackedVector3Array()
var visible_samples := PackedByteArray()
var blends := PackedFloat32Array()
var blend_count := 0
var stamps := PackedInt64Array()
var blast_phases := PackedFloat32Array()
var versions: Array[Dictionary] = []
var previous: Array = []
var proxy: Node3D
var last_seen := 0.0
var born := 0.0
var mutable_mesh := false
static var shader_fields := {}
var multimesh_copy: MultiMesh
var material_templates := {}
var last_prune := 0.0

func setup(node: Node3D, time: float) -> void:
	source = weakref(node); born = time; last_seen = time
	if node is CPUParticles3D:
		var age: Variant = node.get_parent().get("age")
		if age is float or age is int: born -= float(age)
	kind = "mesh" if node is MeshInstance3D else "sprite" if node is Sprite3D else "light" if node is Light3D else "multi" if node is MultiMeshInstance3D else "burst"
	if node is MeshInstance3D and node.mesh is ArrayMesh: blend_count = node.mesh.get_blend_shape_count()
	mutable_mesh = node.get_meta("replay_mutable_mesh",false)
	transforms.resize(CAPACITY*4)
	visible_samples.resize(CAPACITY)
	blends.resize(CAPACITY*blend_count)
	stamps.resize(CAPACITY); stamps.fill(-1)
	if node.get_meta("replay_blast_phase",false): blast_phases.resize(CAPACITY)

func _drop_version() -> void:
	versions.pop_front()

func _prune(tick: int, time: float) -> void:
	while versions.size() > 1 and (versions[1].tick <= tick-CAPACITY+1 or versions[1].time <= time-30.0): _drop_version()
	if time-last_seen > 30.0:
		while not versions.is_empty(): _drop_version()
		previous.clear(); multimesh_copy = null
	if time-last_prune >= 1.0:
		last_prune = time
		for id in material_templates.keys():
			if material_templates[id].get_ref() == null: material_templates.erase(id)

func record(tick: int, time: float, appearances: Dictionary = {}) -> void:
	var node: Node3D = null if detached else source.get_ref()
	_prune(tick,time)
	if node == null: return
	var slot := tick%CAPACITY
	stamps[slot] = tick
	visible_samples[slot] = 0
	if not node.is_inside_tree() or not node.is_visible_in_tree(): return
	# Procedural beams acquire this flag on their first geometry build, which
	# can happen after replay discovers the initially hidden mesh.
	mutable_mesh = mutable_mesh or node.get_meta("replay_mutable_mesh",false)
	var pose := node.global_transform
	var offset := slot*4
	transforms[offset] = pose.basis.x
	transforms[offset+1] = pose.basis.y
	transforms[offset+2] = pose.basis.z
	transforms[offset+3] = pose.origin
	var values := _values(node,appearances)
	if versions.is_empty() or values != previous or mutable_mesh or kind == "multi":
		var state := _state(node,appearances)
		previous = values
		versions.append({"tick":tick,"time":time,"state":state})
	last_seen = time; visible_samples[slot] = 1
	if node is MeshInstance3D:
		var blend_offset := slot*blend_count
		for index in blend_count: blends[blend_offset+index] = node.get_blend_shape_value(index)
		if not blast_phases.is_empty(): blast_phases[slot] = node.material_override.get_shader_parameter("blast_age")

func _values(node: Node3D, appearances: Dictionary) -> Array:
	var instance := node as MeshInstance3D
	if instance != null:
		var mesh := instance.mesh
		var material := instance.material_override
		var overlay := instance.material_overlay
		var surface_count := mesh.get_surface_count() if mesh != null else 0
		var values := [_identity(mesh),_identity(material),instance.layers,instance.transparency,_identity(overlay),surface_count]
		if material != null: values.append(_material_values(material,appearances))
		if overlay != null: values.append(_material_values(overlay,appearances))
		for surface in surface_count:
			var override := instance.get_surface_override_material(surface)
			if override == null: continue
			values.append(surface)
			values.append(_identity(override))
			values.append(_material_values(override,appearances))
		return values
	var result: Array = []
	if node is Sprite3D:
		result = [_identity(node.texture),node.modulate,node.pixel_size,_identity(node.material_override)]
	elif node is MultiMeshInstance3D:
		result = [_identity(node.multimesh),node.multimesh.instance_count,_identity(node.multimesh.mesh),_identity(node.material_override)]
	elif node is Light3D: return [node.light_color,node.light_energy,node.omni_range if node is OmniLight3D else node.spot_range]
	var material: Material = node.material_override if node is GeometryInstance3D else null
	result.append(_material_values(material,appearances))
	return result

func _identity(resource: Resource) -> int:
	return resource.get_instance_id() if resource != null else 0

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
	if material == null: return NO_MATERIAL_VALUES
	var id := material.get_instance_id()
	# The snapshot itself detects changes. Resource uniforms compare by identity,
	# and the same array can supply every track that needs a playback version.
	if appearances.has(id): return appearances[id]
	var values: Array = []
	if material is ShaderMaterial:
		for field in _fields(material):
			var value: Variant = material.get_shader_parameter(field)
			values.append(value.duplicate(true) if value is Array else value)
	elif material is StandardMaterial3D: values = [material.albedo_color,material.albedo_texture,material.emission_texture]
	appearances[id] = values
	return values

func _state(node: Node3D, appearances: Dictionary) -> Dictionary:
	var state := {}
	if node is GeometryInstance3D:
		state = {"layers":node.layers,"shadow":node.cast_shadow,"transparency":node.transparency,"material":_material(node.material_override,appearances)}
	if node is MeshInstance3D:
		state["mesh"] = _mesh_copy(node.mesh,node.get_meta("replay_mesh_arrays",[])) if mutable_mesh and node.mesh != null else node.mesh
		state["bounds"] = node.custom_aabb
		if node.material_overlay != null: state["overlay"] = _material(node.material_overlay,appearances)
		state["surfaces"] = []
		if node.mesh != null:
			for index in node.mesh.get_surface_count(): state.surfaces.append(_material(node.get_surface_override_material(index),appearances))
	elif node is Sprite3D:
		state.merge({"texture":node.texture,"modulate":node.modulate,"pixel_size":node.pixel_size,"billboard":node.billboard,"double_sided":node.double_sided,"no_depth_test":node.no_depth_test})
	elif node is MultiMeshInstance3D:
		# Instance buffers can animate without changing resource identity/count.
		var original: MultiMesh = node.multimesh
		multimesh_copy = MultiMesh.new(); multimesh_copy.transform_format = original.transform_format
		multimesh_copy.use_colors = original.use_colors; multimesh_copy.use_custom_data = original.use_custom_data
		multimesh_copy.mesh = original.mesh; multimesh_copy.instance_count = original.instance_count
		multimesh_copy.visible_instance_count = original.visible_instance_count
		var buffer := original.buffer
		if not buffer.is_empty(): multimesh_copy.buffer = buffer
		state["multimesh"] = multimesh_copy
	elif node is Light3D:
		state = {"color":node.light_color,"energy":node.light_energy,"range":node.omni_range if node is OmniLight3D else node.spot_range,"spot":node is SpotLight3D,"angle":node.spot_angle if node is SpotLight3D else 45.0}
	elif node is CPUParticles3D:
		# Only death bursts use CPU emitters. Keep an analytical visual burst
		# that can seek in either direction without restarting live particles.
		state = {"mesh":node.mesh,"count":node.amount,"lifetime":node.lifetime,"radius":node.emission_sphere_radius if node.emission_shape == CPUParticles3D.EMISSION_SHAPE_SPHERE else 0.0,"speed_min":node.initial_velocity_min,"speed_max":node.initial_velocity_max,"gravity":node.gravity,"size_min":node.scale_amount_min,"size_max":node.scale_amount_max,"spread":node.spread,"seed":node.get_instance_id()}
	return state

func _material(material: Material, appearances: Dictionary) -> Dictionary:
	if material == null: return {}
	var id := material.get_instance_id()
	var base: Material = material_templates[id].get_ref() if material_templates.has(id) else null
	if base == null:
		base = material.duplicate(); material_templates[id] = weakref(base)
	return {"base":base,"fields":_fields(material) if material is ShaderMaterial else ["albedo_color","albedo_texture","emission_texture"],"values":appearances[id],"shader":material is ShaderMaterial}

func _apply_material(state: Dictionary, current: Material) -> Material:
	if state.is_empty(): return null
	if current == null or current.get_meta("replay_base",0) != state.base.get_instance_id():
		current = state.base.duplicate(); current.set_meta("replay_base",state.base.get_instance_id())
	for index in state.values.size():
		if state.shader: current.set_shader_parameter(state.fields[index],state.values[index])
		else: current.set(state.fields[index],state.values[index])
	return current

func _mesh_copy(mesh: Mesh, cpu_arrays: Array = []) -> Mesh:
	var result := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		# Mutable ribbons/tracers in this game are triangle lists, including
		# ImmediateMesh, which does not expose surface_get_primitive_type.
		var arrays: Array = cpu_arrays if surface == 0 and cpu_arrays.size() == Mesh.ARRAY_MAX else mesh.surface_get_arrays(surface)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(surface,mesh.surface_get_material(surface))
	return result

func _pose(slot: int) -> Transform3D:
	var offset := slot*4
	return Transform3D(Basis(transforms[offset],transforms[offset+1],transforms[offset+2]),transforms[offset+3])

func show_at(root: Node3D, tick: int, fraction: float, time: float) -> void:
	var slot := tick%CAPACITY
	if stamps[slot] != tick or visible_samples[slot] == 0:
		if proxy != null: proxy.hide()
		return
	var version: Dictionary = {}
	for entry in versions:
		if entry.tick > tick: break
		version = entry
	if version.is_empty():
		if proxy != null: proxy.hide()
		return
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
	var pose := _pose(slot)
	var next := (tick+1)%CAPACITY
	var interpolate := stamps[next] == tick+1 and visible_samples[next] != 0
	# Zero scale is used by a few effects; do not decompose a singular basis.
	if interpolate and absf(pose.basis.determinant()) > 0.000001:
		var next_pose := _pose(next)
		if absf(next_pose.basis.determinant()) > 0.000001: pose = pose.interpolate_with(next_pose,fraction)
	proxy.global_transform = pose
	if proxy is MeshInstance3D:
		var blend_offset := slot*blend_count
		var next_blend_offset := next*blend_count
		for index in blend_count:
			var weight := blends[blend_offset+index]
			if interpolate: weight = lerpf(weight,blends[next_blend_offset+index],fraction)
			proxy.set_blend_shape_value(index,weight)
		if not blast_phases.is_empty():
			var phase := blast_phases[slot]
			if interpolate: phase = lerpf(phase,blast_phases[next],fraction)
			proxy.material_override.set_shader_parameter("blast_age",phase)
	elif kind == "burst": _burst(version.state,time-born)

func _apply(state: Dictionary) -> void:
	if proxy is GeometryInstance3D and kind != "burst":
		proxy.layers = state.layers; proxy.cast_shadow = state.shadow; proxy.transparency = state.transparency
		proxy.material_override = _apply_material(state.material,proxy.material_override)
	if proxy is MeshInstance3D:
		proxy.mesh = state.mesh
		proxy.custom_aabb = state.get("bounds",AABB())
		proxy.material_overlay = _apply_material(state.get("overlay",{}),proxy.material_overlay)
		for index in state.surfaces.size(): proxy.set_surface_override_material(index,_apply_material(state.surfaces[index],proxy.get_surface_override_material(index)))
	elif proxy is Sprite3D:
		proxy.texture = state.texture; proxy.modulate = state.modulate; proxy.pixel_size = state.pixel_size
		proxy.billboard = state.billboard; proxy.double_sided = state.double_sided; proxy.no_depth_test = state.no_depth_test
	elif proxy is Light3D:
		proxy.light_color = state.color; proxy.light_energy = state.energy; proxy.shadow_enabled = false
		if proxy is OmniLight3D: proxy.omni_range = state.range
		else: proxy.spot_range = state.range; proxy.spot_angle = state.angle
	elif kind == "multi": proxy.multimesh = state.multimesh
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

func dispose() -> void:
	if is_instance_valid(proxy): proxy.free()
	while not versions.is_empty(): _drop_version()
	proxy = null; previous.clear()
	transforms.clear(); visible_samples.clear(); blends.clear(); stamps.clear()
	multimesh_copy = null; material_templates.clear()
