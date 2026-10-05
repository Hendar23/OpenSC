extends SceneTree
const Editor = preload("res://asset_editor.gd")
const Mounts = preload("res://submarine_mounts.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var editor := Editor.new(); editor.remember_preferences = false; root.add_child(editor); await process_frame
	editor._show_mounts(); await process_frame
	var panel: Control = editor.mount_editor
	check(panel.visible and not editor.asset_interface.visible and not editor.map_editor.visible,"Mounts has a dedicated editor mode")
	check(panel.mounts.size() == 2 and panel.pilot.visual != null,"Preview loads the active sub with equipment and weapon mounts")
	panel.selected = "zapper"; panel.selector.select(1); panel._sync()
	var mount: Node3D = panel.mounts.zapper
	var default_pose: Transform3D = mount.get_meta("default_mount")
	panel.controls[2].value += 0.05; panel.controls[4].value = 15
	check(is_equal_approx(mount.position.z,panel.controls[2].value) and is_equal_approx(mount.rotation_degrees.y,15),"Position and rotation controls update the actual preview mount")
	var path := "res://tests/mount-settings-fixtures.json"
	check(Mounts.save(panel.pilot.visual,panel.mounts,path) == OK,"Mount profiles can be saved")
	var clone := Node3D.new(); panel.pilot.add_child(clone); Mounts.apply(clone,panel.pilot.visual,"zapper",path)
	check(clone.transform.is_equal_approx(mount.transform),"Saved positions and rotations round-trip")
	var other := Node3D.new(); other.set_meta("asset_mod","Another submarine")
	var untouched := Node3D.new(); Mounts.apply(untouched,other,"zapper",path)
	check(untouched.transform == Transform3D.IDENTITY,"Other submarine profiles retain their default mounts")
	other.free(); untouched.free(); DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if DisplayServer.get_name() != "headless":
		mount.transform = default_pose; panel._sync(); await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/mount-editor-preview.png")
	editor._set_mode(false)
	check(editor.asset_interface.visible and not panel.visible,"Assets button returns to the asset browser")
	editor.queue_free(); await process_frame
	print("Mount editor: 7 checks, %d failures" % failures); quit(1 if failures else 0)
