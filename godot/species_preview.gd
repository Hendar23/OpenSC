extends SubViewportContainer
const Document = preload("res://map_document.gd")
const Creatures = preload("res://creature_loader.gd")
const CreatureAnimation = preload("res://creature_animation.gd")
var viewport: SubViewport
var pivot: Node3D
var camera: Camera3D
var model: Node3D
var animation: RefCounted
var time := 0.0
var dragging := false
func _ready() -> void:
	custom_minimum_size = Vector2(0,220)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch = true; tooltip_text = "Drag to rotate; mouse wheel to zoom."
	viewport = SubViewport.new(); viewport.own_world_3d = true; viewport.size = Vector2i(280,220); add_child(viewport)
	var scene := Node3D.new(); viewport.add_child(scene)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.025,0.07,0.09)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE; environment.environment.ambient_light_energy = 0.7
	scene.add_child(environment)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-35,-30,0); scene.add_child(light)
	pivot = Node3D.new(); scene.add_child(pivot)
	camera = Camera3D.new(); camera.current = true; camera.near = 0.005; camera.far = 2000; scene.add_child(camera)
	gui_input.connect(_preview_input)
func show_model(id: String, folder: String) -> void:
	animation = null
	if model != null: model.free(); model = null
	pivot.rotation = Vector3.ZERO; time = 0.0
	model = Document.load_model(id,folder,true)
	if model == null: return
	pivot.add_child(model)
	var boxes: Array[AABB] = []; Creatures._collect_bounds(model,model.transform,boxes)
	var box := AABB(Vector3(-0.5,-0.5,-0.5),Vector3.ONE)
	if not boxes.is_empty():
		box = boxes[0]
		for index in range(1,boxes.size()): box = box.merge(boxes[index])
	model.position -= box.get_center()
	camera.position = Vector3(1.0,0.7,1.0).normalized()
	camera.look_at(Vector3.ZERO)
	var tangent := tan(deg_to_rad(camera.fov) * 0.5)
	var distance := 0.15
	for index in range(8):
		var point := camera.basis.inverse() * (box.get_endpoint(index) - box.get_center())
		distance = maxf(distance,maxf(absf(point.y) / tangent,absf(point.x) / (tangent * 280.0 / 220.0)) + point.z)
	camera.position *= distance * 1.15
	animation = CreatureAnimation.new(model)
func show_object(definition: Dictionary, folder: String) -> void:
	animation = null
	if model != null: model.free(); model = null
	pivot.rotation = Vector3.ZERO
	model = preload("res://object_population.gd").appearance(definition,folder)
	if model == null: return
	pivot.add_child(model)
	camera.position = Vector3(0,0,maxf(0.02,float(definition.size) * 1.4))
	camera.look_at(Vector3.ZERO)
func _process(delta: float) -> void:
	if not is_visible_in_tree() or animation == null: return
	time += delta * 0.5; animation.apply(time)
func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		camera.position *= 0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
		accept_event()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed; accept_event()
	if event is InputEventMouseMotion and dragging:
		pivot.rotation.y += event.relative.x * 0.01
		pivot.rotation.x = clampf(pivot.rotation.x + event.relative.y * 0.01,-PI / 3,PI / 3)
		accept_event()
