extends Node3D
## WALKER 00463410 -> 00463010: two rotating ports, alternating every20 ticks.
const PORTS := [Vector3(1.4,-0.1,1.1),Vector3(-1.4,-0.1,1.1)]
const INTERVAL := 20.0/25.0
var hitbox: CollisionObject3D
var bubble_trail: Node3D
var game: Node
var yaw: Node3D
var pitch: Node3D
var missile_template: Node3D
var cooldown := INTERVAL
var port := 0
var shots := 0

func setup(body: RigidBody3D, owner_game: Node) -> void:
	hitbox = body; game = owner_game; bubble_trail = game.submarine_traffic.bubbles
	# Original numbered frames2/4 correspond to the yaw head and gun atomics.
	pitch = body.appearance.find_child("Frame_2",true,false)
	yaw = body.appearance.find_child("Frame_1",true,false)
	missile_template = preload("res://clump_loader.gd").load_clump(game.game_folder.path_join("CLUMPS/MISSILE.DFF"))
	if missile_template != null: add_child(missile_template); missile_template.hide()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(hitbox) or not hitbox.visible or game.pilot.dead or not game.pilot.active: return
	if not is_instance_valid(yaw) or not is_instance_valid(pitch) or missile_template == null: return
	var target: Node3D = game.pilot
	if target.get_meta("bubble_screened",false): return
	var socket: Vector3 = pitch.to_global(PORTS[port])
	# Same bounded tracking as the original two-degree-per-25Hz-tick rotation.
	var predicted: Vector3 = target.global_position+target.linear_velocity*0.15
	var local: Vector3 = yaw.global_basis.inverse()*(predicted-socket)
	yaw.rotation.y += clampf(atan2(local.x,local.z),-deg_to_rad(50)*delta,deg_to_rad(50)*delta)
	socket = pitch.to_global(PORTS[port])
	local = pitch.global_basis.inverse()*(predicted-socket)
	pitch.rotation.x -= clampf(atan2(local.y,Vector2(local.x,local.z).length()),-deg_to_rad(50)*delta,deg_to_rad(50)*delta)
	for child in hitbox.get_children():
		if not child is CollisionShape3D or not child.has_meta("walker_visual"): continue
		var visual: Node3D = child.get_meta("walker_visual").get_ref()
		if visual != null: child.transform = hitbox.global_transform.affine_inverse()*visual.global_transform
	cooldown = maxf(0,cooldown-delta)
	socket = pitch.to_global(PORTS[port])
	var direction := socket.direction_to(predicted)
	# Outside projectile reach there is no useful local shot to simulate.
	if socket.distance_to(predicted) > 20 or cooldown > 0 or pitch.global_basis.z.dot(direction) < 0.998: return
	var query := PhysicsRayQueryParameters3D.create(socket,target.global_position,15,[hitbox.get_rid()])
	var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty() and obstruction.collider != target: return
	var missile := preload("res://turret_missile.gd").new(); game.world_root.add_child(missile)
	missile.inflict = 8.0; missile.setup(self,missile_template,socket,direction,target,false)
	missile.get_child(0).show(); port = 1-port; cooldown = INTERVAL; shots += 1

func burst(point: Vector3, size: float) -> void:
	var traffic: Node = game.submarine_traffic
	var effect := preload("res://mine_explosion.gd").new(); game.world_root.add_child(effect)
	effect.global_position = point; effect.setup(traffic.explosion_frames,size,traffic.explosion_sound)
