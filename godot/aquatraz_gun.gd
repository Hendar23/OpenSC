extends StaticBody3D
## City0044c610 gives each of the eight guns75 shields and .5 sustain.
signal destroyed(gun: Node3D)
var game: Node
var health := 75.0
var dead := false
var cooldown := 0.0
var visual: Node3D
var barrel: Node3D
var collider: CollisionShape3D

func setup(context: Node, model: Node3D) -> void:
	game = context; visual = model
	collision_layer = 9; collision_mask = 0
	set_meta("faction",3); set_meta("damage_sustain",0.5)
	barrel = Node3D.new(); add_child(barrel); barrel.add_child(visual)
	var shape := CollisionShape3D.new()
	shape.shape = preload("res://model_hitbox.gd").fitted_hull(visual)
	add_child(shape); collider = shape
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON

func take_damage(amount: float, source: Vector3 = Vector3.ZERO) -> void:
	take_weapon_damage(amount/3.0,source)

func take_weapon_damage(strength: float, _source: Vector3 = Vector3.ZERO) -> void:
	if dead or strength <= 0: return
	health -= strength*0.5
	if health > 0: return
	dead = true; collision_layer = 0; collision_mask = 0
	collider.set_deferred("disabled",true)
	var explosion := preload("res://mine_explosion.gd").new(); game.world_root.add_child(explosion)
	explosion.global_position = barrel.to_global(Vector3(0,0,1.5))
	explosion.setup(game.submarine_traffic.explosion_frames,1.2,game.submarine_traffic.explosion_sound)
	var wreck := preload("res://submarine_death.gd").new(); game.world_root.add_child(wreck)
	wreck.global_position = global_position
	wreck.setup_machine(self,visual,game.submarine_traffic.bubble_texture)
	visual.hide(); destroyed.emit(self)
