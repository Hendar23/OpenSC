extends "res://rock_body.gd"
## Eruption rock: original 00417450 overrides mass/health; 00415c60 removes on impact.
var age := 0.0

func _ready() -> void:
	custom_integrator = true; contact_monitor = true; max_contacts_reported = 4
	set_meta("grapple_tow_target",false); set_meta("metal_tow_target",false)
	body_entered.connect(func(_body: Node) -> void: queue_free.call_deferred())

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if dead: return
	age += state.step
	state.linear_velocity += Vector3.DOWN*1.2*state.step
	state.linear_velocity *= exp(-0.3*state.step)
	state.angular_velocity *= exp(-0.5*state.step)
	# Bound debris even when launched through an opening in the legacy terrain.
	if age >= 8.0: queue_free.call_deferred()

func take_weapon_damage(_strength: float, _source: Vector3 = Vector3.ZERO) -> void:
	dead = true; queue_free()
