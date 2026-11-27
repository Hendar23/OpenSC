extends RefCounted
## Third-person boom and cockpit camera positioning.

var game: Node3D
var mouse_freelook := false
var stick_freelook_device := -1
var freelook: bool:
	get: return mouse_freelook or stick_freelook_device >= 0
var look_angles := Vector2.ZERO
var damage_shake_strength := 0.0
var damage_shake_phase := 0.0

func _init(context: Node3D) -> void:
	game = context

const SUB_RENDER_LAYER := 2
const Docking = preload("res://docking_controller.gd")
const PilotInput = preload("res://pilot_input.gd")
const STICK_LOOK_SPEED := 2.3
const MAX_DAMAGE_SHAKE := deg_to_rad(2.2)
const MIN_COLLISION_SHAKE := deg_to_rad(1.8)

func _can_shake_on_damage() -> bool:
	return (game.first_person and game.pilot_mode and game.camera.current
		and not game.pilot.remote_controlled and not game.get_tree().paused
		and not game.world_loading and not game.loading_save and not game.map_open
		and game.docking != null and game.docking.stage == Docking.Stage.IDLE
		and (game.fmv == null or not game.fmv.active))

func shake_on_damage(loss: float, capacity: float, collision: bool) -> void:
	if not _can_shake_on_damage(): return
	var kick := loss / capacity * 0.24
	# Terrain impacts can take less than one shield point even at full speed.
	if collision: kick = maxf(kick, MIN_COLLISION_SHAKE)
	damage_shake_strength = minf(MAX_DAMAGE_SHAKE, damage_shake_strength + kick)

func update_damage_shake(delta: float) -> void:
	if damage_shake_strength == 0.0: return
	damage_shake_strength *= exp(-14.0 * delta)
	if damage_shake_strength < 0.0001 or not _can_shake_on_damage():
		damage_shake_strength = 0.0
		damage_shake_phase = 0.0
		return
	damage_shake_phase += delta

func _update_follow_camera(delta: float, snap: bool = false) -> void:
	if not is_instance_valid(game.perspex_cockpit) or not game.perspex_cockpit.redirected:
		game.camera.cull_mask |= preload("res://remote_vehicle.gd").RENDER_LAYER
	var pose: Transform3D = game.pilot.global_transform if snap else game.pilot.get_global_transform_interpolated()
	if game.first_person:
		var active := uses_perspex()
		if not active: cancel_freelook()
		if stick_freelook_device >= 0:
			var stick := Vector2(Input.get_joy_axis(stick_freelook_device, JOY_AXIS_RIGHT_X),
				Input.get_joy_axis(stick_freelook_device, JOY_AXIS_RIGHT_Y))
			_rotate_look(PilotInput.stick(stick) * STICK_LOOK_SPEED * delta)
		if not freelook: look_angles = look_angles.lerp(Vector2.ZERO, 1.0 - exp(-18.0 * delta))
		if look_angles.length_squared() < 0.0000000001: look_angles = Vector2.ZERO
		game.camera.near = 0.01 if active else 0.03
		var view := Basis.from_euler(Vector3(look_angles.x, look_angles.y, 0.0))
		if damage_shake_strength > 0.0:
			var phase := damage_shake_phase
			var angles := Vector3(cos(phase * 64.0), sin(phase * 81.0) * 0.55, sin(phase * 51.0) * 0.35)
			view *= Basis.from_euler(angles * damage_shake_strength)
		game.camera.global_transform = pose * Transform3D(view, eye_offset())
		if is_instance_valid(game.perspex_cockpit):
			game.perspex_cockpit.global_transform = pose
			if snap: game.perspex_cockpit.refresh()
		return
	game.camera.near = 0.03
	var next := third_person_position(pose,delta,snap)
	var target: Vector3 = pose.origin + Vector3.UP * 0.35
	game.camera.global_position = next
	if next.distance_to(target) > 0.01: game.camera.look_at(target, Vector3.UP)

func uses_perspex() -> bool:
	return is_instance_valid(game.perspex_cockpit) and game.perspex_cockpit.enabled()

func eye_offset() -> Vector3:
	return game.perspex_cockpit.eye_position() if uses_perspex() else game.cockpit_camera_offset

func aim_pose() -> Transform3D:
	return game.pilot.get_global_transform_interpolated() * Transform3D(Basis.IDENTITY, eye_offset())

func can_freelook() -> bool:
	return (game.pilot_mode and uses_perspex() and game.perspex_cockpit.visible and not game.get_tree().paused
		and not game.developer_ui_visible and not game.map_open and not game.world_loading
		and not game.loading_save and not game.dock_interface_active and not game.front_end.menu_layer.visible
		and not game.pilot.dead and not game.pilot.remote_controlled
		and (game.fmv == null or not game.fmv.active) and game.camera.current
		and game.docking != null and game.docking.stage == Docking.Stage.IDLE
		and not game._rov_prompt_active() and not game._delivery_prompt_active())

func cancel_freelook() -> void:
	mouse_freelook = false
	set_stick_freelook(-1)
	look_angles = Vector2.ZERO

func set_stick_freelook(device: int) -> void:
	stick_freelook_device = device
	if is_instance_valid(game.pilot): game.pilot.freelook_device = device

func look(relative: Vector2) -> void:
	_rotate_look(relative * 0.003)

func _rotate_look(relative: Vector2) -> void:
	look_angles.x = clampf(look_angles.x - relative.y, deg_to_rad(-78.0), deg_to_rad(78.0))
	look_angles.y = clampf(look_angles.y - relative.x, deg_to_rad(-100.0), deg_to_rad(100.0))

func third_person_position(pose: Transform3D, delta: float, snap: bool) -> Vector3:
	var target: Vector3 = pose.origin + Vector3.UP * 0.35
	var forward: Vector3 = -pose.basis.z
	var heading := atan2(-forward.x, -forward.z)
	var distance := float(game.pilot.movement.settings.camera_distance)
	var tool: Node3D = game.equipment.towing_tool() if game.equipment != null else null
	if tool != null and is_instance_valid(tool.target) and not tool.target.is_queued_for_deletion():
		var cargo: Node3D = tool.target
		var extent: float = pose.origin.distance_to(cargo.global_position)
		if cargo.get("stats") is Dictionary: extent += float(cargo.stats.get("size",0.5)) * 0.5
		distance = game.camera_follow.cargo_distance(distance,extent)
	var desired: Vector3 = game.camera_follow.desired_position(target, heading, game.pilot.velocity, forward,
		float(game.pilot.movement.settings.forward_speed), distance, delta, snap)
	var exclusions: Array[RID] = [game.pilot.get_rid()]
	if tool != null:
		if is_instance_valid(tool.target) and tool.target is CollisionObject3D: exclusions.append(tool.target.get_rid())
		if is_instance_valid(tool.head): exclusions.append(tool.head.get_rid())
	# Solve the full boom before smoothing. Sampling only the already shortened
	# camera position made its own obstruction appear/disappear every frame.
	var offset: Vector3 = desired - target
	var query := PhysicsRayQueryParameters3D.create(target,desired,1,exclusions)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(query)
	var allowed: float = maxf(0.02,target.distance_to(hit.position) - 0.08) if not hit.is_empty() else offset.length()
	var boom: float = game.camera_follow.clear_distance(offset.length(),allowed,delta,snap)
	var limited: Vector3 = target + offset.normalized() * boom
	var next: Vector3 = limited if snap else game.camera.global_position.lerp(limited,1.0-exp(-7.0*delta))
	query.to = next
	hit = game.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): next = target + (next-target).normalized() * maxf(0.02,target.distance_to(hit.position)-0.05)
	next.y = minf(next.y, game.pilot.surface_height - 0.2)
	return next

func update_cinematic_camera() -> void:
	game.camera.global_position = game.docking.cinematic_camera
	var target: Vector3 = game.pilot.get_global_transform_interpolated().origin + Vector3.UP * 0.35
	if game.camera.global_position.distance_to(target) > 0.01: game.camera.look_at(target, Vector3.UP)
	game.camera_was_frozen = true

func _set_camera_mode(cockpit: bool) -> void:
	if game.pilot == null: return
	if game.pilot.dead: cockpit = false
	damage_shake_strength = 0.0
	damage_shake_phase = 0.0
	cancel_freelook()
	if is_instance_valid(game.perspex_cockpit): game.perspex_cockpit.stop()
	game.first_person = cockpit
	if cockpit: game.camera.cull_mask &= ~SUB_RENDER_LAYER
	else: game.camera.cull_mask |= SUB_RENDER_LAYER
	if not cockpit and game.docking != null and game.docking.stage != Docking.Stage.DOCKED and game.docking.camera_frozen():
		update_cinematic_camera()
	else:
		game.camera_was_frozen = false
		game._update_follow_camera(0.0,true)
	if not cockpit: game.camera.near = 0.03
