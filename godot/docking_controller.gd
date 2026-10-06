extends Node
signal docked

const Morph = preload("res://morph_animation.gd")
const Radio = preload("res://docking_radio.gd")
const Transit = preload("res://transit_motion.gd")
const DockAudio = preload("res://docking_audio.gd")
const DOCK_SPEED_FRACTION := 2.0 / 3.0
const APPROACH_RADIUS := 2.0
enum Stage { IDLE, SETTLE, ALIGN, OPEN, DESCEND, CLOSE, DOCKED, EXIT_OPEN, ASCEND, EXIT_CLOSE, APPROACH }

var stage := Stage.IDLE
var approach_radius := APPROACH_RADIUS
var pilot: RigidBody3D
var ports: Array[Dictionary] = []
var nearby: Dictionary = {}
var current: Dictionary = {}
var elapsed := 0.0
var saved_collision_mask := 5
var message := ""
var cinematic_camera := Vector3.ZERO
var radio_messages := {}
var radio_static: Array[Texture2D] = []
var declined_port: Node3D
var view_camera: Camera3D
var transit_settings := {}
var travel_profile := {}
var turn_profile := {}
var travel_start := Vector3.ZERO
var travel_direction := Vector3.ZERO
var turn_basis := Basis.IDENTITY
var turn_axis := Vector3.UP
var audio: Node
var greeting_port: Dictionary = {}
var greeting_remaining := 0.0
var greeting_text := ""
var greeted_ports := {}
const GREETING_SECONDS := 8.0

func setup(player: RigidBody3D, world: Node3D, folder: String = "", follow_view: Camera3D = null, catalogue: Dictionary = {}) -> void:
	pilot = player
	if audio != null: audio.free()
	audio = DockAudio.new()
	audio.name = "DockingAudio"
	add_child(audio)
	audio.setup(pilot.submarine_audio, folder)
	view_camera = follow_view
	radio_messages = Radio.messages(folder)
	if catalogue.is_empty(): catalogue = preload("res://original_game_data.gd").load_catalogue(folder)
	preload("res://original_game_data.gd").apply_city_names(world,catalogue)
	if catalogue.tables.has("radio_messages"): radio_messages.clear()
	for id in catalogue.tables.get("radio_messages",{}).get("records",{}):
		radio_messages[id] = str(catalogue.tables.radio_messages.records[id].get("text",""))
	var portraits := {}
	var distorted := {}
	radio_static = Radio.static_frames(folder)
	for node in world.find_children("*", "Node3D", true, false):
		if not node.has_meta("city_id"): continue
		var meshes: Array[MeshInstance3D] = []
		Morph.collect(node, meshes)
		if meshes.is_empty(): continue
		var boxes: Array[AABB] = []
		_bounds(node, Transform3D.IDENTITY, boxes)
		var box := boxes[0]
		for index in range(1, boxes.size()): box = box.merge(boxes[index])
		var center := box.get_center()
		var entry: Vector3 = node.to_global(Vector3(center.x, box.end.y, center.z)) + Vector3.UP * (pilot.COLLIDER_RADIUS + 0.6)
		entry.y = minf(entry.y, pilot.surface_height - pilot.surface_clearance(Basis.IDENTITY) - pilot.safe_margin)
		var race := int(node.get_meta("race_id", 1))
		var city: Dictionary = catalogue.tables.get("city_info",{}).get("records",{}).get(str(int(node.get_meta("city_id"))),{})
		if not portraits.has(race):
			portraits[race] = Radio.portrait(folder, race)
			distorted[race] = Radio.distorted_portrait(folder,race)
		ports.append({"node": node, "meshes": meshes, "entry": entry,
			"inside": node.to_global(Vector3(center.x, box.position.y + 0.5, center.z)) + Vector3.UP * pilot.collision_height(),
			"name": node.get_meta("city_name"), "race": race, "portrait": portraits[race],"distorted_portrait":distorted[race],
			"collision": node.get_node("SceneryCollision"),"greeting_radius":float(city.get("greeting_radius",0.0)),"greeting":str(radio_messages.get(str(city.get("greeting_neutral","")),""))})
	update_approach()

static func _bounds(node: Node3D, pose: Transform3D, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D: boxes.append(pose * node.mesh.get_aabb())
	for child in node.get_children():
		if child is Node3D: _bounds(child, pose * child.transform, boxes)

func maximum_docking_speed() -> float:
	return float(pilot.movement.settings.forward_speed) * DOCK_SPEED_FRACTION

static func upright_basis(pose: Basis) -> Basis:
	var forward := -pose.z
	return Basis(Vector3.UP, atan2(-forward.x, -forward.z))

static func approach_basis(pose: Basis, position: Vector3, destination: Vector3) -> Basis:
	var offset := destination - position
	if Vector2(offset.x, offset.z).length() < 0.0001: return upright_basis(pose)
	return Basis(Vector3.UP, atan2(-offset.x, -offset.z))

func update_approach() -> void:
	if stage != Stage.IDLE: return
	_update_greeting()
	nearby = {}
	var nearest := approach_radius
	for port in ports:
		var distance: float = pilot.global_position.distance_to(port.entry)
		if distance < nearest:
			nearest = distance
			nearby = port
	if nearby.is_empty():
		declined_port = null
		message = greeting_text if greeting_remaining > 0.0 else ""
	elif nearby.node == declined_port:
		nearby = {}
		message = ""
	elif pilot.velocity.length() > maximum_docking_speed():
		message = _radio_line(nearby, "warning", "CITY DOCKING PAD : Approach too fast to dock. Slow down.")
	else: message = _radio_line(nearby, "prompt", "CITY DOCKING PAD : Do you want to dock? (Y/N)")

func _update_greeting() -> void:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for port in ports:
		var distance: float = pilot.global_position.distance_to(port.entry)
		var radius := float(port.get("greeting_radius",0.0))
		var id: int = port.node.get_instance_id()
		if distance > radius + 2.0: greeted_ports.erase(id)
		if distance < radius and distance < nearest_distance and not str(port.get("greeting","")).is_empty():
			nearest = port; nearest_distance = distance
	if nearest.is_empty(): return
	var id: int = nearest.node.get_instance_id()
	if greeted_ports.has(id): return
	greeted_ports[id] = true
	greeting_port = nearest; greeting_text = str(nearest.greeting)
	greeting_remaining = GREETING_SECONDS

func _radio_line(port: Dictionary, kind: String, fallback: String) -> String:
	var code := 22
	if int(port.race) == 2: code = 25
	elif int(port.race) == 4: code = 28
	if kind == "warning": code = 19 + (1 if int(port.race) == 2 else 2 if int(port.race) == 4 else 0)
	elif kind == "docking": code += 1
	elif kind == "launch": code += 2
	return "%s: %s" % [port.name,str(radio_messages.get("city%d" % code, fallback))]

func portrait_texture() -> Texture2D:
	return _portrait_port().get("portrait")

func distorted_portrait_texture() -> Texture2D:
	return _portrait_port().get("distorted_portrait")

func _portrait_port() -> Dictionary:
	var port := nearby if stage == Stage.IDLE else current
	if port.is_empty() and stage == Stage.IDLE and greeting_remaining > 0.0: port = greeting_port
	return port

func decline_docking() -> void:
	if stage != Stage.IDLE or nearby.is_empty(): return
	declined_port = nearby.node
	nearby = {}
	message = ""

func request_docking() -> bool:
	if stage == Stage.DOCKED:
		_prepare_transit_settings()
		# Reveal behind the closed hatch before it starts opening.
		pilot.visual.visible = true
		_transition(Stage.EXIT_OPEN)
		return true
	if stage != Stage.IDLE: return false
	update_approach()
	if nearby.is_empty() or pilot.velocity.length() > maximum_docking_speed(): return false
	current = nearby
	_prepare_transit_settings()
	if minf(float(transit_settings.forward_speed), float(transit_settings.reverse_speed)) <= 0.0 or float(transit_settings.vertical_speed) <= 0.0 or float(transit_settings.side_thrust) <= 0.0:
		message = "Docking requires movement speed and vertical thrust."
		current = {}
		return false
	if pilot.angular_velocity.length() > 0.00001 and float(transit_settings.turn_acceleration) <= 0.0 and float(transit_settings.turn_drag) <= 0.0:
		message = "Stop turning before docking with turning acceleration and drag disabled."
		current = {}
		return false
	if not pilot.global_basis.is_equal_approx(approach_basis(pilot.global_basis, pilot.global_position, current.entry)) and (float(transit_settings.turn_acceleration) <= 0.0 or float(transit_settings.turn_speed) <= 0.0):
		message = "Face the docking position and level the submarine before docking with turning disabled."
		current = {}
		return false
	saved_collision_mask = pilot.collision_mask
	greeting_remaining = 0.0
	pilot.active = false
	pilot.controls_enabled = false
	# Scripted transit through the open port replaces normal piloting collision.
	pilot.collision_mask = 0
	if view_camera != null: cinematic_camera = view_camera.global_position
	pilot.pending_reset = false
	pilot.movement.angular_velocity = pilot.angular_velocity
	if pilot.velocity.length() > 0.00001 or pilot.movement.angular_velocity.length() > 0.00001:
		pilot.collision_mask = saved_collision_mask
		_transition(Stage.SETTLE)
	else: _transition(Stage.ALIGN)
	return true

func _prepare_transit_settings() -> void:
	transit_settings = pilot.movement.settings.duplicate()
	# Transit planning consumes acceleration rather than force ratings.
	for key in ["main_forward", "main_reverse", "side_thrust"]:
		transit_settings[key] /= maxf(1.0, float(transit_settings.mass))
	for key in ["forward_drag", "lateral_drag", "vertical_drag", "water_resistance"]:
		transit_settings[key] *= 100.0 / maxf(1.0, float(transit_settings.mass))

func camera_frozen() -> bool:
	return stage not in [Stage.IDLE, Stage.EXIT_CLOSE]

func _transition(next_stage: Stage) -> void:
	var previous := stage
	stage = next_stage
	elapsed = 0.0
	if audio != null:
		var door_stages := [Stage.OPEN, Stage.CLOSE, Stage.EXIT_OPEN, Stage.EXIT_CLOSE]
		audio.set_phase(stage not in [Stage.IDLE, Stage.DOCKED], stage in door_stages, previous in door_stages and stage != previous)
	match stage:
		Stage.SETTLE: message = "Preparing to dock…"
		Stage.ALIGN: message = "Aligning with %s…" % current.name
		Stage.APPROACH: message = "Approaching %s…" % current.name
		Stage.OPEN, Stage.EXIT_OPEN: message = "Opening docking port…"
		Stage.DESCEND: message = "Docking at %s…" % current.name
		Stage.CLOSE, Stage.EXIT_CLOSE: message = "Closing docking port…"
		Stage.DOCKED: message = "Docked at %s — Press Y to undock" % current.name
		Stage.ASCEND: message = "Leaving %s…" % current.name
	if stage in [Stage.SETTLE, Stage.ALIGN, Stage.APPROACH, Stage.OPEN, Stage.DESCEND, Stage.CLOSE]:
		message = _radio_line(current, "docking", "CITY DOCKING PAD : Automatic docking in progress")
	elif stage in [Stage.EXIT_OPEN, Stage.ASCEND, Stage.EXIT_CLOSE]:
		message = _radio_line(current, "launch", "CITY DOCKING PAD : Automatic launch in progress")
	if stage in [Stage.ALIGN, Stage.APPROACH, Stage.DESCEND, Stage.ASCEND]:
		pilot.collision_mask = 0
		travel_start = pilot.global_position
		var destination: Vector3 = current.inside if stage == Stage.DESCEND else current.entry
		var offset := destination - travel_start
		if stage == Stage.ALIGN: offset = Vector3.ZERO
		travel_direction = offset.normalized()
		var limits := _travel_limits(travel_direction)
		travel_profile = Transit.plan(offset.length(), limits.x, limits.y)
		turn_basis = pilot.global_basis.orthonormalized()
		var target := approach_basis(turn_basis, travel_start, current.entry)
		var correction := target.get_rotation_quaternion() * turn_basis.get_rotation_quaternion().inverse()
		if correction.w < 0.0: correction = -correction
		var angle := correction.get_angle() if stage == Stage.ALIGN else 0.0
		turn_axis = correction.get_axis() if angle > 0.00001 else Vector3.UP
		var acceleration := _angular_acceleration()
		var speed := deg_to_rad(float(transit_settings.turn_speed))
		if stage == Stage.ALIGN and angle > 0.00001 and (acceleration <= 0.0 or speed <= 0.0):
			# Settling can change the bearing to the port after acceptance.
			# Hand control back here rather than approaching sideways.
			_restore_pilot()
			if audio != null: audio.stop()
			stage = Stage.IDLE
			current = {}
			message = "Face the docking position before docking with turning disabled."
			return
		if acceleration <= 0.0 or speed <= 0.0: angle = 0.0
		turn_profile = Transit.plan(absf(angle), speed, acceleration)

func _angular_acceleration() -> float:
	var physical: float = 2.0 * float(transit_settings.side_thrust) * 0.4 / (0.4 * pilot.COLLIDER_RADIUS * pilot.COLLIDER_RADIUS)
	return minf(deg_to_rad(float(transit_settings.turn_acceleration)), physical)

func _travel_limits(direction: Vector3) -> Vector2:
	var horizontal := Vector2(direction.x, direction.z).length()
	var vertical := absf(direction.y)
	var speed := INF
	var thrust := INF
	var drag := 0.0
	if horizontal > 0.00001:
		speed = minf(float(transit_settings.forward_speed), float(transit_settings.reverse_speed)) / horizontal
		thrust = minf(float(transit_settings.main_forward), float(transit_settings.main_reverse)) + float(transit_settings.side_thrust) * 2.0
		drag = float(transit_settings.forward_drag)
	if vertical > 0.00001:
		speed = minf(speed, float(transit_settings.vertical_speed) / vertical)
		thrust = minf(thrust, float(transit_settings.side_thrust) * 2.0)
		drag = maxf(drag, float(transit_settings.vertical_drag))
	if not is_finite(speed): return Vector2(1.0, 1.0)
	# Leave thrust available to overcome drag, rather than assuming the speed cap
	# is attainable at full acceleration all the way to the end of the ramp.
	var resistance := float(transit_settings.water_resistance)
	if resistance > 0.0:
		speed = minf(speed, (sqrt(drag * drag + 4.0 * resistance * thrust * 0.7) - drag) / (2.0 * resistance))
	elif drag > 0.0: speed = minf(speed, thrust * 0.7 / drag)
	var acceleration := minf(thrust * 0.35, thrust - drag * speed - resistance * speed * speed)
	return Vector2(speed, maxf(0.0001, acceleration))

func _physics_process(delta: float) -> void:
	if stage == Stage.IDLE:
		greeting_remaining = maxf(0.0,greeting_remaining - delta)
		update_approach()
		return
	if stage == Stage.DOCKED: return
	if stage == Stage.SETTLE:
		_settle(delta)
		_animate_pilot(delta)
		return
	elapsed += delta
	var duration := 1.2
	if stage in [Stage.ALIGN, Stage.APPROACH, Stage.DESCEND, Stage.ASCEND]:
		duration = maxf(float(travel_profile.duration), float(turn_profile.duration))
	var fraction := clampf(elapsed / duration, 0.0, 1.0) if duration > 0.0 else 1.0
	var eased := smoothstep(0.0, 1.0, fraction)
	match stage:
		Stage.ALIGN, Stage.APPROACH, Stage.DESCEND, Stage.ASCEND:
			var travel := Transit.sample(travel_profile, elapsed)
			pilot.global_position = travel_start + travel_direction * travel.x
			pilot.velocity = travel_direction * travel.y
			var turn := Transit.sample(turn_profile, elapsed)
			pilot.global_basis = Basis(turn_axis, turn.x) * turn_basis
			pilot.movement.angular_velocity = turn_axis * turn.y
		Stage.OPEN, Stage.EXIT_OPEN:
			_set_open(eased)
		Stage.CLOSE, Stage.EXIT_CLOSE:
			_set_open(1.0 - eased)
	_animate_pilot(delta)
	if fraction < 1.0: return
	match stage:
		Stage.ALIGN: _transition(Stage.APPROACH)
		Stage.APPROACH: _transition(Stage.OPEN)
		Stage.OPEN:
			current.collision.collision_layer = 0
			_transition(Stage.DESCEND)
		Stage.DESCEND:
			_transition(Stage.CLOSE)
		Stage.CLOSE:
			pilot.visual.visible = false
			current.collision.collision_layer = 1
			_transition(Stage.DOCKED)
			docked.emit()
		Stage.EXIT_OPEN:
			current.collision.collision_layer = 0
			pilot.visual.visible = true
			_transition(Stage.ASCEND)
		Stage.ASCEND: _transition(Stage.EXIT_CLOSE)
		Stage.EXIT_CLOSE:
			current.collision.collision_layer = 1
			_restore_pilot()
			_transition(Stage.IDLE)
			current = {}
			update_approach()

func _settle(delta: float) -> void:
	var acceleration := float(transit_settings.side_thrust) * 2.0
	var speed: float = pilot.velocity.length()
	if speed > 0.00001:
		var direction: Vector3 = pilot.velocity / speed
		var time := minf(delta, speed / acceleration)
		var collision := pilot.move_and_collide(direction * (speed * time - acceleration * time * time * 0.5))
		pilot.velocity = direction * maxf(0.0, speed - acceleration * time) if collision == null else Vector3.ZERO
	var angular_acceleration := _angular_acceleration()
	var old_spin: Vector3 = pilot.movement.angular_velocity
	if angular_acceleration > 0.0:
		var time := minf(delta, old_spin.length() / angular_acceleration)
		if old_spin.length() > 0.00001:
			pilot.global_basis = Basis(old_spin.normalized(), old_spin.length() * time - angular_acceleration * time * time * 0.5) * pilot.global_basis
		pilot.movement.angular_velocity = old_spin.move_toward(Vector3.ZERO, angular_acceleration * delta)
	else: pilot.movement.angular_velocity *= exp(-float(transit_settings.turn_drag) * delta)
	if pilot.velocity.length() < 0.00001 and pilot.movement.angular_velocity.length() < 0.00001:
		_transition(Stage.ALIGN)

func _animate_pilot(delta: float) -> void:
	pilot.movement.velocity = pilot.velocity
	var horizontal := Vector2(pilot.velocity.x, pilot.velocity.z).length()
	var moving: bool = pilot.velocity.length() > 0.001
	var tilt := atan2(pilot.velocity.y, horizontal) if moving else 0.0
	pilot.movement.tilt = move_toward(pilot.movement.tilt, tilt, deg_to_rad(float(transit_settings.tilt_speed)) * delta)
	pilot.movement.pods_aligned = is_equal_approx(pilot.movement.tilt,tilt)
	pilot.movement.main_power = 1.0 if horizontal > 0.001 else 0.0
	pilot.movement.left_power = 1.0 if moving else 0.0
	pilot.movement.right_power = pilot.movement.left_power
	if stage == Stage.ALIGN and absf(pilot.movement.angular_velocity.y) > 0.001:
		var turn := clampf(pilot.movement.angular_velocity.y / maxf(0.01, deg_to_rad(float(transit_settings.turn_speed))), -1.0, 1.0)
		pilot.movement.left_power = -turn
		pilot.movement.right_power = turn
	pilot._update_animation(delta)

func _set_open(amount: float) -> void:
	for instance in current.meshes:
		var count: int = instance.mesh.get_blend_shape_count() + 1
		var phase := clampf(amount, 0.0, 1.0) * (count - 1)
		var first := int(floor(phase))
		var next := mini(first + 1, count - 1)
		var weight := phase - first
		for pose in range(1, count):
			instance.set_blend_shape_value(pose - 1, (1.0 - weight if pose == first else 0.0) + (weight if pose == next else 0.0))

func _restore_pilot() -> void:
	pilot.collision_mask = saved_collision_mask
	pilot.active = true
	pilot.visual.visible = true
	pilot.velocity = Vector3.ZERO
	pilot.angular_velocity = Vector3.ZERO
	pilot.movement.reset_motion()

func cancel() -> void:
	if audio != null: audio.stop()
	if stage == Stage.IDLE: return
	_set_open(0.0)
	current.collision.collision_layer = 1
	pilot.global_position = current.entry
	pilot.force_update_transform()
	pilot.reset_physics_interpolation()
	_restore_pilot()
	stage = Stage.IDLE
	current = {}
	update_approach()
