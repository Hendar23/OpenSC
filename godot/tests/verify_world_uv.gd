extends SceneTree
const World = preload("res://world_loader.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var folder := preload("res://asset_paths.gd").find_game_folder()
	var world := await World.load_world(folder.path_join("DATA/SCEN1.BSP"),self,func(_message: String) -> void: pass)
	var roof := world.get_node("Material_60") as MeshInstance3D
	var arrays := roof.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var edges := {}
	for index in range(0,vertices.size(),3):
		for pair in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:
			var a: int = index + pair.x
			var b: int = index + pair.y
			var start := "%.4f,%.4f,%.4f" % [vertices[a].x,vertices[a].y,vertices[a].z]
			var end := "%.4f,%.4f,%.4f" % [vertices[b].x,vertices[b].y,vertices[b].z]
			var key: String = start + ":" + end if start < end else end + ":" + start
			if not edges.has(key): edges[key] = []
			edges[key].append([uvs[a],uvs[b]] if start < end else [uvs[b],uvs[a]])
	var checked := 0
	var failures := 0
	for key in edges:
		var pairs: Array = edges[key]
		if pairs.size() != 2: continue
		checked += 1
		for endpoint in range(2):
			var difference: Vector2 = pairs[0][endpoint] - pairs[1][endpoint]
			for component in [difference.x,difference.y]:
				var wrapped := fposmod(absf(component),1.0)
				if minf(wrapped,1.0 - wrapped) > 2.1 / 128.0:
					failures += 1
					push_error("Roof textures disagree across edge " + key)
	world.free()
	print("World roof UV verification: %d shared edges, %d failures" % [checked,failures])
	quit(1 if failures or checked < 100 else 0)
