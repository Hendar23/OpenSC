extends CharacterBody3D
## Physical hull after a fatal hit, independent of the retired gameplay actor.

signal detonated
enum Fall { INSTANT, SPIN, ARC }
const Explosion = preload("res://mine_explosion.gd")
const Debris = preload("res://submarine_death.gd")
const MAX_FALL_TIME := 6.0
const BURST_INTERVAL := 0.55
var fall := Fall.INSTANT
var elapsed := 0.0
var burst_clock := BURST_INTERVAL
var visual: Node3D
var bounds: AABB
var frames: Array[Texture2D]
var sound: AudioStream
var bubbles: Texture2D
var bubble_emitter: Node3D
var blast: Callable
var player: Node3D
var track_player := false
var finished := false
var bumped_player := false
var spin := 1.0
var initial_heading := 0.0

static func choose_fall(speed: float, roll: float) -> Fall:
	if roll < 0.2: return Fall.INSTANT
	return Fall.ARC if speed >= 0.85 else Fall.SPIN

static func launch(traffic: Node, hull: Node3D, sources: Array[Node3D], momentum: Vector3 = Vector3.ZERO, follows_player: bool = false) -> CharacterBody3D:
	var wreck := new()
	traffic.get_parent().add_child(wreck)
	wreck.global_transform = Transform3D(hull.global_basis.orthonormalized(),hull.global_position)
	wreck.frames = traffic.explosion_frames
	wreck.sound = traffic.explosion_sound
	wreck.bubbles = traffic.bubble_texture
	wreck.bubble_emitter = traffic.bubbles
	wreck.blast = traffic.wreck_blast
	wreck.player = traffic.player
	wreck.track_player = follows_player
	wreck.setup(sources,momentum,choose_fall(momentum.length(),randf()))
	return wreck

static func launch_boss(traffic: Node, boss: Node3D) -> void:
	var wreck := launch(traffic,boss,[boss])
	wreck.add_to_group("base_destruction")
	boss.hide()
	if boss is CollisionObject3D:
		boss.set_deferred("collision_layer",0)
		boss.set_deferred("collision_mask",0)
	for body in boss.find_children("*","CollisionObject3D",true,false):
		body.set_deferred("collision_layer",0)
		body.set_deferred("collision_mask",0)
	boss.reparent(wreck,true)

func setup(sources: Array[Node3D], momentum: Vector3, style: Fall) -> void:
	name = "FallingSubmarine"
	fall = style
	velocity = momentum
	visual = Node3D.new(); add_child(visual)
	for source in sources:
		if is_instance_valid(source): _copy_hull(source)
	if not visual.get_child_count(): bounds = AABB(Vector3.ONE * -0.3,Vector3.ONE * 0.6)
	if fall == Fall.INSTANT:
		call_deferred("_detonate")
		return
	# Sweep a conservative hull shape through actual cave and seabed geometry.
	var shape := BoxShape3D.new(); shape.size = (bounds.size * 0.82).max(Vector3.ONE * 0.12)
	var hull := CollisionShape3D.new(); hull.shape = shape; hull.position = bounds.get_center(); add_child(hull)
	collision_layer = 8
	collision_mask = 1 | 2 | 8
	motion_mode = MOTION_MODE_FLOATING
	if track_player and is_instance_valid(player): add_collision_exception_with(player)
	initial_heading = global_basis.get_euler().y
	spin = -1.0 if randf() < 0.5 else 1.0
	if fall == Fall.SPIN: velocity *= 0.35
	reset_physics_interpolation()

func _copy_hull(source: Node3D) -> void:
	var meshes := source.find_children("*","MeshInstance3D",true,false)
	if source is MeshInstance3D: meshes.push_front(source)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or mesh.get_meta("exclude_from_debris",false): continue
		var ancestor := mesh as Node3D
		while ancestor != source and ancestor.visible and not ancestor.get_meta("exclude_from_debris",false):
			ancestor = ancestor.get_parent() as Node3D
		if ancestor != source: continue
		var copy := MeshInstance3D.new()
		copy.mesh = mesh.mesh; copy.material_override = mesh.material_override
		copy.layers = mesh.layers; copy.cast_shadow = mesh.cast_shadow
		for index in mesh.mesh.get_surface_count():
			copy.set_surface_override_material(index,mesh.get_surface_override_material(index))
		visual.add_child(copy); copy.global_transform = mesh.global_transform
		var box: AABB = copy.transform * copy.get_aabb()
		bounds = box if visual.get_child_count() == 1 else bounds.merge(box)

func _physics_process(delta: float) -> void:
	if fall == Fall.INSTANT or finished: return
	elapsed += delta
	var drag := exp(-delta * (1.4 if fall == Fall.SPIN else 0.42))
	velocity.x *= drag; velocity.z *= drag
	velocity.y = maxf(-5.5,velocity.y - 2.2 * delta)
	var hit := move_and_collide(velocity * delta)
	if hit != null and hit.get_collider() == player:
		if not bumped_player and is_instance_valid(player) and player.has_method("receive_towing_impulse") and not player.dead:
			bumped_player = true
			player.receive_towing_impulse(-hit.get_normal() * clampf(velocity.length() * player.mass * 0.45,1.0,45.0),hit.get_position() - player.global_position)
		velocity = velocity.slide(hit.get_normal())
	elif hit != null:
		_detonate()
		return
	var turn := initial_heading + elapsed * spin * (1.8 if fall == Fall.SPIN else 0.24)
	var pitch := 0.0 if fall == Fall.SPIN else atan2(velocity.y,maxf(0.25,Vector2(velocity.x,velocity.z).length())) * 0.75
	var roll := 0.09 if fall == Fall.SPIN else 0.45
	global_basis = global_basis.slerp(Basis.from_euler(Vector3(pitch,turn,roll * spin)),1.0 - exp(-4.0 * delta))
	_follow_player()
	if elapsed >= MAX_FALL_TIME:
		_detonate()
		return
	burst_clock += delta
	if burst_clock >= BURST_INTERVAL:
		burst_clock -= BURST_INTERVAL
		var spread := bounds.size * Vector3(randf_range(-0.4,0.4),0.42,randf_range(-0.4,0.4))
		_burst(to_global(bounds.get_center() + spread),clampf(bounds.size.length() * 0.25,0.2,1.2),false)

func _follow_player() -> void:
	if track_player and is_instance_valid(player) and player.dead:
		player.global_position = global_position

func _detonate() -> void:
	if finished: return
	finished = true
	set_physics_process(false)
	collision_layer = 0; collision_mask = 0
	_follow_player()
	var point := to_global(bounds.get_center())
	var diameter := clampf(bounds.size.length(),0.65,8.0)
	_burst(point,diameter,true)
	var debris := Debris.new(); get_parent().add_child(debris); debris.global_position = point
	debris.setup_machine(self,visual,null if is_instance_valid(bubble_emitter) else bubbles,[],velocity * 0.35)
	if is_instance_valid(bubble_emitter): bubble_emitter.emit_blast_cloud(point,diameter)
	if is_in_group("trader_wrecks"):
		remove_from_group("trader_wrecks")
		debris.add_to_group("trader_wrecks")
	hide()
	if blast.is_valid():
		blast.call(point,clampf(diameter * 9.0,8.0,52.0),clampf(diameter * 1.75,1.8,11.0),clampf(diameter * 35.0,24.0,180.0))
	detonated.emit()
	queue_free()

func _burst(point: Vector3, diameter: float, main: bool) -> void:
	var effect := Explosion.new(); get_parent().add_child(effect)
	effect.global_position = point
	effect.setup(frames,diameter,sound if main else null,main)
