extends "res://tests/test_scene_tree.gd"
const Turret = preload("res://gun_turret.gd")
const Missile = preload("res://turret_missile.gd")
const System = preload("res://turret_system.gd")
const Assets = preload("res://clump_loader.gd")
const Scenery = preload("res://scenery_loader.gd")
const Document = preload("res://map_document.gd")
const Game = preload("res://game.gd")
class Victim extends CharacterBody3D:
	var active := true
	var controls_enabled := true
	var dead := false
	var damage := 0.0
	var impulse := Vector3.ZERO
	func take_weapon_damage(amount: float, _source: Vector3) -> void: damage += amount
	func receive_projectile_hit(amount: float, _point: Vector3, push: Vector3) -> void:
		damage += amount; impulse = push
class FakeJoy extends RefCounted:
	var calls: Array[Dictionary] = []
	func get_connected_joypads() -> Array: return [0]
	func start_joy_vibration(_device: int, weak: float, strong: float, duration: float) -> void:
		calls.append({"weak":weak,"strong":strong,"duration":duration})
	func stop_joy_vibration(_device: int) -> void: pass
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-turret-fixtures"
	storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE)
	ignore.store_string("")
	var config := ConfigFile.new()
	config.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER") if not OS.get_environment("OPENSC_TEST_GAME_FOLDER").is_empty() else ProjectSettings.globalize_path("res://../Original Sub Culture"))
	config.save(storage.preferences_path())
	call_deferred("run")
func run() -> void:
	preload("res://mod_registry.gd").initialize(false)
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var fixture := Node3D.new(); root.add_child(fixture)
	var model := Document.load_model("TURRET",folder); model.set_meta("editor_model","TURRET"); fixture.add_child(model)
	Scenery._add_prop_collision(model)
	var turret = Turret.install(model)
	turret.set_physics_process(false)
	var victim := Victim.new(); fixture.add_child(victim)
	var shape := CollisionShape3D.new(); var sphere := SphereShape3D.new(); sphere.radius = 0.15; shape.shape = sphere; victim.add_child(shape)
	victim.collision_layer = 2; victim.collision_mask = 0
	victim.global_position = turret.head.global_position + Vector3(0,0,3)
	var system := System.new(); fixture.add_child(system); system.setup(fixture,folder,victim,func(_faction: int) -> bool: return false)
	await physics_frame; await physics_frame
	check(turret.head.name == "Frame_1" and turret.collision_shapes.size() == 2,"Native gun head and base have separate articulated collisions")
	check(turret.health == 8 and turret.tuning.turret_sustain == 0.3,"Turret uses original raw shields and sustain")
	turret._physics_process(0.04)
	check(turret.shots == 0,"Neutral turret tracks without firing")
	var base_pose: Transform3D = model.transform
	victim.global_position = turret.head.global_position + Vector3(3,0,0)
	var heading: Vector3 = turret.head.global_basis.z.normalized()
	turret.tuning.turret_armed = true; turret._physics_process(0.04)
	check(is_equal_approx(rad_to_deg(heading.angle_to(turret.head.global_basis.z.normalized())),0.5),"Head turns exactly half a degree per original tick")
	check(model.transform.is_equal_approx(base_pose) and turret.shots == 0,"Aiming leaves the base planted and cannot fire sideways")
	turret.reset(); turret.tuning.turret_armed = true
	victim.global_position = turret.head.global_position + Vector3(0,0,3)
	var wall := StaticBody3D.new(); fixture.add_child(wall); wall.collision_layer = 1
	var wall_shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(2,2,0.2); wall_shape.shape = box; wall.add_child(wall_shape)
	wall.global_position = turret.head.global_position + Vector3(0,0,1.5)
	await physics_frame; await physics_frame
	turret._physics_process(0.04)
	check(turret.shots == 0,"Terrain and buildings block launch line of sight")
	wall.free(); await physics_frame; await physics_frame
	turret._physics_process(0.04)
	check(turret.shots == 1 and is_equal_approx(turret.cooldown,41.0 / 25.0),"Aligned straight turret launches a missile with the original counter delay")
	var shot: Node3D = get_nodes_in_group("turret_missiles")[0]; shot.set_physics_process(false)
	for tick in range(125):
		if shot.is_queued_for_deletion(): break
		shot._physics_process(0.04)
	check(victim.damage > 0 and shot.is_queued_for_deletion(),"Missile travels through space and damages its swept collision target")
	check(victim.impulse.z > 0 and victim.impulse.length() <= Missile.HIT_IMPULSE,"Missile collision forwards a bounded impulse along its flight")
	check(system.bubbles.particles.size() > 5,"Moving missile emits a visible world-space bubble trail")
	await process_frame
	check(system.bubbles.particles.size() > 0,"Bubble wake survives missile impact")
	var guided := Missile.new(); fixture.add_child(guided)
	victim.global_position = Vector3(3,0,3)
	guided.setup(turret,system.templates[1],Vector3.ZERO,Vector3.BACK,victim,true); guided.set_physics_process(false)
	guided._physics_process(0.04)
	check(guided.direction.x > 0 and is_equal_approx(guided.direction.angle_to(Vector3.BACK),0.1),"Homing missiles steer toward their target with a bounded turn")
	guided._physics_process(Missile.LIFETIME)
	check(guided.is_queued_for_deletion(),"Missiles expire at the recovered lifetime")
	check(Missile.heading_basis(Vector3.UP).is_finite(),"Vertical missile aiming produces a valid transform")
	await process_frame
	victim.global_position = turret.head.global_position + Vector3(0,0,3)
	var predicted := Turret.intercept(Vector3(0,0,5),Vector3(1,0,0))
	check(predicted.x > 1 and predicted.z == 5,"Turret leads moving targets using the recovered interception speed")
	turret.reset(); turret.tuning.turret_armed = false
	turret.hitbox.take_weapon_damage_from(10,Vector3.ZERO,null)
	check(turret.health == 5 and turret.retaliation == 0,"Environmental damage never triggers player retaliation")
	turret.reset()
	turret.hitbox.take_weapon_damage(10,Vector3.ZERO)
	check(turret.health == 5 and turret.retaliation == 60,"Weapon hits apply sustain once and trigger temporary retaliation")
	turret._physics_process(0.04)
	check(turret.shots == 1 and is_equal_approx(turret.cooldown,31.0 / 25.0),"Retaliation uses the faster original counter")
	system.reset()
	check(system.bubbles.particles.is_empty(),"New game clears previous missile wakes")
	var clone := model.duplicate() as Node3D; clone.name = "Clone"; fixture.add_child(clone)
	var duplicate = Turret.install(clone)
	check(duplicate.head != turret.head and duplicate.collision_meshes[0] != turret.collision_meshes[0],"Editor duplicates have independent articulation and hitboxes")
	clone.free()
	var destruction_events: Array = []
	turret.destroyed.connect(func(id: String, attacker: String) -> void: destruction_events.append([id,attacker]))
	preload("res://entity_identity.gd").assign_id(victim,"player")
	turret.mission_owner = "turret_objective"
	turret.take_weapon_damage_from(100,Vector3.ZERO,victim)
	check(turret.dead and not model.visible and turret.hitbox.collision_layer == 0,"Destroyed turret stops rendering and colliding")
	var wreck: Node3D = fixture.get_node("TurretWreck")
	check(wreck.pieces.size() > 1 and wreck.gore.is_empty(),"Turret breaks into its own metal model pieces without blood")
	check(wreck.bubbles != null and wreck.bubbles.amount == 96,"Turret destruction releases submarine-style bubbles")
	var wreck_count := get_nodes_in_group("turret_wrecks").size(); turret.take_weapon_damage(100)
	check(get_nodes_in_group("turret_wrecks").size() == wreck_count,"Destroyed turret cannot release debris twice")
	check(destruction_events == [[preload("res://entity_identity.gd").of(turret),"player"]],"Turret destruction reports persistent target and attacker once")
	var saved := system.snapshot()
	check(System.valid_snapshot(saved),"Turret state serializes without engine references")
	system.reset(); check(not turret.dead and model.visible and turret.health == 8,"New game restores destroyed turrets")
	check(get_nodes_in_group("turret_wrecks").is_empty(),"New game clears old turret pieces")
	system.restore(saved); check(turret.dead and not model.visible,"Saved destruction restores correctly")
	check(turret.mission_owner == "turret_objective","Turret mission ownership survives save restoration")
	var invalid := saved.duplicate(true); invalid[invalid.keys()[0]].health = -1
	check(not System.valid_snapshot(invalid),"Invalid turret saves are rejected")
	fixture.free(); await process_frame
	var pilot := preload("res://submarine_controller.gd").new(); pilot.remember_settings = false; root.add_child(pilot)
	pilot.visual = Node3D.new(); pilot.add_child(pilot.visual); pilot.active = true; pilot.set_physics_process(false)
	var joy := FakeJoy.new(); pilot.impact_rumble.joy_input = joy
	pilot.receive_projectile_hit(1.0,pilot.global_position + Vector3.UP * 0.2,Vector3.BACK * 50)
	check(is_equal_approx(pilot.health,96.5),"Missile hits retain the original hull damage conversion exactly once")
	check(pilot.angular_velocity.x > 0,"Off-centre missile hits turn the hull")
	check(joy.calls.size() == 1 and joy.calls[0].strong > 0,"Missile hits produce one controller impact pulse")
	await physics_frame; await physics_frame
	check(pilot.linear_velocity.z > 0.3,"Missile hit pushes the actual submarine rigid body")
	pilot.controls_enabled = false
	var before_health := pilot.health; var before_velocity := pilot.linear_velocity
	pilot.receive_projectile_hit(1.0,pilot.global_position,Vector3.RIGHT * 50)
	check(pilot.health == before_health and pilot.linear_velocity == before_velocity and joy.calls.size() == 1,"Docking blocks missile damage, push and rumble")
	pilot.controls_enabled = true; pilot.health = 1
	pilot.receive_projectile_hit(1.0,pilot.global_position,Vector3.BACK * 50)
	check(pilot.dead and joy.calls.size() == 2 and joy.calls[-1].duration == 1.2,"Fatal missile hits use one stronger destruction pulse")
	pilot.free(); await process_frame
	var game := Game.new(); game.remember_preferences = false; game.show_start_menu = true; root.add_child(game)
	for frame in range(1800):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game starts with turret support")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game()
	check(game.turret_system.turrets.size() == 22,"Five generic and seventeen dedicated startup turrets are present")
	check(not game.world_root.has_node("Scenery/TURRET_71") and game.world_root.has_node("Scenery/TURRET_30"),"Tryton retains its dedicated defence without the overlapping generic turret")
	var velcova := game.world_root.get_node("Scenery/TURRET_91") as Node3D
	check(velcova.global_basis.y.normalized().is_equal_approx(Vector3.UP),"Velcova turret base loads upright instead of tilted 42.5 degrees")
	var authored: Dictionary = Document.load_path(Document.DEFAULT_PATH).entities["Scenery/TURRET_91"]
	check(velcova.transform.is_equal_approx(Document.decode(authored.transform)),"Velcova correction is a normal editable map placement")
	var turret_bounds: Array[Dictionary] = []
	for controller in game.turret_system.turrets:
		var turret_box := AABB(); var first := true
		for mesh in controller.collision_meshes:
			for corner in range(8):
				var vertex: Vector3 = mesh.global_transform * mesh.mesh.get_aabb().get_endpoint(corner)
				if first: turret_box = AABB(vertex,Vector3.ZERO); first = false
				else: turret_box = turret_box.expand(vertex)
		turret_bounds.append({"name":str(controller.get_parent().name),"box":turret_box})
	var overlaps: Array[String] = []
	for index in range(turret_bounds.size()):
		for other in range(index + 1,turret_bounds.size()):
			if turret_bounds[index].box.intersects(turret_bounds[other].box): overlaps.append(turret_bounds[index].name + " / " + turret_bounds[other].name)
	check(overlaps.is_empty(),"All active turret mesh bounds are separate: " + str(overlaps))
	var buried: Array[String] = []
	for controller in game.turret_system.turrets:
		for mesh in controller.collision_meshes:
			if controller.head.is_ancestor_of(mesh): continue
			var bottom: float = mesh.mesh.get_aabb().position.y
			for surface in range(mesh.mesh.get_surface_count()):
				for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					if vertex.y > bottom + 0.001: continue
					var point: Vector3 = mesh.global_transform * vertex
					var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 10,point - Vector3.UP * 10,16)
					query.hit_back_faces = true
					var hit := game.world_root.get_world_3d().direct_space_state.intersect_ray(query)
					if not hit.is_empty() and hit.position.y > point.y + 0.001:
						buried.append(str(controller.get_parent().name))
	check(buried.is_empty(),"Turret base footprints clear the terrain: " + str(buried))
	var armed := 0; var homing := 0
	for controller in game.turret_system.turrets:
		armed += int(controller.tuning.turret_armed); homing += int(controller.tuning.turret_homing)
	check(armed == 2 and homing == 14,"Dedicated homing turrets start armed; city guards remain neutral")
	game.docking.current = game.docking.ports[0]
	var snapshot: Dictionary = game._save_snapshot("Turret test")
	check(snapshot.has("turrets") and game.save_games.valid(snapshot),"Full game saves include validated turret state")
	snapshot.erase("turrets")
	check(game.save_games.valid(snapshot),"Existing saves without turret state remain compatible")
	for row in Scenery.read_database(folder.path_join("DATA/SCEN1.DDB")).Objects:
		if int(row.get("MissionID",0)) != 2 or int(row.get("ObjectID",-1)) not in [4,11,12]: continue
		if row.get("clump","") != "TURRET": continue
		var original := game.world_root.get_node("Scenery/TURRET_%d" % int(row.index)) as Node3D
		var pose := Scenery.placement(row,game.world_root.get_meta("database_offset"))
		if int(row.index) == 91:
			check(Vector2(original.position.x,original.position.z).is_equal_approx(Vector2(pose.origin.x,pose.origin.z)) and original.basis.get_scale().is_equal_approx(pose.basis.get_scale()),"Levelled Velcova turret retains its original horizontal position and scale")
			check(original.basis.z.normalized().is_equal_approx(Vector3(pose.basis.z.x,0,pose.basis.z.z).normalized()),"Levelled Velcova turret retains its horizontal heading")
		else:
			check(original.basis.is_equal_approx(pose.basis) and Vector2(original.position.x,original.position.z).is_equal_approx(Vector2(pose.origin.x,pose.origin.z)),"Startup turret %d retains its original orientation, scale and horizontal position" % int(row.index))
	check(not game.world_root.has_node("Scenery/TURRET_124"),"Mission-only turrets remain dormant")
	game.queue_free(); await process_frame
	var editor = preload("res://asset_editor.gd").new(); editor.remember_preferences = false; root.add_child(editor)
	await process_frame; editor.game_folder = folder; editor._set_mode(true)
	var map = editor.map_editor
	for frame in range(1800):
		if map.loaded: break
		await process_frame
	check(map.loaded,"Map editor loads turret placements")
	if map.loaded:
		map._add_entity("model","TURRET")
		var key: String = map.selected
		check(map.fields.has("entity_type") and map.fields.has("turret_armed") and not map.fields.has("turret_health"),"Placeable turret exposes its combat properties")
		map.fields.turret_armed.button_pressed = true; map.apply_properties()
		var type_id: String = map.record().entity_type
		map.select("entity_type:" + type_id)
		map.fields.turret_homing.button_pressed = true; map.fields.turret_health.value = 12; map.apply_properties()
		map.select(key)
		var placed = map.world.get_node(key).get_node("GunTurret")
		check(placed.tuning.turret_homing and placed.tuning.turret_armed and placed.tuning.turret_health == 12,"Editor applies turret settings")
		check(placed.player == null,"Editor turrets do not fight during editing")
		var placed_head_id: int = placed.head.get_instance_id()
		map.duplicate_selection()
		var copied = map.world.get_node(map.selected).get_node("GunTurret")
		check(copied.head.get_instance_id() != placed_head_id,"Map editor duplication keeps turret heads independent")
		var copied_key: String = map.selected
		map.delete_selection(); map.undo()
		check(map.world.get_node(copied_key).has_node("GunTurret"),"Editor undo restores turret behaviour")
		var path := "res://tests/cache-turret-fixtures/turret-map.json"
		check(Document.save(map.document,path) == OK,"Turret map saves successfully")
		var loaded := Document.load_path(path)
		var effective := Document.EntityTypes.effective(loaded,loaded.entities[key])
		check(effective.turret_homing and effective.turret_health == 12,"Map round trip preserves turret settings")
		Document.EntityTypes.find_type(loaded,"entity_type",type_id).turret_sustain = -1
		check(not Document.valid(loaded),"Invalid turret map stats are rejected")
	editor.queue_free(); await process_frame
	print("Turrets: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
