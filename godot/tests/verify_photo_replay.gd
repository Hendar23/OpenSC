extends "res://tests/verify_remaining_stage_two.gd"
const Bindings = preload("res://input_bindings.gd")
const Visual = preload("res://replay_visual.gd")
class Actor extends Node3D:
	pass

func button(code: int) -> void:
	var event := InputEventJoypadButton.new(); event.device = 77; event.button_index = code; event.pressed = true
	root.push_input(event,true)
	event = event.duplicate(); event.pressed = false; root.push_input(event,true)

func run() -> void:
	Bindings.install()
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for replay")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game()
	var photo: Node3D = game.photo_mode; var replay: Node3D = photo.replay
	game.set_process(false); game.set_physics_process(false); game.docking.set_physics_process(false)
	game.pilot.freeze = true; game.pilot.set_physics_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	game.camera.global_position = Vector3(0,150,12); game.camera.look_at(Vector3(0,150,0))
	game.docking.current = game.submarine_traffic.port_by_id(1)
	replay.set_process(false); replay.clear(); replay.started = true
	check(replay.enabled and game.front_end.gameplay_menu.replay_enabled,"Replay defaults enabled")
	var actor := Actor.new(); game.world_root.add_child(actor)
	var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); actor.add_child(mesh)
	var material := StandardMaterial3D.new(); material.albedo_color = Color.RED; mesh.material_override = material
	replay._register(mesh)
	var track: RefCounted = replay.tracks[mesh.get_instance_id()]
	mesh.position = Vector3(0,150,0); replay.capture(0.05)
	mesh.position.x = 2; material.albedo_color = Color.BLUE; replay.capture(0.05)
	var born := MeshInstance3D.new(); born.mesh = SphereMesh.new(); actor.add_child(born); born.position = Vector3(4,150,0)
	replay._register(born); replay.capture(0.05)
	var born_track: RefCounted = replay.tracks[born.get_instance_id()]
	mesh.hide(); replay.capture(0.05)
	var ghost := MeshInstance3D.new(); ghost.mesh = BoxMesh.new(); actor.add_child(ghost); ghost.position = Vector3(6,150,0)
	replay._register(ghost); replay.capture(0.05)
	var ghost_track: RefCounted = replay.tracks[ghost.get_instance_id()]
	ghost.free(); replay.capture(0.05)
	# Record a real enhanced explosion, its texture changes and fade state.
	var explosion := preload("res://mine_explosion.gd").new(); actor.add_child(explosion)
	explosion.global_position = Vector3(8,150,0); explosion.setup(game.submarine_explosion_frames,2,null); explosion.set_process(false)
	replay._scan(explosion); explosion._process(0.1); replay.capture(0.05)
	var lobe_track: RefCounted = replay.tracks[explosion.lobes[0].node.get_instance_id()]
	var cloud_track: RefCounted = replay.tracks[explosion.clouds[0].node.get_instance_id()]
	explosion._process(0.5); replay.capture(0.05)
	var cloud_opacity: float = explosion.clouds[0].node.material_override.get_shader_parameter("opacity")
	explosion.free(); replay.capture(0.05)
	# Wake births, lifetime and movement use the real emitter's integrator.
	var wake := preload("res://propeller_bubbles.gd").new(); actor.add_child(wake); wake.set_physics_process(false)
	wake.surface_height = 200
	wake.emit_from(1,Vector3(0,150,0),Vector3.BACK,1,20,0.05); replay._scan(wake); replay.capture(0.05)
	var wake_track: RefCounted = replay.wakes[wake.get_child(0).get_instance_id()]
	var particle_start: Vector3 = wake.particles[0].position
	wake.advance(0.1); replay.capture(0.1)
	var particle_end: Vector3 = wake.particles[0].position
	# A procedural beam must not retain a reference to mutable live geometry.
	var beam := MeshInstance3D.new(); actor.add_child(beam); beam.mesh = ImmediateMesh.new()
	# Live zappers are discovered while hidden, before their first ribbon build.
	replay._register(beam); beam.set_meta("replay_mutable_mesh",true)
	var ribbon: ImmediateMesh = beam.mesh; ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3.ZERO,Vector3.RIGHT,Vector3.UP]: ribbon.surface_add_vertex(point)
	ribbon.surface_end(); replay.capture(0.05)
	var beam_track: RefCounted = replay.tracks[beam.get_instance_id()]
	ribbon.clear_surfaces(); replay.capture(0.05)
	# Use an actual torpedo model, then remove its live projectile entirely.
	var missile := preload("res://turret_missile.gd").new(); actor.add_child(missile)
	var owner := Node3D.new(); actor.add_child(owner)
	var template: Node3D = game.weapons.arsenal.templates.missile
	missile.source = owner; missile.add_child(template.duplicate()); missile.get_child(0).show(); missile.set_physics_process(false)
	missile.position = Vector3(0,150,0); replay._scan(missile); replay.capture(0.05)
	var missile_mesh: MeshInstance3D = missile.find_children("*","MeshInstance3D",true,false)[0]
	var missile_track: RefCounted = replay.tracks[missile_mesh.get_instance_id()]
	var missile_start := missile_mesh.global_transform
	missile.position.x += 2; replay.capture(0.05); missile.free(); replay.capture(0.05)
	var corpse := MeshInstance3D.new(); corpse.mesh = BoxMesh.new(); actor.add_child(corpse); corpse.position = Vector3(0,150,0)
	var wreck := preload("res://submarine_death.gd").new(); actor.add_child(wreck); wreck.global_position = corpse.global_position
	wreck.setup_machine(corpse,corpse,game.submarine_traffic.bubble_texture); wreck.set_process(false); replay._scan(wreck)
	var chunk: MeshInstance3D = wreck.pieces[0].node
	var chunk_track: RefCounted = replay.tracks[chunk.get_instance_id()]
	var burst_track: RefCounted = replay.tracks[wreck.bubbles.get_instance_id()]
	replay.capture(0.05); var chunk_start := chunk.global_transform
	wreck._process(0.1); replay.capture(0.1); wreck.free(); corpse.free(); replay.capture(0.05)
	var live_pose := born.global_transform; var live_visibility := mesh.visible
	var live_state: Dictionary = game._save_snapshot("Replay boundary")
	check(photo.enter(77),"Photo mode opens replay from outside")
	check(paused and replay.playback != null and not born.visible,"Live scene stays paused and replay substitutes visuals")
	replay.seek(0.075)
	check(track.proxy.visible and track.proxy.global_position.distance_to(Vector3(1,150,0)) < 0.001,"Scrubbing interpolates recorded movement")
	check(track.proxy.material_override.albedo_color == Color.RED and material.albedo_color == Color.BLUE,"Past materials are isolated from live resources")
	check(born_track.proxy == null or not born_track.proxy.visible,"Actors do not appear before birth")
	replay.seek(0.175); check(born_track.proxy.visible and track.proxy.visible,"Birth and disappearance switch at recorded boundaries")
	replay.seek(0.275); check(not track.proxy.visible and ghost_track.proxy.visible,"A later disappearance does not erase an earlier actor")
	replay.seek(0.325); check(not ghost_track.proxy.visible,"Deleted actors disappear again after their recorded removal")
	replay.seek(0.35)
	check(lobe_track.proxy.visible and lobe_track.proxy.material_override.get_shader_parameter("albedo_texture") != null,"Destroyed explosion retains its original animated burst")
	replay.seek(0.4)
	check(cloud_track.proxy.visible and is_equal_approx(cloud_track.proxy.material_override.get_shader_parameter("opacity"),cloud_opacity),"Explosion smoke and opacity replay after live effect deletion")
	if DisplayServer.get_name() != "headless":
		for frame in range(3): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../.local/photo-replay-native.png")
	replay.seek(0.5)
	check(wake_track.events.size() == 1 and wake_track.pose_at(wake_track.events[0],0.5).origin.distance_to(particle_start) < 0.001,"Recorded wake begins at its original world position")
	replay.seek(0.6)
	check(wake_track.pose_at(wake_track.events[0],0.6).origin.distance_to(particle_end) < 0.001,"Wake replay reproduces damped drift and rise")
	if DisplayServer.get_name() != "headless": check(wake_track.proxy.multimesh.get_instance_transform(0).origin.distance_to(particle_end) < 0.001,"Wake renderer receives the interpolated historical transform")
	replay.seek(0.65)
	check(beam_track.proxy.mesh.get_surface_count() == 1 and ribbon.get_surface_count() == 0,"Recorded procedural beam survives clearing the live mesh")
	replay.seek(0.775)
	check(missile_track.proxy.visible and missile_track.proxy.global_position.distance_to(missile_start.origin+Vector3.RIGHT) < 0.001,"A real torpedo model interpolates its flight after the projectile is freed")
	replay.seek(0.9)
	check(chunk_track.proxy.visible and chunk_track.proxy.global_transform.is_equal_approx(chunk_start),"Real wreck fragments retain their recorded shape and pose after cleanup")
	check(burst_track.proxy.visible and burst_track.proxy.multimesh.instance_count == 96,"Death bubbles can be reconstructed while the live emitter no longer exists")
	button(JOY_BUTTON_DPAD_LEFT); check(replay.cursor < replay.timeline and not replay.playing,"D-pad left scrubs without moving the sub")
	button(JOY_BUTTON_DPAD_UP); check(replay.playing,"D-pad up starts playback")
	button(JOY_BUTTON_DPAD_DOWN); check(replay.speed == 0.25,"D-pad down enables slow motion")
	var before: float = replay.cursor; replay.advance(0.1)
	check(is_equal_approx(replay.cursor-before,0.025),"Slow motion advances the recorded timeline at quarter speed")
	button(JOY_BUTTON_DPAD_UP); check(not replay.playing,"D-pad up pauses playback")
	photo.leave()
	check(not paused and born.global_transform == live_pose and born.visible and mesh.visible == live_visibility,"Leaving restores exact live poses and local visibility")
	var after: Dictionary = game._save_snapshot("Replay boundary"); live_state.erase("saved_at"); after.erase("saved_at")
	check(after == live_state,"Scrubbing changes no health, inventory, mission or save state")
	check(photo.find_children("*","Control",true,false).is_empty(),"Replay adds no on-screen instructions")
	# Ring eviction and released resources, including destroyed actor templates.
	for index in range(650): replay.capture(0.05)
	check(replay.timeline-replay.oldest <= 30.00001 and not replay.tracks.values().has(ghost_track),"Rolling buffer retains at most thirty seconds and evicts destroyed actors")
	check(track.stamps.size() == Visual.CAPACITY and track.versions.size() <= Visual.CAPACITY,"Transform and appearance history stay bounded")
	var swimmer := MeshInstance3D.new(); actor.add_child(swimmer)
	var swim := ArrayMesh.new(); swim.add_blend_shape("swim")
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	var blend := []; blend.resize(Mesh.ARRAY_MAX); blend[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP*2])
	swim.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[blend]); swimmer.mesh = swim
	var swim_track := Visual.new(); swim_track.setup(swimmer,0); swim_track.record(0,0)
	swimmer.set_blend_shape_value(0,1); swim_track.record(1,0.05)
	var swim_view := Node3D.new(); actor.add_child(swim_view); swim_track.show_at(swim_view,0,0.5,0.025)
	check(is_equal_approx(swim_track.proxy.get_blend_shape_value(0),0.5) and swimmer.get_blend_shape_value(0) == 1,"Fish morph animation interpolates without changing live blend weights")
	swim_track.dispose(); swim_view.free(); swimmer.free()
	var flash := MeshInstance3D.new(); actor.add_child(flash); flash.mesh = QuadMesh.new()
	flash.material_override = preload("res://natural_light.gd").billboard_material(game.submarine_explosion_frames[0])
	flash.material_override.set_shader_parameter("opacity",0.9)
	var flash_track := Visual.new(); flash_track.setup(flash,0); flash_track.record(0,0)
	flash.material_override.set_shader_parameter("opacity",0.2); flash.material_override.set_shader_parameter("albedo_texture",game.submarine_explosion_frames[1]); flash_track.record(1,0.05)
	var flash_view := Node3D.new(); actor.add_child(flash_view); flash_track.show_at(flash_view,0,0,0)
	check(is_equal_approx(flash_track.proxy.material_override.get_shader_parameter("opacity"),0.9) and flash_track.proxy.material_override.get_shader_parameter("albedo_texture") == game.submarine_explosion_frames[0],"Material templates retain earlier fade and texture values")
	flash_track.show_at(flash_view,1,0,0.05)
	check(is_equal_approx(flash_track.proxy.material_override.get_shader_parameter("opacity"),0.2) and flash_track.proxy.material_override.get_shader_parameter("albedo_texture") == game.submarine_explosion_frames[1],"Playback changes uniforms without cloning a material every sample")
	flash_track.dispose(); flash_view.free(); flash.free()
	var menu: CanvasLayer = game.front_end.gameplay_menu
	menu._toggle_replay()
	check(not replay.enabled and replay.tracks.is_empty() and replay.wakes.is_empty() and replay.tick == -1,"Options Off immediately releases all replay history")
	replay._process(0.2); check(replay.tick == -1,"Disabled replay performs no recording")
	check(photo.enter(),"Disabling replay preserves ordinary photo mode")
	check(replay.playback == null,"Disabled replay does not allocate playback visuals"); photo.leave()
	menu._toggle_replay(); replay.set_process(false); replay._process(0.1)
	check(replay.enabled and replay.tick >= 0,"Options On starts a fresh recording")
	check(replay.tracks.has(game.particles.get_instance_id()),"Ambient water particles are included in visual replay")
	var cold: int = replay.last_capture_usec
	var samples := PackedInt64Array()
	for index in range(40):
		replay.capture(0.05); samples.append(replay.last_capture_usec)
	samples.sort()
	print("Replay profile: tracks=",replay.tracks.size()," packed MiB=",float(replay.bytes)/1048576.0," cold usec=",cold," steady median usec=",samples[20]," max=",samples[39])
	var bursts: Array[Node3D] = []
	for index in range(12):
		var effect := preload("res://mine_explosion.gd").new(); actor.add_child(effect)
		effect.position = Vector3(index*0.5,150,0); effect.setup(game.submarine_explosion_frames,2,null); effect.set_process(false); bursts.append(effect)
	for index in range(125): wake.emit_from(2,Vector3(0,150,0),Vector3.BACK,1,200,0.05)
	samples.clear()
	for index in range(40):
		for effect in bursts: effect._process(0.05)
		wake.advance(0.05); replay.capture(0.05); samples.append(replay.last_capture_usec)
	samples.sort()
	print("Busy replay profile: tracks=",replay.tracks.size()," wake bubbles=",wake.particles.size()," packed MiB=",float(replay.bytes)/1048576.0," median usec=",samples[20]," max=",samples[39])
	check(replay.tracks.size() <= replay.MAX_TRACKS and replay.bytes <= replay.MAX_BYTES,"Busy effects retain fixed track and packed-memory limits")
	var particle_pose: Transform3D = game.particles.global_transform
	check(photo.enter(),"Photo mode can replay a busy world")
	var cloud: RefCounted = replay.tracks[game.particles.get_instance_id()]
	photo.move(Vector3.RIGHT,0,1); replay.advance(0)
	check(cloud.proxy == null or cloud.proxy.global_position.is_equal_approx(photo.view.global_position),"Paused replay's ambient cloud follows the free camera")
	photo.leave(); check(game.particles.global_transform == particle_pose,"Free camera never moves the live particle cloud")
	for effect in bursts: effect.free()
	game.docking.stage = game.Docking.Stage.DOCKED; replay._process(0.1)
	check(replay.tick == -1 and replay.tracks.is_empty(),"Docking clears the previous voyage")
	game.docking.stage = game.Docking.Stage.IDLE; replay._process(0.1)
	check(replay.timeline <= 0.11,"Launching starts with a short fresh replay")
	game._reset_loaded_world(); check(replay.tick == -1,"New game and save restoration clear recording history")
	for path in ["res://photo_replay.gd","res://replay_visual.gd","res://replay_wake.gd","res://replay_clock.gdshaderinc","res://tests/verify_photo_replay.gd"]:
		if not FileAccess.file_exists(path+".uid"):
			var file := FileAccess.open(path+".uid",FileAccess.WRITE); file.store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	actor.free(); game.free(); await process_frame
	print("Photo replay: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
