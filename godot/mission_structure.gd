extends StaticBody3D
## Destructible mission scenery. Collision follows the visible model surfaces.
signal destroyed
signal attacked
var health := 20.0
var sustain := 0.1 # OUTPOSTSPHERE, OBJECTS.CSV; mission callback overrides health only.
var dead := false
var visual: Node3D
var game: Node
var smoke: Node3D

func setup(model: Node3D, context: Node, strength: float) -> void:
	game = context; visual = model; health = strength
	collision_layer = 1 | 8; collision_mask = 0
	add_child(model)
	var meshes := preload("res://submarine_equipment.gd")._meshes(model,Transform3D.IDENTITY)
	if not meshes.is_empty(): set_meta("mission_target_center",preload("res://submarine_equipment.gd")._bounds(meshes).get_center())
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null: continue
		var shape := CollisionShape3D.new(); shape.shape = mesh.mesh.create_trimesh_shape(); add_child(shape)
		shape.transform = global_transform.affine_inverse()*mesh.global_transform
	set_meta("damage_sustain",sustain)

func start_smoke() -> void:
	smoke = preload("res://submarine_damage_smoke.gd").new(); add_child(smoke)
	smoke.setup(visual,game.game_folder); smoke.damaged = true; smoke.enabled = true

func take_damage(amount: float, source: Vector3 = Vector3.ZERO) -> void:
	take_weapon_damage(amount/3.0,source)

func take_weapon_damage(strength: float, _source: Vector3 = Vector3.ZERO) -> void:
	if dead or strength <= 0: return
	health -= strength*sustain; attacked.emit()
	if health > 0: return
	dead = true; set_deferred("collision_layer",0)
	var effect := preload("res://base_destruction.gd").new(); game.world_root.add_child(effect)
	var models: Array[Node3D] = [visual]; var plumes: Array[Node] = []
	if is_instance_valid(smoke): plumes.append(smoke)
	effect.setup(models,plumes,game.submarine_traffic)
	destroyed.emit()

func take_weapon_damage_from(strength: float, source: Vector3, _owner: Node3D) -> void:
	take_weapon_damage(strength,source)
