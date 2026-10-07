extends SceneTree
const Map = preload("res://hud_map.gd")
var failures := 0
var checks := 0
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func _initialize() -> void:
	var map := Map.new()
	map.surface_height = 10.0
	map.passage_clearance = 1.1
	map.bounds = AABB(Vector3.ZERO,Vector3(511,10,511))
	map.height_samples.resize(Map.RESOLUTION * Map.RESOLUTION)
	map.height_samples.fill(0.0)
	var centre := 20 * Map.RESOLUTION + 20
	map.height_samples[centre] = 8.0
	check(not map._blocked(20,20) and not map._border_edge(19,20), "A steep hill with swimming clearance has no orange outline")
	map.height_samples[centre] = 9.5
	check(map._blocked(20,20) and map._border_edge(18,20), "A wall meeting the water ceiling marks the navigable border")
	check(not map._border_edge(20,20), "Blocked interiors are not filled with orange")
	check(map._blocked(19,20), "A point beside a wall is blocked when the sub's footprint overlaps it")
	map.height_samples[centre] = 8.8
	check(map._blocked(20,20), "A barely adequate vertical gap retains its border with safe passage margin")
	map.height_samples[centre] = 8.7
	check(map._blocked(20,20), "The lower wall threshold closes marginal gaps previously shown as navigable")
	map.height_samples[centre] = 8.5
	check(not map._blocked(20,20), "Clearance above the stricter threshold still leaves usable passages open")
	map.height_samples[centre] = 8.0
	check(not map._blocked(20,20), "A passage with comfortable clearance remains open")
	map.height_samples[centre] = -INF
	check(not map._border_edge(19,20), "Missing samples are not mistaken for physical walls")
	check(not map._border_edge(0,0), "The texture rectangle is not treated as an impassable wall")
	print("Minimap borders: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
