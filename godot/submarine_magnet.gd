extends Node3D
signal state_changed(on: bool)
const Assets = preload("res://clump_loader.gd")
const Mounts = preload("res://submarine_equipment.gd")
const LINK_COUNT := 4
const CHAIN_LAYER := 32
const CHAIN_RADIUS := 0.008
const CARGO_QUERY_LAYER := 64
class CableBody extends RigidBody3D:
 var water := 0.0
 var drop_limit := 0.0
 var water_drag := 4.0
 func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
  var submerged := state.transform.origin.y < water
  state.linear_velocity += Vector3.DOWN * (1.2 if submerged else 9.8) * state.step
  if submerged:
   state.linear_velocity *= exp(-water_drag * state.step)
   state.angular_velocity *= exp(-8.0 * state.step)
  if drop_limit > 0: state.linear_velocity.y = maxf(state.linear_velocity.y,-drop_limit)
var tool_id := "magnet"
var pilot: RigidBody3D
var housing: Node3D
var chain_template: Node3D
var chain_bounds := AABB()
var chain_has_pose := false
var rig: Node3D
var head: CableBody
var links: Array[Node3D] = []
var link_colliders: Array[CollisionShape3D] = []
var target_chain_mask := false
var target_query_layer := false
var drop_points: Array[Node] = []
var delivery_point: Node
var declined_point: Node
var target: RigidBody3D
var clamp_joint: Generic6DOFJoint3D
var enabled := false
var retracting := false
var deploying := false
var paid_length := 0.0
var head_socket := Vector3.ZERO
var chain_length := 0.3
var speed := 0.8
var water_drag := 4.0
var cargo_weight := 25.0
var pitch_influence := 0.25
var volume_db := -16.0
var deploy_audio: AudioStreamPlayer
var clamp_audio: AudioStreamPlayer
func setup(player: RigidBody3D, appearance: Node3D, folder: String) -> void:
 pilot = player; housing = appearance
 chain_template = Assets.load_clump(folder.path_join("CLUMPS/LINE.DFF" if tool_id == "grapple" else "CLUMPS/CHAIN.DFF"),PackedStringArray(),true)
 if tool_id == "grapple" and chain_template != null:
  var rope_bounds := Mounts._bounds(Mounts._meshes(chain_template,Transform3D.IDENTITY))
  if rope_bounds.size.x > rope_bounds.size.y and rope_bounds.size.x >= rope_bounds.size.z: chain_template.rotation.z += PI / 2.0
  elif rope_bounds.size.z > rope_bounds.size.y: chain_template.rotation.x += PI / 2.0
  var rope := chain_template
  chain_template = Node3D.new(); chain_template.add_child(rope)
 if chain_template != null:
  var first := true
  for entry in Mounts._meshes(chain_template,Transform3D.IDENTITY):
   for surface in range(entry.mesh.get_surface_count()):
    var poses: Array = entry.mesh.surface_get_blend_shape_arrays(surface)
    chain_has_pose = chain_has_pose or not poses.is_empty()
    var arrays: Array = poses.back() if not poses.is_empty() else entry.mesh.surface_get_arrays(surface)
    for vertex in arrays[Mesh.ARRAY_VERTEX]:
     var point: Vector3 = entry.pose * vertex
     if first: chain_bounds = AABB(point,Vector3.ZERO); first = false
     else: chain_bounds = chain_bounds.expand(point)
 deploy_audio = AudioStreamPlayer.new(); deploy_audio.stream = preload("res://submarine_weapons.gd")._sound(folder,"audio.equipment." + tool_id + ".deploy","GRAPPLE" if tool_id == "grapple" else "MAG1"); add_child(deploy_audio)
 clamp_audio = AudioStreamPlayer.new(); clamp_audio.stream = preload("res://submarine_weapons.gd")._sound(folder,"audio.equipment." + tool_id + ".attach","GRAPPLE" if tool_id == "grapple" else "MAG3"); add_child(clamp_audio)
func set_enabled(on: bool) -> void:
 if on == enabled: return
 if on and (housing == null or chain_template == null or not is_instance_valid(pilot) or not pilot.active or not pilot.controls_enabled or pilot.dead):
  state_changed.emit(false); return
 enabled = on
 if on:
  if is_instance_valid(rig): _clear_rig()
  _deploy()
 else:
  release()
  if is_instance_valid(head):
   deploying = false
   head.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC; head.freeze = true; retracting = true
  else: _clear_rig()
 _play(deploy_audio); state_changed.emit(enabled)
func _deploy() -> void:
 drop_points.assign(pilot.get_parent().find_children("*","Area3D",true,false).filter(func(point: Node) -> bool: return point.get_meta("editor_dropoff",false)))
 rig = Node3D.new(); rig.name = "GrappleRope" if tool_id == "grapple" else "MagnetChain"; rig.top_level = true; add_child(rig); rig.global_transform = Transform3D.IDENTITY
 rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
 links.clear()
 for index in range(LINK_COUNT):
  var visual := chain_template.duplicate() as Node3D; visual.name = ("RopeSegment%d" if tool_id == "grapple" else "ChainLink%d") % (index + 1)
  rig.add_child(visual); links.append(visual)
  for mesh in visual.find_children("*","MeshInstance3D",true,false): mesh.layers = 1
  # Kinematic contact follows each animated segment without another joint stack.
  var body := AnimatableBody3D.new(); body.name = "ChainContact%d" % (index + 1)
  body.collision_layer = CHAIN_LAYER; body.collision_mask = 0; body.sync_to_physics = false
  rig.add_child(body)
  var contact := CollisionShape3D.new(); var capsule := CapsuleShape3D.new()
  capsule.radius = CHAIN_RADIUS; capsule.height = CHAIN_RADIUS * 2.0
  contact.shape = capsule; body.add_child(contact); link_colliders.append(contact)
 head = CableBody.new(); head.name = "GrappleHead" if tool_id == "grapple" else "MagnetHead"; head.mass = 0.15; head.gravity_scale = 0.0
 head.water = float(pilot.get_parent().get_meta("surface_height",0.0)); head.water_drag = water_drag
 head.linear_damp = 0.0; head.angular_damp = 0.0; head.continuous_cd = true
 head.collision_layer = 16; head.collision_mask = 11; head.contact_monitor = true; head.max_contacts_reported = 8
 head.add_collision_exception_with(pilot)
 var visual := housing.duplicate() as Node3D; visual.scale *= global_basis.get_scale()
 var bounds := Mounts._bounds(Mounts._meshes(visual,Transform3D.IDENTITY)); visual.position -= bounds.get_center()
 head.add_child(visual)
 for mesh in visual.find_children("*","MeshInstance3D",true,false): mesh.layers = 1
 var collider := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = bounds.size.max(Vector3.ONE * 0.01); collider.shape = shape; head.add_child(collider)
 rig.add_child(head); head_socket = Vector3.UP * bounds.size.y * 0.5
 head.global_transform = Transform3D(global_basis.orthonormalized(),global_position - global_basis.orthonormalized() * head_socket)
 head.linear_velocity = pilot.linear_velocity
 head.body_entered.connect(func(body: Node) -> void: _attach.call_deferred(body))
 paid_length = 0.0; housing.hide(); retracting = false; deploying = true
 _draw_chain()
func _link_basis(up: Vector3) -> Basis:
 var y := up.normalized()
 var x := Vector3.FORWARD.cross(y).normalized()
 if x.length_squared() < 0.1: x = Vector3.RIGHT
 return Basis(x,y,x.cross(y)).orthonormalized()
func _draw_chain() -> void:
 var start := global_position
 var finish := head.to_global(head_socket)
 var slack := maxf(0.0,paid_length - start.distance_to(finish))
 var points: Array[Vector3] = [start]
 for index in range(LINK_COUNT):
  var fraction := float(index + 1) / LINK_COUNT
  points.append(start.lerp(finish,fraction) + Vector3.DOWN * sin(fraction * PI) * slack * 0.5)
 if is_instance_valid(target): _deflect_chain(points)
 var previous := start
 for index in range(LINK_COUNT):
  var next := points[index + 1]
  var length := previous.distance_to(next)
  var pose := clampf(length / maxf(chain_length / LINK_COUNT,0.001),0.0,1.0)
  var link := links[index]; link.visible = length > 0.0001
  var contact := link_colliders[index]
  contact.disabled = length < CHAIN_RADIUS * 2.0
  contact.shape.height = maxf(length,CHAIN_RADIUS * 2.0)
  contact.get_parent().global_transform = Transform3D(_link_basis(previous - next) if length > 0.0001 else Basis.IDENTITY,(previous + next) * 0.5)
  if link.visible:
   var width := (0.008 if tool_id == "grapple" else 0.02) / maxf(maxf(chain_bounds.size.x,chain_bounds.size.z),0.0001)
   var height := length / maxf(chain_bounds.size.y * (maxf(pose,0.0001) if chain_has_pose else 1.0),0.0001)
   var basis := _link_basis(previous - next)
   link.global_transform = Transform3D(basis.scaled_local(Vector3(width,height,width)),previous + basis * Vector3(-chain_bounds.get_center().x * width,-chain_bounds.end.y * height,-chain_bounds.get_center().z * width))
   for mesh in link.find_children("*","MeshInstance3D",true,false):
    for blend in range(mesh.mesh.get_blend_shape_count()): mesh.set_blend_shape_value(blend,pose if blend == mesh.mesh.get_blend_shape_count() - 1 else 0.0)
  previous = next
func _deflect_chain(points: Array[Vector3]) -> void:
 # A flexible chain bends at contact; an infinitely heavy kinematic capsule
 # must not brace the cargo against gravity and fight its magnetic clamp.
 var query := PhysicsShapeQueryParameters3D.new(); var capsule := CapsuleShape3D.new()
 capsule.radius = CHAIN_RADIUS; query.shape = capsule; query.collision_mask = CARGO_QUERY_LAYER
 var space := get_world_3d().direct_space_state
 for iteration in range(6):
  var deflected := false
  for index in range(LINK_COUNT):
   var offset := points[index] - points[index + 1]
   if offset.length() < CHAIN_RADIUS * 2.0: continue
   capsule.height = offset.length()
   query.transform = Transform3D(_link_basis(offset),(points[index] + points[index + 1]) * 0.5)
   var contacts := space.collide_shape(query,4)
   var correction := Vector3.ZERO
   for contact in range(0,contacts.size(),2):
    var penetration: Vector3 = contacts[contact + 1] - contacts[contact]
    if penetration.length_squared() > correction.length_squared(): correction = penetration
   if correction.length_squared() < 0.00000001: continue
   deflected = true
   correction *= 1.1
   if index > 0: points[index] += correction
   if index + 1 < LINK_COUNT: points[index + 1] += correction
  if not deflected: break
func _constrain_cable(delta: float) -> void:
 var offset := head.to_global(head_socket) - global_position
 var length := offset.length()
 if length < 0.0001: return
 var direction := offset / length
 var anchor_velocity := pilot.linear_velocity + pilot.angular_velocity.cross(global_position - pilot.global_position)
 var attached := is_instance_valid(target)
 var load_mass := head.mass + (target.mass if attached else 0.0)
 var center := _body_center(head)
 if attached: center = (center * head.mass + _body_center(target) * target.mass) / load_mass
 var arm := head.to_global(head_socket) - center
 var socket_velocity := head.linear_velocity + head.angular_velocity.cross(head.global_basis * head_socket)
 if attached:
  # The clamped assembly's momentum belongs primarily to its cargo. Sampling
  # only the tiny head can miss the load's pull before the clamp solver catches up.
  var assembly_velocity := (head.linear_velocity * head.mass + target.linear_velocity * target.mass) / load_mass
  socket_velocity = assembly_velocity + target.angular_velocity.cross(arm)
 var radial := (socket_velocity - anchor_velocity).dot(direction)
 if not attached:
  # Damp sideways motion relative to the socket without loading the submarine.
  var tangent := head.linear_velocity - anchor_velocity - direction * radial
  head.linear_velocity -= tangent * (1.0 - exp(-water_drag * 3.0 * delta))
 var excess := maxf(0.0,length - paid_length)
 if length < paid_length and radial <= (paid_length - length) / delta: return
 # One tension-only cable avoids the unstable four-joint/light-body stack.
 # Only attached cargo transmits cable tension back to the submarine.
 # Match cargo drag and submerged weight to the mass added to engine load.
 # The head contributes no apparent weight to the sub, even while towing.
 var cargo_scale := target.mass * cargo_weight / load_mass if attached else 0.0
 var inverse_inertia := head.get_inverse_inertia_tensor()
 if attached:
  var head_inverse := head.get_inverse_inertia_tensor()
  var cargo_inverse := target.get_inverse_inertia_tensor()
  if absf(head_inverse.determinant()) > 0.000001 and absf(cargo_inverse.determinant()) > 0.000001:
   var inertia := head_inverse.inverse()
   for contribution in [cargo_inverse.inverse(),_parallel_inertia(head.mass,_body_center(head) - center),_parallel_inertia(target.mass,_body_center(target) - center)]:
    inertia = Basis(inertia.x + contribution.x,inertia.y + contribution.y,inertia.z + contribution.z)
   inverse_inertia = inertia.inverse()
 var torque_axis := arm.cross(direction)
 var rotational_mass := torque_axis.dot(inverse_inertia * torque_axis)
 var impulse := maxf(0.0,radial + excess * 12.0) / ((0.0 if pilot.freeze else cargo_scale / pilot.mass) + 1.0 / load_mass + rotational_mass)
 if attached and not pilot.freeze:
  var pull := direction * impulse * cargo_scale
  if pilot.has_method("receive_towing_impulse"): pilot.receive_towing_impulse(pull,global_position - pilot.global_position,pitch_influence)
  else: pilot.apply_impulse(pull,global_position - pilot.global_position)
 head.linear_velocity -= direction * impulse / load_mass
 var spin := inverse_inertia * arm.cross(-direction * impulse)
 head.angular_velocity += spin
 if attached:
  target.linear_velocity -= direction * impulse / load_mass
  # The magnetic clamp stays rigid, while the cable freely pivots at its socket.
  # Apply the assembly's rotation to both centres to avoid fighting the joint.
  head.linear_velocity += spin.cross(_body_center(head) - center)
  target.linear_velocity += spin.cross(_body_center(target) - center)
  target.angular_velocity += spin
func _body_center(body: RigidBody3D) -> Vector3:
 var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
 return body.to_global(state.center_of_mass_local) if state != null else body.global_position
func _parallel_inertia(body_mass: float, offset: Vector3) -> Basis:
 var diagonal := offset.length_squared()
 return Basis(Vector3(diagonal - offset.x * offset.x,-offset.y * offset.x,-offset.z * offset.x),Vector3(-offset.x * offset.y,diagonal - offset.y * offset.y,-offset.z * offset.y),Vector3(-offset.x * offset.z,-offset.y * offset.z,diagonal - offset.z * offset.z)).scaled(Vector3.ONE * body_mass)
func _attach(body: Node) -> void:
 if not enabled or not is_instance_valid(head) or is_instance_valid(target) or not is_instance_valid(body) or not body is RigidBody3D: return
 if not body.get_meta("grapple_tow_target" if tool_id == "grapple" else "metal_tow_target",false) or body.has_meta("delivery_city") or bool(body.get("dead")) or body.freeze: return
 target = body
 # World objects inherit the non-interpolated scenery branch. Match the
 # submarine and cable's render timing so the clamp does not judder at 60 Hz.
 target.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
 target.reset_physics_interpolation()
 target_chain_mask = bool(target.collision_mask & CHAIN_LAYER)
 target.collision_mask |= CHAIN_LAYER
 target_query_layer = bool(target.collision_layer & CARGO_QUERY_LAYER)
 target.collision_layer |= CARGO_QUERY_LAYER
 for contact in link_colliders: contact.get_parent().add_collision_exception_with(target)
 _update_cargo_mass()
 clamp_joint = Generic6DOFJoint3D.new(); rig.add_child(clamp_joint); clamp_joint.global_transform = head.global_transform
 clamp_joint.node_a = clamp_joint.get_path_to(head); clamp_joint.node_b = clamp_joint.get_path_to(target)
 for axis in ["x","y","z"]:
  clamp_joint.call("set_flag_" + axis,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT,true)
  clamp_joint.call("set_flag_" + axis,Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,true)
  for parameter in [Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT]: clamp_joint.call("set_param_" + axis,parameter,0.0)
 pilot.add_collision_exception_with(target); target.sleeping = false
 _play(clamp_audio)
func release() -> void:
 delivery_point = null; declined_point = null
 if is_instance_valid(clamp_joint): clamp_joint.free()
 clamp_joint = null
 if is_instance_valid(target):
  if not target_chain_mask: target.collision_mask &= ~CHAIN_LAYER
  if not target_query_layer: target.collision_layer &= ~CARGO_QUERY_LAYER
  for contact in link_colliders: contact.get_parent().remove_collision_exception_with(target)
  if is_instance_valid(pilot): pilot.remove_collision_exception_with(target)
  target.sleeping = false
 target = null
 _update_cargo_mass()
func _update_cargo_mass() -> void:
 if is_instance_valid(pilot) and pilot.has_method("set_towed_mass"):
  pilot.set_towed_mass(target.mass * cargo_weight if is_instance_valid(target) else 0.0)
func reset() -> void:
 enabled = false; retracting = false; deploying = false
 release(); _clear_rig(); state_changed.emit(false)
 if deploy_audio != null: deploy_audio.stop()
 if clamp_audio != null: clamp_audio.stop()
func _clear_rig() -> void:
 release()
 if is_instance_valid(rig): rig.free()
 rig = null; head = null; links.clear(); link_colliders.clear()
 if is_instance_valid(housing): housing.show()
func _play(audio: AudioStreamPlayer) -> void:
 if audio == null or audio.stream == null: return
 _volume(audio); audio.play()
func _volume(audio: AudioStreamPlayer) -> void:
 var master := float(pilot.submarine_audio.tuning.settings.master_volume) if is_instance_valid(pilot) and pilot.submarine_audio != null else 0.0
 audio.volume_db = -80.0 if master <= -60.0 or volume_db <= -60.0 else master + volume_db
func _physics_process(delta: float) -> void:
 if not is_instance_valid(rig): return
 if not is_instance_valid(pilot) or pilot.dead or not pilot.visual.visible:
  reset(); return
 _volume(deploy_audio); _volume(clamp_audio)
 if not is_instance_valid(head): reset(); return
 head.water_drag = water_drag
 _update_cargo_mass()
 if retracting:
  head.add_collision_exception_with(pilot)
  var socket := head.to_global(head_socket).move_toward(global_position,speed * delta)
  head.global_position = socket - head.global_basis * head_socket
  paid_length = socket.distance_to(global_position)
  if paid_length < 0.002:
   retracting = false; _clear_rig(); return
 else:
  paid_length = move_toward(paid_length,chain_length,speed * delta)
  deploying = paid_length < chain_length
  head.drop_limit = speed if deploying else 0.0
  _constrain_cable(delta)
  if head.to_global(head_socket).distance_to(global_position) > head_socket.length() * 2.0 + 0.02:
   head.remove_collision_exception_with(pilot)
 _draw_chain()
 delivery_point = null
 if is_instance_valid(target):
  if is_instance_valid(declined_point) and not declined_point.contains_point(target.global_position): declined_point = null
  for point in drop_points:
   if is_instance_valid(point) and point.contains_point(target.global_position):
    if point != declined_point: delivery_point = point
    break
func decline_delivery() -> void:
 declined_point = delivery_point; delivery_point = null
func _exit_tree() -> void:
 release()
 if chain_template != null: chain_template.free()
