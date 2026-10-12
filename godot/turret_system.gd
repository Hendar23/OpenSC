extends Node
const Identity = preload("res://entity_identity.gd")
var events: RefCounted
const Turret = preload("res://gun_turret.gd")
const Assets = preload("res://clump_loader.gd")
var turrets: Array[Node3D] = []
var templates: Array[Node3D] = []
var bubbles: Node3D
func setup(world: Node3D, folder: String, player: Node3D, faction_hostile: Callable) -> void:
	# One bounded world-space batch for all missiles; wakes survive their missile.
	bubbles = preload("res://propeller_bubbles.gd").new(); bubbles.name = "MissileBubbles"; add_child(bubbles)
	bubbles.surface_height = float(world.get_meta("surface_height",INF))
	var texture := Assets._load_texture(folder,"BUBBLE","BUBBLEM",{})
	bubbles.configure(texture)
	var frames := preload("res://mine_explosion.gd").load_frames(folder)
	var sound := preload("res://submarine_weapons.gd")._sound(folder,"audio.object.mine.explosion","EXPLODE1")
	for model in ["TMISSILE","HMISSILE"]: templates.append(Assets.load_clump(folder.path_join("CLUMPS/" + model + ".DFF")))
	for node in world.find_children("GunTurret","Node3D",true,false):
		if not node is Turret: continue
		node.player = player; node.hostile = faction_hostile
		node.bubble_trail = bubbles
		node.bubble_texture = texture
		node.missile_template = templates[1 if node.tuning.turret_homing else 0]
		node.explosion_frames = frames; node.explosion_sound = sound
		turrets.append(node)
		if events != null: node.destroyed.connect(events.entity_destroyed.emit)
func reset() -> void:
	for wreck in get_tree().get_nodes_in_group("turret_wrecks"):
		if get_parent().is_ancestor_of(wreck): wreck.free()
	if bubbles != null: bubbles.clear()
	for missile in get_tree().get_nodes_in_group("turret_missiles"): missile.free()
	for turret in turrets:
		turret.mission_owner = ""
		turret.reset()
func snapshot() -> Dictionary:
	var result := {}
	for turret in turrets:
		result[Identity.of(turret)] = {"mission_owner":turret.mission_owner,"health":turret.health,"retaliation":turret.retaliation,"cooldown":turret.cooldown}
	return result
static func valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 5000: return false
	for key in value:
		if not Identity.valid(key) or not value[key] is Dictionary: return false
		if not value[key].get("mission_owner","") is String or value[key].get("mission_owner","").length() > 256: return false
		for field in ["health","retaliation","cooldown"]:
			var amount: Variant = value[key].get(field)
			if not (amount is float or amount is int) or not is_finite(amount) or amount < 0 or amount > 100000: return false
	return true
func restore(value: Dictionary) -> void:
	for turret in turrets:
		var state: Dictionary = value.get(Identity.of(turret),{})
		if state.is_empty(): continue
		turret.mission_owner = state.get("mission_owner","")
		turret.health = minf(float(turret.tuning.turret_health),float(state.health))
		turret.retaliation = float(state.retaliation); turret.cooldown = float(state.cooldown)
		turret.dead = turret.health <= 0
		turret.get_parent().visible = not turret.dead
		if turret.hitbox != null: turret.hitbox.collision_layer = 0 if turret.dead else 1
func _exit_tree() -> void:
	for template in templates:
		if is_instance_valid(template): template.free()
