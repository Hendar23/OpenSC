extends Node3D
const Definitions = preload("res://object_definitions.gd")
const Document = preload("res://map_document.gd")
const Assets = preload("res://clump_loader.gd")
const Mine = preload("res://floating_mine.gd")
const Thorium = preload("res://thorium_body.gd")
const Clam = preload("res://clam.gd")
const Pearl = preload("res://pearl_body.gd")
const Salvage = preload("res://salvage_body.gd")
const Explosion = preload("res://mine_explosion.gd")
const Identity = preload("res://entity_identity.gd")
const DOCK_SPAWN_MARGIN := 5.0
var player: Node3D:
	set(value):
		player = value
		for mine in get_children():
			if mine is Mine or mine is Clam: mine.player = value
var simulating := true
var placements: Array[Vector3] = []
var asset_folder := ""
var explosion_frames: Array[Texture2D] = []
var thorium_explosion_sound: AudioStream
var thorium_types: Dictionary = {}
var salvage_types: Dictionary = {}
var clam_types: Dictionary = {}
var pearl_types: Dictionary = {}
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
		elif entry.get("behavior","mine") in ["clam","pearl"]:
			(clam_types if entry.behavior == "clam" else pearl_types)[entry.id] = entry.duplicate(true)
			_thorium_template(entry,0)
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
			var pose := Transform3D(Basis.from_euler(Document.vector(group.get("rotation",[0,0,0])) * PI / 180.0),center + offset)
			if definition.get("behavior","mine") == "clam":
				var clam := _create_clam(definition,pose,float(group.get("initial_delay",0)))
				if clam != null:
					clam.set_meta("object_group",group.id)
					Identity.assign_id(clam,Identity.authored(str(group.id),index))
				placements.append(center + offset)
				continue
			if definition.get("behavior","mine") in ["thorium","salvage","pearl"]:
				var body := _create_thorium(definition,0,pose)
				if body != null:
					body.set_meta("object_group",group.id)
					Identity.assign_id(body,Identity.authored(str(group.id),index))
				placements.append(center + offset)
				continue
			var mine := preload("res://floating_mine.gd").new(); mine.name = "Mine_%s_%d" % [group.id,index]
			mine.setup(definition,template.duplicate(),sound,enabled); add_child(mine)
			Identity.assign_id(mine,Identity.authored(str(group.id),index))
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
	var body: RigidBody3D = Pearl.new() if definition.get("behavior","") == "pearl" else Salvage.new() if definition.get("behavior","") == "salvage" else Thorium.new()
	body.setup(definition,template.duplicate(),fragment,surface_height,simulating)
	Identity.assign_id(body)
	add_child(body); body.transform = pose
	if body is Thorium: body.shattered.connect(_shatter.call_deferred)
	return body

func _create_clam(definition: Dictionary, pose: Transform3D, delay: float) -> StaticBody3D:
	var template := _thorium_template(definition,0)
	if template == null: return null
	var body := Clam.new(); body.name = "Clam"; add_child(body); body.transform = pose
	Identity.assign_id(body)
	body.population = self; body.player = player
	body.setup(definition,template.duplicate(),simulating,delay)
	if delay <= 0: body._grow_pearl()
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
			# Each shard is a new entity; retain its origin for future objectives.
			piece.set_meta("source_entity_id",Identity.of(body))
			piece.position += direction * float(piece.get_child(0).get_meta("diameter",0.5)) * 0.7
			piece.linear_velocity = velocity + direction * 0.7
			piece.angular_velocity = spin + Vector3(index,1,-index) * 0.5

func snapshot() -> Array:
	var result: Array = []
	for body in get_children():
		if body is Clam and not body.is_queued_for_deletion():
			result.append({"entity_id":Identity.of(body),"stats":body.stats.duplicate(true),"pose":Document.encode(body.transform),"clam_state":body.state()})
			if body.has_meta("object_group"): result.back()["object_group"] = body.get_meta("object_group")
			continue
		if body is Pearl and is_instance_valid(body.clam): continue
		if (body is Thorium or body is Salvage) and not body.dead and not body.is_queued_for_deletion():
			result.append({"entity_id":Identity.of(body),"stats":body.stats.duplicate(true),"shard":body.shard,"pose":Document.encode(body.transform),"velocity":Document.array(body.linear_velocity),"spin":Document.array(body.angular_velocity),"health":body.health})
			if body.has_meta("delivery_city"): result.back()["delivery_city"] = body.get_meta("delivery_city")
			for key in ["object_group","source_entity_id"]:
				if body.has_meta(key): result.back()[key] = body.get_meta(key)
	return result
func collect_delivered_objects(city_id: int) -> void:
	for body in get_children():
		if body.has_meta("delivery_city") and int(body.get_meta("delivery_city")) == city_id: body.queue_free()

static func valid_snapshot(value: Variant) -> bool:
	if not value is Array or value.size() > 15000: return false
	var identities := {}
	for entry in value:
		if not entry is Dictionary or not entry.get("stats") is Dictionary: return false
		# Identity fields are optional for older saves; reject ambiguous targets.
		if entry.has("entity_id"):
			if not Identity.valid(entry.entity_id) or identities.has(entry.entity_id): return false
			identities[entry.entity_id] = true
		if entry.has("source_entity_id") and not Identity.valid(entry.source_entity_id): return false
		if entry.has("delivery_city") and (not Definitions.numeric(entry.delivery_city,0,1000000000000) or float(entry.delivery_city) != floorf(float(entry.delivery_city))): return false
		if not Definitions.valid({"object_types":[entry.stats],"object_groups":[]}): return false
		if entry.stats.get("behavior","") == "clam":
			if not Document.finite_array(entry.get("pose"),12) or not entry.get("clam_state") is Dictionary: return false
			var state: Dictionary = entry.clam_state
			if state.has("pearl_id"):
				if not Identity.valid(state.pearl_id) or identities.has(state.pearl_id): return false
				identities[state.pearl_id] = true
			if not Definitions.numeric(state.get("angle"),0,180) or not Definitions.numeric(state.get("remaining"),0,86400): return false
			if not state.get("pearl_offset") is Array or (not state.pearl_offset.is_empty() and not Document.finite_array(state.pearl_offset,3)): return false
			if state.has("pearl_id") and state.pearl_offset.is_empty(): return false
			continue
		if entry.stats.get("behavior","") not in ["thorium","salvage","pearl"] or not Definitions.numeric(entry.get("shard"),0,3): return false
		if float(entry.shard) != floorf(float(entry.shard)) or (entry.stats.get("behavior") != "thorium" and entry.shard != 0): return false
		if not Document.finite_array(entry.get("pose"),12) or not Document.finite_array(entry.get("velocity"),3) or not Document.finite_array(entry.get("spin"),3): return false
		if not Definitions.numeric(entry.get("health"),0,100000): return false
	return true

func restore_snapshot(entries: Array) -> void:
	if not valid_snapshot(entries): return
	# Saves from before interactive clams were added have no clam records.
	# Seed the new authored clams and loose pearls once on that migration.
	var restored := entries.duplicate(true)
	if initial_thorium.any(func(entry: Dictionary) -> bool: return entry.stats.get("behavior","") == "clam") and not entries.any(func(entry: Dictionary) -> bool: return entry.stats.get("behavior","") == "clam"):
		for entry in initial_thorium:
			if entry.stats.get("behavior","") in ["clam","pearl"]: restored.append(entry.duplicate(true))
	for body in get_children():
		if body is Clam: body.free()
	for body in get_children():
		if body is Thorium or body is Salvage: body.free()
	var identities := {}
	for entry in restored:
		if entry.has("entity_id"): identities[entry.entity_id] = true
		if entry.get("clam_state",{}).has("pearl_id"): identities[entry.clam_state.pearl_id] = true
	for index in range(restored.size()):
		var entry: Dictionary = restored[index]
		# Assign once on old-save migration, then preserve the saved identity.
		var identity: String = entry.get("entity_id","legacy/%d" % index)
		if not entry.has("entity_id"):
			while identities.has(identity): identity += "/migrated"
			identities[identity] = true
		if entry.stats.get("behavior","") == "clam":
			var clam := _create_clam(clam_types.get(str(entry.stats.id),entry.stats),Document.decode(entry.pose),1)
			if clam != null:
				Identity.assign_id(clam,identity)
				if entry.has("object_group"): clam.set_meta("object_group",entry.object_group)
				clam.restore_state(entry.clam_state)
			continue
		var definition: Dictionary = pearl_types.get(str(entry.stats.id),salvage_types.get(str(entry.stats.id),thorium_types.get(str(entry.stats.id),entry.stats)))
		var body := _create_thorium(definition,int(entry.shard),Document.decode(entry.pose))
		if body != null:
			Identity.assign_id(body,identity)
			for key in ["object_group","source_entity_id"]:
				if entry.has(key): body.set_meta(key,entry[key])
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

func populate_startup() -> void:
	if not simulating: return
	# Original world creation makes twelve attempts per salvage type. These are
	# independent of the ongoing replenishment budget and per-minute chance.
	for definition in thorium_types.values() + salvage_types.values():
		for attempt in range(12):
			var point := _random_spawn_point(definition,true)
			if point.is_empty(): continue
			_spawn_at(definition,point.position)

func _spawn_at(definition: Dictionary, point: Vector3) -> void:
	_create_thorium(definition,0,Transform3D(Basis.from_euler(Vector3(random.randf(),random.randf(),random.randf()) * TAU),point))

func _random_drop(definition: Dictionary) -> void:
	# Each type has its own population limit; crystals reserve their future shards.
	var population := 0
	var cost := 3 if definition.get("behavior","") == "thorium" else 1
	for body in get_children():
		if (body is Thorium or body is Salvage) and not body.dead and not body.is_queued_for_deletion() and str(body.stats.id) == str(definition.id):
			population += 3 if body is Thorium and body.shard == 0 else 1
	if population + cost > int(definition.get("maximum_population",60)): return
	if not is_instance_valid(view_camera): view_camera = get_viewport().get_camera_3d()
	for attempt in range(40):
		var point := _random_spawn_point(definition,false)
		if point.is_empty(): continue
		if is_instance_valid(view_camera) and (view_camera.is_position_in_frustum(point.position) or view_camera.is_position_in_frustum(point.floor)): continue
		_spawn_at(definition,point.position)
		return

func _random_spawn_point(definition: Dictionary, startup: bool) -> Dictionary:
	if world_bounds.size.x <= 0 or world_bounds.size.z <= 0: return {}
	var radius := float(definition.size) * 0.5
	var above := Vector3(random.randf_range(world_bounds.position.x,world_bounds.end.x),surface_height + 5.0,random.randf_range(world_bounds.position.z,world_bounds.end.z))
	if not _clear_of_docks(above,radius): return {}
	var space := get_world_3d().direct_space_state
	var floor_query := PhysicsRayQueryParameters3D.create(above,Vector3(above.x,world_bounds.position.y - 5.0,above.z),1)
	var floor_hit := space.intersect_ray(floor_query)
	if floor_hit.is_empty() or floor_hit.normal.y < 0.25 or floor_hit.position.y + radius >= surface_height: return {}
	var point := above
	if startup:
		# Crystals rest on terrain. Other salvage starts on terrain one quarter
		# of the time, otherwise 5–8.75 original units higher, capped at water.
		var lift := 0.0
		if definition.get("behavior","") == "salvage" and (random.randi() & 3) != 0:
			lift = 5.0 + float(random.randi() & 15) * 0.25
		point.y = minf(surface_height - radius,floor_hit.position.y + radius + 0.03 + lift)
	var sphere := SphereShape3D.new(); sphere.radius = maxf(0.01,radius * 0.9)
	var clearance := PhysicsShapeQueryParameters3D.new(); clearance.shape = sphere; clearance.transform.origin = point; clearance.collision_mask = 9
	if not space.intersect_shape(clearance,1).is_empty(): return {}
	return {"position":point,"floor":floor_hit.position}

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
			var distance: float = body.global_position.distance_to(player.global_position)
			if radius > 0 and distance < radius:
				strength += preload("res://original_damage.gd").radiation(float(body.stats.get("radiation_strength",Definitions.THORIUM.radiation_strength)),distance)
	player.receive_radiation(strength,delta)
