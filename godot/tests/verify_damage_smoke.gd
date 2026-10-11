extends SceneTree
const Pilot = preload("res://submarine_controller.gd")
const Effect = preload("res://submarine_damage_smoke.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var sub := Pilot.new(); sub.remember_settings = false; root.add_child(sub)
	sub.set_physics_process(false)
	sub.visual = Node3D.new(); sub.add_child(sub.visual)
	sub.visual.rotation.y = PI; sub.visual.scale = Vector3.ONE * 0.8
	sub.setup_damage_smoke(folder)
	var smoke: Node3D = sub.damage_smoke; smoke.set_process(false)
	check(smoke.textures.all(func(texture: Texture2D) -> bool: return texture != null),"Damage smoke loads original masked textures")
	sub.restore_health(100,15); smoke._process(0.2)
	check(not smoke.enabled and smoke.puffs.is_empty(),"Exact 15 point boundary does not smoke")
	sub.active = true; sub.take_damage(1,Vector3.ZERO,false)
	smoke._process(0.2)
	check(smoke.enabled and not smoke.puffs.is_empty(),"Damage crossing threshold starts smoke through health signal")
	var lighting := preload("res://natural_light.gd").new()
	lighting.attach(sub); smoke._process(0.1)
	check(smoke.puffs[0].node.material_override is ShaderMaterial and float(smoke.puffs[0].node.material_override.get_shader_parameter("opacity")) > 0.0,"Lighting attachment preserves animated smoke opacity")
	check(smoke.emission_origin().is_equal_approx(sub.visual.global_transform * Vector3(0,0,-0.5)),"Emission follows transformed original hull offset")
	var puff: Dictionary = smoke.puffs[0]
	var initial: Vector3 = puff.node.global_position
	sub.position.x += 10
	smoke._process(0.1)
	check(puff.node.global_position.distance_to(initial) < 0.1,"Emitted smoke remains behind moving hull")
	check(smoke.emission_origin().x > 9,"New smoke follows moved hull")
	sub.visual.hide(); smoke._process(0.2)
	check(not smoke.enabled,"Hidden docked hull stops producing smoke")
	sub.visual.show(); smoke._process(0.2)
	check(smoke.enabled,"Visible damaged hull resumes smoke")
	sub.restore_health(100,8)
	check(smoke.enabled and smoke.puffs.is_empty(),"Loading damaged health resets old wake and activates effect")
	smoke._process(0.2); sub.restore_health()
	check(not smoke.enabled and smoke.puffs.is_empty(),"Restoring health clears smoke for new game")
	# NPCs can use the component with any Node3D hull and their own health system.
	var npc := Node3D.new(); root.add_child(npc)
	var npc_smoke := Effect.new(); npc.add_child(npc_smoke); npc_smoke.setup(npc,folder); npc_smoke.set_process(false)
	npc_smoke.trigger_health = 30; npc_smoke.set_health(20,200); npc_smoke._process(0.2)
	check(npc_smoke.enabled and not smoke.enabled,"NPC effect works independently with a type-specific threshold")
	npc_smoke.set_health(30,200); npc_smoke._process(0.2)
	check(not npc_smoke.enabled and not npc_smoke.puffs.is_empty(),"Repairs stop new emissions while existing puffs fade")
	for frame in range(70): npc_smoke._process(0.1)
	check(npc_smoke.puffs.is_empty(),"Repaired sub smoke dissipates")
	sub.restore_health(100,10); sub.take_damage(1000,Vector3.ZERO,false); smoke._process(0.2)
	check(sub.dead and not smoke.enabled,"Destruction stops damage smoke")
	sub.setup_damage_smoke(folder)
	check(sub.health_changed.get_connections().size() == 1,"Reinitialization replaces health listener cleanly")
	sub.queue_free(); npc.queue_free(); await process_frame
	print("Damage smoke: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
