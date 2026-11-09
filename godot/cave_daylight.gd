extends RefCounted

# Envelope fitted to the original Touka tunnel's rock cross sections. Each
# entry spans the walls at successive two-unit X sections. The small feather
# lies in the rock, where it blends back into the outdoor lighting.
const FIRST_X := 348.0
const STEP := 2.0
const WALL_PAD := 0.85
const VIEW_RADIUS := 23.0
const MOUTH := Vector3(348.87,155.59,260.28)
const INWARD := Vector3(0.877,-0.392,0.274)
const REGION := AABB(Vector3(346,117,245),Vector3(56,44,66))
const SECTIONS := [
	Vector4(152.8,158.6,256.8,263.7),
	Vector4(152.2,158.6,256.9,263.7),
	Vector4(152.0,157.5,258.1,263.6),
	Vector4(151.6,156.5,258.4,267.4),
	Vector4(150.6,156.1,258.8,273.5),
	Vector4(148.9,156.1,261.1,277.8),
	Vector4(148.1,156.0,264.8,278.6),
	Vector4(147.1,154.4,265.1,279.6),
	Vector4(146.1,152.6,263.3,278.9),
	Vector4(145.7,152.6,262.8,278.1),
	Vector4(144.2,152.3,263.7,278.4),
	Vector4(142.7,151.6,264.6,276.5),
	Vector4(140.2,150.3,264.6,303.1),
	Vector4(137.3,149.3,264.1,306.0),
	Vector4(135.8,147.7,264.6,306.5),
	Vector4(134.4,147.0,265.0,307.8),
	Vector4(132.8,145.0,254.3,306.8),
	Vector4(130.8,143.2,252.3,306.9),
	Vector4(129.1,142.0,252.4,304.9),
	Vector4(127.3,140.1,251.4,303.8),
	Vector4(124.9,139.4,250.5,306.6),
	Vector4(122.4,139.2,249.5,308.2),
	Vector4(120.8,136.9,248.5,309.2),
	Vector4(120.1,135.1,248.5,309.2),
	Vector4(119.6,134.2,249.8,305.7),
	Vector4(124.0,133.2,252.3,273.1),
	Vector4(119.0,133.2,248.0,309.2),
]

static func texture() -> ImageTexture:
	var image := Image.create(SECTIONS.size(),1,false,Image.FORMAT_RGBAF)
	for i in SECTIONS.size():
		var section: Vector4 = SECTIONS[i]
		image.set_pixel(i,0,Color(section.x,section.y,section.z,section.w))
	return ImageTexture.create_from_image(image)

static func shelter(point: Vector3) -> float:
	if not REGION.has_point(point): return 0.0
	var index := clampf((point.x - FIRST_X) / STEP,0.0,SECTIONS.size() - 1.0)
	var lo := floori(index)
	var section: Vector4 = SECTIONS[lo].lerp(SECTIONS[mini(lo + 1,SECTIONS.size() - 1)],index - lo)
	var wall := maxf(maxf(section.x - point.y,point.y - section.y),maxf(section.z - point.z,point.z - section.w))
	return (1.0 - smoothstep(WALL_PAD,WALL_PAD + 0.65,wall)) * smoothstep(-0.35,4.0,INWARD.dot(point - MOUTH))
