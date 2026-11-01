extends "res://gun_turret.gd"
## Original BOSS guns fire a straight MISSILE every 15 ticks (00439620).
func take_weapon_damage(strength: float, point: Vector3 = Vector3.ZERO) -> void:
	var was_dead := dead
	super.take_weapon_damage(strength,point)
	if was_dead or not dead: return
	var boss := get_parent().get_parent()
	# The shared turret assumes a world-level mount. Keep detached gun wrecks
	# outside our nested boss so they survive and are not fragmented twice.
	for child in boss.get_children():
		if child.is_in_group("turret_wrecks"): child.reparent(boss.get_parent(),true)

func burst(point: Vector3, diameter: float) -> void:
	var effect := preload("res://mine_explosion.gd").new()
	get_parent().get_parent().get_parent().add_child(effect)
	effect.global_position = point; effect.setup(explosion_frames,diameter,explosion_sound)

func _physics_process(delta: float) -> void:
	if dead or head == null or not is_instance_valid(player) or not player.active or player.dead: return
	cooldown = maxf(0,cooldown-delta)
	var direction := (player.global_position-head.global_position).normalized()
	if direction.is_zero_approx(): return
	var up := Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP
	var desired := Basis.looking_at(direction,up,true)
	var angle := head.global_basis.orthonormalized().get_rotation_quaternion().angle_to(desired.get_rotation_quaternion())
	head.global_basis = head.global_basis.orthonormalized().slerp(desired,minf(1,deg_to_rad(50)*delta/maxf(0.00001,angle)))
	if cooldown > 0 or head.global_basis.z.angle_to(direction) > deg_to_rad(2) or missile_template == null: return
	var muzzle := head.global_position+direction*0.7
	if not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle,player.global_position,1,[hitbox.get_rid()])).is_empty(): return
	var missile := preload("res://turret_missile.gd").new()
	get_parent().get_parent().get_parent().add_child(missile)
	missile.inflict = 8; missile.setup(self,missile_template,muzzle,direction,player,false)
	missile.get_child(0).show()
	cooldown = 15.0/25.0; shots += 1
