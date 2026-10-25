extends "res://tests/test_scene_tree.gd"
const Cache = preload("res://asset_cache.gd")
const Assets = preload("res://clump_loader.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
const BASE := "res://tests/cache-dependencies-fixtures"
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func write(path: String, data: PackedByteArray) -> void:
	preload("res://player_storage.gd").ensure_parent(path)
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_buffer(data); file.close()
	Cache.reset_session()
func text_chunk(value: String) -> PackedByteArray:
	var bytes := value.to_ascii_buffer(); bytes.append(0)
	while bytes.size() % 4: bytes.append(0)
	var header := "gnts".to_ascii_buffer(); var size := PackedByteArray(); size.resize(4); size.encode_u32(0,bytes.size())
	return header + size + bytes
func key() -> String: return Assets.conversion_key("clump",BASE + "/CLUMPS/fixture.DFF")
func run() -> void:
	preload("res://player_storage.gd").root_override = BASE
	Mods.initialized = true; Mods.layers = {}
	DirAccess.remove_absolute(BASE + "/replacement.png")
	write(BASE + "/.gdignore",PackedByteArray())
	write(BASE + "/CLUMPS/fixture.DFF", "rxet".to_ascii_buffer() + PackedByteArray([0,0,0,0]) + text_chunk("COLOR") + text_chunk("MASK"))
	write(BASE + "/GAMETEX/COLOR.BMP","one".to_ascii_buffer())
	write(BASE + "/GAMETEX/MASK.BMP","one".to_ascii_buffer())
	var before := key()
	check(Assets._texture_references[BASE + "/CLUMPS/fixture.DFF"].names == ["COLOR","MASK"],"Source scanner includes texture and alpha mask")
	write(BASE + "/GAMETEX/UNUSED.BMP","two".to_ascii_buffer())
	check(key() == before,"Unreferenced image does not invalidate model")
	write(BASE + "/GAMETEX/COLOR.BMP","two".to_ascii_buffer())
	check(key() != before,"Referenced same-size image edit invalidates model"); before = key()
	write(BASE + "/GAMETEX/MASK.BMP","two".to_ascii_buffer())
	check(key() != before,"Alpha mask edit invalidates model"); before = key()
	Mods.layers = {"texture.color":[{"path":BASE + "/replacement.png"}]}
	check(key() != before,"Adding a replacement invalidates model"); before = key()
	write(BASE + "/replacement.png","repaired".to_ascii_buffer())
	check(key() != before,"Repairing missing replacement invalidates model"); before = key()
	Mods.layers["texture.unused"] = [{"path":BASE + "/unrelated.png"}]
	check(key() == before,"Unrelated replacement does not invalidate model")
	Mods.layers["texture.color"].append({"path":BASE + "/fallback.png"}); before = key()
	Mods.layers["texture.color"].reverse()
	check(key() != before,"Replacement priority affects model key")
	print("Cache dependencies: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
