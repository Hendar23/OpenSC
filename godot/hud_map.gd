extends RefCounted

const RESOLUTION := 512
var bounds: AABB
var texture: ImageTexture
var markers: Array[Dictionary] = []
var height_samples := PackedFloat32Array()
var scenery_baked := false
var surface_height := INF
var passage_clearance := 1.1
var blocked_samples := PackedByteArray()
const PASSAGE_MARGIN := 0.15
const REVEAL_RADIUS := 10.0
var reveal_radius := REVEAL_RADIUS:
	set(value):
		reveal_radius = clampf(value,2.0,30.0)
		last_explored = Vector2(INF,INF)
var explored: Image
var exploration_texture: ImageTexture
var last_explored := Vector2(INF,INF)
var last_explored_height := INF
func initialize_exploration() -> void:
	# Exploration belongs to this game, independently of saved preferences.
	explored = Image.create(RESOLUTION,RESOLUTION,false,Image.FORMAT_L8)
	explored.fill(Color.BLACK)
	exploration_texture = ImageTexture.create_from_image(explored)
	last_explored = Vector2(INF,INF)
	last_explored_height = INF

func explore(point: Vector3) -> void:
	if explored == null: return
	var position := Vector2(point.x,point.z)
	if position.distance_squared_to(last_explored) < 0.25 and absf(point.y - last_explored_height) < 0.25: return
	last_explored = position
	last_explored_height = point.y
	var centre := uv(point) * (RESOLUTION - 1)
	var radius := Vector2(reveal_radius / bounds.size.x,reveal_radius / bounds.size.z) * (RESOLUTION - 1)
	var low := (centre - radius).floor().clamp(Vector2.ZERO,Vector2.ONE * (RESOLUTION - 1))
	var high := (centre + radius).ceil().clamp(Vector2.ZERO,Vector2.ONE * (RESOLUTION - 1))
	var changed := false
	for y in range(int(low.y),int(high.y) + 1):
		for x in range(int(low.x),int(high.x) + 1):
			var distance := ((Vector2(x,y) - centre) / radius).length()
			var reveal := 1.0 - smoothstep(0.88,1.0,distance)
			if reveal > explored.get_pixel(x,y).r and _visible_from(point,x,y):
				explored.set_pixel(x,y,Color(reveal,reveal,reveal))
				changed = true
	if changed:
		exploration_texture.update(explored)

func _visible_from(observer: Vector3, x: int, y: int) -> bool:
	if height_samples.size() != RESOLUTION * RESOLUTION: return true
	var destination_height := height_samples[y * RESOLUTION + x]
	if not is_finite(destination_height): return false
	var start := uv(observer) * (RESOLUTION - 1)
	var end := Vector2(x,y)
	var distance := end - start
	var steps := maxi(1,int(ceil(maxf(absf(distance.x),absf(distance.y)) * 2.0)))
	# Follow the sightline to the mapped surface, rather than revealing a
	# flat circle through ridges. Half-cell steps catch narrow occluders.
	for step in range(1,steps):
		var fraction := float(step) / steps
		var cell := Vector2i((start + distance * fraction).round())
		if cell.x < 0 or cell.y < 0 or cell.x >= RESOLUTION or cell.y >= RESOLUTION: return false
		var terrain := height_samples[cell.y * RESOLUTION + cell.x]
		var ray_height := lerpf(observer.y,destination_height + 0.1,fraction)
		if is_finite(terrain) and terrain > ray_height + 0.1: return false
	return true

func reset_exploration() -> void:
	if explored == null: return
	explored.fill(Color.BLACK)
	exploration_texture.update(explored)
	last_explored = Vector2(INF,INF)
	last_explored_height = INF

func is_explored(point: Vector3) -> bool:
	if explored == null: return false
	var cell := Vector2i(uv(point) * (RESOLUTION - 1))
	if cell.x < 0 or cell.y < 0 or cell.x >= RESOLUTION or cell.y >= RESOLUTION: return false
	return explored.get_pixel(cell.x,cell.y).r > 0.5

func bake_world(world: Node3D, tree: SceneTree) -> void:
	if DisplayServer.get_name() == "headless": return
	# Render once in an isolated, daylight scene. Sharing mesh resources
	# preserves original textures and modern replacements without copying
	# scripts, moving wildlife, water or the player's submarine.
	var view := SubViewport.new()
	view.size = Vector2i(2048,maxi(1,int(2048.0 * bounds.size.z / bounds.size.x)))
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(view)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.005,0.01,0.025)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	view.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65,-30,0)
	sun.light_energy = 0.65
	view.add_child(sun)
	for source in world.find_children("*", "MeshInstance3D",true,false):
		if source.name == "WaterSurface": continue
		var ancestor: Node = source
		var excluded := false
		while ancestor != world and ancestor != null:
			if str(ancestor.name) in ["AmbientFish", "Wildlife", "PulseLights"]: excluded = true; break
			ancestor = ancestor.get_parent()
		if excluded: continue
		var copy := MeshInstance3D.new()
		copy.mesh = source.mesh
		copy.material_override = _map_material(source.material_override)
		copy.transform = world.global_transform.affine_inverse() * source.global_transform
		for surface in range(source.get_surface_override_material_count()):
			copy.set_surface_override_material(surface,_map_material(source.get_surface_override_material(surface)))
		view.add_child(copy)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = bounds.size.z
	camera.far = bounds.size.y + 200.0
	view.add_child(camera)
	camera.position = Vector3(bounds.get_center().x,bounds.end.y + 50.0,bounds.get_center().z)
	camera.look_at(bounds.get_center(),Vector3.FORWARD)
	camera.current = true
	for frame in range(3): await tree.process_frame
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	view.queue_free()
	var outlines := PackedByteArray()
	var blocked_cells := PackedByteArray()
	outlines.resize(RESOLUTION * RESOLUTION)
	blocked_cells.resize(RESOLUTION * RESOLUTION)
	for y in range(RESOLUTION):
		for x in range(RESOLUTION):
			outlines[y * RESOLUTION + x] = 1 if _border_edge(x,y) else 0
			blocked_cells[y * RESOLUTION + x] = 1 if _blocked(x,y) else 0
	# Muted terrain colours and warm impassable borders echo the original map,
	# while retaining roof textures and other recognisable scenery details.
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var colour := image.get_pixel(x,y)
			var grey := colour.get_luminance()
			colour = colour.lerp(Color(grey,grey,grey),0.7)
			var cell := Vector2i(int(float(x) / image.get_width() * (RESOLUTION - 1)),int(float(y) / image.get_height() * (RESOLUTION - 1)))
			if blocked_cells[cell.y * RESOLUTION + cell.x] == 1: colour *= Color(0.25,0.25,0.3)
			if outlines[cell.y * RESOLUTION + cell.x] == 1: colour = Color(0.95,0.23,0.045)
			image.set_pixel(x,y,colour)
		if y % 128 == 0: await tree.process_frame
	image.generate_mipmaps()
	texture = ImageTexture.create_from_image(image)
	scenery_baked = true

static func _map_material(material: Material) -> Material:
	if material == null: return null
	# The map is an illuminated instrument, baked in its own daylight scene.
	# Use source colours rather than the live cave/depth lighting shaders.
	if material.has_meta("natural_original"): material = material.get_meta("natural_original")
	if material is ShaderMaterial and material.shader in [preload("res://plant_current.gdshader"),preload("res://natural_plant.gdshader")]:
		var leaf := StandardMaterial3D.new(); leaf.albedo_color = material.get_shader_parameter("albedo_color")
		if material.get_shader_parameter("has_texture"): leaf.albedo_texture = material.get_shader_parameter("albedo_texture")
		leaf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR; leaf.alpha_scissor_threshold = 0.5; leaf.cull_mode = BaseMaterial3D.CULL_DISABLED; leaf.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		return leaf
	var copy: Material = material.duplicate(); copy.next_pass = null
	return copy

func _border_edge(x: int, y: int) -> bool:
	var height := height_samples[y * RESOLUTION + x]
	if not is_finite(height) or _blocked(x,y): return false
	for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var neighbour: Vector2i = Vector2i(x,y) + offset
		if neighbour.x < 0 or neighbour.y < 0 or neighbour.x >= RESOLUTION or neighbour.y >= RESOLUTION: continue
		if _blocked(neighbour.x,neighbour.y): return true
	return false

func _blocked(x: int,y: int) -> bool:
	if blocked_samples.size() == height_samples.size(): return blocked_samples[y * RESOLUTION + x] == 1
	return _passage_blocked(x,y)

func _passage_blocked(x: int,y: int) -> bool:
	# A point sample can leave a false opening on a sloping rim. Check the
	# sub's whole footprint, allowing for the map cell's sampling uncertainty.
	var spacing := Vector2(bounds.size.x,bounds.size.z) / (RESOLUTION - 1)
	if spacing.x <= 0.0 or spacing.y <= 0.0:
		var height := height_samples[y * RESOLUTION + x]
		return is_finite(height) and surface_height - height <= passage_clearance + PASSAGE_MARGIN
	var footprint := passage_clearance * 0.5 + spacing.length() * 0.5
	var reach := Vector2i(ceil(footprint / spacing.x),ceil(footprint / spacing.y))
	for dy in range(-reach.y,reach.y + 1):
		for dx in range(-reach.x,reach.x + 1):
			if (Vector2(dx,dy) * spacing).length_squared() > footprint * footprint: continue
			var cell := Vector2i(x + dx,y + dy)
			if cell.x < 0 or cell.y < 0 or cell.x >= RESOLUTION or cell.y >= RESOLUTION: continue
			var height := height_samples[cell.y * RESOLUTION + cell.x]
			if is_finite(height) and surface_height - height <= passage_clearance + PASSAGE_MARGIN: return true
	return false

func setup(world: Node3D, clearance: float = 1.1) -> void:
	bounds = world.get_meta("bounds")
	surface_height = float(world.get_meta("surface_height",bounds.end.y))
	passage_clearance = clearance
	blocked_samples.clear()
	height_samples.resize(RESOLUTION * RESOLUTION)
	height_samples.fill(-INF)
	# Height data supplies the immediate map and cliff outlines. The detailed
	# scenery render follows separately; dock markers retain editable positions.
	for node in world.get_children():
		if not node is MeshInstance3D: continue
		if node.name == "WaterSurface": continue
		var faces: PackedVector3Array = node.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			var a: Vector3 = node.transform * faces[index]
			var b: Vector3 = node.transform * faces[index + 1]
			var c: Vector3 = node.transform * faces[index + 2]
			_triangle(a, b, c)
	blocked_samples.resize(RESOLUTION * RESOLUTION)
	for y in range(RESOLUTION):
		for x in range(RESOLUTION): blocked_samples[y * RESOLUTION + x] = 1 if _passage_blocked(x,y) else 0
	var image := Image.create(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGB8)
	image.fill(Color(0.015, 0.02, 0.025))
	for y in range(RESOLUTION):
		for x in range(RESOLUTION):
			var height := height_samples[y * RESOLUTION + x]
			if not is_finite(height): continue
			var shade := lerpf(0.1, 0.85, clampf((height - bounds.position.y) / maxf(bounds.size.y, 1.0), 0.0, 1.0))
			image.set_pixel(x, y, Color(shade, shade, shade))
	texture = ImageTexture.create_from_image(image)
	for node in world.find_children("*", "Node3D", true, false):
		if node.has_meta("city_id"):
			markers.append({"position": node.global_position, "name": str(node.get_meta("city_name", "Dock"))})

func uv(point: Vector3) -> Vector2:
	return Vector2((point.x - bounds.position.x) / bounds.size.x, (point.z - bounds.position.z) / bounds.size.z)

func _triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	var pa := uv(a) * (RESOLUTION - 1)
	var pb := uv(b) * (RESOLUTION - 1)
	var pc := uv(c) * (RESOLUTION - 1)
	var divisor := (pb.y - pc.y) * (pa.x - pc.x) + (pc.x - pb.x) * (pa.y - pc.y)
	if absf(divisor) < 0.00001: return
	var low := pa.min(pb).min(pc).floor().clamp(Vector2.ZERO, Vector2.ONE * (RESOLUTION - 1))
	var high := pa.max(pb).max(pc).ceil().clamp(Vector2.ZERO, Vector2.ONE * (RESOLUTION - 1))
	for y in range(int(low.y), int(high.y) + 1):
		for x in range(int(low.x), int(high.x) + 1):
			var p := Vector2(x, y)
			var u := ((pb.y - pc.y) * (p.x - pc.x) + (pc.x - pb.x) * (p.y - pc.y)) / divisor
			var v := ((pc.y - pa.y) * (p.x - pc.x) + (pa.x - pc.x) * (p.y - pc.y)) / divisor
			if u < -0.001 or v < -0.001 or u + v > 1.001: continue
			var index := y * RESOLUTION + x
			height_samples[index] = maxf(height_samples[index], u * a.y + v * b.y + (1.0 - u - v) * c.y)
