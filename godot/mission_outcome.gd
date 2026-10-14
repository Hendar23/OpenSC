extends CanvasLayer
## Original COMPLL/FAILEDL masks, animated with a settling ripple.
var graphic: TextureRect
var age := 0.0
const DURATION := 5.0
var textures := {}
var audio: AudioStreamPlayer
func _ready() -> void:
	layer = 90; process_mode = Node.PROCESS_MODE_ALWAYS
	graphic = TextureRect.new(); graphic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graphic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var effect := ShaderMaterial.new(); effect.shader = preload("res://mission_outcome.gdshader")
	graphic.material = effect; add_child(graphic); hide()
	audio = AudioStreamPlayer.new(); add_child(audio)
func dismiss() -> void:
	hide(); age = 0
	if audio != null: audio.stop()
func play(folder: String, success: bool) -> void:
	var key := folder + str(success)
	if not textures.has(key):
		var base := folder.path_join("GAMETEX/ENGLISH")
		var image := preload("res://legacy_bmp.gd").load_image(base.path_join("COMPLL.BMP" if success else "FAILEDL.BMP"))
		var mask := preload("res://legacy_bmp.gd").load_image(base.path_join("COMPLM.BMP" if success else "FAILEDLM.BMP"))
		if image == null or mask == null: return
		image = image.duplicate(); image.convert(Image.FORMAT_RGBA8)
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var colour := image.get_pixel(x,y); colour.a = mask.get_pixel(x,y).r; image.set_pixel(x,y,colour)
		textures[key] = ImageTexture.create_from_image(image)
	graphic.texture = textures[key]; age = 0; show(); _process(0)
	audio.stream = preload("res://legacy_audio.gd").load_file(folder.path_join("WAVES/MISSCOMP.RAW" if success else "WAVES/MISSFAIL.RAW"))
	if audio.stream != null: audio.play()
func _process(delta: float) -> void:
	if not visible or graphic == null: return
	age += delta
	if age >= DURATION: dismiss(); return
	var viewport := get_viewport().get_visible_rect().size
	var factor := minf(viewport.x / 640.0,viewport.y / 480.0)
	var settle := 1.0 + 0.3 * exp(-age * 4.0)
	graphic.size = Vector2(212,82) * factor * settle
	graphic.position = (viewport - graphic.size) * 0.5
	graphic.modulate.a = minf(age * 5.0,1.0) * clampf(DURATION - age,0.0,1.0)
	graphic.material.set_shader_parameter("age",age)
