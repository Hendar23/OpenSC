extends StaticBody3D
signal disabled
signal armour_hit
var health := 1.5
var open := false
var dead := false
var door: Node3D
var shut_pose := Transform3D.IDENTITY
var open_amount := 0.0
var animated_door: Node3D
var door_meshes: Array[MeshInstance3D] = []
var shell: StaticBody3D
const INTERNAL_DEPTH := 2.0 # 00490640, 004dbf10
const INTERNAL_SUSTAIN := 0.1 # 004735c0
const APERTURE_HALF_SIZE := Vector2(0.87,0.684) # TESTDOOR inner edges, local X/Z.
const CHARGE_RADIUS := 0.1

func contains_charge(point: Vector3) -> bool:
	var offset := point-global_position
	var local := door.to_local(point) if is_instance_valid(door) else offset
	return not dead and offset.y <= 0.901 and offset.y >= -INTERNAL_DEPTH-CHARGE_RADIUS and absf(local.x) <= APERTURE_HALF_SIZE.x and absf(local.z) <= APERTURE_HALF_SIZE.y

func charge_at_target(point: Vector3) -> bool:
	# The scenery floor covers the bottom of the shaft just above the hidden
	# target. Treat reaching that floor as a direct hit, rather than exploding
	# against terrain and losing most of the damage to artificial separation.
	return contains_charge(point) and point.y-global_position.y <= -INTERNAL_DEPTH+0.4

func _ready() -> void:
	add_to_group("depth_charge_vents")
	# Retail scales the hidden .5-radius target by .3, two units below the
	# moving hatch. Blast damage is measured against this point, not the hatch.
	var target := StaticBody3D.new(); target.name = "InternalTarget"
	target.collision_layer = 4; target.collision_mask = 0; add_child(target)
	target.position.y = -INTERNAL_DEPTH
	var shape := CollisionShape3D.new(); shape.shape = SphereShape3D.new(); shape.shape.radius = 0.15; target.add_child(shape)

func accepts_charge(point: Vector3, motion: Vector3, step: float = 0.0) -> bool:
	if dead or open_amount <= 0.0 or motion.y > 0.0: return false
	var offset := point - global_position
	# Check the approaching segment too, before physics can hit the solid shell.
	if offset.y > 0.9 and motion.y < 0.0:
		var crossing := (0.9-offset.y)/motion.y
		if crossing > step: return false
		point += motion * crossing; offset = point-global_position
	if offset.y < -0.1 or offset.y > 0.901: return false
	var local := door.to_local(point) if is_instance_valid(door) else offset
	return absf(local.x) <= APERTURE_HALF_SIZE.x-CHARGE_RADIUS and absf(local.z) <= APERTURE_HALF_SIZE.y * open_amount-CHARGE_RADIUS

func _process(delta: float) -> void:
	if not is_instance_valid(door): return
	if animated_door != door:
		animated_door = door; door_meshes.clear()
		for mesh: MeshInstance3D in door.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh != null and mesh.mesh.get_blend_shape_count() > 0: door_meshes.append(mesh)
	open_amount = move_toward(open_amount,1.0 if open or dead else 0.0,delta * 2)
	door.transform = shut_pose
	# TESTDOOR's base mesh has the gap; its morph brings both leaves together.
	# Unlike city hatch assets, blend weight 1 means CLOSED for this model.
	if not door_meshes.is_empty(): preload("res://dock_access.gd").open({"meshes":door_meshes},1.0-open_amount)
	else: door.transform = shut_pose.translated_local(Vector3(0,0,0.65 * open_amount))

func take_damage(_amount: float, _source: Vector3 = Vector3.ZERO) -> void:
	armour_hit.emit()

func take_weapon_damage(_strength: float, _source: Vector3 = Vector3.ZERO) -> void:
	armour_hit.emit()

func take_weapon_damage_from(strength: float, source: Vector3, _attacker: Node3D) -> void:
	take_weapon_damage(strength,source)

func depth_charge(strength: float) -> void:
	if dead or not open: return
	health -= strength
	if health <= 0: dead = true; disabled.emit()

func depth_charge_from(_strength: float, source: Vector3, _motion: Vector3, _entered: bool = false) -> void:
	if dead: return
	var internal_point := global_position + Vector3.DOWN * INTERNAL_DEPTH
	var distance := source.distance_to(internal_point)
	# Original 0044a2d0 applies radial damage directly to the hidden target;
	# no entry flag, direction test, or additional narrow column is involved.
	if distance > preload("res://depth_charge.gd").BLAST_RADIUS: return
	health -= preload("res://depth_charge.gd").damage_at(distance) * INTERNAL_SUSTAIN
	if health <= 0: dead = true; disabled.emit()
