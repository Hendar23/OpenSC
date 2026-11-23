extends SceneTree

const Mods = preload("res://mod_registry.gd")
const Modern = preload("res://modern_model.gd")
const Assets = preload("res://clump_loader.gd")
const Cache = preload("res://asset_cache.gd")
const Storage = preload("res://player_storage.gd")
var checks := 0
var failures := 0
var fixture := ""

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(text); file.close()

func manifest(path: String, value: Dictionary) -> void:
	write(path.path_join("mod.json"), JSON.stringify(value))

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	fixture = ProjectSettings.globalize_path("res://tests/protected-mods-%d-fixtures" % OS.get_process_id())
	Storage.root_override = fixture.path_join("player")
	var folder := fixture.path_join("mods/protected-fixture")
	DirAccess.make_dir_recursive_absolute(folder)
	var virtual := "res://_protected_mods/protected-fixture/" + "a".repeat(24)
	var scene := Node3D.new(); scene.name = "ProtectedFixture"; scene.set_meta("protected_model", true)
	var mesh := MeshInstance3D.new(); mesh.name = "Cube"; mesh.mesh = BoxMesh.new(); scene.add_child(mesh); mesh.owner = scene
	var packed := PackedScene.new(); packed.pack(scene); scene.free()
	var source := fixture.path_join("cube.scn")
	check(ResourceSaver.save(packed, source) == OK, "Fixture scene saved")
	var pck := folder.path_join("assets.pck")
	var packer := PCKPacker.new()
	# Synthetic zero-key fixtures match the unmodified editor; no licensed data
	# or real build key is used by this publicly runnable regression suite.
	check(packer.pck_start(pck, 32, "0".repeat(64), true) == OK, "Fixture encrypted directory")
	check(packer.add_file(virtual.path_join("cube.scn"), source, true) == OK, "Fixture encrypted scene")
	check(packer.add_file_from_buffer(virtual.path_join("proof.txt"), "fixture".to_utf8_buffer(), true) == OK, "Fixture encrypted proof")
	check(packer.flush() == OK, "Fixture pack flushed")
	var value := {"schema_version": 1, "id": "protected-fixture", "name": "Protected Fixture", "description": "Owner's exact description",
		"resource_pack": {"file": "assets.pck", "root": virtual},
		"assets": {"model.fixture": {"file": "cube.scn", "scale": 2.0, "forward_axis": "+Z"}},
		"scenery": {"file": "cube.scn", "seed": 1, "count": 1, "patch_radius": 2.0,
			"models": [{"node": "Cube", "size": 1.0, "weight": 1.0}]}}
	manifest(folder, value)
	Mods.root = fixture.path_join("mods")
	var preview := Mods.discover_installed([])
	check(preview.size() == 1 and preview[0].description == value.description, "Preview reads encrypted mod metadata")
	check(not FileAccess.file_exists(virtual.path_join("proof.txt")), "Preview leaves encrypted resources unmounted")
	Mods.initialize(false, fixture.path_join("mods"), fixture.path_join("unused.cfg"))
	check(Mods.packs.size() == 1 and Mods.packs[0].valid, "Encrypted pack discovered")
	var entry := Mods.packs[0]
	check(entry.errors.is_empty() and entry.description == value.description, "Description preserved")
	check(Mods.apply(["protected-fixture"], ["protected-fixture"], false) == OK, "Enable without player preference writes")
	check(Mods.scenery_packs().size() == 1, "Protected scenery registered")
	Cache.enabled = true
	Cache.resident_enabled = true
	var first := Assets.load_clump("fixture/CLUMPS/FIXTURE.DFF")
	check(first != null and first.scale == Vector3.ONE * 2.0, "Protected replacement routed with scale")
	if first != null: first.free()
	var second := Modern.load_model(entry.scenery.path, {"forward_axis": "+Z"})
	check(second != null and second.find_child("Cube", true, false) != null, "Protected scenery loaded")
	if second != null: second.free()
	check(Cache.writes == 0 and not DirAccess.dir_exists_absolute(Storage.root_path().path_join("cache")), "No decrypted disk cache")
	var invalid := value.duplicate(true); invalid.resource_pack.root = "res://game/" + "a".repeat(24)
	manifest(folder, invalid)
	check(not Mods._read_pack(folder).valid, "Foreign virtual namespace rejected")
	invalid = value.duplicate(true); invalid.resource_pack.file = "../assets.pck"
	manifest(folder, invalid)
	check(not Mods._read_pack(folder).valid, "Pack traversal rejected")
	invalid = value.duplicate(true); invalid.assets["model.fixture"].file = "../cube.scn"
	manifest(folder, invalid)
	check(Mods._read_pack(folder).assets.is_empty(), "Protected asset traversal rejected")
	invalid = value.duplicate(true); invalid.erase("resource_pack")
	manifest(folder, invalid)
	check(not Mods._read_pack(folder).valid, "Loose executable scene not admitted as scenery")
	# Changed bytes cannot silently reuse the resources of an already mounted pack.
	var append := FileAccess.open(pck, FileAccess.READ_WRITE); append.seek_end(); append.store_8(0); append.close()
	manifest(folder, value)
	check(not Mods._read_pack(folder).valid, "Mounted namespace content change rejected")
	DirAccess.remove_absolute(pck)
	check(not Mods._read_pack(folder).valid, "Missing encrypted pack fails closed")
	# Existing plain mods still work and require no key/template changes.
	manifest(folder, {"schema_version": 1, "id": "plain", "movement": {"mass": 150.0}})
	check(Mods._read_pack(folder).valid, "Plain mod support preserved")
	_remove(fixture)
	print("Protected mods: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _remove(path: String) -> void:
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path): _remove(path.path_join(name))
	DirAccess.remove_absolute(path)
