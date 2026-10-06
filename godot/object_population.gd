extends Node3D
const Definitions = preload("res://object_definitions.gd")
const Document = preload("res://map_document.gd")
const Assets = preload("res://clump_loader.gd")
var player: Node3D:
	set(value):
		player = value
		for mine in get_children():
			if mine.has_method("take_damage"): mine.player = value
var simulating := true
var placements: Array[Vector3] = []
func setup(folder: String, document: Dictionary, enabled: bool = true) -> void:
	simulating = enabled
	var types := {}
	for entry in document.get("object_types",[Definitions.FLOATING_MINE]): types[entry.id] = entry
	var cache := {}
	var explosion_frames: Array[Texture2D] = []
	if not document.get("object_groups",[]).is_empty():
		explosion_frames = preload("res://mine_explosion.gd").load_frames(folder,cache)
	var sound := preload("res://submarine_weapons.gd")._sound(folder,"audio.object.mine.explosion","EXPLODE1")
	for group in document.get("object_groups",[]):
		if not types.has(group.type): continue
		var random := RandomNumberGenerator.new(); random.seed = int(document.get("seed",8675309)) ^ int(str(group.id).hash())
		var definition: Dictionary = types[group.type]
		var template := appearance(definition,folder,cache)
		if template == null: continue
		definition = definition.duplicate(true)
		if template.has_meta("trigger_distance"): definition.trigger_distance = float(template.get_meta("trigger_distance"))
		var center := Vector3(group.position[0],group.position[1],group.position[2])
		for index in range(int(group.count)):
			# Uniform volume scatter, stable across editor previews and game loads.
			var offset := Vector3.ZERO
			if int(group.count) > 1 and float(group.radius) > 0.0:
				var vertical := random.randf_range(-1,1); var angle := random.randf() * TAU
				var horizontal := sqrt(1.0 - vertical * vertical)
				offset = Vector3(cos(angle) * horizontal,vertical,sin(angle) * horizontal) * pow(random.randf(),1.0 / 3.0) * float(group.radius)
			var mine := preload("res://floating_mine.gd").new(); mine.name = "Mine_%s_%d" % [group.id,index]
			mine.setup(definition,template.duplicate(),sound,enabled); add_child(mine)
			mine.home = center + offset; mine.position = mine.home; mine.phase = random.randf() * TAU; mine.player = player; mine.explosion_frames.assign(explosion_frames)
			mine.set_meta("object_group",group.id); mine.exploded.connect(_exploded.bind(float(definition.get("blast_force",300.0)))); placements.append(mine.home)
		template.free()
static func appearance(definition: Dictionary, folder: String, cache: Dictionary = {}) -> Node3D:
	# A model.mine mod replaces the default billboard without needing a map edit.
	var model_id := str(definition.model).to_lower().trim_prefix("model.")
	if definition.appearance == "model" or not preload("res://mod_registry.gd").candidates("model." + model_id).is_empty():
		var model := Document.load_model(str(definition.model),folder)
		if model == null: return null
		var boxes: Array[AABB] = []; preload("res://creature_loader.gd")._collect_bounds(model,model.transform,boxes)
		if boxes.is_empty(): model.free(); return null
		var bounds := boxes[0]
		for box in boxes: bounds = bounds.merge(box)
		var scale_factor := float(definition.size) / maxf(0.001,maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z)))
		var pivot := Node3D.new(); pivot.add_child(model); model.scale *= scale_factor; model.position -= bounds.get_center() * scale_factor
		for candidate in preload("res://mod_registry.gd").candidates("model." + model_id):
			if candidate.path == model.get_meta("asset_source","") and candidate.get("trigger_distance","") == "model_radius":
				pivot.set_meta("trigger_distance",float(definition.size) * 0.5)
				break
		return pivot
	var texture := Assets._load_texture(folder,str(definition.texture).trim_prefix("texture."),str(definition.mask).trim_prefix("texture."),cache)
	if texture == null: return null
	var sprite := Sprite3D.new(); sprite.texture = texture; sprite.pixel_size = float(definition.size) / maxf(texture.get_width(),texture.get_height())
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.material_override = preload("res://natural_light.gd").billboard_material(texture)
	return sprite
func _exploded(point: Vector3, damage: float, radius: float, force: float = 300.0) -> void:
	if not simulating or radius <= 0.0: return
	if is_instance_valid(player) and player.has_method("receive_explosion"):
		var distance := point.distance_to(player.global_position)
		if distance < radius:
			var falloff := 1.0 - distance / radius
			player.receive_explosion(point,damage,force * falloff)
	if damage <= 0.0: return
	var sphere := SphereShape3D.new(); sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = sphere; query.transform.origin = point; query.collision_mask = 10
	var struck := {}
	for hit in get_world_3d().direct_space_state.intersect_shape(query,256):
		var body: Node3D = hit.collider
		if struck.has(body.get_instance_id()) or not body.has_method("take_damage"): continue
		struck[body.get_instance_id()] = true
		# Defer to avoid recursive minefield detonations. Player damage can use this
		# same hook when submarine health is implemented.
		body.call_deferred("take_damage",damage,point)
