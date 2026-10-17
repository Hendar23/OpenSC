extends "res://tests/test_scene_tree.gd"
const Weapons = preload("res://submarine_weapons.gd")
const Pilot = preload("res://submarine_controller.gd")
const Fish = preload("res://fish_controller.gd")
const Assets = preload("res://clump_loader.gd")
const Paths = preload("res://asset_paths.gd")
const Data = preload("res://original_game_data.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-zapper-fixtures"
	storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",ProjectSettings.globalize_path("res://../Original Sub Culture")); config.save(storage.preferences_path())
	call_deferred("_run")
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
	check(weapon.audio is AudioStreamPlayer and weapon.audio.volume_db == weapon.settings.volume_db,"Player zapper uses constant volume independent of camera position")
	var start: Vector3 = weapon.muzzle.get_node("Emitter").global_position
	check(start.z < 0,"Emitter is mounted at the bow, ahead of the cockpit")
	pilot.rotation = Vector3(0.3,0.8,0)
	weapon.update_fire(true,0)
	check((weapon.beam_end - weapon.beam_start).normalized().dot(-pilot.global_basis.z.normalized()) > 0.999,"Beam follows the submarine's forward direction while pitched and turned")
	weapon.update_fire(false,0); pilot.rotation = Vector3.ZERO
	var target := Fish.new(); var fish_model := Assets.load_clump(folder.path_join("CLUMPS/ANGEL.DFF"),PackedStringArray(),true)
	target.setup(fish_model,start + Vector3(0,0,-2),AABB(Vector3.ONE * -10,Vector3.ONE * 20),10,0.35,123)
	world.add_child(target); target.set_physics_process(false); target.configure_health(10); target.damage_sustain = 0.2
	target.death_texture = Assets._load_texture(folder,"BUBBLE","BUBBLEM",{}); target.death_sound = Weapons._sound(folder,"audio.creature.death","SPLAT")
	target.death_frames = preload("res://creature_death.gd").load_gore(folder)
	await physics_frame; await physics_frame
	weapon.update_fire(true,0.1)
	check(weapon.firing and weapon.last_hit == target and is_equal_approx(target.health,9.0),"Holding fire damages a creature directly ahead")
	check(not weapon.hit_blood.particles.is_empty() and not target.dead,"Nonlethal zapper damage emits blood feedback")
	var blood_count: int = weapon.hit_blood.particles.size()
	weapon.update_fire(true,0)
	check(weapon.hit_blood.particles.size() == blood_count,"A visual update without damage does not emit blood")
	if DisplayServer.get_name() != "headless":
		weapon._process(0.05)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/zapper-hit-blood-preview.png")
	check(weapon.beam_end.distance_to(start) < 2.0,"Beam ends at the target's collision body")
	weapon.update_fire(false,0.1)
	check(not weapon.firing and not weapon.beam.visible and not weapon.audio.playing,"Release immediately stops beam, damage and sound")
	check(weapon.hit_blood.particles.size() == blood_count,"Releasing fire stops emitting blood")
	weapon.hit_blood._process(1.0)
	check(weapon.hit_blood.particles.is_empty(),"Hit blood fades and cleans up after release")
	weapon.configure({"gore_amount":0.0})
	weapon.update_fire(true,0.04)
	check(weapon.hit_blood.particles.is_empty() and target.health < 9.0,"Zero gore suppresses hit blood while retaining damage")
	target.health = 9.0; weapon.configure({"gore_amount":20.0})
	target.position = start + Vector3(0,0,-6)
	await physics_frame; await physics_frame
	weapon.update_fire(true,0.2)
	check(target.health == 9 and weapon.last_hit == null,"Out-of-range creatures are not damaged")
	target.position = start + Vector3(0.9,0,-2)
	await physics_frame; await physics_frame
	weapon.update_fire(true,0.2)
	check(target.health == 9 and weapon.last_hit == null,"A creature outside the default cone is not targeted")
	weapon.configure({"auto_aim_cone":60.0})
	weapon.update_fire(true,0)
	check(weapon.last_hit == null,"Player auto aim is Off by default even with a wide developer cone")
	weapon.auto_aim_enabled = true
	weapon.update_fire(true,0)
	check(weapon.last_hit == target,"A wider cone locks onto a nearby off-axis creature")
	weapon.configure({"auto_aim_cone":0.0})
	weapon.update_fire(true,0)
	check(weapon.last_hit == null,"Zero cone disables auto aim")
	weapon.configure({"auto_aim_cone":60.0,"range":8.0})
	target.position = start + Vector3(0,0,-12)
	await physics_frame; await physics_frame
	weapon.update_fire(true,0); weapon._process(0.01)
	var ribbon_arrays: Array = weapon.beam.mesh.surface_get_arrays(0)
	var ribbon_vertices: PackedVector3Array = ribbon_arrays[Mesh.ARRAY_VERTEX]
	var ribbon_uvs: PackedVector2Array = ribbon_arrays[Mesh.ARRAY_TEX_UV]
	check(ribbon_vertices.size() == 22,"Original beam uses eleven vertex pairs and ten segments")
	var tip := (ribbon_vertices[-2] + ribbon_vertices[-1]) * 0.5
	check(is_equal_approx(weapon.beam_start.distance_to(weapon.beam_end),8.0) and tip.is_equal_approx(weapon.beam_end - weapon.beam_start),"Distorted visual and damage beam end at configured range")
	check(((ribbon_vertices[0] + ribbon_vertices[1]) * 0.5).is_zero_approx(),"Ribbon starts at muzzle")
	check(weapon.material.texture_repeat and ribbon_uvs[-1].y > 8.0 / weapon.settings.beam_width,"Lightning repeats along the original constant-width ribbon")
	check(is_zero_approx(ribbon_uvs[0].y),"Repeated lightning stays anchored to muzzle")
	var bent := false
	for index in range(1,10):
		var center := (ribbon_vertices[index * 2] + ribbon_vertices[index * 2 + 1]) * 0.5
		if center.cross(tip.normalized()).length() > 0.01: bent = true
	check(bent,"Beam has lateral bends rather than a straight centerline")
	weapon._process(0.06)
	var next_vertices: PackedVector3Array = weapon.beam.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(next_vertices != ribbon_vertices,"Crackle geometry changes on successive animation ticks")
	check(((next_vertices[-2] + next_vertices[-1]) * 0.5).is_equal_approx(tip),"Animated crackle retains endpoint")
	weapon.configure({"range":4.0})
	target.position = start + Vector3(0,0,-2)
	var wall := StaticBody3D.new(); var collider := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(2,2,0.2); collider.shape = box; wall.add_child(collider); wall.position = start + Vector3(0,0,-1); world.add_child(wall)
	await physics_frame; await physics_frame
	weapon.update_fire(true,0.2)
	check(target.health == 9 and weapon.last_hit == wall and weapon.beam_end.distance_to(start) < 1,"Scenery blocks the beam and protects creatures behind it")
	check(weapon.hit_blood.particles.is_empty(),"Scenery hits do not emit blood")
	check(weapon.impact.visible and weapon.impact_frames.size() == 2,"Terrain hit uses the two original masked spark textures")
	weapon._process(0.05); var spark: Texture2D = weapon.impact.texture
	var short_arrays: Array = weapon.beam.mesh.surface_get_arrays(0)
	var short_vertices: PackedVector3Array = short_arrays[Mesh.ARRAY_VERTEX]
	check(((short_vertices[-2] + short_vertices[-1]) * 0.5).is_equal_approx(weapon.beam_end - weapon.beam_start),"Scenery shortens distorted beam at collision")
	check(is_zero_approx(short_arrays[Mesh.ARRAY_TEX_UV][0].y),"Shortened beam retains muzzle texture phase")
	weapon._process(0.08)
	check(weapon.impact.texture != spark,"Terrain spark cycles animation frames while firing")
	wall.queue_free(); await process_frame; await physics_frame
	if DisplayServer.get_name() != "headless":
		weapon.update_fire(true,0); weapon._process(0.05); await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/zapper-beam-preview.png")
	# The same elapsed time must produce identical damage at 25 and 60 Hz.
	target.health = 100; weapon.update_fire(false,0)
	for frame in range(60): weapon.update_fire(true,1.0 / 60)
	var sixty_hz: float = target.health
	target.health = 100; weapon.update_fire(false,0)
	for frame in range(25): weapon.update_fire(true,1.0 / 25)
	check(is_equal_approx(target.health,sixty_hz) and is_equal_approx(target.health,87.5),"Raw zapper tick damage is independent of Godot frame rate")
	var original_mount := weapon.muzzle.transform
	weapon.update_fire(false,0); weapon.configure({"range":2.5}); weapon.set_upgraded(true)
	check(weapon.muzzle.transform == original_mount and weapon.muzzle.find_children("ELECTRIC","Node3D",false,false).size() == 1,"Upgrade keeps the same equipment mount and one original twin-prong housing")
	check(weapon.upgraded_emitters[0].is_equal_approx(Vector3(-0.165859,0.037052,-0.000778)) and weapon.upgraded_emitters[1].is_equal_approx(Vector3(0.165859,0.037052,-0.000778)),"Upgraded arcs originate at the pointed electrode vertices instead of their base faces")
	check(weapon.effective_range() == 5 and weapon.effective_damage() == 5,"Original upgrade doubles range and raw damage")
	check(weapon.icon == weapon.upgraded_icon and weapon.upgraded_icon != null,"Upgrade switches to ELECTRI2 HUD artwork")
	target.position = weapon.muzzle.get_node("Emitter").global_position + Vector3(0,0,-4)
	target.health = 100
	await physics_frame; await physics_frame
	weapon.update_fire(true,0.04)
	check(weapon.last_hit == target and is_equal_approx(target.health,99.0),"Upgraded zapper reaches four units and applies five raw damage once per tick")
	weapon._process(0.04); weapon.secondary_arc._process(0.04)
	check(weapon.secondary_arc.beam.visible and weapon.secondary_arc.beam.mesh.get_surface_count() == 1 and weapon.secondary_arc.beam_end == weapon.beam_end,"Twin lightning ribbons converge on one hit point")
	pilot.rotation = Vector3(0.2,0.7,0); weapon.muzzle.rotation.x = 0.15; weapon.muzzle.scale = Vector3.ONE * 1.2
	weapon.update_fire(true,0)
	check(weapon.beam_start.is_equal_approx(weapon.muzzle.to_global(weapon.upgraded_emitters[0])) and weapon.secondary_arc.beam_start.is_equal_approx(weapon.muzzle.to_global(weapon.upgraded_emitters[1])),"Both arcs follow their prong tips through ship and custom mount transforms")
	pilot.rotation = Vector3.ZERO; weapon.muzzle.transform = original_mount
	weapon.update_fire(false,0)
	check(not weapon.secondary_arc.firing and not weapon.secondary_arc.beam.visible,"Releasing fire stops the second arc")
	weapon.set_installed([])
	check(not weapon.muzzle.visible and weapon.upgraded,"Unequipping hides the housing without removing the upgrade")
	weapon.set_installed(["zapper"]); weapon.set_upgraded(false)
	check(weapon.effective_range() == 2.5 and weapon.icon == weapon.standard_icon and weapon.muzzle.get_node("Emitter").position == weapon.standard_emitter,"Reset restores the standard zapper and icon")
	target.position = start + Vector3(0,0,-2)
	await physics_frame; await physics_frame
	target.health = 9; weapon.update_fire(false,0)
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
