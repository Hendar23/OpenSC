extends Node3D
## Player missiles and Electro Bolt use swept collision at the original 25 Hz.
## Modern physics supplies the collision surface; damage retains raw shield units.
const Damage = preload("res://original_damage.gd")
# Player launcher 0045a5d0 multiplies HMISSILE's CSV inflict by twelve.
# NPC homing missiles do not pass through that launcher.
const HOMING_INFLICT := 2.0*12.0
const TORPEDO_DAMAGE_MULTIPLIER := 2.0
const STANDARD_LIFETIME := 40.0 / Damage.TICKS_PER_SECOND
const HOMING_LIFETIME := 133.333333 / Damage.TICKS_PER_SECOND
const STANDARD_THRUST := 0.0075
const HOMING_THRUST := 0.0025
const TORPEDO_DAMPING := 0.857142857
const SINK_ACCELERATION := 0.65
const SINK_SPEED := 1.2
const ELECTRO_RADIUS := 0.5 # ELECTROBOLT's one-unit collision sphere.
var arsenal: Node3D
var kind := "missile"
var target: Node3D
var direction := Vector3.FORWARD
var velocity := Vector3.ZERO
var age := 0.0
var clock := 0.0
var bursting := false
var burst_ticks := 0
var arcs: Array[Node3D] = []
var visual: Node3D
var lamp: OmniLight3D
var glow_material: ShaderMaterial
var spent := false
var out_of_fuel := false
var powered_distance := 0.0
var fuel_range := 0.0
var tumble_axis := Vector3(0.7,0.4,0.25).normalized()

static func powered_range(id: String) -> float:
	# Twice the distance travelled from rest before the old flight timer expired.
	# Keep the original speed/acceleration, rather than increasing weapon speed.
	var lifetime := STANDARD_LIFETIME if id == "missile" else HOMING_LIFETIME
	var ticks := ceili(lifetime * Damage.TICKS_PER_SECOND)-1
	var thrust := STANDARD_THRUST if id == "missile" else HOMING_THRUST
	var terminal_speed := thrust / 0.1 * Damage.TICKS_PER_SECOND * TORPEDO_DAMPING / (1.0-TORPEDO_DAMPING)
	return 2.0 * terminal_speed * (ticks-TORPEDO_DAMPING*(1.0-pow(TORPEDO_DAMPING,ticks))/(1.0-TORPEDO_DAMPING)) / Damage.TICKS_PER_SECOND

func setup(context: Node3D, id: String, point: Vector3, heading: Vector3, victim: Node3D = null) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	arsenal = context; kind = id; direction = heading.normalized(); target = victim
	if kind != "electro":
		fuel_range = powered_range(kind)
		tumble_axis.x *= -1.0 if get_instance_id() % 2 else 1.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_to_group("player_projectiles")
	global_position = point
	velocity = arsenal.weapons.pilot.linear_velocity * (0.1 if kind == "electro" else 1.0)
	if kind == "electro":
		var sprite := Sprite3D.new(); sprite.texture = arsenal.bolt_frames[0]
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sprite.no_depth_test = false
		sprite.pixel_size = 0.5/maxf(1,sprite.texture.get_width()) if sprite.texture != null else 0.005
		visual = sprite; add_child(visual)
		glow_material = preload("res://natural_light.gd").billboard_material(sprite.texture)
		glow_material.set_shader_parameter("emission_color",Color.WHITE); glow_material.set_shader_parameter("has_emission_texture",true); glow_material.set_shader_parameter("emission_texture",sprite.texture)
		sprite.material_override = glow_material
		lamp = OmniLight3D.new(); lamp.light_color = Color(0.35,0.6,1); lamp.light_energy = 1.5; lamp.omni_range = 4; add_child(lamp)
		for index in range(5):
			var arc := preload("res://submarine_weapons.gd").create_arc(arsenal.weapons.pilot,arsenal.weapons.frames)
			arc.camera = arsenal.weapons.camera; arc.settings.beam_width = 0.045; arc.settings.animation_speed = 12.5
			add_child(arc); arc.set_physics_process(false); arcs.append(arc)
	else:
		var template: Node3D = arsenal.templates.get(kind)
		if template != null: visual = template.duplicate(); add_child(visual); visual.show()
		global_basis = Basis.looking_at(direction,Vector3.RIGHT if absf(direction.y) > 0.999 else Vector3.UP,true)
	reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	advance(delta)

func _process(_delta: float) -> void:
	if kind == "electro" and is_instance_valid(arsenal) and visual is Sprite3D:
		visual.texture = arsenal.bolt_frames[int(age*5.0) % arsenal.bolt_frames.size()]
		glow_material.set_shader_parameter("albedo_texture",visual.texture); glow_material.set_shader_parameter("emission_texture",visual.texture)

func advance(delta: float) -> void:
	if spent or not is_instance_valid(arsenal): queue_free(); return
	clock += maxf(0,delta) * Damage.TICKS_PER_SECOND
	while clock >= 1.0 and not spent:
		clock -= 1.0; age += 1.0/Damage.TICKS_PER_SECOND
		if kind == "electro" and bursting:
			pulse(); continue
		if out_of_fuel:
			_sink_tick(); continue
		if kind == "homers" and is_instance_valid(target) and not bool(target.get("dead")):
			var desired := (target.global_position-global_position).normalized()
			if not desired.is_zero_approx():
				var angle := direction.angle_to(desired)
				if angle > 0.000001: direction = direction.slerp(desired,minf(1,0.1/angle)).normalized()
		# Preserve the original player launcher thrust; fuel now limits distance.
		var thrust := STANDARD_THRUST if kind == "missile" else HOMING_THRUST
		var acceleration := 2.5 if kind == "electro" else thrust / 0.1 * Damage.TICKS_PER_SECOND
		velocity = (velocity + direction * acceleration) * (0.95 if kind == "electro" else TORPEDO_DAMPING)
		var movement := velocity / Damage.TICKS_PER_SECOND
		if kind != "electro": movement = movement.limit_length(maxf(0,fuel_range-powered_distance))
		var next := global_position + movement
		var pilot: Node3D = arsenal.weapons.pilot
		var hit := _impact(next,pilot)
		if not hit.is_empty():
			global_position = hit.position
			if kind == "electro":
				bursting = true; burst_ticks = 20; pulse()
			else:
				var body: Node3D = hit.collider
				var relative: Vector3 = velocity - (body.linear_velocity if body is RigidBody3D else body.velocity if body is CharacterBody3D else Vector3.ZERO)
				var strength := (HOMING_INFLICT if kind == "homers" else 8.0) * TORPEDO_DAMAGE_MULTIPLIER * 10.0 * maxf(0,relative.dot(direction)) / Damage.TICKS_PER_SECOND
				var damage_source: Vector3 = global_position if body.has_method("take_typed_weapon_damage") else hit.position
				Damage.weapon(body,strength,damage_source,pilot,kind,hit); finish(true)
			return
		global_position = next
		if kind != "electro":
			powered_distance += movement.length()
			if powered_distance >= fuel_range-0.00001:
				_run_out_of_fuel(); continue
		if kind != "electro": global_basis = Basis.looking_at(direction,Vector3.RIGHT if absf(direction.y) > 0.999 else Vector3.UP,true)
		else: _arcs([])
		var trail: Node3D = arsenal.bubbles()
		if trail != null: trail.emit_from(get_instance_id(),global_position-direction*0.15,-direction,1,12.5,1.0/Damage.TICKS_PER_SECOND)

func _run_out_of_fuel() -> void:
	out_of_fuel = true; target = null
	var trail: Node3D = arsenal.bubbles()
	if trail != null: trail.credits.erase(get_instance_id())

func _sink_tick() -> void:
	var step := 1.0/Damage.TICKS_PER_SECOND
	# Water quickly damps forward momentum; negative buoyancy remains after
	# the motor stops. Rotate independently of travel for a slow end-over-end fall.
	velocity.x *= 0.94; velocity.z *= 0.94
	if velocity.y > 0: velocity.y *= 0.94
	velocity.y = maxf(-SINK_SPEED,velocity.y-SINK_ACCELERATION*step)
	var next := global_position+velocity*step
	var hit := _impact(next,arsenal.weapons.pilot)
	if not hit.is_empty():
		global_position = hit.position
		finish(true); return
	global_position = next
	global_basis = (global_basis*Basis(tumble_axis,0.7*step)).orthonormalized()

func _impact(next: Vector3, pilot: Node3D) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(global_position,next,15,[pilot.get_rid()])
	ray.hit_back_faces = true; ray.hit_from_inside = true
	if kind != "electro": return space.intersect_ray(ray)
	# The visible bolt has volume. A point ray misses fish that the globe
	# overlaps, and can jump entirely past a small fish between 25 Hz steps.
	var shape := SphereShape3D.new(); shape.radius = ELECTRO_RADIUS
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape; query.transform.origin = global_position
	query.collision_mask = 15; query.exclude = [pilot.get_rid()]; query.margin = 0.001
	var overlaps := space.intersect_shape(query,8)
	if not overlaps.is_empty(): return {"collider":overlaps[0].collider,"position":global_position}
	query.motion = next-global_position
	var fractions := space.cast_motion(query)
	if fractions[0] >= 1.0: return {}
	query.transform.origin = global_position+query.motion*minf(1.0,fractions[1]+0.001)
	query.motion = Vector3.ZERO
	var info := space.get_rest_info(query)
	if not info.is_empty(): return {"collider":instance_from_id(info.collider_id),"position":global_position+(next-global_position)*fractions[0]}
	return space.intersect_ray(ray)

func pulse() -> void:
	var shape := SphereShape3D.new(); shape.radius = 5.0
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape; query.transform.origin = global_position; query.collision_mask = 15
	query.exclude = [arsenal.weapons.pilot.get_rid()]
	var struck := {}; var points: Array[Vector3] = []
	for entry in get_world_3d().direct_space_state.intersect_shape(query,256):
		var body: Node3D = entry.collider
		if struck.has(body.get_instance_id()) or body.get("dead") == true or not body.has_method("take_damage"): continue
		struck[body.get_instance_id()] = true
		# The retail radial discharge excludes the player, but damages other
		# creatures, submarines, mines and destructible structures alike.
		Damage.weapon(body,4.0,global_position,arsenal.weapons.pilot)
		points.append(body.global_position)
	_arcs(points)
	burst_ticks -= 1
	if burst_ticks <= 0: finish(true)

func _arcs(points: Array) -> void:
	for index in range(arcs.size()):
		var arc: Node3D = arcs[index]
		arc.firing = true; arc.beam.show(); arc.beam_start = global_position
		var end := Vector3(sin(age*13+index*2.4),cos(age*17+index*1.7),sin(age*19+index)).normalized()
		arc.beam_end = points[index % points.size()] if not points.is_empty() else global_position + end*(1.0 if bursting else 0.3)

func finish(explode: bool) -> void:
	if spent: return
	spent = true
	if explode and is_instance_valid(arsenal): arsenal.burst(global_position,0.5 if kind != "electro" else 1.0)
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(arsenal):
		var trail: Node3D = arsenal.bubbles()
		if trail != null: trail.credits.erase(get_instance_id())
