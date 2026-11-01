extends RefCounted
## Presentation of the original capture placement and tag-5 hatch.
## 0043b540: captive position = boss position + forward*1.3 - world Y*0.3.
## 00439620: hide the tag-5 atomic when both weapon modules are defeated.
const SOS_TIME := 6.0
const LOCKED_TIME := 30.0
var boss: Node3D
var shuttle: Node3D
var body: CollisionObject3D
var hatch: Node3D
var hatch_visible := true
var initial := Transform3D.IDENTITY
var outside := Transform3D.IDENTITY
var approach_corner := Transform3D.IDENTITY
var inside := Transform3D.IDENTITY
var release_start := Transform3D.IDENTITY
var clock := 0.0
var release_clock := 0.0
var release_duration := 1.0
var releasing := false
var released := false
var layer := 0
var mask := 0

func setup(mothership: Node3D, agent: Node3D) -> void:
	boss = mothership; shuttle = agent.get_parent(); body = agent.body
	initial = shuttle.global_transform
	layer = body.collision_layer; mask = body.collision_mask
	# The source turns shuttle collision off during capture; ordinary weapons
	# must not hit prisoners through the closed hull, nor stop the scripted pull.
	body.collision_layer = 0; body.collision_mask = 0
	agent.motion.velocity = Vector3.ZERO; body.velocity = Vector3.ZERO
	for frame in boss.find_children("*","Node3D",true,false):
		if int(frame.get_meta("legacy_frame_tag",-1)) == 5: hatch = frame; break
	if hatch == null: hatch = boss.find_child("Frame_2",true,false)
	if hatch != null: hatch_visible = hatch.visible
	inside = Transform3D(boss.global_basis,boss.global_position+boss.global_basis.z*1.3-Vector3.UP*0.3)
	var geometry = preload("res://submarine_equipment.gd")
	var ship_bounds: AABB = agent.bounds
	var mouth_z := 2.13
	if hatch != null:
		var pieces: Array = geometry._meshes(hatch,boss.global_transform.affine_inverse()*hatch.get_parent().global_transform)
		if not pieces.is_empty(): mouth_z = geometry._bounds(pieces).end.z
	# Clear the entire hull before closing the hatch or returning navigation
	# control. This also accommodates replacement shuttle meshes of other sizes.
	outside = inside
	outside.origin = boss.to_global(Vector3(0,0,mouth_z-minf(0,ship_bounds.position.z)+0.15))-Vector3.UP*0.3
	approach_corner = outside
	var corner := boss.to_local(initial.origin)
	corner.z = maxf(corner.z,boss.to_local(outside.origin).z)
	approach_corner.origin = boss.to_global(corner)
	_open(true)
	body.reset_physics_interpolation()

func step(delta: float) -> void:
	if not is_instance_valid(shuttle) or not is_instance_valid(boss): return
	if releasing:
		release_clock = minf(release_duration,release_clock+delta)
		shuttle.global_transform = release_start.interpolate_with(outside,release_clock/release_duration)
		if release_clock >= release_duration:
			released = true; restore_collision()
		return
	clock = minf(LOCKED_TIME,clock+delta)
	if clock <= SOS_TIME*0.5:
		shuttle.global_transform = initial.interpolate_with(approach_corner,smoothstep(0,SOS_TIME*0.5,clock))
	elif clock <= SOS_TIME:
		shuttle.global_transform = approach_corner.interpolate_with(outside,smoothstep(SOS_TIME*0.5,SOS_TIME,clock))
	else:
		shuttle.global_transform = outside.interpolate_with(inside,smoothstep(SOS_TIME,LOCKED_TIME,clock))
	_open(clock < LOCKED_TIME)

func release(speed: float) -> void:
	releasing = true; release_start = shuttle.global_transform
	if clock < SOS_TIME:
		# An early rescue leaves the still-outside shuttle where it is. Do not
		# pull it back toward a defeated ship simply to play the exit animation.
		outside = release_start
	release_duration = maxf(0.04,release_start.origin.distance_to(outside.origin)/maxf(0.1,speed))
	_open(true)

func restore_collision() -> void:
	if is_instance_valid(body):
		body.collision_layer = layer; body.collision_mask = mask

func clear() -> void:
	restore_collision()
	if is_instance_valid(hatch): hatch.visible = hatch_visible

func _open(value: bool) -> void:
	if is_instance_valid(hatch): hatch.visible = hatch_visible and not value
