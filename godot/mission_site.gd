extends Node3D
## A temporary replacement restores the authored scenery when it leaves the tree.
var masked: Array[Dictionary] = []
var committed := false
signal stepped(delta: float)

func _physics_process(delta: float) -> void:
	stepped.emit(delta)

func mask(scene: Node3D) -> void:
	if scene == null: return
	masked.append({"node":weakref(scene),"visible":scene.visible,"had_dock":scene.has_meta("mission_dock_disabled"),"dock":scene.get_meta("mission_dock_disabled",false)})
	scene.hide()
	for child in scene.find_children("*","CollisionObject3D",true,false):
		masked.append({"node":weakref(child),"layer":child.collision_layer,"mask":child.collision_mask})
		child.collision_layer = 0; child.collision_mask = 0
	for child in scene.get_children():
		if child.get_script() == preload("res://scenery_rotation.gd"):
			masked.append({"node":weakref(child),"mode":child.process_mode}); child.process_mode = Node.PROCESS_MODE_DISABLED

func restore() -> void:
	for state in masked:
		var node: Node = state.node.get_ref()
		if node == null: continue
		if state.has("visible"):
			node.visible = state.visible
			if state.had_dock: node.set_meta("mission_dock_disabled",state.dock)
			else: node.remove_meta("mission_dock_disabled")
		elif state.has("layer"): node.collision_layer = state.layer; node.collision_mask = state.mask
		elif state.has("mode"): node.process_mode = state.mode
		elif state.has("armed"): node.tuning.turret_armed = state.armed; node.mission_owner = state.owner
	masked.clear()

func _exit_tree() -> void:
	if not committed: restore()
