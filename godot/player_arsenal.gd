extends Node3D
## Remaining retail weapons. Shop stock and ammo packs live in equipment_shop.
const Assets = preload("res://clump_loader.gd")
const Damage = preload("res://original_damage.gd")
const Projectile = preload("res://player_projectile.gd")
const Creature = preload("res://fish_controller.gd")
const MISSILE_COOLDOWN := 5.0/25.0
const RIPPER_RANGE := 10.0
var weapons: Node3D
var folder := ""
var mounts := {}
var templates := {}
var bolt_frames: Array[Texture2D] = []
var shots: Array[Node3D] = []
var cooldown := 0.0
var ripper_clock := 0.0
var ripper_credit := 100.0
var charge_remaining := 0.0
var charge_audio: AudioStreamPlayer
var gun_audio: AudioStreamPlayer
var fire_audio: AudioStreamPlayer
var tracer: MeshInstance3D
var tracer_material: StandardMaterial3D
var tracer_remaining := 0.0
var tracer_from := Vector3.ZERO
var tracer_to := Vector3.ZERO
var homing_target: Node3D
var target_clock := 0.0
var sight: Control
var electro_housing: Node3D

func setup(context: Node3D, game_folder: String) -> void:
	weapons = context; folder = game_folder
	_add("missile","Torpedo Launcher","MISSILEL","MISSILE",Vector3(0.28,0.12,0))
	# The original Ripper creates its tracer procedurally; there is no Ripper
	# hull model in the shipped assets. Its mount still supports mod replacements.
	_add("ripper","Ripper","","GUN",Vector3(0.28,0.12,0))
	var mast := Vector3(0,0.22,-0.22)
	var equipment: Node3D = weapons.pilot.get_node_or_null("MountedEquipment")
	if equipment != null:
		for entry in equipment.available:
			if entry.id == "attract": mast = entry.mount.position
	_add("electro","Electro Bolt","ELECTRO","ELECTRO1",mast)
	weapons.available.append({"id":"homers","name":"Homing Torpedoes","icon":Assets._load_texture(folder,"HMISSILE","",{})})
	for id in ["missile","homers"]:
		var visual := Assets.load_clump(folder.path_join("CLUMPS/" + ("HMISSILE" if id == "homers" else "MISSILE") + ".DFF"))
		if visual != null: add_child(visual); visual.hide(); templates[id] = visual
	for index in range(1,5): bolt_frames.append(Assets._load_texture(folder,"BOLT%d" % index,"BOLT%dM" % index,{}))
	charge_audio = _audio("audio.weapon.electro.charge","CHARGEUP",false)
	gun_audio = _audio("audio.weapon.ripper","GUNSHOT",true)
	fire_audio = AudioStreamPlayer.new(); add_child(fire_audio)
	tracer = MeshInstance3D.new(); tracer.mesh = ImmediateMesh.new(); tracer.top_level = true; tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(tracer)
	tracer_material = StandardMaterial3D.new(); tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_material.albedo_color = Color(1,0.85,0.5); tracer_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	tracer.material_override = tracer_material; tracer.hide()
	var overlay := CanvasLayer.new(); overlay.layer = 1; add_child(overlay)
	sight = preload("res://homing_target.gd").new(); sight.arsenal = self
	sight.frame = Assets._load_texture(folder,"HTARGETL","HTARGETM",{})
	overlay.add_child(sight)

func _add(id: String, caption: String, model: String, icon: String, point: Vector3) -> void:
	var mount := Node3D.new(); mount.name = id.capitalize() + "Mount"; weapons.add_child(mount); mount.position = point
	# Optional modern models use the same mod-aware clump lookup as other gear.
	var path := folder.path_join("CLUMPS/" + (model if not model.is_empty() else "RIPPER") + ".DFF")
	var housing: Node3D
	if FileAccess.file_exists(path) or not preload("res://mod_registry.gd").candidates("model.ripper").is_empty(): housing = Assets.load_clump(path)
	if housing != null: housing.rotation.y = PI; mount.add_child(housing)
	if id == "electro": electro_housing = housing
	preload("res://submarine_mounts.gd").apply(mount,weapons.pilot.visual,id)
	for mesh: MeshInstance3D in mount.find_children("*","MeshInstance3D",true,false): mesh.layers = 2
	mounts[id] = mount; mount.hide()
	weapons.available.append({"id":id,"name":caption,"icon":Assets._load_texture(folder,icon,"",{})})

func _audio(id: String, sample: String, loop: bool) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new(); player.stream = preload("res://audio_loop.gd").prepare(weapons._sound(folder,id,sample),loop,30)
	add_child(player); return player

func progress() -> Dictionary:
	var mission := get_tree().get_first_node_in_group("mission_runtime")
	return mission.game.player_progress if mission != null else {}

func bubbles() -> Node3D:
	var mission := get_tree().get_first_node_in_group("mission_runtime")
	return mission.game.submarine_traffic.bubbles if mission != null and is_instance_valid(mission.game.submarine_traffic) else null

func installed(ids: Array) -> void:
	for id in mounts: mounts[id].visible = id in ids
	if "electro" not in ids: cancel_charge()
	if "ripper" not in ids: gun_audio.stop(); ripper_clock = 0

func count(id: String) -> int:
	var state := progress()
	if state.is_empty(): return 0
	if id == "electro": return clampi(int(state.ammunition.get("electro",99)),0,99)
	return int(state.hold.get({"missile":"mammo","homers":"homers","ripper":"rammo","depthl":"depth"}.get(id,""),0))

func update(held: bool, delta: float) -> void:
	delta = maxf(0,delta); cooldown = maxf(0,cooldown-delta)
	var pilot: Node3D = weapons.pilot
	var live: bool = pilot.active and pilot.controls_enabled and not pilot.dead and not pilot.remote_controlled
	var id: String = weapons.current().get("id","")
	var state := progress()
	if state.is_empty(): return
	if electro_housing != null and charge_remaining <= 0: electro_housing.position.z = move_toward(electro_housing.position.z,0,delta*0.5)
	var gain: float = -16.0 + (float(pilot.submarine_audio.tuning.settings.master_volume) if pilot.submarine_audio != null else 0)
	gun_audio.volume_db = gain; charge_audio.volume_db = gain; fire_audio.volume_db = gain
	target_clock = maxf(0,target_clock-delta)
	if live and id == "homers" and target_clock <= 0:
		target_clock = 0.1
		homing_target = select_target(weapons.pilot.global_position,-weapons.pilot.global_basis.z)
	elif not live or id != "homers": homing_target = null
	for index in range(shots.size()-1,-1,-1):
		if not is_instance_valid(shots[index]): shots.remove_at(index)
	if charge_remaining > 0:
		if not live or id != "electro": cancel_charge()
		else:
			if electro_housing != null: electro_housing.position.z -= minf(delta,charge_remaining)*0.025
			charge_remaining = maxf(0,charge_remaining-delta)
			state.ammunition.electro = maxf(0,float(state.ammunition.electro)-75.0*delta)
			if charge_remaining <= 0:
				state.ammunition.electro = 0.0; charge_audio.stop(); _launch("electro"); _sound("audio.weapon.electro.fire","ELECTRO")
				if electro_housing != null: electro_housing.position.z = 0.2
	elif live and weapons.mounted.any(func(item: Dictionary) -> bool: return item.id == "electro"):
		state.ammunition.electro = minf(99,float(state.ammunition.get("electro",99))+12.5*delta)
	if not live or not held:
		gun_audio.stop(); ripper_clock = 0; return
	if id in ["missile","homers"] and cooldown <= 0 and count(id) > 0:
		if _launch(id):
			var ammo: String = "mammo" if id == "missile" else "homers"
			state.hold[ammo] -= 1
			if state.hold[ammo] <= 0: state.hold.erase(ammo)
			cooldown = MISSILE_COOLDOWN
			if id == "homers" and count(id) == 0: weapons.select_id("missile")
	elif id == "ripper" and count(id) > 0:
		if not gun_audio.playing and gun_audio.stream != null: gun_audio.play()
		ripper_clock += delta*25.0
		while ripper_clock >= 1.0 and count("ripper") > 0:
			ripper_clock -= 1.0; ripper_credit -= 10.0
			if ripper_credit < 0:
				ripper_credit += 100.0; state.hold.rammo -= 1
				if state.hold.rammo <= 0: state.hold.erase("rammo")
			_ripper_tick()
	elif id == "electro" and charge_remaining <= 0 and count(id) >= 99:
		charge_remaining = 33.0/25.0
		if charge_audio.stream != null: charge_audio.play()
	if id != "ripper" or count("ripper") <= 0: gun_audio.stop()

func select_target(point: Vector3, forward: Vector3) -> Node3D:
	var sphere := SphereShape3D.new(); sphere.radius = 10.0
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = sphere; query.transform.origin = point; query.collision_mask = 8
	var best: Node3D; var distance := INF
	for entry in get_world_3d().direct_space_state.intersect_shape(query,256):
		var body: Node3D = entry.collider
		if body == weapons.pilot or body.get("dead") == true or not body.has_method("take_damage") or not body.get_meta("weapon_target",true): continue
		var offset := body.global_position-point
		if offset.length_squared() >= distance or offset.normalized().dot(forward) < 0.5: continue
		var sight := PhysicsRayQueryParameters3D.create(point,body.global_position,13,[weapons.pilot.get_rid()]); sight.hit_back_faces = true
		var hit := get_world_3d().direct_space_state.intersect_ray(sight)
		if hit.get("collider") != body: continue
		best = body; distance = offset.length_squared()
	return best

func _launch(id: String) -> bool:
	var mount: Node3D = mounts["missile" if id == "homers" else id]
	var forward: Vector3 = -mount.global_basis.z.normalized()
	var point := preload("res://submarine_mounts.gd").launch_point(mount,weapons.pilot.visual,id,Vector3(0,0,-0.3))
	var projectile := Projectile.new(); weapons.pilot.get_parent().add_child(projectile)
	projectile.setup(self,id,point,forward,select_target(point,forward) if id == "homers" else null)
	shots.append(projectile)
	return true

func _ripper_tick() -> void:
	var mount: Node3D = mounts.ripper
	var start := preload("res://submarine_mounts.gd").launch_point(mount,weapons.pilot.visual,"ripper",Vector3(0,0.1,-0.2))
	var forward: Vector3 = (-mount.global_basis.z + Vector3(randf_range(-0.07,0.08),randf_range(-0.07,0.08),randf_range(-0.07,0.08))).normalized()
	var query := PhysicsRayQueryParameters3D.create(start,start+forward*RIPPER_RANGE,13,[weapons.pilot.get_rid()]); query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end: Vector3 = hit.get("position",query.to)
	if not hit.is_empty():
		Damage.weapon(hit.collider,maxf(0,RIPPER_RANGE-start.distance_to(end))*0.7,start,weapons.pilot)
		if hit.collider is Creature and weapons.blood_cooldown <= 0:
			weapons.hit_blood.emit_hit(end,hit.normal,hit.collider.death_frames,weapons.settings.gore_amount,weapons.settings.gore_lifetime,weapons.settings.gore_settle_speed)
			weapons.blood_cooldown = 0.15
	tracer_from = start; tracer_to = end; tracer_remaining = 0.04; tracer.show()

func _process(delta: float) -> void:
	tracer_remaining -= delta
	tracer.visible = tracer_remaining > 0
	if not tracer.visible: return
	var forward := tracer_to-tracer_from
	var side := forward.cross(weapons.camera.global_position-(tracer_from+tracer_to)*0.5).normalized()*0.006
	var mesh := tracer.mesh as ImmediateMesh; mesh.clear_surfaces(); mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for point: Vector3 in [tracer_from-side,tracer_from+side,tracer_to+side,tracer_from-side,tracer_to+side,tracer_to-side]: mesh.surface_add_vertex(point)
	mesh.surface_end(); tracer.mesh = mesh; tracer.global_transform = Transform3D.IDENTITY
	tracer.set_meta("replay_mutable_mesh",true)

func _sound(id: String, sample: String) -> void:
	fire_audio.stream = weapons._sound(folder,id,sample)
	if fire_audio.stream != null: fire_audio.play()

func burst(point: Vector3, size: float) -> void:
	var equipment: Node3D = weapons.pilot.get_node_or_null("MountedEquipment")
	if equipment == null or equipment.support_tools == null: return
	var effect := preload("res://mine_explosion.gd").new(); weapons.pilot.get_parent().add_child(effect); effect.global_position = point
	effect.setup(equipment.support_tools.explosion_frames,size,equipment.support_tools.explosion_sound)

func cancel_charge() -> void:
	charge_remaining = 0
	if electro_housing != null: electro_housing.position = Vector3.ZERO
	if charge_audio != null: charge_audio.stop()

func reset() -> void:
	for shot in shots:
		if is_instance_valid(shot): shot.free()
	shots.clear(); cooldown = 0; ripper_clock = 0; ripper_credit = 100; cancel_charge()
	homing_target = null; target_clock = 0
	gun_audio.stop(); fire_audio.stop(); tracer.hide(); tracer_remaining = 0

func _exit_tree() -> void:
	for shot in shots:
		if is_instance_valid(shot) and not shot.is_queued_for_deletion(): shot.queue_free()
