extends "res://tests/test_scene_tree.gd"
const Traffic = preload("res://submarine_traffic.gd")
const Trader = preload("res://trader_submarine.gd")
class FailedRoutes extends Traffic:
	var requests := 0
	var available := false
	func route(_start: Vector3,finish: Vector3) -> PackedVector3Array:
		requests += 1
		return PackedVector3Array([finish]) if available else PackedVector3Array()
	func choose_city(_agent: Node3D) -> int: return 0
class BlockedEndpoint extends Traffic:
	var anchors := 0
	func segment_clear(a: Vector3,b: Vector3) -> bool: return a != Vector3.ONE and b != Vector3.ONE
	func anchor(_point: Vector3) -> int: anchors += 1; return 0
var checks := 0
var failures := 0
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var traffic := FailedRoutes.new(); world.add_child(traffic); traffic.navigation_ready = true; traffic.set_physics_process(false)
	var model := Node3D.new(); world.add_child(model)
	var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); model.add_child(mesh)
	var ship := Trader.install(model,{}); ship.system = traffic; ship.running = true; ship.wait = 0; ship.set_physics_process(false)
	ship.flee = 8; ship.attacker = Vector3.LEFT*5
	await physics_frame
	for tick in range(120): ship._advance_motion(1.0/60.0)
	print("Failed flee routes over two seconds: ",traffic.requests)
	check(traffic.requests <= 3,"A blocked fleeing NPC retries at a bounded rate instead of every physics tick")
	check(is_equal_approx(ship.flee,6.0),"Flee countdown keeps advancing while route retries are throttled")
	traffic.available = true
	for tick in range(50): ship._advance_motion(1.0/60.0)
	check(not ship.path.is_empty() and model.position.x > 0,"Fleeing resumes promptly when a route becomes available")
	var nav := BlockedEndpoint.new(); world.add_child(nav); nav.navigation_ready = true; nav.graph.add_point(0,Vector3.ZERO)
	check(nav.route(Vector3.ONE,Vector3.ZERO).is_empty() and nav.anchors == 0,"Blocked starting position avoids an exhaustive anchor search")
	check(nav.route(Vector3.ZERO,Vector3.ONE).is_empty() and nav.anchors == 0,"Blocked destination avoids an exhaustive anchor search")
	check(nav.route(Vector3.ZERO,Vector3.RIGHT*5) == PackedVector3Array([Vector3.RIGHT*5]),"Clear direct routes retain their original destination")
	world.free(); print("NPC route budget: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
