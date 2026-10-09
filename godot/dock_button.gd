extends Button
# Original artwork is drawn over the matching part of the screen background.
var highlight_art: Array = []
var held_art: Array = []
var highlighted := false
var held := false
var hit_polygon := PackedVector2Array()

func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point,hit_polygon) if not hit_polygon.is_empty() else Rect2(Vector2.ZERO,size).has_point(point)

func _draw() -> void:
	if disabled: return
	if highlighted or held:
		for piece in highlight_art: draw_texture_rect(piece.texture,piece.rect,false)
	if held:
		for piece in held_art: draw_texture_rect(piece.texture,piece.rect,false)
