extends Control

var kind := "map"
var pilot: Node3D
var equipment: Node3D
var weapons: Node3D
var map_data: RefCounted
var frame: Texture2D
var sub_icon: Texture2D
var tilt_angle := 0.0
var shield_blue: Texture2D
var shield_orange: Texture2D
var radiation_icon: Texture2D
var radiation_clock := 0.0
var screen := Rect2(0, 0, 128, 80)
var screen_only := false
var map_span := 70.0
var full_world := false
var fog_material: ShaderMaterial
var player_marker: Polygon2D
var city_markers: Control
var casing_light := Color.WHITE
var casing_panel: TextureRect
var camera_feed: Texture2D
func set_camera_feed(texture: Texture2D) -> void:
	camera_feed = texture
	material = null if texture != null else fog_material
	if player_marker != null: player_marker.visible = texture == null
	if city_markers != null: city_markers.visible = texture == null
	queue_redraw()

func _ready() -> void:
	if kind != "map": return
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2D explored_mask : filter_linear, repeat_disable;
uniform vec2 screen_origin;
uniform vec2 screen_size;
uniform vec2 map_centre;
uniform vec2 map_span_uv;
varying vec2 screen_position;
void vertex() { screen_position = VERTEX; }
void fragment() {
    vec2 location = (screen_position - screen_origin) / screen_size;
    vec2 map_uv = map_centre + (location - vec2(0.5)) * map_span_uv;
    float revealed = texture(explored_mask, map_uv).r;
    if (any(lessThan(map_uv, vec2(0.0))) || any(greaterThan(map_uv, vec2(1.0)))) revealed = 0.0;
    bool orange = COLOR.r > COLOR.g * 1.7 && COLOR.r > COLOR.b * 2.0;
    if (!orange) COLOR.rgb *= vec3(0.45, 0.72, 1.0);
    COLOR.rgb = mix(vec3(0.002, 0.005, 0.015), COLOR.rgb, revealed);
}"""
	fog_material = ShaderMaterial.new()
	fog_material.shader = shader
	material = fog_material
	# Discovered names can extend onto unexplored terrain without being
	# darkened by the terrain's fog shader.
	city_markers = Control.new(); city_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	city_markers.use_parent_material = false; add_child(city_markers)
	city_markers.draw.connect(_draw_city_markers)
	# The player's position stays visible even where terrain is unexplored.
	# A separate canvas item keeps the map's fog shader off the orange arrow.
	player_marker = Polygon2D.new()
	player_marker.polygon = PackedVector2Array([Vector2(0,-5),Vector2(-3,4),Vector2(0,2),Vector2(3,4)])
	player_marker.color = Color(1.0,0.25,0.05)
	player_marker.use_parent_material = false
	add_child(player_marker)
	if not screen_only and frame != null:
		# Frame goes above the content, preserving the original bevel and
		# angled corners; its transparent opening supplies the exact shape.
		casing_panel = TextureRect.new()
		casing_panel.texture = frame
		casing_panel.size = size
		casing_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		casing_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		casing_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(casing_panel)

func _process(_delta: float) -> void:
	radiation_clock += _delta
	if casing_panel != null: casing_panel.modulate = casing_light
	if kind == "map" and camera_feed == null and fog_material != null and map_data.exploration_texture != null:
		var rect := Rect2(Vector2.ZERO,size) if screen_only else screen
		var point: Vector3 = _map_centre()
		fog_material.set_shader_parameter("explored_mask",map_data.exploration_texture)
		fog_material.set_shader_parameter("screen_origin",rect.position)
		fog_material.set_shader_parameter("screen_size",rect.size)
		fog_material.set_shader_parameter("map_centre",map_data.uv(point))
		fog_material.set_shader_parameter("map_span_uv",Vector2(map_span / map_data.bounds.size.x,map_span * rect.size.y / rect.size.x / map_data.bounds.size.z))
		player_marker.position = rect.get_center() + Vector2(pilot.global_position.x - point.x,pilot.global_position.z - point.z) / Vector2(map_span,map_span * rect.size.y / rect.size.x) * rect.size
		player_marker.scale = Vector2.ONE * minf(rect.size.x / 124.0,2.5)
		var forward: Vector3 = -pilot.get_global_transform_interpolated().basis.z
		player_marker.rotation = atan2(forward.x,-forward.z)
	if kind == "tilt" and pilot != null:
		var forward := -pilot.get_global_transform_interpolated().basis.z
		tilt_angle = asin(clampf(forward.y,-1.0,1.0))
	queue_redraw()
	if city_markers != null: city_markers.queue_redraw()

func _draw() -> void:
	if pilot == null: return
	if frame != null and not screen_only and kind != "map": draw_texture_rect(frame, Rect2(Vector2.ZERO,size), false,casing_light)
	var rect := Rect2(Vector2.ZERO, size) if screen_only else screen
	if kind == "map":
		if camera_feed != null: draw_texture_rect(camera_feed,rect,false)
		else: _draw_map(rect)
	elif kind == "equipment":
		var item: Dictionary = equipment.current()
		if not item.is_empty():
			var icon_index := 0 if item.enabled else 1
			if item.id == "magnet": icon_index = 2 if is_instance_valid(equipment.magnet.target) else (1 if item.enabled else 0)
			var icon: Texture2D = item.icons[icon_index]
			if icon != null: draw_texture_rect(icon, rect, false)
			if item.id == "suckomat" and equipment.counter_digits.size() == 10:
				var count: int = equipment.vacuum.storage.size()
				for digit in range(2):
					var texture: Texture2D = equipment.counter_digits[0 if digit == 0 else count]
					if texture != null: draw_texture_rect(texture,Rect2(Vector2(9.5 + digit * 9,23.5),Vector2(8,10)),false)
	elif kind == "tilt":
		var centre := rect.get_center()
		draw_circle(centre, minf(rect.size.x, rect.size.y) * 0.5, Color(0.005, 0.035, 0.04))
		if sub_icon != null:
			draw_set_transform(centre,tilt_angle)
			var icon_size := Vector2(44,28.6)
			draw_texture_rect(sub_icon,Rect2(-icon_size * 0.5,icon_size),false)
			draw_set_transform(Vector2.ZERO)
	elif kind == "weapon":
		draw_rect(rect, Color(0.0, 0.18, 0.2))
		var item: Dictionary = weapons.current() if weapons != null else {}
		if not item.is_empty() and item.icon != null: draw_texture_rect(item.icon,rect,false)
		else: draw_string(ThemeDB.fallback_font, rect.position + Vector2(17, 25), "—", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 34, 16, Color(0.4, 0.7, 0.7))
	elif kind == "shield":
		var centre := rect.get_center()
		draw_circle(centre, minf(rect.size.x,rect.size.y) * 0.5, Color(0.01, 0.04, 0.05))
		var gauge_scale := minf(rect.size.x,rect.size.y) / 62.0
		var offsets := [Vector2(-11,-23),Vector2(-23,-11),Vector2(-23,11),Vector2(-11,23),Vector2(11,23),Vector2(23,11),Vector2(23,-11),Vector2(11,-23)]
		for i in range(8):
			var state := shield_segment_state(i)
			if state == "empty": continue
			var atlas: Texture2D = shield_orange if state == "orange" else shield_blue
			if atlas != null: draw_texture_rect_region(atlas, Rect2(centre + (offsets[i] - Vector2(7,7.5)) * gauge_scale, Vector2(14,15) * gauge_scale), Rect2(0,i * 15,14,15))

		if radiation_symbol_visible() and radiation_icon != null:
			var icon_size := radiation_icon.get_size() * gauge_scale
			draw_texture_rect(radiation_icon,Rect2(centre - icon_size * 0.5,icon_size),false)

func radiation_symbol_visible() -> bool:
	return pilot != null and bool(pilot.get("radiation_exposed")) and fmod(radiation_clock,0.5) < 0.25

func shield_segment_state(index: int) -> String:
	var ratio := clampf(float(pilot.health) / maxf(1.0,float(pilot.max_health)),0.0,1.0) if pilot != null else 1.0
	if ratio <= 0.0: return "empty"
	if ratio >= 1.0: return "blue"
	var depleted := int(floor((1.0 - ratio) * 8.0))
	return "empty" if index < depleted else "orange" if index == depleted else "blue"

func _draw_map(rect: Rect2) -> void:
	if map_data == null or map_data.texture == null: return
	var point: Vector3 = _map_centre()
	var span := Vector2(map_span, map_span * rect.size.y / rect.size.x)
	var uv: Vector2 = map_data.uv(point)
	var uv_size := Vector2(span.x / map_data.bounds.size.x, span.y / map_data.bounds.size.z)
	draw_texture_rect_region(map_data.texture, rect, Rect2((uv - uv_size * 0.5) * map_data.texture.get_size(), uv_size * map_data.texture.get_size()))

func _draw_city_markers() -> void:
	if pilot == null or map_data == null or map_data.texture == null: return
	var rect := Rect2(Vector2.ZERO,size) if screen_only else screen
	var point: Vector3 = _map_centre()
	var span := Vector2(map_span,map_span * rect.size.y / rect.size.x)
	var marker_scale := minf(rect.size.x / 124.0,2.5)
	for marker in map_data.markers:
		if not map_data.is_explored(marker.position): continue
		var offset := Vector2(marker.position.x - point.x, marker.position.z - point.z) / span * rect.size
		var position := rect.get_center() + offset
		if rect.grow(-4 * marker_scale).has_point(position):
			city_markers.draw_circle(position, 2.5 * marker_scale, Color(0.15, 0.95, 0.2))
			var text_position := position + Vector2(4, -3) * marker_scale
			var text_width := rect.end.x - text_position.x - 2.0
			if text_width > 12.0:
				city_markers.draw_string(ThemeDB.fallback_font, text_position, str(marker.name).to_upper().left(18), HORIZONTAL_ALIGNMENT_LEFT, text_width, maxi(6, int(6 * marker_scale)), Color(0.15,0.85,0.2))

func _map_centre() -> Vector3:
	if full_world:
		map_span = maxf(map_data.bounds.size.x,map_data.bounds.size.z * size.x / maxf(size.y,1))
		return map_data.bounds.get_center()
	return pilot.get_global_transform_interpolated().origin
