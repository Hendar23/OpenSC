extends Node3D
signal activated(equipment_id: String, active: bool)

const Assets = preload("res://clump_loader.gd")
const Images = preload("res://legacy_bmp.gd")
const Mods = preload("res://mod_registry.gd")
const DEFAULTS := {"light_energy": 3.0, "light_range": 18.0, "light_angle": 45.0, "light_down_angle": 45.0, "som_range": 2.0, "som_radius": 0.25, "som_pull_speed": 2.0, "som_pull_strength": 8.0, "som_capture_distance": 0.15, "som_volume_db": -16.0, "magnet_length":0.3, "magnet_speed":0.8, "magnet_water_drag":4.0, "magnet_cargo_weight":25.0, "magnet_pitch_influence":0.25, "magnet_volume_db":-16.0, "grapple_length":1.0, "grapple_speed":1.0, "grapple_water_drag":0.1, "grapple_cargo_weight":4.0, "grapple_pitch_influence":0.25, "grapple_volume_db":-16.0}
var settings := DEFAULTS.duplicate()
var mounted: Array[Dictionary] = []
var available: Array[Dictionary] = []
var selected := 0
var cycle_audio: AudioStreamPlayer
var grapple: Node3D
var magnet: Node3D
var vacuum: Node3D
var counter_digits: Array[Texture2D] = []
var pilot: Node3D
var lamp: SpotLight3D
var bulb_materials: Array[StandardMaterial3D] = []

func setup(player: Node3D, folder: String) -> void:
	pilot = player
	name = "MountedEquipment"
	var mount := Node3D.new()
	mount.name = "DeepSeaLightsMount"
	# Player-local mount stays independent of the legacy model's inverted basis.
	var socket := player.visual.find_child("EquipmentMount_DeepSeaLights", true, false) as Node3D
	if socket != null:
		mount.transform = player.global_transform.affine_inverse() * socket.global_transform
		mount.basis = mount.basis.orthonormalized()
	add_child(mount)
	var housing := Assets.load_clump(folder.path_join("CLUMPS/LIGHT.DFF"))
	var housing_bounds := AABB(Vector3(-0.035,-0.017,-0.028), Vector3(0.07,0.034,0.056))
	if housing != null:
		housing.rotation.y = PI
		housing.scale *= player.VISUAL_SCALE
		mount.add_child(housing)
		_prepare_bulb(housing)
		housing_bounds = _bounds(_meshes(housing, Transform3D.IDENTITY))
	if socket == null: mount.position = _hull_mount(player.visual, housing_bounds)
	preload("res://submarine_mounts.gd").apply(mount,player.visual,"deep_sea_lights")
	lamp = SpotLight3D.new()
	lamp.name = "DeepSeaBeam"
	lamp.position = Vector3(0, housing_bounds.get_center().y, housing_bounds.position.z - 0.008)
	lamp.light_color = Color(1.0, 0.97, 0.9)
	lamp.spot_attenuation = 0.5
	# Dock walls and terrain must occlude the beam, including during launch.
	# Small biases suit the original world's metre-scale geometry.
	lamp.shadow_enabled = true
	lamp.shadow_bias = 0.01
	lamp.shadow_normal_bias = 0.02
	mount.add_child(lamp)
	var icons: Array[Texture2D] = []
	for file in ["DEEPWP1", "DEEPWP2"]:
		var image: Image
		for replacement in Mods.candidates("texture." + file):
			image = Assets._replacement_image(replacement.path)
			if image != null: break
		if image == null: image = Images.load_image(folder.path_join("GAMETEX/" + file + ".RAS"))
		icons.append(ImageTexture.create_from_image(image) if image != null else null)
	mounted.append({"id": "deep_sea_lights", "name": "Deep-Sea Lights", "enabled": false, "mount": mount, "icons": icons})
	_setup_cycle_audio(folder)
	_setup_vacuum(player,folder)
	available.assign(mounted)
	_setup_magnet(player,folder)
	_setup_grapple(player,folder)
	apply_settings()

static func _meshes(node: Node3D, parent_pose: Transform3D, hull_only: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pose := parent_pose * node.transform
	if node is MeshInstance3D and node.mesh != null: result.append({"mesh": node.mesh, "pose": pose})
	for child in node.get_children():
		if hull_only and child.name in ["LeftPod","RightPod","RearPropeller","LeftPropeller","RightPropeller"]: continue
		if child is Node3D: result.append_array(_meshes(child, pose,hull_only))
	return result

static func _bounds(meshes: Array[Dictionary]) -> AABB:
	var box: AABB = meshes[0].pose * meshes[0].mesh.get_aabb()
	for entry in meshes: box = box.merge(entry.pose * entry.mesh.get_aabb())
	return box

static func _hull_mount(visual: Node3D, housing_bounds: AABB) -> Vector3:
	var meshes := _meshes(visual, Transform3D.IDENTITY,true)
	if meshes.is_empty(): return Vector3(0,0.25,-0.22)
	var box := _bounds(meshes)
	var x := box.get_center().x
	# The original canopy ends below the raised roof and rear fin. Find its
	# upper rim from the glass surface, then seat the lamp against the bow.
	var height := box.position.y + box.size.y * 0.64
	if str(visual.get_meta("asset_source", "")).get_extension().to_lower() == "dff":
		for entry in meshes:
			var mesh: Mesh = entry.mesh
			if mesh.get_surface_count() < 3: continue
			var arrays := mesh.surface_get_arrays(2)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var rim := -INF
			for index in indices: rim = maxf(rim, (entry.pose * vertices[index]).y)
			if is_finite(rim): height = rim
	var start := Vector3(x,height,box.position.z - 1.0)
	var end := Vector3(x,height,box.end.z + 1.0)
	var front := INF
	for entry in meshes:
		var faces: PackedVector3Array = entry.mesh.get_faces()
		for index in range(0,faces.size(),3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(start,end,entry.pose * faces[index],entry.pose * faces[index + 1],entry.pose * faces[index + 2])
			if hit is Vector3: front = minf(front,hit.z)
	if not is_finite(front): front = box.position.z
	return Vector3(x,height - housing_bounds.position.y - 0.002,front - housing_bounds.end.z + 0.005)

func _prepare_bulb(housing: Node3D) -> void:
	# LIGHT.DFF's untextured second surface is the recessed bulb dish.
	# Duplicate the mesh so this equipment instance owns its on/off material.
	if str(housing.get_meta("asset_source", "")).get_extension().to_lower() == "dff":
		for node in housing.find_children("*", "MeshInstance3D", true, false):
			if node.mesh.get_surface_count() != 2: continue
			var mesh: ArrayMesh = node.mesh.duplicate()
			var material := StandardMaterial3D.new()
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.surface_set_material(1,material)
			node.mesh = mesh
			bulb_materials.append(material)
	else:
		# Modern replacements can supply a separate Bulb or Lens mesh.
		for node in housing.find_children("*", "MeshInstance3D",true,false):
			if not str(node.name).to_lower() in ["bulb", "lens"]: continue
			var material := StandardMaterial3D.new()
			node.material_override = material
			bulb_materials.append(material)
func cycle(direction: int) -> void:
	if mounted.is_empty(): return
	var previous := selected
	selected = posmod(selected + direction, mounted.size())
	if selected != previous: _play_cycle_sound()

func _play_cycle_sound() -> void:
	if cycle_audio != null and cycle_audio.stream != null:
		var volume := float(pilot.submarine_audio.tuning.settings.master_volume) if pilot != null and pilot.submarine_audio != null else 0.0
		cycle_audio.volume_db = -80.0 if volume <= -60.0 else volume
		cycle_audio.play()

func toggle_selected() -> void:
	if mounted.is_empty(): return
	mounted[selected].enabled = not mounted[selected].enabled
	apply_settings()
	activated.emit(str(mounted[selected].id),bool(mounted[selected].enabled))

func current() -> Dictionary:
	return {} if mounted.is_empty() else mounted[selected]

func apply_settings() -> void:
	for item in available: item.mount.visible = item in mounted
	for tool in [magnet,grapple]:
		if tool == null: continue
		var id: String = tool.tool_id
		tool.chain_length = settings[id + "_length"]; tool.speed = settings[id + "_speed"]; tool.volume_db = settings[id + "_volume_db"]
		tool.water_drag = settings[id + "_water_drag"]; tool.cargo_weight = settings[id + "_cargo_weight"]; tool.pitch_influence = settings[id + "_pitch_influence"]
		tool.set_enabled(mounted.any(func(item: Dictionary) -> bool: return item.id == id and item.enabled))
	if vacuum != null:
		vacuum.enabled = false
		vacuum.range_metres = settings.som_range
		vacuum.intake_radius = settings.som_radius
		vacuum.pull_speed = settings.som_pull_speed
		vacuum.pull_strength = settings.som_pull_strength
		vacuum.capture_distance = settings.som_capture_distance
		vacuum.volume_db = settings.som_volume_db
		for item in mounted:
			if item.id == "suckomat": vacuum.enabled = item.enabled
	if lamp == null: return
	lamp.light_energy = settings.light_energy
	lamp.spot_range = settings.light_range
	lamp.spot_angle = settings.light_angle
	lamp.rotation_degrees.x = -settings.light_down_angle
	lamp.visible = mounted.any(func(item: Dictionary) -> bool: return item.id == "deep_sea_lights" and item.enabled)
	for material in bulb_materials:
		material.albedo_color = Color.WHITE if lamp.visible else Color(0.12,0.15,0.16)
		material.emission_enabled = lamp.visible
		material.emission = Color.WHITE
		material.emission_energy_multiplier = 1.5

func _process(_delta: float) -> void:
	if pilot != null and pilot.visual != null: visible = pilot.visual.visible

func _setup_vacuum(player: Node3D, folder: String) -> void:
	var mount := Node3D.new(); mount.name = "SuckOMaticMount"; add_child(mount)
	var housing := Assets.load_clump(folder.path_join("CLUMPS/PICKUP.DFF"))
	var box := AABB(Vector3(-0.05,-0.1,-0.05),Vector3(0.1,0.1,0.1))
	if housing != null:
		housing.rotation.y = PI; housing.scale *= player.VISUAL_SCALE; mount.add_child(housing)
		var meshes := _meshes(housing,Transform3D.IDENTITY)
		if not meshes.is_empty(): box = _bounds(meshes)
	var hull := _bounds(_meshes(player.visual,Transform3D.IDENTITY,true))
	mount.position = Vector3(hull.get_center().x,hull.position.y - box.end.y + 0.002,hull.get_center().z)
	var socket := player.visual.find_child("EquipmentMount_SuckOMatic",true,false) as Node3D
	if socket != null: mount.transform = player.global_transform.affine_inverse() * socket.global_transform; mount.basis = mount.basis.orthonormalized()
	preload("res://submarine_mounts.gd").apply(mount,player.visual,"suckomat")
	vacuum = preload("res://suck_o_matic.gd").new(); mount.add_child(vacuum)
	vacuum.position = Vector3(box.get_center().x,box.position.y,box.get_center().z); vacuum.setup(player,folder)
	vacuum.item_collected.connect(func(_item: String) -> void:
		for item in mounted:
			if item.id == "suckomat": item.enabled = false
		_play_cycle_sound()
	)
	var icons: Array[Texture2D] = []
	var cache := {}
	for file in ["PICKUP1","PICKUP2","PICKUP3"]: icons.append(Assets._load_texture(folder,file,"",cache))
	mounted.append({"id":"suckomat","name":"Suck-O-Matic","enabled":false,"mount":mount,"icons":icons})
	for index in range(10):
		var image := Images.load_image(folder.path_join("GAMETEX/NUMBER%d.RAS" % index))
		counter_digits.append(ImageTexture.create_from_image(image) if image != null else null)

func _setup_cycle_audio(folder: String) -> void:
	cycle_audio = AudioStreamPlayer.new(); cycle_audio.name = "EquipmentCycleSound"
	for replacement in Mods.candidates("audio.equipment.cycle"):
		cycle_audio.stream = preload("res://legacy_audio.gd").load_file(replacement.path)
		if cycle_audio.stream != null: break
	if cycle_audio.stream == null:
		var path := folder.path_join("WAVES/SUBCYCLE.WAV")
		if not FileAccess.file_exists(path): path = folder.path_join("WAVES/SUBCYCLE.RAW")
		cycle_audio.stream = preload("res://legacy_audio.gd").load_file(path)
	add_child(cycle_audio)

func set_installed(ids: Array) -> void:
	var selected_id: String = current().get("id","")
	for item in available:
		if item.id not in ids: item.enabled = false
	mounted.clear()
	for id in ids:
		for item in available:
			if item.id == id: mounted.append(item); break
	selected = 0
	for index in range(mounted.size()):
		if mounted[index].id == selected_id: selected = index
	apply_settings()

func _setup_magnet(player: Node3D, folder: String) -> void:
	magnet = _setup_towing_tool(player,folder,"magnet","MAGNET","GRAPPLE")

func _setup_grapple(player: Node3D, folder: String) -> void:
	grapple = _setup_towing_tool(player,folder,"grapple","TOW","TOW")

func towing_tool() -> Node3D:
	for item in mounted:
		if item.id == "magnet": return magnet
		if item.id == "grapple": return grapple
	return null

func reset_towing() -> void:
	for tool in [magnet,grapple]:
		if tool != null: tool.reset()

func _setup_towing_tool(player: Node3D, folder: String, id: String, model: String, icon: String) -> Node3D:
	var mount := Node3D.new(); mount.name = "GrappleMount" if id == "grapple" else "MagnetMount"; add_child(mount)
	mount.transform = (magnet.get_parent() if id == "grapple" and magnet != null else available[1].mount).transform
	var housing := Assets.load_clump(folder.path_join("CLUMPS/" + model + ".DFF"))
	if housing != null:
		housing.rotation.y = PI; housing.scale *= player.VISUAL_SCALE; mount.add_child(housing)
	preload("res://submarine_mounts.gd").apply(mount,player.visual,id)
	var icons: Array[Texture2D] = []
	for file in [icon + "1",icon + "2",icon + "3"]:
		var image: Image
		for replacement in Mods.candidates("texture." + file):
			image = Assets._replacement_image(replacement.path)
			if image != null: break
		if image == null: image = Images.load_image(folder.path_join("GAMETEX/" + file + ".RAS"))
		icons.append(ImageTexture.create_from_image(image) if image != null else null)
	available.append({"id":id,"name":"Grappling Hook" if id == "grapple" else "Magnet","enabled":false,"mount":mount,"icons":icons})
	var tool := preload("res://submarine_magnet.gd").new(); tool.tool_id = id; mount.add_child(tool); tool.setup(player,housing,folder)
	tool.state_changed.connect(func(on: bool) -> void:
		for item in available:
			if item.id == id: item.enabled = on
	)
	mount.hide()
	return tool
