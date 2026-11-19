extends RefCounted
## Fixed exterior view exposed through the original city-picture window.
var port_node: Node3D
var eye := Vector3.ZERO
var target := Vector3.ZERO
var active := false
var hud_was_visible := true

func close(game: Node3D) -> void:
	if active and is_instance_valid(game.cockpit_hud): game.cockpit_hud.visible = hud_was_visible
	active = false; port_node = null

func update(game: Node3D) -> void:
	var port: Dictionary = game.docking.current
	if port.is_empty(): return
	if not active:
		active = true; hud_was_visible = game.cockpit_hud.visible
	game.cockpit_hud.hide()
	if port_node != port.node:
		port_node = port.node
		var angles := {1:145.0,2:35.0,3:0.0,4:325.0,5:135.0,6:0.0}
		var angle := deg_to_rad(float(angles.get(int(port.node.get_meta("city_id")),45.0)))
		target = port.entry - Vector3.UP * 1.8
		if int(port.node.get_meta("city_id")) == 5: target = port.inside + Vector3.UP
		eye = port.entry + Vector3(sin(angle)*17,5,cos(angle)*17)
		eye.y = minf(eye.y,game.pilot.surface_height - 0.8)
		var start: Vector3 = port.entry + Vector3.UP * 0.2
		start.y = minf(start.y,game.pilot.surface_height - 0.5)
		var hit := game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,eye,1))
		if not hit.is_empty(): eye = start.lerp(eye,maxf(0.05,(start.distance_to(hit.position)-0.8)/start.distance_to(eye)))
	game.camera.global_position = eye
	game.camera.look_at(target,Vector3.UP)
	# Centre the subject in the upper picture window, also on widescreen displays.
	var ui: Control = game.dock_interface.layout
	var screen_point := ui.position + Vector2(320,150) * ui.scale
	var ray: Vector3 = game.camera.project_ray_normal(screen_point)
	game.camera.global_basis = Basis(Quaternion(ray,(target-eye).normalized())) * game.camera.global_basis
