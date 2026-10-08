extends HBoxContainer
const Assets = preload("res://clump_loader.gd")
const Pilot = preload("res://submarine_controller.gd")
const Equipment = preload("res://submarine_equipment.gd")
const Weapons = preload("res://submarine_weapons.gd")
const Mounts = preload("res://submarine_mounts.gd")
var viewport: SubViewport
var camera: Camera3D
var stage: Node3D
var pilot: Node3D
var mounts := {}
var selector: OptionButton
var controls: Array[SpinBox] = []
var size_control: SpinBox
var status: Label
var label: Label
var updating := false
var yaw := 0.8
var pitch := 0.25
var distance := 2.0
var target := Vector3.ZERO
var dragging := false
var selected := "deep_sea_lights"
var equipment: Node3D
var weapons: Node3D

func _ready() -> void:
	var sidebar := VBoxContainer.new(); sidebar.custom_minimum_size.x = 320; add_child(sidebar)
	label = Label.new(); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sidebar.add_child(label)
	selector = OptionButton.new(); selector.add_item("Deep-Sea Lights"); selector.add_item("Zapper"); selector.add_item("Suck-O-Matic"); selector.add_item("Magnet"); sidebar.add_child(selector)
	selector.item_selected.connect(func(index: int) -> void: selected = ["deep_sea_lights","zapper","suckomat","magnet"][index]; _sync())
	for caption in ["Position X (right)","Position Y (up)","Position Z (back)","Rotation X (degrees)","Rotation Y (degrees)","Rotation Z (degrees)"]:
		var row := HBoxContainer.new(); sidebar.add_child(row)
		var text := Label.new(); text.text = caption; text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(text)
		var field := SpinBox.new(); field.min_value = -180 if controls.size() >= 3 else -10; field.max_value = 180 if controls.size() >= 3 else 10
		field.step = 0.5 if controls.size() >= 3 else 0.005; field.custom_minimum_size.x = 115; row.add_child(field); controls.append(field)
		field.value_changed.connect(func(_value: float) -> void: _edit())
	var size_row := HBoxContainer.new(); sidebar.add_child(size_row)
	var size_label := Label.new(); size_label.text = "Model size (%)"; size_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; size_row.add_child(size_label)
	size_control = SpinBox.new(); size_control.min_value = 1; size_control.max_value = 1000; size_control.step = 1; size_control.value = 100; size_control.custom_minimum_size.x = 115
	size_row.add_child(size_control); size_control.value_changed.connect(func(_value: float) -> void: _edit())
	var actions := HBoxContainer.new(); sidebar.add_child(actions)
	var reset := Button.new(); reset.text = "Reset selected"; actions.add_child(reset)
	reset.pressed.connect(func() -> void:
		if mounts.has(selected): mounts[selected].transform = mounts[selected].get_meta("default_mount"); _sync(); status.text = "Default restored in preview. Save mounts to apply.")
	var save := Button.new(); save.text = "Save mounts"; actions.add_child(save)
	save.pressed.connect(_save)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sidebar.add_child(status)
	var instructions := Label.new(); instructions.text = "Drag to orbit · Wheel to zoom\nPositions are relative to the submarine.\nSave, then start a new game to apply.\nEach submarine model has its own profile."; instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sidebar.add_child(instructions)
	var preview := SubViewportContainer.new(); preview.stretch = true; preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL; preview.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(preview)
	preview.gui_input.connect(_input_preview)
	viewport = SubViewport.new(); viewport.own_world_3d = true; viewport.size = Vector2i(960,640); preview.add_child(viewport)
	stage = Node3D.new(); viewport.add_child(stage)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color(0.025,0.065,0.085)
	stage.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45,-30,0); stage.add_child(sun)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(25,130,0); fill.light_energy = 0.5; stage.add_child(fill)
	camera = Camera3D.new(); camera.current = true; camera.fov = 40; stage.add_child(camera)

func open(folder: String) -> void:
	if pilot != null: pilot.free(); pilot = null
	mounts.clear()
	var visual := Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF"))
	if visual == null: status.text = "Could not load the submarine."; return
	pilot = Pilot.new(); pilot.remember_settings = false; stage.add_child(pilot); pilot.set_physics_process(false); pilot.set_process(false)
	visual.scale *= Pilot.VISUAL_SCALE; visual.rotation.y = PI; pilot.add_child(visual); pilot.visual = visual
	equipment = Equipment.new(); pilot.add_child(equipment); equipment.setup(pilot,folder); equipment.set_process(false)
	weapons = Weapons.new(); pilot.add_child(weapons); weapons.setup(pilot,folder,camera,{}); weapons.set_physics_process(false)
	for item in equipment.available: mounts[item.id] = item.mount
	mounts.zapper = weapons.muzzle
	var box := Equipment._bounds(Equipment._meshes(visual,Transform3D.IDENTITY))
	target = box.get_center(); distance = maxf(0.6,box.size.length() * 1.5)
	label.text = "Submarine mounts\n" + Mounts.profile(visual)
	status.text = "Adjust a mount and save when ready."
	_sync(); _camera()

func _sync() -> void:
	if not mounts.has(selected): return
	for id in mounts: mounts[id].visible = id == selected
	updating = true
	var mount: Node3D = mounts[selected]
	for index in range(3): controls[index].value = mount.position[index]; controls[index + 3].value = mount.rotation_degrees[index]
	size_control.value = mount.scale.x * 100.0
	updating = false

func _edit() -> void:
	if updating or not mounts.has(selected): return
	var mount: Node3D = mounts[selected]
	mount.position = Vector3(controls[0].value,controls[1].value,controls[2].value)
	mount.rotation_degrees = Vector3(controls[3].value,controls[4].value,controls[5].value)
	mount.scale = Vector3.ONE * size_control.value / 100.0
	status.text = "Preview updated. Save mounts to keep changes."

func _save() -> void:
	if pilot == null: return
	status.text = "Mounts saved. Start a new game to apply." if Mounts.save(pilot.visual,mounts) == OK else "Could not save mounting positions."

func _input_preview(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1),0.2,20); _camera()
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.008; pitch = clampf(pitch + event.relative.y * 0.008,-1.4,1.4); _camera()

func _camera() -> void:
	camera.position = target + Vector3(sin(yaw) * cos(pitch),sin(pitch),cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)
