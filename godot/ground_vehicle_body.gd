extends CharacterBody3D
var dead: bool:
	get: return get_parent().get_node("GroundVehicle").dead
func take_weapon_damage(strength: float, source: Vector3 = Vector3.ZERO) -> void:
	get_parent().get_node("GroundVehicle").take_weapon_damage(strength,source)
func take_damage(amount: float, source: Vector3 = Vector3.ZERO) -> void:
	take_weapon_damage(amount / maxf(0.0001,float(get_meta("damage_sustain",0.1))),source)

func take_weapon_damage_from(strength: float, source: Vector3, attacker: Node3D) -> void:
	get_parent().get_node("GroundVehicle").take_weapon_damage_from(strength,source,attacker)

func take_damage_from(amount: float, source: Vector3, attacker: Node3D) -> void:
	take_weapon_damage_from(amount / maxf(0.0001,float(get_meta("damage_sustain",0.1))),source,attacker)
