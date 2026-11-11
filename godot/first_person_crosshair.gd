extends Control

const Projectile = preload("res://player_projectile.gd")
const Arsenal = preload("res://player_arsenal.gd")
const Mounts = preload("res://submarine_mounts.gd")
const GREEN := Color(0.15,1.0,0.25)
const RED := Color(1.0,0.12,0.08)
var game: Node3D
var on_target := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()

func _process(_delta: float) -> void:
	visible = _enabled()
	if visible: queue_redraw()

func _physics_process(_delta: float) -> void:
	on_target = _enabled() and _lined_up()

func _enabled() -> bool:
	if not is_instance_valid(game.pilot) or not game.pilot_mode or not game.first_person: return false
	if not game.front_end.gameplay_menu.crosshair_enabled or game.pilot.dead or game.pilot.remote_controlled: return false
	if game.world_loading or game.loading_save or game.get_tree().paused: return false
	if game.map_open or game.developer_ui_visible or game.dock_interface_active: return false
	if game.loading_canvas.visible or game.front_end.menu_layer.visible: return false
	if game.photo_mode != null and game.photo_mode.active: return false
	if game.fmv != null and game.fmv.active: return false
	return game.camera.current

func _lined_up() -> bool:
	var weapons: Node3D = game.weapons
	if not is_instance_valid(weapons): return false
	var id: String = weapons.current().get("id","")
	var origin: Vector3
	var forward: Vector3
	var reach: float
	var mask := 13
	if id == "zapper":
		origin = weapons.muzzle.get_node("Emitter").global_position
		forward = -weapons.muzzle.global_basis.z.normalized()
		reach = weapons.effective_range()
	elif id in ["missile","homers","ripper","electro"]:
		var mount: Node3D = weapons.arsenal.mounts.get("missile" if id == "homers" else id)
		if not is_instance_valid(mount): return false
		var offset := Vector3(0,0.1,-0.2) if id == "ripper" else Vector3(0,0,-0.3)
		origin = Mounts.launch_point(mount,game.pilot.visual,id,offset)
		forward = -mount.global_basis.z.normalized()
		reach = Arsenal.RIPPER_RANGE if id == "ripper" else game.camera.far if id == "electro" else Projectile.powered_range(id)
		if id != "ripper": mask = 15
	else: return false
	var camera_origin: Vector3 = game.camera.global_position
	var camera_forward: Vector3 = -game.camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(camera_origin,camera_origin + camera_forward * (reach + camera_origin.distance_to(origin)),mask,[game.pilot.get_rid()])
	query.hit_back_faces = true; query.hit_from_inside = true
	var space := game.get_world_3d().direct_space_state
	var aimed := space.intersect_ray(query)
	var body: Node3D = aimed.get("collider")
	if not _damageable(body) or origin.distance_to(aimed.position) > reach: return false
	# Check the weapon's own firing line too, so the camera cannot mark a
	# target red while a nearby rock blocks the muzzle.
	query.from = origin; query.to = origin + forward * reach
	var actual := space.intersect_ray(query)
	return actual.get("collider") == body

static func _damageable(body: Node3D) -> bool:
	if not is_instance_valid(body) or body.get("dead") == true or not body.get_meta("weapon_target",true): return false
	return body.has_method("take_damage") or body.has_method("take_weapon_damage") or body.has_method("take_weapon_damage_from") or body.has_method("take_typed_weapon_damage") or body.has_method("take_located_weapon_damage")

func _draw() -> void:
	var factor := maxf(1.0,get_viewport_rect().size.y / 720.0)
	var center := (get_viewport_rect().size * 0.5).round()
	var tint := RED if on_target else GREEN
	for x in [-1.0,1.0]:
		for y in [-1.0,1.0]:
			var corner := center + Vector2(x,y) * 7.0 * factor
			draw_polyline(PackedVector2Array([corner - Vector2(x * 4.0 * factor,0),corner,corner - Vector2(0,y * 4.0 * factor)]),tint,1.2 * factor,true)
