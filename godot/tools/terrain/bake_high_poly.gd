extends SceneTree
## -- <original game folder> <output.oscterrain> [profile.json] [placement map.json]

const World = preload("res://world_loader.gd")
const TerrainAsset = preload("res://terrain_asset.gd")
const Detail = preload("res://tools/terrain/terrain_detail.gd")
const Scenery = preload("res://scenery_loader.gd")
const MapDocument = preload("res://map_document.gd")
const WorldCache = preload("res://world_cache.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 4 or args[1].get_extension() != "oscterrain":
		fail("Expected an original game folder and a new .oscterrain output path")
		return
	var folder := args[0]
	var output := ProjectSettings.globalize_path(args[1])
	if FileAccess.file_exists(output) or FileAccess.file_exists(output + ".tmp"):
		fail("Output already exists: " + output)
		return
	var profile := Detail.read_profile(args[2] if args.size() > 2 else "res://tools/terrain/high_poly_profile.json")
	if profile.is_empty():
		fail("Invalid high-poly profile")
		return
	var map_data := MapDocument.load_path(args[3] if args.size() > 3 else "res://../Maps/scen1.json")
	if map_data.is_empty():
		fail("Invalid placement map for the dock protection masks")
		return
	preload("res://asset_cache.gd").enabled = false
	preload("res://mod_registry.gd").initialize(false, output.get_base_dir())
	var progress := func(_message: String) -> void: pass
	var world := await World.load_world(folder.path_join("DATA/SCEN1.BSP"), self, progress, false)
	if world == null:
		fail("Could not read original terrain")
		return
	root.add_child(world)
	var builder := Detail.new()
	await builder.round_world(world, folder, self, progress, profile)
	await World.add_collision(world, self, progress)
	await physics_frame
	await physics_frame
	await Scenery.populate(world, folder, self, progress)
	MapDocument.apply_entities(world, folder, map_data)
	await builder.add_detail(world, self, progress, profile)
	var source_signature := "terrain-v1:" + FileAccess.get_sha256(folder.path_join("DATA/SCEN1.BSP"))
	var ok := write_asset(world, output + ".tmp", source_signature, profile.exploration_aliases)
	world.free()
	if not ok or DirAccess.rename_absolute(output + ".tmp", output) != OK:
		DirAccess.remove_absolute(output + ".tmp")
		fail("Could not write terrain: " + output)
		return
	print("Wrote %s (%d bytes)" % [output, FileAccess.get_file_as_bytes(output).size()])
	quit()

func write_asset(world: Node3D, path: String, source_signature: String, aliases: Array) -> bool:
	var nodes := world.get_children().filter(func(node: Node) -> bool: return node.has_meta("terrain_reference"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_32(TerrainAsset.MAGIC)
	file.store_32(TerrainAsset.VERSION)
	if not TerrainAsset.write_record(file, {
		"bounds": world.get_meta("bounds"), "surface_height": world.get_meta("surface_height"),
		"database_offset": world.get_meta("database_offset"), "chunks": nodes.size(),
		"exploration_signature": source_signature,
		"exploration_aliases": aliases,
	}): return false
	for node in nodes:
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var coarse := 0
		if node.has_meta("terrain_source_mesh"):
			var base: PackedVector3Array = WorldCache.terrain_source(node).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			if arrays[Mesh.ARRAY_VERTEX].slice(0, base.size()) != base: return false
			coarse = base.size()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if not TerrainAsset.write_record(file, {
			"slot": node.get_meta("terrain_material"), "cell": node.get_meta("terrain_cell"),
			"material": node.get_meta("terrain_reference"), "vertices": arrays[Mesh.ARRAY_VERTEX],
			"normals": arrays[Mesh.ARRAY_NORMAL], "uvs": arrays[Mesh.ARRAY_TEX_UV], "indices": indices,
			"coarse_count": coarse, "lod_error": Detail.LOD_ERROR,
		}): return false
	file.flush()
	return file.get_error() == OK

func fail(message: String) -> void:
	push_error(message)
	quit(1)
