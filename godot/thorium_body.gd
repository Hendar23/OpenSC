extends RigidBody3D
signal shattered(body: RigidBody3D)
var stats: Dictionary = {}
var health := 1.0
var dead := false
var shard := 0
var surface_height := 0.0
var enabled := true
var glow_light: OmniLight3D
var glow_energy := 0.0
var glow_emission_colour := Color.BLACK
var glow_materials: Array[Material] = []
var halo: Sprite3D
var halo_material: ShaderMaterial
var surface_emission_strength := 0.0
var glow_age := 0.0
const GLOW_PERIOD := 4.0
func setup(definition: Dictionary, visual: Node3D, fragment: int, water: float, running: bool) -> void:
	stats = definition.duplicate(true); shard = fragment; surface_height = water; enabled = running
	health = float(stats.health); mass = float(stats.get("mass" if shard == 0 else "shard_mass",2.0 if shard == 0 else 1.0))
	collision_layer = 9; collision_mask = 11; freeze = not running; continuous_cd = true
	gravity_scale = 0.0
	linear_damp = 0.3; angular_damp = 0.5
	var material := PhysicsMaterial.new(); material.friction = 0.45; material.bounce = 0.1; physics_material_override = material
	add_child(visual)
	_setup_glow(visual)
	set_meta("weapon_target",shard == 0)
	set_meta("metal_tow_target",bool(stats.get("magnet_compatible",false)))
	var points := PackedVector3Array()
	for entry in preload("res://submarine_equipment.gd")._meshes(visual,Transform3D.IDENTITY):
		for surface in range(entry.mesh.get_surface_count()):
			var arrays: Array = entry.mesh.surface_get_arrays(surface)
			for vertex in arrays[Mesh.ARRAY_VERTEX]: points.append(entry.pose * vertex)
	var shape: Shape3D
	if points.size() >= 4:
		var hull := ConvexPolygonShape3D.new(); hull.points = points; shape = hull
	else:
		var sphere := SphereShape3D.new(); sphere.radius = float(stats.size) * 0.5; shape = sphere
	var collider := CollisionShape3D.new(); collider.shape = shape; add_child(collider)
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not enabled or dead: return
	var submerged := state.transform.origin.y < surface_height
	state.linear_velocity += Vector3.DOWN * (1.2 if submerged else 9.8) * state.step
	if submerged:
		state.linear_velocity *= exp(-0.4 * state.step)
		state.angular_velocity *= exp(-0.6 * state.step)
func take_damage(amount: float, _source: Vector3 = Vector3.ZERO) -> void:
	if dead or shard != 0 or not enabled or amount <= 0.0 or has_meta("delivery_city"): return
	health = maxf(0.0,health - amount)
	if health == 0.0:
		dead = true; shattered.emit(self)

func _setup_glow(visual: Node3D) -> void:
	var defaults := preload("res://object_definitions.gd").THORIUM
	var colour := Color(float(stats.get("glow_red",defaults.glow_red)),float(stats.get("glow_green",defaults.glow_green)),float(stats.get("glow_blue",defaults.glow_blue)))
	glow_energy = float(stats.get("glow_energy",defaults.glow_energy))
	var radius := float(stats.get("glow_range",defaults.glow_range))
	if glow_energy > 0 and radius > 0:
		var light := OmniLight3D.new(); light.name = "ThoriumGlow"
		light.light_color = colour; light.light_energy = glow_energy; light.omni_range = radius
		light.shadow_enabled = false; light.distance_fade_enabled = true; light.distance_fade_begin = 20; light.distance_fade_length = 10
		add_child(light); glow_light = light
	surface_emission_strength = float(stats.get("glow_emission",defaults.glow_emission)) * 4.0
	glow_emission_colour = colour * float(stats.get("glow_emission",defaults.glow_emission))
	preload("res://natural_light.gd").new().attach(visual)
	_apply_emission(visual,glow_emission_colour)
	if glow_energy > 0 or glow_emission_colour.r + glow_emission_colour.g + glow_emission_colour.b > 0:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0,0.35,1.0])
		gradient.colors = PackedColorArray([Color(1,1,1,0.22),Color(1,1,1,0.09),Color(1,1,1,0)])
		var texture := GradientTexture2D.new(); texture.gradient = gradient; texture.width = 128; texture.height = 128
		texture.fill = GradientTexture2D.FILL_RADIAL; texture.fill_from = Vector2(0.5,0.5); texture.fill_to = Vector2(0.5,1)
		var meshes := preload("res://submarine_equipment.gd")._meshes(visual,Transform3D.IDENTITY)
		var diameter := float(stats.size)
		if not meshes.is_empty():
			var box := preload("res://submarine_equipment.gd")._bounds(meshes)
			diameter = maxf(box.size.x,maxf(box.size.y,box.size.z))
			halo = Sprite3D.new(); halo.position = box.get_center()
		else: halo = Sprite3D.new()
		halo.name = "ThoriumHalo"; halo.texture = texture; halo.pixel_size = diameter * 2.2 / 128.0
		halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED; halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		halo_material = preload("res://natural_light.gd").billboard_material(texture)
		halo_material.set_shader_parameter("emission_color",colour)
		halo_material.set_shader_parameter("emission_texture",texture); halo_material.set_shader_parameter("has_emission_texture",true)
		halo.material_override = halo_material; add_child(halo)
	set_process(glow_light != null or glow_emission_colour.r + glow_emission_colour.g + glow_emission_colour.b > 0)

func _apply_emission(node: Node3D, colour: Color) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var source: Material = node.get_active_material(surface)
			if source == null: continue
			var material: Material = source.duplicate()
			if material is ShaderMaterial:
				material.set_shader_parameter("emission_color",colour)
				material.set_shader_parameter("self_illuminated",surface_emission_strength > 0.0)
				material.set_shader_parameter("surface_emission_strength",surface_emission_strength)
			elif material is BaseMaterial3D:
				material.emission_enabled = colour.r + colour.g + colour.b > 0
				material.emission = colour; material.emission_energy_multiplier = 1.0
			if material is ShaderMaterial or material is BaseMaterial3D: glow_materials.append(material)
			node.set_surface_override_material(surface,material)
			if node.material_override != null: node.material_override = material
	for child in node.get_children():
		if child is Node3D: _apply_emission(child,colour)

func _process(delta: float) -> void:
	if dead: return
	glow_age = fmod(glow_age + delta,GLOW_PERIOD)
	# Smoothly breathe between half brightness and the configured peak.
	var brightness := 0.75 + 0.25 * cos(glow_age * TAU / GLOW_PERIOD)
	if halo_material != null: halo_material.set_shader_parameter("opacity",brightness)
	if glow_light != null: glow_light.light_energy = glow_energy * brightness
	for material in glow_materials:
		if material is ShaderMaterial:
			material.set_shader_parameter("emission_color",glow_emission_colour * brightness)
			material.set_shader_parameter("surface_emission_strength",surface_emission_strength * brightness)
		elif material is BaseMaterial3D: material.emission = glow_emission_colour * brightness

func pickup_item() -> String:
	return "ore" if shard > 0 and enabled and not dead and not is_queued_for_deletion() else ""
