shader_type canvas_item;

uniform vec2 card_size = vec2(294.0,114.0);
uniform float corner_radius = 12.0;

void fragment() {
	float radius = clamp(corner_radius,0.0,min(card_size.x,card_size.y) * 0.5);
	vec2 edge = abs((UV - 0.5) * card_size) - card_size * 0.5 + radius;
	float distance = length(max(edge,vec2(0.0))) + min(max(edge.x,edge.y),0.0) - radius;
	COLOR.a *= 1.0 - smoothstep(-0.5,0.5,distance);
}
