extends SceneTree
const Population = preload("res://object_population.gd")
const Definitions = preload("res://object_definitions.gd")
const Document = preload("res://map_document.gd")
const Explosion = preload("res://mine_explosion.gd")
const Thorium = preload("res://thorium_body.gd")
class Player extends Node3D:
	var active := true
	var controls_enabled := true
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	preload("res://mod_registry.gd").initialize(false)
	var data := Document.empty()
	data.object_groups = [{"id":"crystals","name":"Crystals","type":"thorium","position":[0,2,0],"count":1,"radius":0}]
	var legacy := Document.empty(); legacy.object_types = [Definitions.FLOATING_MINE.duplicate(true)]; Definitions.ensure(legacy)
	check(legacy.object_types.any(func(type: Dictionary) -> bool: return type.id == "inert_thorium") and Document.valid(legacy) and legacy.object_groups.is_empty(),"Old maps gain inert Thorium without adding placements")
	var authored := Document.load_path("res://../Maps/scen1.json")
	var starting: Array = authored.object_groups.filter(func(group: Dictionary) -> bool: return group.id == "original_thorium_53")
	check(starting.size() == 1 and starting[0].count == 1 and starting[0].type == "thorium", "One normal starting Thorium is authored")
	var original_pose := Document.decode(authored.entities["Scenery/THORIUM_53"].transform)
	check(Document.vector(starting[0].position).is_equal_approx(original_pose.origin) and Basis.from_euler(Document.vector(starting[0].rotation) * PI / 180.0).is_equal_approx(original_pose.basis.orthonormalized()),"Starting Thorium preserves original position and orientation")
	var normal: Dictionary = authored.object_types.filter(func(type: Dictionary) -> bool: return type.id == "thorium")[0]
	var inert_stats: Dictionary = authored.object_types.filter(func(type: Dictionary) -> bool: return type.id == "inert_thorium")[0]
	check(is_equal_approx(inert_stats.radiation_strength,normal.radiation_strength * 0.1) and inert_stats.mass == normal.mass and inert_stats.health == normal.health and inert_stats.model == normal.model,"Inert Thorium retains current tuning with one-tenth radiation")
	check(inert_stats.grapple_compatible and not inert_stats.magnet_compatible and inert_stats.delivery_quantity == 4 and inert_stats.delivery_commodity == "ore","Inert Thorium uses grapple and yields four Thorium")
	check(Document.valid(data),"Thorium stats and manually placed group validate")
	var bad := data.duplicate(true); bad.object_types[1].spawn_chance = 101
	check(not Document.valid(bad),"Invalid spawn probability rejected")
	var world := Node3D.new(); root.add_child(world)
	world.set_meta("bounds",AABB(Vector3(-50,-10,-50),Vector3(100,20,100))); world.set_meta("surface_height",0.0)
	var ground := StaticBody3D.new(); ground.position.y = -6
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(100,1,100); shape.shape = box; ground.add_child(shape); world.add_child(ground)
	var pilot := Player.new(); world.add_child(pilot); pilot.position = Vector3(0,-2,0)
	var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(0,-1,3); camera.look_at(Vector3(0,-2,-10)); camera.current = true
	var pop := Population.new(); world.add_child(pop)
	pop.setup(ProjectSettings.globalize_path("res://../Original Sub Culture"),data); pop.player = pilot; pop.view_camera = camera
	check(pop.get_child_count() == 1,"Authored crystal uses original model")
	if pop.get_child_count() == 0: quit(1); return
	var crystal = pop.get_child(0)
	check(crystal is RigidBody3D and crystal.mass == 2 and crystal.collision_layer == 9,"Crystal uses original mass and collides with submarine and terrain")
	for tick in range(100): await physics_frame
	check(crystal.position.y < 0 and crystal.position.y > -6,"Crystal drops through the surface into water")
	crystal.apply_central_impulse(Vector3(3,0,0))
	var start: Vector3 = crystal.position
	for tick in range(20): await physics_frame
	check(crystal.position.x > start.x,"Crystal can be pushed by an impulse")
	var saved := pop.snapshot(); var json: Array = JSON.parse_string(JSON.stringify(saved))
	check(Population.valid_snapshot(json),"Persistent objects validate after JSON numeric conversion")
	pop.restore_snapshot(json)
	check(Document.decode(pop.snapshot()[0].pose).is_equal_approx(Document.decode(json[0].pose)) and Document.vector(pop.snapshot()[0].velocity).is_equal_approx(Document.vector(json[0].velocity)),"Intact pose and motion survive save JSON round trip")
	crystal = pop.get_child(0); crystal.take_damage(1)
	await process_frame; await process_frame
	var fragments := pop.get_children().filter(func(body: Node) -> bool: return body is Thorium and not body.dead)
	var bursts := pop.get_children().filter(func(node: Node) -> bool: return node is Explosion)
	check(bursts.size() == 1 and bursts[0].frames.size() == 12,"Thorium shattering plays the original explosion animation")
	var audio: Array = bursts[0].get_children().filter(func(node: Node) -> bool: return node is AudioStreamPlayer3D)
	check(audio.size() == 1 and audio[0].stream != null and audio[0].playing,"Thorium shattering plays the original explosion sound")
	check(fragments.size() == 3,"Weapon damage produces exactly three physical shards")
	check(fragments.map(func(body: Node) -> int: return body.shard) == [1,2,3],"Each original shard model is used once")
	var shard_save := pop.snapshot(); json = JSON.parse_string(JSON.stringify(shard_save)); pop.restore_snapshot(json)
	check(pop.snapshot().size() == 3 and Document.decode(pop.snapshot()[1].pose).is_equal_approx(Document.decode(json[1].pose)),"Shards retain individual saved positions")
	var corrupt := json.duplicate(true); corrupt[0].pose = [0]
	check(not Population.valid_snapshot(corrupt),"Malformed persistent object state rejected")
	pop.reset_population()
	check(pop.get_child_count() == 1 and pop.get_child(0).shard == 0 and pop.get_child(0).position == Vector3(0,2,0),"New game restores authored crystals instead of previous shards")
	pop.restore_snapshot([])
	var scaled_stats := Definitions.THORIUM.duplicate(true); scaled_stats.shard_scale_percent = 50.0
	var scaled_shard := pop._create_thorium(scaled_stats,1,Transform3D.IDENTITY)
	var boxes: Array[AABB] = []
	preload("res://creature_loader.gd")._collect_bounds(scaled_shard.get_child(0),Transform3D.IDENTITY,boxes)
	var bounds := boxes[0]
	for model_box in boxes: bounds = bounds.merge(model_box)
	var original := Document.load_model("SHARD1",pop.asset_folder)
	var original_boxes: Array[AABB] = []
	preload("res://creature_loader.gd")._collect_bounds(original,original.transform,original_boxes)
	var original_bounds := original_boxes[0]
	for model_box in original_boxes: original_bounds = original_bounds.merge(model_box)
	check(bounds.size.is_equal_approx(original_bounds.size * 0.5),"50 percent scales the shard to half its original model dimensions")
	original.free()
	scaled_shard.free()
	var definition := Definitions.THORIUM.duplicate(true); definition.maximum_population = 6; definition.spawn_chance = 100
	pop.thorium_types = {"thorium":definition}; pop.random.seed = 42
	await physics_frame; await physics_frame
	pop._random_drop(definition)
	check(pop.get_child_count() == 1,"Random drop finds unobstructed water across the map")
	if pop.get_child_count() > 0:
		var point: Vector3 = pop.get_child(0).position
		check(point.y > 0 and point.x >= -50 and point.x <= 50 and point.z >= -50 and point.z <= 50 and not camera.is_position_in_frustum(point),"Random crystals start above water within map bounds and outside view")
	pop._random_drop(definition); pop._random_drop(definition)
	check(pop.get_child_count() == 2,"Population cap reserves space for three shards per crystal")
	pilot.controls_enabled = false; pop.spawn_elapsed = 59; pop._physics_process(2)
	check(pop.spawn_elapsed == 59,"Random spawning stops during dock/menu sequences")
	pop.restore_snapshot([])
	var radioactive := pop._create_thorium(Definitions.THORIUM,0,Transform3D.IDENTITY)
	radioactive.freeze = true
	var light: OmniLight3D = radioactive.get_node("ThoriumGlow")
	check(light.light_color.r > light.light_color.b and light.light_energy == 1 and light.omni_range == 3 and not light.shadow_enabled,"Thorium has configurable yellow light without expensive shadows")
	check(radioactive.glow_materials.all(func(material: Material) -> bool: return material is ShaderMaterial and material.get_shader_parameter("self_illuminated") == true and material.get_shader_parameter("has_texture") == true),"Every crystal surface emits its original texture independently of light direction")
	radioactive.set_process(false); radioactive._process(2.0)
	check(is_equal_approx(light.light_energy,0.5),"Yellow light smoothly pulses down to half brightness after two seconds")
	var glowing_material: Material = radioactive.glow_materials[0]
	var emission: Color = glowing_material.get_shader_parameter("emission_color") if glowing_material is ShaderMaterial else glowing_material.emission
	check(is_equal_approx(emission.r,radioactive.glow_emission_colour.r * 0.5),"Model emission pulses in step with the yellow light")
	check(is_equal_approx(float(glowing_material.get_shader_parameter("surface_emission_strength")),radioactive.surface_emission_strength * 0.5),"Whole textured surface pulses alongside the surrounding glow")
	radioactive._process(2.0)
	check(is_equal_approx(light.light_energy,1.0),"Glow returns to configured peak over a four-second cycle")
	var sub := preload("res://submarine_controller.gd").new(); sub.remember_settings = false; world.add_child(sub)
	sub.set_physics_process(false); sub.active = true; sub.controls_enabled = true; sub.freeze = true; sub.position = Vector3(0,0,1)
	pop.player = sub; pop._update_radiation(1.0)
	check(sub.health == 95 and sub.radiation_exposed,"Nearby Thorium causes configured shield damage per second")
	sub.position = Vector3(0,0,0.5); pop._update_radiation(1.0)
	check(is_equal_approx(sub.health,85),"Moving twice as close doubles Thorium radiation damage")
	sub.position = Vector3(0,0,Definitions.THORIUM.radiation_range); pop._update_radiation(1.0)
	check(is_equal_approx(sub.health,85) and not sub.radiation_exposed,"Radiation stops exactly at the configured range boundary")
	sub.restore_health(100,95); sub.position = Vector3(0,0,1); pop._update_radiation(0)
	var gauge := preload("res://hud_display.gd").new(); gauge.kind = "shield"; gauge.pilot = sub
	gauge.radiation_icon = preload("res://clump_loader.gd")._load_texture(pop.asset_folder,"RADIO","RADIOM",{})
	check(gauge.radiation_icon != null and gauge.radiation_icon.get_size() == Vector2(35,34),"HUD uses original masked radiation symbol")
	gauge.radiation_clock = 0.1; check(gauge.radiation_symbol_visible(),"Radiation warning flashes on")
	gauge.radiation_clock = 0.3; check(not gauge.radiation_symbol_visible(),"Radiation warning flashes off")
	sub.position = Vector3(0,0,5); pop._update_radiation(1.0)
	check(sub.health == 95 and not sub.radiation_exposed,"Leaving radiation range stops damage and warning")
	sub.position = Vector3(0,0,1); sub.controls_enabled = false; pop._update_radiation(1.0)
	check(sub.health == 95 and not sub.radiation_exposed,"Docked submarine takes no radiation damage")
	sub.controls_enabled = true; radioactive.stats.radiation_strength = 0; pop._update_radiation(1.0)
	check(sub.health == 95 and not sub.radiation_exposed,"Zero radiation strength disables damage")
	var dark_stats := Definitions.THORIUM.duplicate(true); dark_stats.glow_energy = 0; dark_stats.glow_emission = 0; dark_stats.radiation_strength = 0
	var dark := pop._create_thorium(dark_stats,1,Transform3D.IDENTITY)
	check(dark.get_node_or_null("ThoriumGlow") == null,"Zero glow strength removes the light")
	radioactive.stats.radiation_strength = 5.0; pop._shatter(radioactive); pop._update_radiation(1.0)
	check(sub.health == 95 and not sub.radiation_exposed,"Shattered Thorium shards cause neither radiation damage nor warning")
	var inert := pop._create_thorium(Definitions.inert_thorium(),0,Transform3D.IDENTITY); inert.freeze = true
	pop._update_radiation(1.0)
	check(is_equal_approx(sub.health,94.5) and sub.radiation_exposed,"Inert Thorium is still radioactive at one tenth strength")
	var inert_saved := pop.snapshot(); pop.restore_snapshot(JSON.parse_string(JSON.stringify(inert_saved)))
	inert = pop.get_children().filter(func(body: Node) -> bool: return body is Thorium and body.stats.id == "inert_thorium")[0]
	check(inert.stats.radiation_strength == 0.5 and inert.shard == 0,"Inert identity and radiation survive save/load")
	pop._shatter(inert)
	check(pop.get_children().filter(func(body: Node) -> bool: return body is Thorium and body.stats.id == "inert_thorium" and body.shard > 0).size() == 3,"Inert crystal shatters into three collectible shards")
	var exported := pop.snapshot()
	check(Population.valid_snapshot(JSON.parse_string(JSON.stringify(exported))),"Radiation and glow settings survive saved object JSON")
	gauge.free()
	world.free()
	print("Thorium: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
