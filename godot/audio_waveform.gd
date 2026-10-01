extends Control

var peaks := PackedFloat32Array()
var progress := 0.0

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.065, 0.085))
	draw_line(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5), Color(0.2, 0.3, 0.35))
	for index in range(peaks.size()):
		var x := float(index) / maxf(1, peaks.size() - 1) * size.x
		var height := peaks[index] * (size.y * 0.45)
		draw_line(Vector2(x, size.y * 0.5 - height), Vector2(x, size.y * 0.5 + height), Color(0.3, 0.8, 0.85))
	draw_line(Vector2(size.x * progress, 0), Vector2(size.x * progress, size.y), Color(1, 0.75, 0.35), 2.0)
