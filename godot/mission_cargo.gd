extends RigidBody3D
signal destroyed
var health := 5.0
var dead := false
var shard := 0
var delivered := false:
	set(value):
		delivered = value
		_refresh_smoke()
var damage_smoke: Node3D
var appearance: Node3D
var stats := {"delivery_commodity":"Bacau shuttle","delivery_quantity":1}
var surface_height := 0.0

func _ready() -> void:
	# Use the same solid salvage layer as other magnet cargo. Layer 4 alone
	# cannot contact the magnet head (mask 11), so no attachment event arrives.
	# Deliberately heavier in our physics units: 250 units of engine load with
	# the standard magnet multiplier, rather than the nearly weightless raw1.
	gravity_scale = 0; mass = 10; collision_layer = 9; collision_mask = 1 | 2 | 8
	linear_damp = 1.0; angular_damp = 3.0
	set_meta("metal_tow_target",true); set_meta("grapple_tow_target",false)
	set_meta("damage_sustain",0.3)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON

func setup_damage_smoke(visual: Node3D, folder: String) -> void:
	appearance = visual
	damage_smoke = preload("res://submarine_damage_smoke.gd").new(); add_child(damage_smoke)
	damage_smoke.setup(visual,folder)
	_refresh_smoke()

func _refresh_smoke() -> void:
	if not is_instance_valid(damage_smoke): return
	# The mission's disabled power unit smokes even with an intact hull.
	damage_smoke.damaged = not dead and not delivered
	damage_smoke.enabled = damage_smoke.damaged

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not delivered: state.linear_velocity += Vector3.DOWN * (1.2 if global_position.y < surface_height else 9.8) * state.step

func take_damage(amount: float, _source: Vector3 = Vector3.ZERO) -> void:
	take_weapon_damage(amount / 3.0)

func take_weapon_damage(strength: float, _source: Vector3 = Vector3.ZERO) -> void:
	if dead or delivered: return
	health -= maxf(0,strength) * 0.3
	if health <= 0:
		dead = true; collision_layer = 0; _refresh_smoke(); destroyed.emit()

func take_weapon_damage_from(strength: float, source: Vector3, _attacker: Node3D) -> void:
	take_weapon_damage(strength,source)
