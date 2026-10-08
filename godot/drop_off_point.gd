extends Area3D
var radius := 0.5
var city_id := 0
func configure(detection_radius: float, destination: int) -> void:
	radius = detection_radius; city_id = destination
	collision_layer = 0; collision_mask = 0
	monitoring = false; monitorable = false
	set_meta("editor_dropoff", true)
	var shape := get_node_or_null("DetectionShape") as CollisionShape3D
	if shape == null:
		shape = CollisionShape3D.new(); shape.name = "DetectionShape"; add_child(shape)
	var sphere := SphereShape3D.new(); sphere.radius = radius; shape.shape = sphere
	shape.scale = Vector3(1,2,1)
func contains_point(point: Vector3) -> bool:
	var offset := point - global_position
	offset.y *= 0.5
	return offset.length() <= radius
