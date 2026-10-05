extends Node3D
const Assets = preload("res://clump_loader.gd")
const Equipment = preload("res://submarine_equipment.gd")
const AudioLoop = preload("res://audio_loop.gd")
const LegacyAudio = preload("res://legacy_audio.gd")
const Mods = preload("res://mod_registry.gd")
const DEFAULTS := {"range":4.0,"damage_per_second":10.0,"beam_width":0.18,"animation_speed":20.0,"volume_db":-16.0,"gore_amount":20.0,"gore_settle_speed":1.0,"gore_lifetime":2.0,"chunk_lifetime":60.0}
var settings := DEFAULTS.duplicate()
var pilot: Node3D
var camera: Camera3D
var muzzle: Node3D
var beam: MeshInstance3D
var material: StandardMaterial3D
var frames: Array[Texture2D] = []
var audio: AudioStreamPlayer3D
var icon: Texture2D
var firing := false
var elapsed := 0.0
var beam_start := Vector3.ZERO
var beam_end := Vector3.ZERO
var selected := 0
var mounted: Array[Dictionary] = []
var impact_frames: Array[Texture2D] = []
var impact: Sprite3D
var spark: OmniLight3D
var last_hit: Node3D

func setup(player: Node3D, folder: String, view: Camera3D, catalogue: Dictionary) -> void:
	pilot = player; camera = view; name = "MountedWeapons"
	if catalogue.get("tables",{}).has("weapon_tuning"):
		configure(catalogue.tables.weapon_tuning.records.get("zapper",{}))
	muzzle = Node3D.new(); muzzle.name = "ZapperMuzzle"; add_child(muzzle)
	var housing := Assets.load_clump(folder.path_join("CLUMPS/ELECTRIC.DFF"))
	var bounds := AABB(Vector3(-0.035,-0.02,-0.03),Vector3(0.07,0.04,0.06))
	if housing != null:
		housing.rotation.y = PI; housing.scale *= player.VISUAL_SCALE; muzzle.add_child(housing)
		bounds = Equipment._bounds(Equipment._meshes(housing,Transform3D.IDENTITY))
		for mesh in housing.find_children("*","MeshInstance3D",true,false): mesh.layers = 2
	# Seat the rear of the zapper into the canopy rim rather than suspending
	# the whole housing ahead of it. The emitter travels with this mount.
	muzzle.position = Equipment._hull_mount(player.visual,bounds) + Vector3(0,0,bounds.size.z * 1.15)
	var socket := player.visual.find_child("WeaponMount_Zapper",true,false) as Node3D
	if socket != null: muzzle.transform = player.global_transform.affine_inverse() * socket.global_transform; muzzle.basis = muzzle.basis.orthonormalized()
	preload("res://submarine_mounts.gd").apply(muzzle,player.visual,"zapper")
	var emitter := Marker3D.new(); emitter.name = "Emitter"; emitter.position = Vector3(0,bounds.get_center().y,bounds.position.z - 0.002); muzzle.add_child(emitter)
	var cache := {}
	for index in range(1,4): frames.append(Assets._load_texture(folder,"ZAPPER%d" % index,"ZAPPER%dM" % index,cache))
	icon = _icon(folder,catalogue)
	mounted.append({"id":"zapper","name":"Zapper","icon":icon})
	beam = MeshInstance3D.new(); beam.name = "ZapperBeam"; beam.top_level = true; beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.mesh = QuadMesh.new(); beam.mesh.size = Vector2(settings.beam_width,settings.range)
	material = StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; material.cull_mode = BaseMaterial3D.CULL_DISABLED; material.no_depth_test = false
	beam.material_override = material; add_child(beam); beam.hide()
	for name in ["SPARK1","SPARK"]:
		var texture := Assets._load_texture(folder,name,name + "M",cache)
		if texture != null: impact_frames.append(texture)
	impact = Sprite3D.new(); impact.texture = Assets._load_texture(folder,"SPARK1","SPARK1M",cache); impact.billboard = BaseMaterial3D.BILLBOARD_ENABLED; impact.pixel_size = 0.004; impact.no_depth_test = false; impact.top_level = true; add_child(impact); impact.hide()
	spark = OmniLight3D.new(); spark.top_level = true; spark.light_color = Color(0.55,0.7,1); spark.light_energy = 1; spark.omni_range = 1.5; add_child(spark); spark.hide()
	audio = AudioStreamPlayer3D.new(); audio.stream = AudioLoop.prepare(_sound(folder,"audio.weapon.zapper","ELECTRIC"),true,35); audio.volume_db = settings.volume_db; audio.max_distance = 25; muzzle.add_child(audio)

static func _sound(folder: String, id: String, sample: String) -> AudioStream:
	for replacement in Mods.candidates(id):
		var stream := LegacyAudio.load_file(replacement.path)
		if stream != null: return stream
	return LegacyAudio.load_file(folder.path_join("WAVES/" + sample + ".RAW"))

func _icon(folder: String, catalogue: Dictionary) -> Texture2D:
	var record: Dictionary = catalogue.get("tables",{}).get("equipment",{}).get("records",{}).get("zapper",{})
	# Sq Pic is the shop illustration. ELECTRIC.RAS is the cockpit icon.
	var name: String = str(record.get("HUD Pic","ELECTRIC")).to_upper()
	var image: Image
	for replacement in Mods.candidates("texture." + name):
		image = Assets._replacement_image(replacement.path)
		if image != null: break
	if image == null: image = preload("res://legacy_bmp.gd").load_image(folder.path_join("GAMETEX/" + name + ".RAS"))
	return ImageTexture.create_from_image(image) if image != null else null

func configure(values: Dictionary) -> void:
	for key in DEFAULTS:
		var value: Variant = values.get(key,settings[key])
		if (value is float or value is int) and is_finite(float(value)):
			settings[key] = clampf(float(value),-60,6) if key == "volume_db" else clampf(float(value),0.0,300.0 if key == "chunk_lifetime" else 100.0)
	preload("res://creature_death.gd").settings = {"gore_amount":int(settings.gore_amount),"gore_settle_speed":settings.gore_settle_speed,"gore_lifetime":settings.gore_lifetime,"chunk_lifetime":settings.chunk_lifetime}
	if audio != null: audio.volume_db = settings.volume_db

func cycle(amount: int) -> void:
	if not mounted.is_empty(): selected = posmod(selected + amount,mounted.size())

func current() -> Dictionary:
	return {} if mounted.is_empty() else mounted[selected]

func _held() -> bool:
	preload("res://input_bindings.gd").install()
	return Input.is_action_pressed("weapon_fire")

func _physics_process(delta: float) -> void:
	if pilot == null: return
	update_fire(pilot.active and pilot.controls_enabled and _held(),delta)

func update_fire(held: bool, delta: float) -> void:
	firing = held and not mounted.is_empty() and settings.range > 0
	beam.visible = firing; spark.visible = firing
	if not firing:
		impact.hide(); last_hit = null
		if audio.playing: audio.stop()
		return
	if not audio.playing and audio.stream != null: audio.play()
	if pilot.submarine_audio != null: audio.volume_db = settings.volume_db + float(pilot.submarine_audio.tuning.settings.master_volume)
	beam_start = muzzle.get_node("Emitter").global_position
	var forward := -muzzle.global_basis.z.normalized()
	beam_end = beam_start + forward * settings.range
	var query := PhysicsRayQueryParameters3D.create(beam_start,beam_end,13,[pilot.get_rid()]); query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	last_hit = hit.get("collider")
	impact.visible = not hit.is_empty()
	if not hit.is_empty():
		beam_end = hit.position
		impact.global_position = beam_end - forward * 0.025
		if last_hit.has_method("take_damage"): last_hit.take_damage(settings.damage_per_second * delta,beam_start)
	spark.global_position = beam_start

func _process(delta: float) -> void:
	if beam == null or not firing: return
	elapsed += delta
	if impact.visible and not impact_frames.is_empty():
		impact.texture = impact_frames[int(elapsed * settings.animation_speed) % impact_frames.size()]
		impact.scale = Vector3.ONE * (0.85 + 0.25 * sin(elapsed * 47.0))
	material.albedo_texture = frames[int(elapsed * settings.animation_speed) % frames.size()]
	var direction := beam_end - beam_start
	if direction.length_squared() < 0.00001: beam.hide(); return
	var side := direction.cross(camera.global_position - (beam_start + beam_end) * 0.5).normalized()
	if side.length_squared() < 0.01: side = pilot.global_basis.x
	var up := direction.normalized()
	beam.global_transform = Transform3D(Basis(side,up,side.cross(up).normalized()),(beam_start + beam_end) * 0.5)
	beam.mesh.size = Vector2(settings.beam_width,direction.length())
