extends SceneTree
const Game = preload("res://game.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Game loads for submarine damage")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.set_physics_process(false)
	game.pilot.freeze = true; game.pilot.controls_enabled = true
	var gauge: Control = game.cockpit_hud.displays[4]
	check(range(8).all(func(index: int) -> bool: return gauge.shield_segment_state(index) == "blue"),"An undamaged sub has eight blue shield segments")
	await physics_frame
	game.object_population._exploded(game.pilot.global_position,30.0,0.2,0.0)
	await process_frame; await process_frame
	check(is_equal_approx(game.pilot.health,70.0),"Explosion overlapping the real hull damages it only once")
	check(game._dock_ui_model().status.shields == 70 and game._dock_ui_model().status.hull_strength == 100,"Dock status follows current shield health and maximum hull strength")
	check(gauge.shield_segment_state(0) == "empty" and gauge.shield_segment_state(1) == "empty" and gauge.shield_segment_state(2) == "orange" and gauge.shield_segment_state(3) == "blue","Damage removes segments and advances the orange boundary")
	game.pilot.controls_enabled = false
	game.pilot.take_damage(50)
	check(game.pilot.health == 70,"Docking and disabled controls prevent damage")
	game.pilot.controls_enabled = true
	game.pilot.take_damage(-10); game.pilot.take_damage(NAN)
	check(game.pilot.health == 70,"Negative and invalid damage cannot heal or corrupt shields")
	game.player_progress.status.hull_strength = 180; game.pilot.hull_rating = 180
	game.pilot.restore_health(100,50)
	check(game._dock_ui_model().status.shields == 50 and game._dock_ui_model().status.hull_strength == 180,"Shield charge updates leave the applied hull upgrade unchanged")
	game.player_progress.status.hull_strength = 100; game.pilot.hull_rating = 100
	game.pilot.restore_health()
	game._set_camera_mode(true)
	game.pilot.take_damage(1000)
	check(game.pilot.dead and game.pilot.health == 0 and not game.pilot.active and not game.pilot.controls_enabled,"Fatal damage stops the submarine and clamps shields to zero")
	check(not game.first_person and game.camera.cull_mask & game.SUB_RENDER_LAYER != 0,"Destruction leaves cockpit view for third person")
	var wreck: Node3D = game.world_root.get_node_or_null("SubmarineWreck")
	check(wreck != null and wreck.pieces.size() > 8 and wreck.gore.is_empty(),"The actual sub and mounted equipment become textured metal pieces without blood")
	check(wreck.pieces.all(func(piece: Dictionary) -> bool: return piece.velocity.length() <= 2.51),"Submarine fragments use a gentler burst to remain near the wreck")
	check(wreck.bubbles != null and wreck.bubbles.amount == 96 and wreck.bubbles.lifetime > 2.0,"Destruction releases a substantial burst of rising bubbles")
	check(game.world_root.get_node_or_null("MineExplosion") != null and not game.pilot.visual.visible and not game.weapons.visible,"Original explosion animation replaces the intact submarine")
	check(range(8).all(func(index: int) -> bool: return gauge.shield_segment_state(index) == "empty"),"Destroyed sub has no remaining health segments")
	var before := game.world_root.get_child_count()
	game.pilot.take_damage(30)
	check(game.world_root.get_child_count() == before,"Destroyed sub cannot explode a second time")
	for frame in range(8): await process_frame
	check(not game.front_end.menu_layer.visible and not paused,"Death stays at the wreck until the player opens the main menu")
	check(game.docking.message.is_empty() and game.docking.nearby.is_empty(),"Destroyed submarine no longer receives docking prompts")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/submarine-destruction-preview.png")
	game._show_main_menu()
	check(not game.front_end.is_button_available("continue") and game.front_end.is_button_available("new_game"),"Main menu cannot resume a destroyed sub")
	game._begin_new_game()
	check(not game.pilot.dead and game.pilot.health == 100 and game.pilot.visual.visible and game.weapons.visible and game.pilot.collision_layer == 2,"New game restores the intact submarine and collision")
	check(game.equipment.visible and game.equipment.mounted.all(func(item: Dictionary) -> bool: return item.mount.visible),"New game restores equipment hidden by the previous submarine destruction")
	check(game.world_root.get_node_or_null("SubmarineWreck") == null,"New game clears old submarine pieces")
	paused = false; game.queue_free(); await process_frame
	print("Submarine damage: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
