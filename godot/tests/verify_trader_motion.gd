extends SceneTree
const Trader = preload("res://trader_submarine.gd")
const Explosion = preload("res://mine_explosion.gd")
var checks := 0
var failures := 0
class OpenWater extends "res://submarine_traffic.gd":
	func segment_clear(_a: Vector3,_b: Vector3) -> bool: return true
	func choose_city(_agent: Node3D) -> int: return 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	preload("res://player_storage.gd").root_override = "res://tests/cache-traffic-fixtures"
	call_deferred("run")
func ship(world: Node3D, position: Vector3, traffic: Node) -> Node3D:
	var model := Node3D.new(); world.add_child(model); model.position = position
	var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); mesh.mesh.size = Vector3(0.6,0.6,1); model.add_child(mesh)
	var agent := Trader.install(model,{})
	agent.system = traffic; agent.running = true; agent.wait = 0; agent.set_physics_process(false)
	traffic.traders.append(agent); return agent
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var traffic := OpenWater.new(); world.add_child(traffic); traffic.navigation_ready = true; traffic.set_physics_process(false)
	var a := ship(world,Vector3(0,0,-8),traffic); var b := ship(world,Vector3(0,0,8),traffic)
	a.path = PackedVector3Array([Vector3(0,0,8)]); b.path = PackedVector3Array([Vector3(0,0,-8)])
	a.get_parent().basis = Basis.IDENTITY; b.get_parent().basis = Basis(Vector3.UP,PI)
	await physics_frame
	var moved_every_tick := true; var minimum := INF; var largest_step := 0.0; var passing := 0.0
	for tick in range(720):
		var previous: Vector3 = a.global_position
		a._physics_process(1.0 / 60.0); b._physics_process(1.0 / 60.0)
		var step := previous.distance_to(a.global_position)
		if tick < 100 and step < 0.000001: moved_every_tick = false
		largest_step = maxf(largest_step,step)
		minimum = minf(minimum,a.global_position.distance_to(b.global_position))
		passing = maxf(passing,absf(a.global_position.x))
		await physics_frame
	check(moved_every_tick,"Visible motion advances every physics tick")
	check(largest_step < 0.034,"No batched movement jumps")
	check(passing > 0.6,"Head-on traffic turns aside before contact")
	check(minimum > 1.2,"Head-on vessels maintain hull separation")
	check(a.global_position.z > 6 and b.global_position.z < -6,"Both vessels continue past one another")
	print("Passing separation ",minimum," lateral ",passing," end ",a.global_position," / ",b.global_position)
	# A rising route translates forward and pitches the hull throughout travel.
	b.running = false; b.body.collision_layer = 0
	a.get_parent().position = Vector3.ZERO; a.steering = Vector3.ZERO; a.path = PackedVector3Array([Vector3(0,6,12)]); a.wait = 0
	for tick in range(120): a._physics_process(1.0/60.0); await physics_frame
	check(a.global_position.y > 0.4 and a.global_position.z > 1,"Climb includes forward travel")
	check(a.get_parent().basis.z.y > 0.2,"Hull pitches into the climb")
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	traffic.bubbles = preload("res://propeller_bubbles.gd").new(); traffic.add_child(traffic.bubbles)
	traffic.bubbles.configure(preload("res://clump_loader.gd")._load_texture(folder,"BUBBLE","BUBBLEM",{}))
	traffic.bubbles.set_physics_process(false)
	var real_traders: Array[Node3D] = []
	for id in Trader.MODELS:
		var model := preload("res://map_document.gd").load_model(id,folder); world.add_child(model)
		var agent := Trader.install(model,{}); agent.system = traffic; agent.running = true; agent.speed = 2; agent.propeller_power = 1; agent.set_physics_process(false)
		real_traders.append(agent)
	check(real_traders[0].propeller != null and real_traders[1].twin_exhaust,"Original models resolve propeller and twin exhaust")
	var rest: Basis = real_traders[0].propeller.basis
	real_traders[0]._propulsion(0.07)
	check(not real_traders[0].propeller.basis.is_equal_approx(rest),"Bohine propeller animates with propulsion")
	traffic.bubbles.clear()
	for tick in range(10):
		for agent in real_traders: agent._propulsion(0.1)
	check(traffic.bubbles.particles.size() >= 22,"Both traders continuously produce their own wakes")
	check(traffic.bubbles.particles.any(func(particle: Dictionary) -> bool: return particle.position.x < -0.2) and traffic.bubbles.particles.any(func(particle: Dictionary) -> bool: return particle.position.x > 0.2),"Procha bubbles emerge from both aft outlets")
	traffic.bubbles.clear()
	traffic.bubbles.emit_from(101,Vector3(-2,0,0),Vector3.BACK,1,10,0.06)
	traffic.bubbles.emit_from(102,Vector3(2,0,0),Vector3.BACK,1,10,0.06)
	check(traffic.bubbles.particles.is_empty(),"Separate ships cannot spend each other's fractional emission")
	traffic.bubbles.emit_from(101,Vector3(-2,0,0),Vector3.BACK,1,10,0.06)
	traffic.bubbles.emit_from(102,Vector3(2,0,0),Vector3.BACK,1,10,0.06)
	check(traffic.bubbles.particles.size() == 2,"Each ship retains its fractional emission credit")
	var wreck := preload("res://submarine_death.gd").new(); world.add_child(wreck)
	var inherited := Vector3(0.5,0,0)
	wreck.setup_machine(real_traders[0].get_parent(),real_traders[0].get_parent(),null,[],inherited); wreck.set_process(false)
	check(not wreck.pieces.is_empty() and wreck.pieces.all(func(piece: Dictionary) -> bool: return piece.velocity.y >= 1.5 and (piece.velocity - inherited).length() <= 7.0),"Debris gets stronger upward scatter while preserving inherited motion")
	var frames := Explosion.load_frames(folder)
	check(frames.size() == 12 and Explosion.smoke_frames.size() == 3,"Original explosion and smoke BMPs load")
	Explosion.enhanced_enabled = true
	var burst := Explosion.new(); world.add_child(burst); burst.setup(frames,2,null); burst.set_process(false); burst._process(0.5)
	check(burst.lobes.size() == 8 and burst.clouds.size() == 12,"Enhanced explosion has bounded layered bursts and smoke")
	check(burst.lobes[0].node.visible and burst.clouds[0].node.visible,"Burst and smoke overlap")
	for index in range(12):
		var extra := Explosion.new(); world.add_child(extra); extra.setup(frames,1,null); extra.set_process(false)
	check(get_nodes_in_group("enhanced_explosions").size() == 12,"Chain explosions cap enhanced effects at twelve")
	Explosion.enhanced_enabled = false
	var classic := Explosion.new(); world.add_child(classic); classic.setup(frames,2,null); classic.set_process(false)
	check(classic.lobes.is_empty() and classic.clouds.is_empty() and classic.sprite != null,"Classic mode retains the original single sprite")
	var camera := Camera3D.new(); world.add_child(camera); camera.current = true
	var shake := preload("res://explosion_camera_shake.gd").new(); camera.add_child(shake); shake.set_process(false)
	shake.blast(Vector3(100,0,0),2); check(shake.strength == 0,"Distant explosion does not shake camera")
	shake.blast(Vector3.ZERO,2); shake._process(0.01)
	check(shake.strength > 0 and camera.h_offset != 0,"Nearby explosion shakes view")
	shake.observer = a; camera.position = Vector3(100,0,0); shake.strength = 0; shake.blast(a.global_position,2)
	check(shake.strength > 0,"Shake proximity follows the sub when camera is zoomed out")
	for tick in range(120): shake._process(0.0167)
	check(camera.h_offset == 0 and camera.v_offset == 0,"Shake settles without altering camera pose")
	var menu := preload("res://gameplay_menu.gd").new(); menu.settings_path = "res://tests/cache-traffic-fixtures/effect-options.cfg"; menu.remember_preferences = false; root.add_child(menu)
	check(menu.explosion_button.text == "Explosions: Enhanced","General options expose enhanced explosions")
	menu._toggle_explosions(); check(not Explosion.enhanced_enabled and menu.explosion_button.text.ends_with("Classic"),"General option switches classic effects")
	menu.remember_preferences = true; menu._save(); menu.free()
	menu = preload("res://gameplay_menu.gd").new(); menu.settings_path = "res://tests/cache-traffic-fixtures/effect-options.cfg"; root.add_child(menu)
	check(not menu.enhanced_explosions and not Explosion.enhanced_enabled,"Explosion preference persists")
	menu.free(); world.free(); Explosion.enhanced_enabled = true
	print("Trader motion and explosions: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
