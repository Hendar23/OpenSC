extends TextureRect
## Brief receiver lock/drop animation using the original radio images.
const INTRO_SECONDS := 0.32
const OUTRO_SECONDS := 0.24
var clear_portrait: Texture2D
var distorted_portrait: Texture2D
var noise_frames: Array[Texture2D] = []
var receiving := false
var transition := ""
var age := 0.0

func reset_signal() -> void:
	receiving = false; transition = ""; age = 0.0
	clear_portrait = null; distorted_portrait = null
	texture = null; modulate.a = 1.0; hide()

func update_signal(portrait: Texture2D, distorted: Texture2D, noise: Array[Texture2D], delta: float) -> void:
	var next_receiving := portrait != null
	if next_receiving and (not receiving or portrait != clear_portrait):
		clear_portrait = portrait; distorted_portrait = distorted
		noise_frames = noise; transition = "intro"; age = 0.0
	elif receiving and not next_receiving:
		transition = "outro"; age = 0.0
	receiving = next_receiving
	age += maxf(0.0,delta)
	modulate.a = 1.0
	if transition == "intro":
		if age >= INTRO_SECONDS: transition = ""
		else:
			texture = _interference(int(age / 0.064)); show(); return
	elif transition == "outro":
		if age >= OUTRO_SECONDS: reset_signal(); return
		texture = _interference(3 - mini(3,int(age / 0.06)))
		modulate.a = clampf((OUTRO_SECONDS - age) / 0.06,0.0,1.0)
		show(); return
	texture = clear_portrait if receiving else null
	visible = texture != null

func _interference(frame: int) -> Texture2D:
	if frame % 2 == 0 and not noise_frames.is_empty(): return noise_frames[(frame / 2) % noise_frames.size()]
	return distorted_portrait if distorted_portrait != null else clear_portrait
