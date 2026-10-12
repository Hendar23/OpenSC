extends StaticBody3D
func take_weapon_damage(strength: float, source: Vector3 = Vector3.ZERO) -> void:
	var turret := get_parent().get_node_or_null("GunTurret")
	if turret != null: turret.take_weapon_damage(strength,source)
func take_damage(amount: float, source: Vector3 = Vector3.ZERO) -> void:
	# Compatibility for callers that have already applied sustain.
	take_weapon_damage(amount / maxf(0.0001,float(get_meta("damage_sustain",0.3))),source)

func take_weapon_damage_from(strength: float, source: Vector3, attacker: Node3D) -> void:
	var turret := get_parent().get_node_or_null("GunTurret")
	if turret != null: turret.take_weapon_damage_from(strength,source,attacker)

func take_damage_from(amount: float, source: Vector3, attacker: Node3D) -> void:
	take_weapon_damage_from(amount / maxf(0.0001,float(get_meta("damage_sustain",0.3))),source,attacker)
