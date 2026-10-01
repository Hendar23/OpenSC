extends SceneTree
const Pilot = preload("res://submarine_controller.gd")
const Assets = preload("res://clump_loader.gd")
const Paths = preload("res://asset_paths.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(description)
func _run() -> void:
	Mods.initialize(false)
	var folder := Paths.find_game_folder()
	var bubble_texture := Assets._load_texture(folder, "BUBBLE", "BUBBLEM", {})
	check(bubble_texture != null and bubble_texture.get_image().get_format() == Image.FORMAT_RGBA8, "Original bubble sprite loads with its alpha mask")
	for modern in [false, true]:
		var enabled: Array[String] = []
		if modern: enabled.append("example.glb-submarine")
		Mods.apply(enabled, Mods.order, false)
		var pilot := Pilot.new()
		pilot.remember_settings = false
		root.add_child(pilot)
		pilot.position = Vector3(0, 10, 0)
		pilot.set_physics_process(false)
		pilot.bubbles.set_physics_process(false)
		pilot.visual = Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF"))
		pilot.visual.rotation.y = PI
		pilot.add_child(pilot.visual)
		pilot.bubbles.configure(bubble_texture)
		pilot.surface_height = 100.0
		pilot.movement.settings.bubble_rate = 24.0
		check(pilot.bubbles.material.billboard_keep_scale, "Billboard rendering preserves the small bubble sizes")
		pilot.movement.main_power = 1
		pilot.movement.left_power = 1
		pilot.movement.right_power = 1
		pilot._update_animation(0.15)
		check(pilot.propeller_speeds.is_equal_approx(Vector3.ONE), "All three propellers reach commanded speed")
		check(pilot.bubbles.particles.size() >= 9 and pilot.bubbles.particles.all(func(p: Dictionary) -> bool: return p.drift.z > 0), "Forward thrust emits bubbles aft from original and GLB propellers")
		var old_position: Vector3 = pilot.bubbles.particles[0].position
		pilot.position.x += 10
		check(pilot.bubbles.global_position.is_zero_approx() and pilot.bubbles.particles[0].position == old_position, "The wake stays in world space when the hull moves")
		pilot.movement.main_power = 0
		pilot.movement.left_power = 0
		pilot.movement.right_power = 0
		var angle: float = pilot.angles.x
		pilot._update_animation(0.1)
		check(pilot.propeller_speeds.x > 0 and pilot.propeller_speeds.x < 1 and not is_equal_approx(pilot.angles.x, angle), "Released propellers slow while continuing to rotate")
		for frame in range(60): pilot._update_animation(1.0 / 60)
		check(pilot.propeller_speeds.is_zero_approx(), "Propellers decelerate to a complete stop")
		pilot.bubbles.advance(2.0)
		check(not pilot.bubbles.particles.is_empty() and pilot.bubbles.instances.visible_instance_count > 0, "Released bubbles remain alive while rising toward the surface")
		check(pilot.bubbles.particles[0].position.y > old_position.y + 1.5 and absf(pilot.bubbles.particles[0].position.z - old_position.z) < 0.02, "Bubbles rise promptly with negligible horizontal travel")
		pilot.bubbles.advance(20.0)
		check(not pilot.bubbles.particles.is_empty(), "Deep bubbles survive well beyond the former short lifetime")
		pilot.bubbles.clear()
		pilot.movement.tilt = PI / 2
		pilot.movement.left_power = 1
		pilot._update_animation(0.15)
		check(not pilot.bubbles.particles.is_empty() and pilot.bubbles.particles.all(func(p: Dictionary) -> bool: return p.drift.y < 0), "Tilted side propellers direct the wake down while ascending")
		var below: float = pilot.bubbles.particles[0].position.y
		pilot.bubbles.advance(0.05)
		check(pilot.bubbles.particles[0].position.y > below, "Even downward-facing propellers produce bubbles that immediately rise")
		pilot.reset_at(Vector3(0, 10, 0))
		check(pilot.propeller_speeds.is_zero_approx() and pilot.bubbles.particles.is_empty(), "Reset clears propeller rotation speed and old bubbles")
		pilot.movement.main_power = -1
		pilot._update_animation(0.15)
		check(pilot.bubbles.particles.all(func(p: Dictionary) -> bool: return p.drift.z < 0), "Reverse main thrust reverses the bubble jet")
		pilot.bubbles.clear()
		pilot.visual.visible = false
		pilot._update_animation(0.1)
		check(pilot.bubbles.particles.is_empty(), "Hidden docked submarine emits no new bubbles")
		pilot.visual.visible = true
		pilot.movement.settings.bubble_rate = 0
		pilot._update_animation(0.1)
		check(pilot.bubbles.particles.is_empty(), "Bubble density zero disables new emission")
		pilot.bubbles.emit_from(0, Vector3(0, 10, 0), Vector3.BACK, 1, 10000, 100)
		for frame in range(600): pilot.bubbles.emit_from(0, Vector3(0, 10, 0), Vector3.BACK, 1, 10000, 1)
		check(pilot.bubbles.particles.size() == pilot.bubbles.MAX_BUBBLES, "Particle storage stays bounded under excessive density")
		pilot.bubbles.surface_height = 0
		pilot.bubbles.advance(0.1)
		check(pilot.bubbles.particles.is_empty(), "Bubbles disappear at the water surface")
		pilot.free()
	Mods.initialize(false)
	print("Propeller visual verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
