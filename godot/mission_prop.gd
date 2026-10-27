extends "res://salvage_body.gd"
## Physical mission cargo/scenery; no commodity or save-format additions.
signal destroyed
signal damaged
signal towing_attempted
var delivered := false
var sustain := 0.3
var towing_allowed := true
var release_on_tow := false

func prepare_towing() -> bool:
	towing_attempted.emit()
	if not towing_allowed: return false
	if release_on_tow: freeze = false; release_on_tow = false
	return true

func take_damage(amount: float, source: Vector3 = Vector3.ZERO) -> void:
	take_weapon_damage(amount/3.0,source)

func take_weapon_damage(strength: float, _source: Vector3 = Vector3.ZERO) -> void:
	if dead or delivered or strength <= 0: return
	health -= strength*sustain; damaged.emit()
	if health <= 0:
		dead = true; set_deferred("collision_layer",0); destroyed.emit()

func take_weapon_damage_from(strength: float, source: Vector3, _attacker: Node3D) -> void:
	take_weapon_damage(strength,source)

func set_towing_attached(on: bool) -> void:
	set_meta("towing_attached",on)
