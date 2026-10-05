extends SceneTree
const Weapons = preload("res://submarine_weapons.gd")
const Pilot = preload("res://submarine_controller.gd")
const Fish = preload("res://fish_controller.gd")
const Assets = preload("res://clump_loader.gd")
const Paths = preload("res://asset_paths.gd")
const Data = preload("res://original_game_data.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var folder := Paths.find_game_folder(); var catalogue := Data.load_catalogue(folder,false)
	var pilot := Pilot.new(); pilot.remember_settings = false; world.add_child(pilot); pilot.set_physics_process(false)
	var visual := Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF")); pilot.add_child(visual); pilot.visual = visual; visual.scale *= pilot.VISUAL_SCALE
	# Match Game's legacy model orientation: its bow faces pilot-local -Z.
	visual.rotation.y = PI; pilot.fit_collision_to_visual()
	var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(2,1.5,1); camera.look_at(Vector3(0,0,-1)); camera.fov = 40; camera.current = true
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50,-30,0); world.add_child(sun)
	var weapon := Weapons.new(); pilot.add_child(weapon); weapon.setup(pilot,folder,camera,catalogue); weapon.set_physics_process(false)
	check(weapon.frames.size() == 3 and weapon.frames.all(func(frame: Texture2D) -> bool: return frame != null) and weapon.icon != null,"Original lightning frames, masks and weapon HUD icon load")
	check(weapon.audio.stream != null and weapon.audio.stream is AudioStreamWAV and weapon.audio.stream.loop_mode != AudioStreamWAV.LOOP_DISABLED,"Zapper sound has a prepared seamless loop")
	var start: Vector3 = weapon.muzzle.get_node("Emitter").global_position
	check(start.z < 0,"Emitter is mounted at the bow, ahead of the cockpit")
	pilot.rotation = Vector3(0.3,0.8,0)
	weapon.update_fire(true,0)
	check((weapon.beam_end - weapon.beam_start).normalized().dot(-pilot.global_basis.z.normalized()) > 0.999,"Beam follows the submarine's forward direction while pitched and turned")
	weapon.update_fire(false,0); pilot.rotation = Vector3.ZERO
	var target := Fish.new(); var fish_model := Assets.load_clump(folder.path_join("CLUMPS/ANGEL.DFF"),PackedStringArray(),true)
	target.setup(fish_model,start + Vector3(0,0,-2),AABB(Vector3.ONE * -10,Vector3.ONE * 20),10,0.35,123)
	world.add_child(target); target.set_physics_process(false); target.configure_health(10)
	target.death_texture = Assets._load_texture(folder,"BUBBLE","BUBBLEM",{}); target.death_sound = Weapons._sound(folder,"audio.creature.death","SPLAT")
	target.death_frames = preload("res://creature_death.gd").load_gore(folder)
	await physics_frame; await physics_frame
	weapon.update_fire(true,0.1)
	check(weapon.firing and weapon.last_hit == target and is_equal_approx(target.health,9.0),"Holding fire damages a creature directly ahead")
	check(weapon.beam_end.distance_to(start) < 2.0,"Beam ends at the target's collision body")
	weapon.update_fire(false,0.1)
	check(not weapon.firing and not weapon.beam.visible and not weapon.audio.playing,"Release immediately stops beam, damage and sound")
	target.position = start + Vector3(0,0,-6)
	await physics_frame; await physics_frame
	weapon.update_fire(true,0.2)
	check(target.health == 9 and weapon.last_hit == null,"Out-of-range creatures are not damaged")
	target.position = start + Vector3(0.9,0,-2)
	await physics_frame; await physics_frame
	weapon.update_fire(true,0.2)
	check(target.health == 9 and weapon.last_hit == null,"Beam fires straight rather than snapping onto nearby creatures")
	target.position = start + Vector3(0,0,-2)
	var wall := StaticBody3D.new(); var collider := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(2,2,0.2); collider.shape = box; wall.add_child(collider); wall.position = start + Vector3(0,0,-1); world.add_child(wall)
	await physics_frame; await physics_frame
	weapon.update_fire(true,0.2)
	check(target.health == 9 and weapon.last_hit == wall and weapon.beam_end.distance_to(start) < 1,"Scenery blocks the beam and protects creatures behind it")
	check(weapon.impact.visible and weapon.impact_frames.size() == 2,"Terrain hit uses the two original masked spark textures")
	weapon._process(0.05); var spark: Texture2D = weapon.impact.texture
	weapon._process(0.05)
	check(weapon.impact.texture != spark,"Terrain spark cycles animation frames while firing")
	wall.queue_free(); await process_frame; await physics_frame
	if DisplayServer.get_name() != "headless":
		weapon.update_fire(true,0); weapon._process(0.05); await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/zapper-beam-preview.png")
	var deaths := []; target.died.connect(func() -> void: deaths.append(true))
	preload("res://creature_death.gd").settings.chunk_lifetime = 1.0
	weapon.update_fire(true,1.0)
	check(target.dead and target.health == 0 and not target.visible and target.collision_layer == 0 and deaths.size() == 1,"Lethal damage hides the creature and removes its weapon collision")
	target.take_damage(100); check(deaths.size() == 1,"A dead creature cannot explode twice")
	var bursts := world.find_children("CreatureBurst","Node3D",true,false)
	check(bursts.size() == 1 and bursts[0].pieces.size() > 1,"Death breaks the original fish model into flying pieces")
	check(bursts.size() == 1 and bursts[0].gore.size() == 20 and bursts[0].gore_frames.size() == 12,"Organic deaths scatter masked original FLAK sprites")
	preload("res://creature_death.gd").settings.gore_amount = 0
	var clean_burst := preload("res://creature_death.gd").new(); world.add_child(clean_burst); clean_burst.setup(target,null,null,target.death_frames)
	check(clean_burst.gore.is_empty() and not clean_burst.pieces.is_empty(),"Zero gore setting disables blood sprites while retaining fragments")
	clean_burst.queue_free(); preload("res://creature_death.gd").settings.gore_amount = 20
	if DisplayServer.get_name() != "headless":
		await create_timer(0.15).timeout; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/zapper-death-preview.png")
	weapon.update_fire(false,0)
	await create_timer(2.2).timeout
	check(world.find_children("CreatureBurst","Node3D",true,false).is_empty(),"Death effects clean themselves up")
	for frame in range(600): weapon.update_fire(true,1.0 / 60)
	check(weapon.firing and not weapon.settings.has("ammo") and not weapon.settings.has("energy"),"Weapon can fire continuously without ammo or energy consumption")
	weapon.update_fire(false,0); world.queue_free(); await process_frame
	print("Zapper: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
