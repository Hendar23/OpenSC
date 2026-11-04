extends SceneTree
class Traffic extends Node:
	var navigation_ready := false
	var bubble_texture: Texture2D
	var explosion_frames: Array[Texture2D] = []
	var explosion_sound: AudioStream
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var traffic := Traffic.new(); world.add_child(traffic)
	var model := MeshInstance3D.new(); model.mesh = BoxMesh.new(); world.add_child(model); model.position.z = -2
	var ship: Node3D = preload("res://trader_submarine.gd").install(model,{})
	ship.system = traffic; ship.running = true; ship.set_physics_process(false); ship.health.configure(1,1)
	var player := RigidBody3D.new(); player.gravity_scale = 0; player.linear_damp = 0; player.can_sleep = false
	player.collision_layer = 2; player.collision_mask = 9
	var collider := CollisionShape3D.new(); var shape := SphereShape3D.new(); shape.radius = 0.4; collider.shape = shape
	player.add_child(collider); world.add_child(player)
	player.linear_velocity = Vector3.FORWARD*6
	for tick in range(60): await physics_frame
	check(player.position.z > -1.5,"Live NPC hull physically blocks the player")
	player.linear_velocity = Vector3.FORWARD*6
	ship.take_weapon_damage(100)
	check(ship.dead and not model.visible and ship.body.collision_layer == 0 and ship.body.collision_mask == 0,"Death immediately disables the hidden hull's layer and mask")
	for tick in range(60): await physics_frame
	check(player.position.z < -5.5,"Player passes through the destroyed submarine's former position under real physics")
	check(ship.body.get_children().all(func(node):return not node is CollisionShape3D or node.disabled),"Destroyed hull shapes are disabled")
	ship.set_local_simulation(false); ship.set_local_simulation(true)
	check(ship.body.collision_mask == 0,"Activity changes cannot revive a dead hull's collision mask")
	ship.reset(); ship.set_physics_process(false)
	player.position = Vector3.ZERO; player.linear_velocity = Vector3.FORWARD*6
	for tick in range(60): await physics_frame
	check(not ship.dead and ship.body.collision_mask == 11 and player.position.z > -1.5,"Respawn restores physical collision")
	world.free(); print("Destroyed submarine collision: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
