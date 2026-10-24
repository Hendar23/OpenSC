extends "res://tests/test_scene_tree.gd"
const Assets = preload("res://clump_loader.gd")
const Mods = preload("res://mod_registry.gd")
const Images = preload("res://legacy_bmp.gd")
var checks := 0
var failures := 0

func _init() -> void:
	super._init(); call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func run() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-raster-icons-fixtures"
	storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	Mods.initialize(false)
	var path: String = storage.root_override.path_join("icon.png")
	var image := Image.create(4,4,false,Image.FORMAT_RGBA8); image.fill(Color.BLUE)
	image.save_png(ProjectSettings.globalize_path(path))
	for enabled in [false,true]:
		# Reproduce the colliding texture ID without requiring a separately
		# distributed texture pack or writing to the player's mod preferences.
		Mods.apply([],[],false)
		if enabled: Mods.layers["texture.grapple1"] = [{"path":path,"name":"Hull atlas fixture"}]
		for name in ["GRAPPLE1","GRAPPLE2","GRAPPLE3"]:
			var icon := Assets._load_raster_icon(folder,name)
			var original := Images.load_image(folder.path_join("GAMETEX/"+name+".RAS"))
			check(icon != null and original != null and icon.get_image().get_data() == original.get_data(),"Correct "+name+" HUD pixels with texture pack "+str(enabled))
		var hull := Assets._load_texture(folder,"GRAPPLE1","",{})
		check(hull != null and hull.has_meta("asset_mod") == enabled,"Hull atlas still follows the enabled texture pack")
	Mods.layers["texture.grapple1.ras"] = [{"path":path,"name":"Explicit HUD fixture"}]
	var replacement := Assets._load_raster_icon(folder,"GRAPPLE1")
	check(replacement.get_image().get_pixel(0,0).is_equal_approx(Color.BLUE),"Explicit RAS-only icon replacement remains supported")
	check(Assets._load_texture(folder,"GRAPPLE1","",{}).get_meta("asset_mod","") != "Explicit HUD fixture","HUD replacement does not replace the hull atlas")
	Mods.layers["texture.icon_fixture"] = [{"path":path,"name":"Legacy HUD fixture"}]
	check(Assets._load_raster_icon(folder,"ICON_FIXTURE").get_image().get_pixel(0,0).is_equal_approx(Color.BLUE),"Unambiguous legacy icon replacement IDs still work")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RAS HUD icons: %d checks; %d failures" % [checks,failures]); quit(1 if failures else 0)
