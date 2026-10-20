extends "res://tests/test_scene_tree.gd"
const Mounts = preload("res://submarine_mounts.gd")
# Independent fixtures transcribed from the retail equipment callbacks.
const POINTS := {
	"deep_sea_lights":Vector3(0,.16,.27), "zapper":Vector3(0,.15,.18),
	"suckomat":Vector3(0,-.25,-.1), "magnet":Vector3(0,-.2,0),
	"grapple":Vector3(0,-.23,0), "bigears":Vector3(0,.24,.22),
	"escape":Vector3(0,-.3,0), "depthl":Vector3(0,-.08,-.35),
	"attract":Vector3(0,.22,.22), "rover":Vector3(0,-.125,-.35),
	"bubble":Vector3(0,.22,-.35), "repel":Vector3(0,.22,.22),
	"strobe":Vector3(0,.255,.25), "flarel":Vector3(-.12,.15,0),
	"sflarel":Vector3(-.12,.15,0), "woosh":Vector3(0,.25,.1),
	"missile":Vector3(-.12,.15,0), "ripper":Vector3(0,.25,.2),
	"electro":Vector3(.12,.18,.05),
}
var game: Node
var checks := 0
var failures := 0

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-original-mounts-fixtures"; storage.ensure_parent(storage.preferences_path())
	var config := ConfigFile.new()
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	config.set_value("game","folder",folder); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game loads")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.set_process(false); game.docking.set_physics_process(false)
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.weapons.set_physics_process(false)
	game.equipment.extra_tools.set_physics_process(false); game.equipment.support_tools.set_physics_process(false)
	game.pilot.active = true; game.pilot.controls_enabled = true; game.pilot.pending_reset = false
	game.pilot.global_position = Vector3(0,game.pilot.surface_height-2,0)
	game.pilot.rotation = Vector3(.2,.8,-.1)
	var hull: Node3D = game.pilot.visual.get_node("Hull")
	var all := {}
	for item in game.equipment.available: all[item.id] = item.mount
	all.zapper = game.weapons.muzzle; all.depthl = game.weapons.depth_mount
	all.merge(game.weapons.arsenal.mounts)
	check(all.size() == POINTS.size(),"Every implemented socket has original evidence")
	for id in POINTS:
		var mount: Node3D = all[id]
		check(hull.to_local(mount.global_position).distance_to(POINTS[id]) < 0.0001,"Saved original hull-relative position: "+id)
		check(mount.scale.is_equal_approx(Vector3.ONE),"Original equipment keeps its native model size: "+id)
		var expected: Basis = hull.global_basis * Basis(Vector3.RIGHT,deg_to_rad(50) if id in ["depthl","rover"] else 0.0)
		var wrapper: Node3D = mount.get_child(0) if mount.get_child_count() > 0 else null
		if wrapper != null:
			check(wrapper.global_basis.is_equal_approx(expected),"Housing orientation, including tilt exactly once: "+id)
		var fallback := Node3D.new(); game.pilot.add_child(fallback)
		Mounts.apply(fallback,game.pilot.visual,id,"res://tests/absent-original-mounts.json")
		check(fallback.transform.is_equal_approx(mount.transform),"Built-in default agrees with saved profile: "+id)
		fallback.free()
	check(game.equipment.lamp.global_position.is_equal_approx(hull.to_global(POINTS.deep_sea_lights)),"Deep-sea beam starts at the original light frame")
	check(game.equipment.extra_tools.strobe.global_position.is_equal_approx(hull.to_global(Vector3(0,.25,.3))),"Strobe light uses its separate original frame")
	var zapper: Node3D = game.weapons.muzzle
	check(zapper.get_node("Emitter").global_position.is_equal_approx(hull.to_global(Vector3(0,.22,.22))),"Regular Zapper arc origin")
	game.weapons.set_upgraded(true)
	check(zapper.get_node("Emitter").global_position.is_equal_approx(hull.to_global(Vector3(.15,.17,.17))),"First upgraded Zapper arc origin")
	check(zapper.get_node("SecondEmitter").global_position.is_equal_approx(hull.to_global(Vector3(-.15,.17,.17))),"Second upgraded Zapper arc origin")
	game.weapons.set_upgraded(false)
	var arsenal: Node3D = game.weapons.arsenal
	for id in ["missile","homers","electro"]:
		arsenal._launch(id)
		var shot: Node3D = arsenal.shots.back(); shot.set_physics_process(false)
		var point := Vector3(.12,.18,.35) if id == "electro" else Vector3(-.12,.15,0)
		check(shot.global_position.is_equal_approx(hull.to_global(point)),"Actual projectile spawn matches original callback: "+id)
		check(shot.direction.is_equal_approx(-game.pilot.global_basis.z),"Actual projectile heading follows the sub: "+id)
	arsenal._ripper_tick()
	check(arsenal.tracer_from.is_equal_approx(hull.to_global(Vector3(0,.25,.2))),"Ripper uses original firing origin")
	for id in ["flarel","sflarel"]:
		game.equipment.extra_tools.flare_cooldown = 0
		game.equipment.extra_tools.activate(id)
		var flare: Node3D = game.equipment.extra_tools.flares.back(); flare.set_physics_process(false)
		check(flare.global_position.is_equal_approx(hull.to_global(Vector3(-.12,.15,0))),"Flare launch uses shared original launcher socket: "+id)
	game.player_progress.ammunition.bigears = 5; game.equipment.support_tools.fire_listening()
	var probe: Node3D = game.equipment.support_tools.projectiles.back(); probe.freeze = true; probe.set_physics_process(false)
	check(probe.global_position.is_equal_approx(hull.to_global(Vector3(0,.24,.26))),"Big Ears probe starts .04 ahead of its housing")
	game.player_progress.hold.depth = 4; game.weapons.set_installed(["depthl"]); game.weapons.select_id("depthl")
	game.equipment.support_tools.fire_depth(true)
	var charge: Node3D = game.equipment.support_tools.projectiles.back(); charge.freeze = true; charge.set_physics_process(false)
	check(charge.global_position.is_equal_approx(hull.to_global(Vector3(0,-.08,-.35))),"Depth charge uses original rear underside origin")
	var rover: Node3D = game.equipment.support_tools.rover
	game.equipment.set_installed(["rover"]); rover.set_deployed(true); rover.set_physics_process(false)
	check(rover.global_transform.is_equal_approx(all.rover.global_transform),"ROV deploys from its actual tilted socket")
	check(not all.rover.get_child(0).visible,"Stowed ROV is hidden during deployment")
	rover.reset()
	check(all.rover.get_child(0).visible,"Recovered ROV restores the stowed housing")
	game.weapons.set_installed(["electro"]); game.weapons.select_id("electro")
	game.player_progress.ammunition.electro = 99
	var pose: Transform3D = all.electro.transform
	arsenal.update(true,0); arsenal.update(false,.5)
	check(arsenal.electro_housing.position.z < -.012 and all.electro.transform == pose,"Electro charge moves the housing without changing its socket/profile")
	arsenal.update(false,1)
	check(is_equal_approx(arsenal.electro_housing.position.z,.2),"Electro housing retracts after firing")
	arsenal.update(false,.4)
	check(arsenal.electro_housing.position.is_zero_approx(),"Electro housing returns to its original resting position")
	arsenal.reset(); game.equipment.reset_towing()
	# Custom replacement profiles and explicit edits still override the baseline.
	var replacement := Node3D.new(); replacement.set_meta("asset_mod","Test replacement"); replacement.set_meta("asset_source","custom.glb")
	var custom := Node3D.new(); custom.position = Vector3(1,2,3); custom.rotation = Vector3(.1,.2,.3); custom.scale = Vector3.ONE*1.5
	var custom_pose := custom.transform
	Mounts.apply(custom,replacement,"depthl","res://tests/absent-original-mounts.json")
	check(custom.transform == custom_pose,"Original defaults leave a replacement's own socket unchanged")
	var fixture := "res://tests/cache-original-mounts-fixtures/mounts.json"
	check(Mounts.save(replacement,{"depthl":custom},fixture) == OK,"Replacement profile can be saved")
	var restored := Node3D.new(); Mounts.apply(restored,replacement,"depthl",fixture)
	check(restored.transform.is_equal_approx(custom_pose),"Replacement profile position/orientation/scale round-trip")
	custom.position += Vector3(.12,.03,-.02)
	check(Mounts.save(game.pilot.visual,{"depthl":custom},fixture) == OK,"Original-sub mount edits can still be saved")
	Mounts.apply(restored,game.pilot.visual,"depthl",fixture)
	check(restored.transform.is_equal_approx(custom.transform),"New authored original-sub edits override the recovered default")
	replacement.free(); custom.free(); restored.free()
	if DisplayServer.get_name() != "headless":
		var panel := preload("res://mount_editor.gd").new(); root.add_child(panel); panel.open(game.game_folder)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.viewport.get_parent().stretch = false
		panel.viewport.get_parent().custom_minimum_size = Vector2(640,480)
		panel.viewport.size = Vector2i(640,480)
		for id in POINTS:
			panel.camera.position = Vector3(1.4,-.7,1.5) if id in ["suckomat","magnet","grapple","escape","depthl","rover"] else Vector3(1.4,.7,-1.5)
			panel.camera.look_at(Vector3(0,0,0))
			for key in panel.mounts: panel.mounts[key].visible = key == id
			await process_frame; await RenderingServer.frame_post_draw
			panel.viewport.get_texture().get_image().save_png("res://../.local/mount-research/"+id+".png")
		panel.queue_free()
	print("Original equipment mounts: %d checks, %d failures" % [checks,failures])
	game.queue_free(); await process_frame; quit(1 if failures else 0)
