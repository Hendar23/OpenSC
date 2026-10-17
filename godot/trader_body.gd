extends CharacterBody3D
var radius := 0.6
var dead: bool:
	get: return get_parent().get_node("Trader").dead
var active: bool:
	get: return get_parent().visible and not dead and get_parent().get_node("Trader").running and get_parent().get_node("Trader").stage == "travel"
var controls_enabled: bool:
	get: return active

func apply_weapon_impulse(impulse: Vector3) -> void:
	# NPC steering owns momentum; changing body.velocity alone is overwritten
	# on the next movement step. Feed blasts into that same inertial state.
	var agent := get_parent().get_node("Trader")
	agent.motion.velocity += impulse
	velocity += impulse

func take_weapon_damage(strength: float, source: Vector3 = Vector3.ZERO) -> void:
	get_parent().get_node("Trader").take_weapon_damage(strength,source)
func take_damage(amount: float, source: Vector3 = Vector3.ZERO) -> void:
	take_weapon_damage(amount / (preload("res://original_damage.gd").SHIELD_POINTS_PER_RAW * maxf(0.0001,float(get_meta("damage_sustain",0.3)))),source)

func take_damage_from(amount: float, source: Vector3, attacker: Node3D) -> void:
	take_weapon_damage_from(amount / (preload("res://original_damage.gd").SHIELD_POINTS_PER_RAW * maxf(0.0001,float(get_meta("damage_sustain",0.3)))),source,attacker)

func take_weapon_damage_from(strength: float, source: Vector3, attacker: Node3D) -> void:
	var agent := get_parent().get_node("Trader")
	if agent.has_method("take_weapon_damage_from"): agent.take_weapon_damage_from(strength,source,attacker)
	else: agent.take_weapon_damage(strength,source)
