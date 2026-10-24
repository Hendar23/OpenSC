extends Node3D
## Big Ears, Escape Pod and depth launcher share ordinary equipment input.
const ListeningProbe = preload("res://listening_probe.gd")
const DepthCharge = preload("res://depth_charge.gd")
var equipment: Node3D
var folder := ""
var pod: RigidBody3D
var cable: MeshInstance3D
var pod_target: Node3D
var pod_attached := false
var pod_anchor := Vector3.ZERO
var pod_anchor_basis := Basis.IDENTITY
var passengers := false
var pod_deployment := 0.0
var pod_enabled := false
var pod_stowed := true
var pod_reel_offset := Vector3.ZERO
var depth_cooldown := 0.0
var projectiles: Array[Node3D] = []
var explosion_frames: Array[Texture2D] = []
var explosion_sound: AudioStream
var fire_audio: AudioStreamPlayer
var depth_audio: AudioStreamPlayer
var attractatron: Node3D
var rover: CharacterBody3D

func setup(owner_equipment: Node3D, game_folder: String) -> void:
	equipment = owner_equipment; folder = game_folder
	fire_audio = AudioStreamPlayer.new(); add_child(fire_audio)
	fire_audio.stream = preload("res://submarine_weapons.gd")._sound(folder,"audio.equipment.bigears.fire","LISTEN")
	depth_audio = AudioStreamPlayer.new(); add_child(depth_audio)
	depth_audio.stream = preload("res://submarine_weapons.gd")._sound(folder,"audio.weapon.depth.fire","DEPTH")
	explosion_frames = preload("res://mine_explosion.gd").load_frames(folder)
	explosion_sound = preload("res://submarine_weapons.gd")._sound(folder,"audio.weapon.depth.explosion","DCHARGE")
	_add_tool("bigears","Big Ears","LISTENL",["LISTEN1","LISTEN2"],Vector3(-0.24,0.08,-0.03))
	_add_tool("escape","Escape Pod","ESCAPE",["ESCAPE1","ESCAPE2","ESCAPE3","ESCAPE4"],equipment.available[1].mount.position)
	_add_tool("attract","Attractatron","ATTRACT",["ATTRON","ATTROFF"],Vector3(0,0.22,-0.22)*equipment.pilot.VISUAL_SCALE)
	attractatron = preload("res://attractatron.gd").new(); add_child(attractatron); attractatron.setup(equipment,folder)
	_add_tool("rover","ROV","ROVER",["ROVERWP"],Vector3(0,-0.2,0.1)*equipment.pilot.VISUAL_SCALE)
	rover = preload("res://remote_vehicle.gd").new(); equipment.pilot.get_parent().add_child(rover); rover.setup(self)

func runtime() -> Node:
	return get_tree().get_first_node_in_group("mission_runtime")

func _add_tool(id: String, caption: String, model_id: String, textures: Array, position: Vector3) -> void:
	var mount := Node3D.new(); mount.name = id.capitalize().replace(" ","") + "Mount"; equipment.add_child(mount); mount.position = position
	var visual := preload("res://clump_loader.gd").load_clump(folder.path_join("CLUMPS/" + model_id + ".DFF"))
	if visual != null: visual.rotation.y = PI; visual.scale *= equipment.pilot.VISUAL_SCALE; mount.add_child(visual)
	preload("res://submarine_mounts.gd").apply(mount,equipment.pilot.visual,id)
	var icons: Array[Texture2D] = []
	for file in textures: icons.append(preload("res://clump_loader.gd")._load_texture(folder,file,"",{}))
	equipment.available.append({"id":id,"name":caption,"enabled":false,"mount":mount,"icons":icons})
	mount.hide()

func activate(id: String, on: bool) -> void:
	if id == "rover": rover.set_deployed(on)
	elif id == "bigears" and on:
		fire_listening()
		for item in equipment.available:
			if item.id == id: item.enabled = false
	elif id == "escape":
		pod_enabled = on
		if on:
			pod_stowed = false
			if is_instance_valid(pod): pod.freeze = false; pod.sleeping = false; pod.linear_velocity = equipment.pilot.linear_velocity
		if not on:
			_detach_pod(false)
			if is_instance_valid(pod): pod_reel_offset = equipment.pilot.global_basis.inverse() * (pod.global_position-pod_socket())
		if pod == null and on:
			var visual := preload("res://clump_loader.gd").load_clump(folder.path_join("CLUMPS/ESCAPE.DFF"))
			if visual != null:
				visual.rotation.y = PI; visual.scale *= equipment.pilot.VISUAL_SCALE
				pod = preload("res://escape_pod.gd").new(); pod.tools = self
				equipment.pilot.get_parent().add_child(pod); pod.add_child(visual)
				pod.global_position = pod_socket(); pod.add_collision_exception_with(equipment.pilot)
				var shape := CollisionShape3D.new(); shape.shape = SphereShape3D.new(); shape.shape.radius = pod.radius; pod.add_child(shape)
				pod.reset_physics_interpolation()
				var mission := runtime()
				if mission != null: mission.game.water_visuals.attach(pod)
				preload("res://natural_light.gd").new().attach(pod)
				cable = MeshInstance3D.new(); cable.mesh = CylinderMesh.new(); cable.mesh.top_radius = 0.004; cable.mesh.bottom_radius = 0.004; cable.mesh.height = 1.0; cable.mesh.radial_segments = 6
				var material := StandardMaterial3D.new(); material.albedo_color = Color(0.3,0.35,0.36); cable.material_override = material
				cable.top_level = true; add_child(cable)
		for item in equipment.available:
			if item.id == "escape" and item.mount.get_child_count() > 0: item.mount.get_child(0).visible = not on

func pod_socket() -> Vector3:
	for item in equipment.available:
		if item.id == "escape": return item.mount.global_position
	return equipment.pilot.to_global(Vector3(0,-0.1,0))

func _detach_pod(recall: bool = true) -> void:
	if is_instance_valid(pod_target):
		if is_instance_valid(pod): pod.remove_collision_exception_with(pod_target); pod_target.remove_collision_exception_with(pod)
		if is_instance_valid(equipment.pilot): equipment.pilot.remove_collision_exception_with(pod_target)
		if pod_target.has_meta("rescue_pod_pilot"): pod_target.remove_meta("rescue_pod_pilot")
	pod_target = null
	pod_attached = false
	pod_anchor_basis = Basis.IDENTITY
	if recall and pod_enabled: _recall_pod()

func _recall_pod() -> void:
	for item in equipment.available:
		if item.id == "escape": item.enabled = false
	activate("escape",false)

func _attach_pod(body: Node) -> void:
	if not pod_enabled or pod_deployment < 0.2 or not is_instance_valid(pod) or is_instance_valid(pod_target): return
	var mission := runtime()
	if mission == null or not mission.side_jobs.can_attach_pod(body): return
	# Thwart Terrorists starts with the SWAT team already in the pod. Other
	# rescues still require an empty pod; their mission eligibility enforces it.
	if passengers and mission.side_jobs.terrorists == null and not (mission.side_jobs.stage_three != null and mission.side_jobs.id == "rovrtn"): return
	# Seat the pod at the transport's visible surface, preserving its contact
	# point as the convoy moves. The enclosing NPC collider includes empty space.
	var agent: Node3D = mission.side_jobs.target
	var appearance: Node3D = body if body == agent else agent.get_parent()
	var point := pod.global_position; var closest := point; var distance := INF
	for mesh: MeshInstance3D in appearance.find_children("*","MeshInstance3D",true,false):
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
	if not is_finite(distance): return
	var normal := (point-closest).normalized()
	if normal.is_zero_approx(): normal = Vector3.UP
	var center: Vector3 = body.get_meta("mission_target_center",Vector3.ZERO)
	if normal.dot(closest-body.to_global(center)) < 0: normal = -normal
	point = closest + normal * pod.radius
	if equipment.pilot.global_position.distance_to(point) > 3.0: return
	pod_target = body; pod_attached = true; pod_anchor = body.to_local(point)
	# Keep the orientation at contact in the host's rotating frame, rather
	# than leaving the frozen pod aligned to the world as the ship turns.
	pod_anchor_basis = body.global_basis.orthonormalized().inverse() * pod.global_basis
	pod.add_collision_exception_with(body); body.add_collision_exception_with(pod)
	equipment.pilot.add_collision_exception_with(body)
	body.set_meta("rescue_pod_pilot",weakref(equipment.pilot))
	pod.freeze = true; pod.angular_velocity = Vector3.ZERO; pod.collision_mask = 0; pod.collision_layer = 0; pod.global_position = point; pod.reset_physics_interpolation()

func fire_listening() -> void:
	var mission := runtime()
	if mission == null: return
	var progress: Dictionary = mission.game.player_progress
	var count := int(progress.ammunition.get("bigears",5))
	if count <= 0: return
	var mount: Node3D
	for item in equipment.available:
		if item.id == "bigears": mount = item.mount
	if mount == null: return
	var projectile := _projectile("LISTEND",preload("res://submarine_mounts.gd").launch_point(mount,equipment.pilot.visual,"bigears",Vector3(0,0,-0.25)))
	if projectile == null: return
	projectile.linear_velocity = equipment.pilot.linear_velocity
	projectile.add_collision_exception_with(equipment.pilot)
	if mission.side_jobs.id in ["spytrad","spytrad2","spytech","spytech2"] and is_instance_valid(mission.side_jobs.target):
		var listening_target: Node3D = mission.side_jobs.remaining.ship if mission.side_jobs.remaining != null else mission.side_jobs.target
		projectile.designated_target = listening_target.body
	progress.ammunition.bigears = count - 1
	if fire_audio.stream != null:
		fire_audio.volume_db = -16.0 + float(equipment.pilot.submarine_audio.tuning.settings.master_volume); fire_audio.play()
	if count == 1:
		var ids: Array = equipment.mounted.map(func(item: Dictionary) -> String: return str(item.id)); ids.erase("bigears"); equipment.set_installed(ids)

func fire_depth(held: bool) -> void:
	if not held or depth_cooldown > 0: return
	if equipment.pilot.dead or not equipment.pilot.active or not equipment.pilot.controls_enabled: return
	depth_cooldown = 1.0
	var mission := runtime()
	if mission == null or int(mission.game.player_progress.hold.get("depth",0)) <= 0: return
	var weapons: Node3D = equipment.pilot.get_node_or_null("MountedWeapons")
	if weapons == null or weapons.current().get("id","") != "depthl": return
	var projectile := _projectile("DEPTHD",weapons.depth_mount.global_position)
	if projectile == null: return
	projectile.linear_velocity = equipment.pilot.linear_velocity
	projectile.add_collision_exception_with(equipment.pilot)
	mission.game.player_progress.hold.depth -= 1
	projectile.prepare_aperture()
	if mission.game.player_progress.hold.depth == 0: mission.game.player_progress.hold.erase("depth")
	if depth_audio.stream != null:
		depth_audio.volume_db = -16.0 + float(equipment.pilot.submarine_audio.tuning.settings.master_volume); depth_audio.play()

func _projectile(model_id: String, point: Vector3) -> Node3D:
	var visual := preload("res://clump_loader.gd").load_clump(folder.path_join("CLUMPS/" + model_id + ".DFF"))
	if visual == null: return null
	var projectile: RigidBody3D = ListeningProbe.new() if model_id == "LISTEND" else DepthCharge.new()
	equipment.pilot.get_parent().add_child(projectile)
	projectile.tools = self; projectile.global_position = point; projectile.global_basis = equipment.pilot.global_basis
	projectile.add_child(visual); visual.scale *= equipment.pilot.VISUAL_SCALE; projectiles.append(projectile)
	var mission := runtime()
	if mission != null: mission.game.water_visuals.attach(visual)
	preload("res://natural_light.gd").new().attach(visual)
	return projectile

func _physics_process(delta: float) -> void:
	depth_cooldown = maxf(0,depth_cooldown - delta)
	projectiles.assign(projectiles.filter(func(node: Variant) -> bool: return is_instance_valid(node)))
	for item in equipment.available:
		if item.id == "bigears": item["icon_state"] = 1 if projectiles.any(func(node: Node3D) -> bool: return node is ListeningProbe and node.attached) else 0
	if pod == null: return
	if pod_enabled and pod_attached and (not is_instance_valid(pod_target) or bool(pod_target.get("dead")) or equipment.pilot.global_position.distance_to(pod_target.to_global(pod_anchor)) > 3.0):
		_recall_pod()
	if equipment.pilot.dead or not equipment.pilot.active: pod_enabled = false; _detach_pod(false)
	pod_deployment = move_toward(pod_deployment,0.6 if pod_enabled else 0.0,delta * 0.8)
	if not pod_enabled and not pod_stowed:
		# The winch reels relative to the moving hull; water drag must not leave
		# the pod perpetually trailing behind a sub travelling at full speed.
		pod_reel_offset = pod_reel_offset.move_toward(Vector3.ZERO,1.2*delta)
		pod.freeze = true; pod.global_position = pod_socket() + equipment.pilot.global_basis * pod_reel_offset
	if not pod_enabled and (pod_stowed or (pod_deployment <= 0.001 and pod.global_position.distance_to(pod_socket()) < 0.12)):
		# Once reeled in, latch the pod to its equipment mount. A spring-followed
		# hidden body used to lag behind a moving sub and become visible again.
		pod_stowed = true; pod.freeze = true; pod.collision_layer = 0; pod.collision_mask = 0
		pod.global_position = pod_socket(); pod.visible = false
		if cable != null: cable.visible = false
		for item in equipment.available:
			if item.id == "escape":
				item.icon_state = 3 if passengers else 0
				if item.mount.get_child_count() > 0: item.mount.get_child(0).show()
		return
	var point: Vector3 = pod.global_position
	if is_instance_valid(pod_target):
		point = pod_target.to_global(pod_anchor)
		pod.global_transform = Transform3D(pod_target.global_basis.orthonormalized() * pod_anchor_basis,point)
		var pull: Vector3 = point - equipment.pilot.global_position
		if pull.length() > 0.8: equipment.pilot.apply_central_force(pull.normalized() * (pull.length() - 0.8) * equipment.pilot.mass * 6.0)
	if not is_instance_valid(pod_target):
		if pod.freeze and pod_enabled:
			pod.freeze = false; pod.collision_mask = 1 | 8; pod.linear_velocity = equipment.pilot.linear_velocity
		pod.sleeping = false
		# A hull may already touch the pod when it is re-enabled. Contact lists
		# cover that case without requiring a new body_entered edge.
		if pod_enabled and pod_deployment >= 0.2:
			for body in pod.get_colliding_bodies(): _attach_pod(body)
	pod.visible = pod_enabled or pod.global_position.distance_to(pod_socket()) > 0.1
	if not is_instance_valid(pod_target): pod.collision_mask = (1 | 8) if pod.visible and pod_enabled else 0
	pod.collision_layer = 8 if pod.visible and pod_enabled and not is_instance_valid(pod_target) else 0
	for item in equipment.available:
		if item.id == "escape" and item.mount.get_child_count() > 0: item.mount.get_child(0).visible = not pod.visible
	if cable != null:
		var socket: Vector3 = pod_socket()
		var span: Vector3 = point - socket; cable.visible = pod.visible and span.length() > 0.005
		if cable.visible:
			cable.global_position = (point + socket) * 0.5
			cable.global_basis = Basis(Quaternion(Vector3.UP,span.normalized())).scaled(Vector3(1,span.length(),1))
	for item in equipment.available:
		if item.id == "escape": item["icon_state"] = 3 if passengers else 2 if is_instance_valid(pod_target) else 1 if pod_enabled else 0

func reset(reset_rover: bool = true) -> void:
	if reset_rover and is_instance_valid(rover): rover.reset()
	_detach_pod(false)
	for node in projectiles:
		if is_instance_valid(node): node.queue_free()
	projectiles.clear(); pod_target = null; passengers = false; pod_enabled = false; pod_stowed = true; pod_deployment = 0; depth_cooldown = 0
	if is_instance_valid(pod): pod.queue_free()
	if is_instance_valid(cable): cable.queue_free()
	pod = null; cable = null
	for item in equipment.available:
		if item.id == "escape":
			item.enabled = false; item.icon_state = 0
			if is_instance_valid(item.mount) and item.mount.get_child_count() > 0: item.mount.get_child(0).show()

func _exit_tree() -> void:
	reset()
	if is_instance_valid(rover): rover.queue_free()
