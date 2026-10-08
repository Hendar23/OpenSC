extends Node3D
const Definitions = preload("res://object_definitions.gd")
const Document = preload("res://map_document.gd")
const Assets = preload("res://clump_loader.gd")
const Mine = preload("res://floating_mine.gd")
const Thorium = preload("res://thorium_body.gd")
const Salvage = preload("res://salvage_body.gd")
const Explosion = preload("res://mine_explosion.gd")
const DOCK_SPAWN_MARGIN := 5.0
var player: Node3D:
	set(value):
		player = value
		for mine in get_children():
			if mine is Mine: mine.player = value
var simulating := true
var placements: Array[Vector3] = []
var asset_folder := ""
var explosion_frames: Array[Texture2D] = []
var thorium_explosion_sound: AudioStream
var thorium_types: Dictionary = {}
var salvage_types: Dictionary = {}
var thorium_templates: Dictionary = {}
var initial_thorium: Array = []
var spawn_elapsed := 0.0
var world_bounds := AABB()
var surface_height := 0.0
var view_camera: Camera3D
var random := RandomNumberGenerator.new()
var dock_spawn_exclusions: Array[Dictionary] = []

func setup(folder: String, document: Dictionary, enabled: bool = true) -> void:
	simulating = enabled
	asset_folder = folder
	random.randomize()
	if get_parent().has_meta("bounds"): world_bounds = get_parent().get_meta("bounds")
	surface_height = float(get_parent().get_meta("surface_height",0.0))
	dock_spawn_exclusions.clear()
	for dock in get_parent().find_children("*","Node3D",true,false):
		if not dock.has_meta("city_id"): continue
		var meshes := preload("res://submarine_equipment.gd")._meshes(dock,dock.get_parent().global_transform)
		if meshes.is_empty(): continue
		var bounds := preload("res://submarine_equipment.gd")._bounds(meshes)
		dock_spawn_exclusions.append({"center":Vector2(bounds.get_center().x,bounds.get_center().z),"radius":Vector2(bounds.size.x,bounds.size.z).length() * 0.5 + DOCK_SPAWN_MARGIN})
	var types := {}
	for entry in document.get("object_types",[Definitions.FLOATING_MINE]): types[entry.id] = entry
	for entry in types.values():
		if entry.get("behavior","mine") == "thorium":
			thorium_types[entry.id] = entry.duplicate(true)
			for fragment in range(4): _thorium_template(entry,fragment)
		elif entry.get("behavior","mine") == "salvage":
			salvage_types[entry.id] = entry.duplicate(true)
			_thorium_template(entry,0)
	var cache := {}
	if not document.get("object_groups",[]).is_empty() or not thorium_types.is_empty():
		explosion_frames = preload("res://mine_explosion.gd").load_frames(folder,cache)
	var sound := preload("res://submarine_weapons.gd")._sound(folder,"audio.object.mine.explosion","EXPLODE1")
	if not thorium_types.is_empty(): thorium_explosion_sound = preload("res://submarine_weapons.gd")._sound(folder,"audio.object.thorium.explosion","EXPLODE1")
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
			if definition.get("behavior","mine") in ["thorium","salvage"]:
				var body := _create_thorium(definition,0,Transform3D(Basis.IDENTITY,center + offset))
				if body != null: body.set_meta("object_group",group.id)
				placements.append(center + offset)
				continue
			var mine := preload("res://floating_mine.gd").new(); mine.name = "Mine_%s_%d" % [group.id,index]
			mine.setup(definition,template.duplicate(),sound,enabled); add_child(mine)
			mine.home = center + offset; mine.position = mine.home; mine.phase = random.randf() * TAU; mine.player = player; mine.explosion_frames.assign(explosion_frames)
			mine.set_meta("object_group",group.id); mine.exploded.connect(_exploded.bind(float(definition.get("blast_force",300.0)))); placements.append(mine.home)
		template.free()
	initial_thorium = snapshot()
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
		if definition.has("model_scale_percent"): scale_factor = float(definition.model_scale_percent) / 100.0
		var pivot := Node3D.new(); pivot.set_meta("diameter",maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z)) * scale_factor); pivot.add_child(model); model.scale *= scale_factor; model.position -= bounds.get_center() * scale_factor
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

func reset_population() -> void:
	restore_snapshot(initial_thorium)
	spawn_elapsed = 0.0
	for mine in get_children():
		if mine is Explosion:
			mine.free()
		elif mine is Mine:
			mine.dead = false; mine.health = float(mine.stats.health)
			mine.age = 0.0; mine.position = mine.home
			mine.collision_layer = 8; mine.visible = true

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
		if body == player: continue # Already hit once through receive_explosion.
		if struck.has(body.get_instance_id()) or not body.has_method("take_damage"): continue
		struck[body.get_instance_id()] = true
		# Defer to avoid recursive minefield detonations.
		body.call_deferred("take_damage",damage,point)

func _thorium_template(definition: Dictionary, fragment: int) -> Node3D:
	var key := JSON.stringify(definition).sha256_text() + ":" + str(fragment)
	if not thorium_templates.has(key):
		var appearance_stats := definition.duplicate(true)
		if fragment > 0:
			appearance_stats.appearance = "model"
			appearance_stats.model = definition.get("shard" + str(fragment),"SHARD" + str(fragment))
			appearance_stats.model_scale_percent = definition.get("shard_scale_percent",100.0)
		var template := appearance(appearance_stats,asset_folder)
		if template == null: return null
		preload("res://natural_light.gd").new().attach(template)
		thorium_templates[key] = template
	return thorium_templates[key]

func _create_thorium(definition: Dictionary, fragment: int, pose: Transform3D) -> RigidBody3D:
	var template := _thorium_template(definition,fragment)
	if template == null: return null
	var body: RigidBody3D = Salvage.new() if definition.get("behavior","") == "salvage" else Thorium.new()
	body.setup(definition,template.duplicate(),fragment,surface_height,simulating)
	add_child(body); body.transform = pose
	if body is Thorium: body.shattered.connect(_shatter.call_deferred)
	return body

func _shatter(body: RigidBody3D) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion(): return
	var pose := body.transform
	var definition: Dictionary = body.stats
	var velocity := body.linear_velocity
	var spin := body.angular_velocity
	if simulating:
		var burst := Explosion.new(); add_child(burst); burst.global_position = body.global_position
		burst.setup(explosion_frames,float(definition.size) * 3.0,thorium_explosion_sound)
	body.collision_layer = 0; body.hide(); body.queue_free()
	for index in range(1,4):
		var direction := Vector3(cos(index * TAU / 3.0),0.3,sin(index * TAU / 3.0))
		var piece := _create_thorium(definition,index,pose)
		if piece != null:
			piece.position += direction * float(piece.get_child(0).get_meta("diameter",0.5)) * 0.7
			piece.linear_velocity = velocity + direction * 0.7
			piece.angular_velocity = spin + Vector3(index,1,-index) * 0.5

func snapshot() -> Array:
	var result: Array = []
	for body in get_children():
		if (body is Thorium or body is Salvage) and not body.dead and not body.is_queued_for_deletion():
			result.append({"stats":body.stats.duplicate(true),"shard":body.shard,"pose":Document.encode(body.transform),"velocity":Document.array(body.linear_velocity),"spin":Document.array(body.angular_velocity),"health":body.health})
			if body.has_meta("delivery_city"): result.back()["delivery_city"] = body.get_meta("delivery_city")
	return result
func collect_delivered_objects(city_id: int) -> void:
	for body in get_children():
		if body.has_meta("delivery_city") and int(body.get_meta("delivery_city")) == city_id: body.queue_free()

static func valid_snapshot(value: Variant) -> bool:
	if not value is Array or value.size() > 15000: return false
	for entry in value:
		if not entry is Dictionary or not entry.get("stats") is Dictionary: return false
		if entry.has("delivery_city") and (not Definitions.numeric(entry.delivery_city,0,1000000000000) or float(entry.delivery_city) != floorf(float(entry.delivery_city))): return false
		if not Definitions.valid({"object_types":[entry.stats],"object_groups":[]}): return false
		if entry.stats.get("behavior","") not in ["thorium","salvage"] or not Definitions.numeric(entry.get("shard"),0,3): return false
		if float(entry.shard) != floorf(float(entry.shard)) or (entry.stats.get("behavior") == "salvage" and entry.shard != 0): return false
		if not Document.finite_array(entry.get("pose"),12) or not Document.finite_array(entry.get("velocity"),3) or not Document.finite_array(entry.get("spin"),3): return false
		if not Definitions.numeric(entry.get("health"),0,100000): return false
	return true

func restore_snapshot(entries: Array) -> void:
	if not valid_snapshot(entries): return
	for body in get_children():
		if body is Thorium or body is Salvage: body.free()
	for entry in entries:
		var definition: Dictionary = salvage_types.get(str(entry.stats.id),thorium_types.get(str(entry.stats.id),entry.stats))
		var body := _create_thorium(definition,int(entry.shard),Document.decode(entry.pose))
		if body != null:
			if entry.has("delivery_city"):
				body.set_meta("delivery_city",int(entry.delivery_city)); body.set_meta("metal_tow_target",false)
			body.health = minf(float(entry.health),float(definition.health))
			body.linear_velocity = Document.vector(entry.velocity); body.angular_velocity = Document.vector(entry.spin)

func _physics_process(delta: float) -> void:
	_update_radiation(delta)
	if not simulating or not is_instance_valid(player) or not bool(player.get("active")) or not bool(player.get("controls_enabled")): return
	spawn_elapsed += delta
	if spawn_elapsed < 60.0: return
	spawn_elapsed -= 60.0
	for definition in thorium_types.values() + salvage_types.values():
		if random.randf() * 100.0 < float(definition.get("spawn_chance",0.0)): _random_drop(definition)

func _random_drop(definition: Dictionary) -> void:
	# Each type has its own population limit; crystals reserve their future shards.
	var population := 0
	var cost := 3 if definition.get("behavior","") == "thorium" else 1
	for body in get_children():
		if (body is Thorium or body is Salvage) and not body.dead and str(body.stats.id) == str(definition.id):
			population += 3 if body is Thorium and body.shard == 0 else 1
	if population + cost > int(definition.get("maximum_population",60)): return
	if not is_instance_valid(view_camera): view_camera = get_viewport().get_camera_3d()
	var space := get_world_3d().direct_space_state
	for attempt in range(40):
		var angle := random.randf() * TAU
		var distance := random.randf_range(12.0,35.0)
		var target := player.global_position + Vector3(cos(angle),0,sin(angle)) * distance
		if target.x < world_bounds.position.x or target.x > world_bounds.end.x or target.z < world_bounds.position.z or target.z > world_bounds.end.z: continue
		if not _clear_of_docks(target,float(definition.size) * 0.5): continue
		var above := Vector3(target.x,surface_height + 5.0,target.z)
		if is_instance_valid(view_camera) and (view_camera.is_position_in_frustum(target) or view_camera.is_position_in_frustum(above)): continue
		# Clear water between the player and drop avoids walls and isolated pockets.
		var approach := PhysicsRayQueryParameters3D.create(player.global_position,target,1)
		if not space.intersect_ray(approach).is_empty(): continue
		var floor_query := PhysicsRayQueryParameters3D.create(above,Vector3(target.x,world_bounds.position.y - 5.0,target.z),1)
		var floor_hit := space.intersect_ray(floor_query)
		if floor_hit.is_empty() or floor_hit.position.y >= target.y - float(definition.size): continue
		_create_thorium(definition,0,Transform3D(Basis.from_euler(Vector3(random.randf(),random.randf(),random.randf()) * TAU),above))
		return

func _clear_of_docks(position: Vector3, item_radius: float) -> bool:
	var horizontal := Vector2(position.x,position.z)
	for dock in dock_spawn_exclusions:
		var radius := float(dock.radius) + item_radius
		if horizontal.distance_squared_to(dock.center) <= radius * radius: return false
	return true

func _exit_tree() -> void:
	for template in thorium_templates.values(): template.free()

func _update_radiation(delta: float) -> void:
	if not is_instance_valid(player) or not player.has_method("receive_radiation"): return
	var strength := 0.0
	if simulating and bool(player.get("active")) and bool(player.get("controls_enabled")):
		for body in get_children():
			if not body is Thorium or body.shard != 0 or body.dead or body.is_queued_for_deletion(): continue
			var radius := float(body.stats.get("radiation_range",Definitions.THORIUM.radiation_range))
			if radius > 0 and body.global_position.distance_squared_to(player.global_position) < radius * radius:
				strength += float(body.stats.get("radiation_strength",Definitions.THORIUM.radiation_strength))
	player.receive_radiation(strength,delta)
