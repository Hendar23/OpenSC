extends Node3D

const Assets = preload("res://clump_loader.gd")
const Images = preload("res://legacy_bmp.gd")
const Mods = preload("res://mod_registry.gd")
const DEFAULTS := {"light_energy": 3.0, "light_range": 18.0, "light_angle": 45.0, "light_down_angle": 45.0}
var settings := DEFAULTS.duplicate()
var mounted: Array[Dictionary] = []
var selected := 0
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
	lamp = SpotLight3D.new()
	lamp.name = "DeepSeaBeam"
	lamp.position = Vector3(0, housing_bounds.get_center().y, housing_bounds.position.z - 0.008)
	lamp.light_color = Color(1.0, 0.97, 0.9)
	lamp.spot_attenuation = 0.5
	# Simple floodlight illumination stays clean even immediately above
	# the coarse original seabed, without shadow-map self-shadow stripes.
	lamp.shadow_enabled = false
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
	if not mounted.is_empty(): selected = posmod(selected + direction, mounted.size())

func toggle_selected() -> void:
	if mounted.is_empty(): return
	mounted[selected].enabled = not mounted[selected].enabled
	apply_settings()

func current() -> Dictionary:
	return {} if mounted.is_empty() else mounted[selected]

func apply_settings() -> void:
	if lamp == null: return
	lamp.light_energy = settings.light_energy
	lamp.spot_range = settings.light_range
	lamp.spot_angle = settings.light_angle
	lamp.rotation_degrees.x = -settings.light_down_angle
	lamp.visible = not mounted.is_empty() and mounted[0].enabled
	for material in bulb_materials:
		material.albedo_color = Color.WHITE if lamp.visible else Color(0.12,0.15,0.16)
		material.emission_enabled = lamp.visible
		material.emission = Color.WHITE
		material.emission_energy_multiplier = 1.5

func _process(_delta: float) -> void:
	if pilot != null and pilot.visual != null: visible = pilot.visual.visible
