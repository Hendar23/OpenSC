extends RefCounted

# Mouth centre, inward axis, clear opening (half width/height), length,
# then inner wall sections (bottom, top, left, right) along that axis.
# Tryton follows the slope of the original gravel tunnel. The metal passages
# use the clear inner rim; their geometry and any mission grilles still occlude.
const PROFILES := [
	[Vector3(172.6,155.0,152.0),Vector3(-1,0,0),Vector2(2.1,1.85),34.0,
		[
		 Vector4(-1.80,2.20,-2.50,2.50),Vector4(-2.00,1.80,-2.50,2.30),Vector4(-2.80,1.00,-2.60,2.50),Vector4(-3.30,0.50,-2.10,3.20),
		 Vector4(-4.10,0.20,-2.20,4.40),Vector4(-4.60,-0.30,-2.60,4.70),Vector4(-5.10,-1.40,-1.20,4.60),Vector4(-6.00,-2.70,-2.60,4.30),
		 Vector4(-7.00,-3.00,-7.00,8.00),Vector4(-8.00,-3.00,-21.50,12.00),Vector4(-8.30,-3.00,-22.50,12.00),Vector4(-9.00,-3.50,-22.50,16.00),
		 Vector4(-9.50,-4.00,-22.00,23.00),Vector4(-10.20,-3.40,-21.00,26.00),Vector4(-10.80,-3.00,-20.00,31.00),Vector4(-11.40,-2.20,-18.00,33.00),
		 Vector4(-12.00,-2.00,-16.00,34.00),Vector4(-12.50,-1.50,-14.00,35.00)
		]],
	[Vector3(186.42,158.8,210.08),Vector3(-1,0,0),Vector2(1.9,1.9),11.5,[]],
	[Vector3(255.32,158.81,289.31),Vector3(0,0,1),Vector2(1.9,1.9),13.7,[]],
]
const SECTION_COUNT := 18

static func texture() -> ImageTexture:
	var image := Image.create(2 + SECTION_COUNT,PROFILES.size(),false,Image.FORMAT_RGBAF)
	for row in PROFILES.size():
		var p: Array = PROFILES[row]
		var mouth: Vector3 = p[0]; var axis: Vector3 = p[1].normalized()
		image.set_pixel(0,row,Color(mouth.x,mouth.y,mouth.z,p[3]))
		image.set_pixel(1,row,Color(axis.x,axis.z,p[2].x,p[2].y))
		for i in SECTION_COUNT:
			var section: Vector4 = p[4][i] if not p[4].is_empty() else Vector4(-p[2].y,p[2].y,-p[2].x,p[2].x)
			image.set_pixel(i + 2,row,Color(section.x,section.y,section.z,section.w))
	return ImageTexture.create_from_image(image)

static func near_view(eye: Vector3) -> bool:
	if shelter(eye) > 0.0: return true
	for p in PROFILES:
		var centre: Vector3 = p[0]
		if eye.distance_squared_to(centre) < 23.0 * 23.0: return true
	return false

static func shelter(point: Vector3) -> float:
	var value := 0.0
	for profile in PROFILES:
		var offset: Vector3 = point - profile[0]
		var axis: Vector3 = profile[1].normalized()
		var depth := offset.dot(axis)
		var length_inward: float = profile[3]
		if depth < -0.35 or depth > length_inward + 0.65: continue
		var side := offset.dot(Vector3(-axis.z,0,axis.x))
		if absf(side) > 39.0 or absf(offset.y) > 30.0: continue
		var rim: Vector2 = profile[2]
		var section := Vector4(-rim.y,rim.y,-rim.x,rim.x)
		if not profile[4].is_empty():
			var index := clampf(depth / length_inward,0,1) * (SECTION_COUNT - 1)
			var lo := floori(index)
			var first: Vector4 = profile[4][lo]
			section = first.lerp(profile[4][mini(lo+1,SECTION_COUNT-1)],index-lo)
		var wall := maxf(maxf(section.x-offset.y,offset.y-section.y),maxf(section.z-side,side-section.w))
		var west_rim := smoothstep(139.0,142.0,point.x)
		value = maxf(value,(1.0-smoothstep(0.35,0.85,wall)) *
			smoothstep(-0.35,3.0,depth) * (1.0-smoothstep(length_inward-0.35,length_inward+0.65,depth)) * west_rim)
	return value
