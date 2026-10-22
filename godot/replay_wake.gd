extends RefCounted
## Record each wake bubble once, then evaluate its existing drift/rise formula.
var source: WeakRef
var events: Array[Dictionary] = []
var alive := {}
var mesh: Mesh
var surface := INF
var proxy: MultiMeshInstance3D
var last_seen := 0.0
var last_trim := 0.0

func setup(node: Node3D, time: float) -> void:
	source = weakref(node); last_seen = time

func record(time: float, oldest: float) -> void:
	var node: Node3D = source.get_ref()
	var present := {}
	if node != null and node.is_inside_tree():
		mesh = node.instances.mesh; surface = node.surface_height
		for particle in node.particles:
			var id: int = particle.replay_id
			present[id] = true
			if alive.has(id): continue
			var event := {"id":id,"start":time,"end":INF,"point":particle.position,"drift":particle.drift,"rise":particle.rise,"age":particle.age,"size":particle.size,"opacity":particle.get("opacity",0.7),"lifetime":particle.get("lifetime",120.0),"end_size":particle.get("end_size",-1.0)}
			events.append(event); alive[id] = event
		if not node.particles.is_empty(): last_seen = time
	for id in alive.keys():
		if not present.has(id): alive[id].end = time; alive.erase(id)
	# Birth order is not expiry order; one long-lived bubble must not pin
	# every later, expired event in memory.
	if time-last_trim >= 1.0:
		last_trim = time
		events = events.filter(func(event: Dictionary) -> bool: return float(event.end) >= oldest)

func show_at(root: Node3D, time: float, camera: Camera3D) -> void:
	if mesh == null: return
	if proxy == null:
		proxy = MultiMeshInstance3D.new(); proxy.process_mode = Node.PROCESS_MODE_DISABLED
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		proxy.multimesh = MultiMesh.new(); proxy.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		proxy.multimesh.use_colors = true; proxy.multimesh.mesh = mesh; root.add_child(proxy)
	var selected: Array[Dictionary] = []
	for event in events:
		if time >= event.start and time < event.end: selected.append(event)
	if proxy.multimesh.instance_count < selected.size(): proxy.multimesh.instance_count = selected.size()
	proxy.multimesh.visible_instance_count = selected.size()
	for index in selected.size():
		var event := selected[index]; var elapsed: float = time-event.start; var age: float = event.age+elapsed
		var pose := pose_at(event,time); var point := pose.origin
		var opacity: float = event.opacity*smoothstep(0.25,1.25,camera.global_position.distance_to(point))
		if is_finite(surface): opacity *= smoothstep(0,0.2,surface-point.y)
		if event.end_size >= 0: opacity *= smoothstep(0,0.5,float(event.lifetime)-age)
		proxy.multimesh.set_instance_transform(index,pose)
		proxy.multimesh.set_instance_color(index,Color(0.82,0.94,1,opacity))

func pose_at(event: Dictionary, time: float) -> Transform3D:
	var elapsed: float = time-event.start; var age: float = event.age+elapsed
	var point: Vector3 = event.point+event.drift*((1.0-exp(-12.0*elapsed))/12.0)+Vector3.UP*float(event.rise)*elapsed
	var size := lerpf(event.size,event.end_size,minf(1,age/float(event.lifetime))) if event.end_size >= 0 else float(event.size)*(1.0+minf(age/6.0,1.0)*0.45)
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size),point)

func dispose() -> void:
	if is_instance_valid(proxy): proxy.free()
	proxy = null; events.clear(); alive.clear()
