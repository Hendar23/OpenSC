extends Area3D
const VERTICAL_STRETCH := 8.0
var radius := 0.5
var city_id := 0
func _enter_tree() -> void:
	add_to_group("city_drop_off_points")
	# Cached worlds may contain the old enabled editor-only shape.
	var shape := get_node_or_null("DetectionShape") as CollisionShape3D
	if shape != null: shape.disabled = true
func configure(detection_radius: float, destination: int) -> void:
	radius = detection_radius; city_id = destination
	if city_id == 6: add_to_group("ambient_factories")
	else: remove_from_group("ambient_factories")
	collision_layer = 0; collision_mask = 0
	monitoring = false; monitorable = false
	set_meta("editor_dropoff", true)
	var shape := get_node_or_null("DetectionShape") as CollisionShape3D
	if shape == null:
		shape = CollisionShape3D.new(); shape.name = "DetectionShape"; shape.disabled = true; add_child(shape)
	var sphere := SphereShape3D.new(); sphere.radius = radius; shape.shape = sphere
	shape.scale = Vector3(1,VERTICAL_STRETCH,1)
	# Editor bounds only: acceptance uses contains_point, never physics overlaps.
	shape.disabled = true
func contains_point(point: Vector3) -> bool:
	var offset := point - global_position
	offset.y /= VERTICAL_STRETCH
	return offset.length() <= radius
