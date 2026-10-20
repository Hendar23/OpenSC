extends CharacterBody3D
## ROVER 004209d0: remotely driven camera, four-second exposure, return/recovery.
const RENDER_LAYER := 1 << 18
const Radio = preload("res://docking_radio.gd")
var tools: Node3D
var deployed := false
var launched := false
var returning := false
var docking_prompt := false
var declined_nearby := false
var recording := 0.0
var exposure := 0.0
var yaw := 0.0
var pitch := 0.0
var visual: Node3D
var speech: AudioStreamPlayer
var radio_lines := {}
var fire_latched := false
var health := 2.0
var dead := false

func setup(owner_tools: Node3D) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	tools = owner_tools; collision_layer = 8; collision_mask = 1 | 8
	var collider := CollisionShape3D.new(); collider.shape = SphereShape3D.new(); collider.shape.radius = 0.12; add_child(collider)
	visual = preload("res://map_document.gd").load_model("ROVER",tools.folder)
	if visual != null:
		visual.rotation.y = PI; add_child(visual)
		for mesh in visual.find_children("*","GeometryInstance3D",true,false): mesh.layers = RENDER_LAYER
	add_collision_exception_with(tools.equipment.pilot)
	set_meta("damage_sustain",0.75) # 004209d0 overrides the generic CSV value.
	var lamp := SpotLight3D.new(); lamp.position = Vector3(0,0.04,-0.15); lamp.spot_range = 5; lamp.spot_angle = 45; lamp.light_energy = 1.5; add_child(lamp)
	var fill := OmniLight3D.new(); fill.omni_range = 4; fill.light_energy = 0.3; add_child(fill)
	speech = AudioStreamPlayer.new(); speech.volume_db = Radio.SPEECH_VOLUME_DB; add_child(speech)
	hide(); set_physics_process(false)

func set_deployed(on: bool) -> void:
	if on == deployed: return
	if on and (dead or returning): return
	tools.equipment.pilot.remote_controlled = on
	if on:
		deployed = true; docking_prompt = false
		if not launched:
			launched = true
			var mount := socket()
			global_transform = mount.global_transform if mount != null else tools.equipment.pilot.global_transform
			if mount != null and mount.get_child_count() > 0: mount.get_child(0).hide()
			yaw = global_rotation.y; pitch = global_rotation.x; velocity = tools.equipment.pilot.linear_velocity
			reset_physics_interpolation()
		show(); set_physics_process(true)
		var runtime: Node = tools.runtime()
		if runtime != null: runtime.game.natural_light.attach(visual); runtime.game.water_visuals.attach(visual)
		_radio("rover3")
	else:
		deployed = false; recording = 0; docking_prompt = false
		if launched and global_position.distance_squared_to(docking_approach()) < 1.0:
			returning = true; _radio("rover2")
		else: _radio("rover4")
		var runtime: Node = tools.runtime()
		if runtime != null: runtime.game._update_follow_camera(0,true)

func transmission(code: String) -> Dictionary:
	if radio_lines.has(code): return radio_lines[code]
	var runtime: Node = tools.runtime()
	if runtime == null: return {}
	var row: Dictionary = runtime.game.gameplay_catalogue.tables.get("radio_messages",{}).get("records",{}).get(code,{})
	radio_lines[code] = {"speaker":"ship","key":"equipment/"+code,"text":str(row.get("text","")),"portrait":Radio.speaker_portrait(tools.folder,"ship"),"distorted_portrait":Radio.speaker_portrait(tools.folder,"ship",true)}
	return radio_lines[code]

func _radio(code: String, prompt: bool = false) -> void:
	var message := transmission(code)
	if message.is_empty(): return
	var path: String = tools.folder.path_join("WAVES/ENGLISH/"+code.to_upper()+".RAW")
	speech.stop()
	# Several retail ship-computer lines have text but no corresponding sample.
	# Display the original line without inventing speech or a replacement clip.
	speech.stream = preload("res://legacy_audio.gd").load_file(path)
	if speech.stream != null: speech.play()
	if not prompt:
		var runtime: Node = tools.runtime()
		if runtime.game.radio_feed != null:
			var feed: Control = runtime.game.radio_feed
			if str(feed.prompt.get("message",{}).get("key","")) == "equipment/rover1": feed.set_prompt({},runtime.game.docking.radio_static)
			feed.push_message(message,runtime.game.docking.radio_static)

func docking_approach() -> Vector3:
	var pilot: Node3D = tools.equipment.pilot
	if preload("res://submarine_mounts.gd").is_original(pilot.visual): return pilot.visual.get_node("Hull").to_global(Vector3(0,-0.8,-0.5))
	return pilot.to_global(Vector3(0,-0.8,0.5))

func check_docking_prompt() -> void:
	if not launched or returning or dead: return
	if global_position.distance_squared_to(docking_approach()) >= 1.0:
		docking_prompt = false; declined_nearby = false
	elif not docking_prompt and not declined_nearby:
		docking_prompt = true; _radio("rover1",true)

func answer_docking(accepted: bool) -> void:
	if not docking_prompt: return
	docking_prompt = false; declined_nearby = not accepted
	if not accepted: return
	deployed = false; returning = true; recording = 0
	tools.equipment.pilot.remote_controlled = false
	for item in tools.equipment.available:
		if item.id == "rover": item.enabled = false
	_radio("rover2")
	var runtime: Node = tools.runtime()
	if runtime != null: runtime.game._update_follow_camera(0,true)

func can_control() -> bool:
	var runtime: Node = tools.runtime()
	return deployed and tools.equipment.pilot.controls_enabled and runtime != null and not runtime.game.map_open and not runtime.game.world_loading and not runtime.game.developer_ui_visible and not runtime.game.front_end.menu_layer.visible and not runtime.game.dock_interface_active and not tools.equipment.pilot.dead

func socket() -> Node3D:
	for item in tools.equipment.available:
		if item.id == "rover": return item.mount
	return null

func _physics_process(delta: float) -> void:
	if tools.equipment.pilot.dead: reset(); return
	var mission: Node = tools.runtime()
	if deployed and mission != null and mission.game.docking.stage != mission.game.Docking.Stage.IDLE:
		for item in tools.equipment.available:
			if item.id == "rover": item.enabled = false
		set_deployed(false)
	check_docking_prompt()
	if returning:
		var mount := socket()
		var offset: Vector3 = (mount.global_position if mount != null else tools.equipment.pilot.global_position)-global_position
		velocity = offset.normalized()*3.0; move_and_slide()
		if offset.length() < 0.08: reset(false)
		return
	if not can_control():
		if not deployed and launched:
			velocity = velocity.move_toward(Vector3.ZERO,delta*4); move_and_slide()
		return
	var controls := preload("res://pilot_input.gd").read()
	yaw += controls.z*delta*1.5; pitch = clampf(pitch+controls.w*delta,-1.2,1.2)
	global_basis = Basis.from_euler(Vector3(pitch,yaw,0))
	var desired := -global_basis.z*controls.x*2.0+Vector3.UP*controls.y*1.5
	velocity = velocity.lerp(desired,1-exp(-3.0*delta)); move_and_slide()
	global_position.y = minf(global_position.y,tools.equipment.pilot.surface_height-0.2)
	var pressed := preload("res://input_bindings.gd").strength("weapon_fire") > 0.5
	if pressed and not fire_latched and recording <= 0: recording = 4.0; exposure = 0
	fire_latched = pressed
	if recording > 0: advance_recording(delta)

func advance_recording(delta: float) -> void:
	var runtime: Node = tools.runtime()
	var jobs: Node = runtime.side_jobs if runtime != null else null
	var step := minf(delta,recording)
	if jobs != null and jobs.remaining != null and jobs.remaining.family == "recon":
		var target: Node3D = jobs.remaining.structure
		if is_instance_valid(target) and not target.dead:
			var point: Vector3 = target.to_global(target.get_meta("mission_target_center",Vector3.ZERO))
			var offset := point-global_position; var distance := offset.length()
			var facing := maxf(0,-global_basis.z.dot(offset.normalized()))
			var ray := PhysicsRayQueryParameters3D.create(global_position,point,1 | 8,[get_rid(),tools.equipment.pilot.get_rid(),target.get_rid()])
			# Original ROVER accumulates (forward dot direction / distance)^2
			# over 100 ticks, then divides by 100. Recon accepts quality > .05.
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): exposure += pow(facing/(distance if distance >= 0.5 else 10.0),2)*step
	recording = maxf(0,recording-step)
	if recording == 0 and jobs != null and jobs.remaining != null: jobs.remaining.rov_recorded(exposure/4.0)

func camera_pose() -> Transform3D:
	return get_global_transform_interpolated()*Transform3D(Basis.IDENTITY,Vector3(0,0.04,-0.15))

func take_weapon_damage(strength: float, _point: Vector3 = Vector3.ZERO) -> void:
	if not launched or dead: return
	health -= maxf(0,strength)*0.75
	if health <= 0:
		# 004209d0 message 3 removes retail inventory item 0x15. A destroyed
		# ROV cannot be recovered by toggling it off and on for a free replacement.
		reset(false); dead = true
		var ids: Array = tools.equipment.mounted.map(func(item: Dictionary) -> String: return str(item.id))
		ids.erase("rover"); tools.equipment.set_installed(ids)
		var runtime: Node = tools.runtime()
		if runtime != null: runtime.game._update_follow_camera(0,true)

func take_weapon_damage_from(strength: float, point: Vector3, _owner: Node3D) -> void:
	take_weapon_damage(strength,point)

func reset(repair: bool = true) -> void:
	if is_instance_valid(tools.equipment.pilot): tools.equipment.pilot.remote_controlled = false
	deployed = false; launched = false; returning = false; docking_prompt = false; declined_nearby = false; recording = 0; velocity = Vector3.ZERO
	if repair: dead = false; health = 2
	hide(); set_physics_process(false)
	for item in tools.equipment.available:
		if item.id == "rover":
			item.enabled = false
			if item.mount.get_child_count() > 0: item.mount.get_child(0).show()
