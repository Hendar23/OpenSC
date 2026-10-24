extends "res://salvage_body.gd"
## TRADMININGSUB 0047a950 / rovrtn 0043c3e0; retains a physical disabled hull.
signal destroyed
var damage_sustain := 0.3
var game: Node
var smoke: Node3D
var movable := false

func setup(definition: Dictionary, visual: Node3D, fragment: int, water: float, running: bool) -> void:
	super.setup(definition,visual,fragment,water,running)
	linear_damp = 1.25; angular_damp = 2.0
	set_meta("damage_sustain",damage_sustain)
	set_meta("mission_target_center",preload("res://submarine_equipment.gd")._bounds(preload("res://submarine_equipment.gd")._meshes(visual,Transform3D.IDENTITY)).get_center())

func _integrate_forces(_state: PhysicsDirectBodyState3D) -> void:
	# Disabled, neutrally buoyant; must not sink out of the authored mine puzzle.
	pass

func receive_rov_push(motion: Vector3) -> void:
	if not movable or dead or motion.length() < 0.05: return
	sleeping = false
	apply_central_impulse(motion.limit_length(2.0)*mass*0.15)

func take_damage(amount: float, source: Vector3 = Vector3.ZERO) -> void:
	take_weapon_damage(amount,source)

func take_weapon_damage(strength: float, _source: Vector3 = Vector3.ZERO) -> void:
	if dead or strength <= 0: return
	health = maxf(0,health-strength*damage_sustain)
	if health > 0: return
	dead = true; set_deferred("collision_layer",0); set_deferred("collision_mask",0); set_deferred("freeze",true)
	if is_instance_valid(smoke): smoke.enabled = false
	if is_instance_valid(game):
		var wreck := preload("res://submarine_death.gd").new(); game.world_root.add_child(wreck); wreck.global_position = global_position
		wreck.setup_machine(self,get_child(0),game.submarine_traffic.bubble_texture,[],linear_velocity)
		var effect := preload("res://mine_explosion.gd").new(); game.world_root.add_child(effect); effect.global_position = global_position
		effect.setup(game.submarine_traffic.explosion_frames,1.5,game.submarine_traffic.explosion_sound)
	hide(); destroyed.emit()

func take_weapon_damage_from(strength: float, source: Vector3, _attacker: Node3D) -> void:
	take_weapon_damage(strength,source)
