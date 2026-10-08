extends SceneTree
const Mods = preload("res://mod_registry.gd")
const Document = preload("res://map_document.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	Mods.initialize(false)
	var base := Document.load_active()
	Mods.apply(["clownfish"],[],false)
	var data := Document.load_active()
	check(data.species.size() == base.species.size() + 1,"Activation adds one species without editing the map")
	var added: Array = data.species.filter(func(s: Dictionary) -> bool: return s.id == "clownfish")
	check(added.size() == 1 and added[0].random_spawn,"Added species participates in random spawning")
	for species in base.species:
		check(data.species.has(species),"Existing species stays unchanged: " + str(species.id))
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var original := Document.load_model("JACKFISH",folder,true)
	var custom := Document.load_model("clownfish",folder,true)
	check(original != null and custom != null,"Both original and custom models load")
	if original != null and custom != null:
		var a: Array = original.find_children("*","MeshInstance3D",true,false)
		var b: Array = custom.find_children("*","MeshInstance3D",true,false)
		check(a.size() == b.size() and not b.is_empty(),"Custom fish retains the original meshes")
		for i in range(b.size()):
			check(b[i].mesh.get_blend_shape_count() > 0 and a[i].mesh.get_blend_shape_count() == b[i].mesh.get_blend_shape_count(),"Original swimming animation is retained")
			var tex: Texture2D = b[i].mesh.surface_get_material(0).albedo_texture
			check(tex != null and tex.get_meta("asset_mod","") == "Clownfish","Custom fish uses the editable PNG")
			var original_tex: Texture2D = a[i].mesh.surface_get_material(0).albedo_texture
			check(not original_tex.has_meta("asset_mod"),"Original jackfish skin stays unchanged")
		original.free(); custom.free()
	Mods.apply([],[],false)
	check(Document.load_active().species == base.species,"Disabling the mod removes the extra species")
	var duplicate := base.duplicate(true)
	duplicate.species.append(base.species[0].duplicate(true))
	check(not Document.valid(duplicate),"Duplicate creature IDs are rejected")
	print("Custom Jackfish: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
