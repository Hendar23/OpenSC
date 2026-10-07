extends SceneTree
const Data = preload("res://original_game_data.gd")
const Paths = preload("res://asset_paths.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _run() -> void:
	var folder := Paths.find_game_folder()
	var base := Data.load_catalogue(folder,false)
	check(base.tables.city_info.records.size() == 6,"All six city names are recovered from original place and relay data")
	check(base.tables.city_info.records["1"].name == "Touka Reef" and base.tables.city_info.records["2"].name == "Velcova Station" and base.tables.city_info.records["3"].name == "Beluga Basin" and base.tables.city_info.records["4"].name == "Tryton Institute" and base.tables.city_info.records["5"].name == "Aquatraz" and base.tables.city_info.records["6"].name == "Refinery","Original dock IDs map to the correct named places")
	check(base.tables.radio_messages.records.city1.text.contains("TOUKA REEF") and base.tables.city_info.records["1"].greeting_radius == 20.0,"Relay greeting text and approach radius are imported")
	var descriptions: Dictionary = base.tables.city_descriptions.records
	check(descriptions.size() == 72,"All six cities, four story stages and three standings have original dock descriptions")
	check(descriptions["touka1.neutral"].text.begins_with("Welcome to Touka Reef, the cultural centre of the Bohine.") and descriptions["touka1.neutral"].text.contains("\n\nProcha activity"),"Touka opening welcome and paragraph spacing match the reference")
	check(descriptions["touka2.bad"].text.contains("Your reputation precedes you") and descriptions["touka2.good"].text.contains("terrorist infiltration units"),"Reputation-specific paragraphs retain the correct city and standing")
	check(descriptions["refinery1.neutral"] == descriptions["refinery4.good"] and descriptions["aquatraz1.neutral"] == descriptions["aquatraz3.bad"],"Shared city stage and standing aliases resolve to the same paragraph")
	for city in base.tables.city_info.records.values():
		check(preload("res://legacy_bmp.gd").load_image(folder.path_join(city.title_bitmap)) != null,"Original title bitmap exists for " + city.name)
	check(base.warnings.is_empty(),"All original archives and full database decode without warnings")
	check(base.tables.equipment.records.size() == 30,"Original equipment catalogue has thirty records")
	check(base.tables.economy_cities.records.size() == 5 and base.tables.economy_commodities.records.size() == 95,"Economy contains five cities and nineteen commodities per city")
	check(base.tables["database.missions"].records.size() == 85,"All eighty-five database mission/bulletin records decode")
	check(base.tables["database.objects"].records.size() == 434 and base.tables["database.object_types"].records.size() == 10,"Placement and object-type tables retain their separate identities")
	check(base.tables.mission_text.records.size() == 67,"All sixty-seven English mission text sections decode")
	check(base.tables.equipment.records.lights["Sq Pic"] == "sqlights","Equipment sprite references retain original values")
	check(base.tables.commodity_text.records.has("ore"),"Commodity descriptions have stable commodity IDs")
	check(base.tables["database.missions"].records["4.4"].MissionText.begins_with("A Recent Report"),"Dynamic mission strings are recovered")
	check(base.tables.has("database.storyrules") and base.tables.has("mission_routes") and base.tables.has("mission_requirements") and base.tables.has("campaign_stages"),"Campaign dependencies, routes and equipment requirements are imported")
	var placed: Array = base.tables["database.objects"].records.values().filter(func(row: Dictionary) -> bool: return row.has("matrix"))
	check(placed[0].matrix[3] == null,"Uninitialized matrix lanes are excluded from meaningful data")
	var rows := Data.csv_rows("id,text,number\nthing,\"comma, and \"\"quotes\"\"\",4\n")
	check(rows[1][1] == 'comma, and "quotes"' and rows[1][2] == "4","CSV quoting and escaped quotes decode")
	var changed := base.duplicate(true)
	check(Data.apply_patch(changed,{"schema_version":1,"tables":{"city_descriptions":{"records":{"touka1.neutral":{"text":"Modded welcome"}}}}}).is_empty() and changed.tables.city_descriptions.records["touka1.neutral"].text == "Modded welcome","Mods can replace original dock welcome text through gameplay data")
	var patch := {"schema_version":1,"tables":{"equipment":{"records":{"lights":{"Maximum":2},"new_tool":{"id":"new_tool","Type":"tool"},"map":null}}}}
	check(Data.apply_patch(changed,patch).is_empty(),"Mods can change, add and remove individual records")
	check(changed.tables.equipment.records.lights.Maximum == 2 and changed.tables.equipment.records.lights["Sq Pic"] == "sqlights" and not changed.tables.equipment.records.has("map"),"Partial override preserves unmodified fields")
	check(base.tables.equipment.records.lights.Maximum == 1 and base.tables.equipment.records.has("map"),"Patches never mutate original imported data")
	var before := JSON.stringify(changed)
	check(not Data.apply_patch(changed,{"schema_version":1,"tables":{"equipment":{"records":{"lights":3}}}}).is_empty() and JSON.stringify(changed) == before,"Malformed patches are rejected atomically")
	var fixture := "res://tests/gameplay-data-fixtures"
	DirAccess.make_dir_recursive_absolute(fixture.path_join("first")); DirAccess.make_dir_recursive_absolute(fixture.path_join("second"))
	for id in ["first","second"]:
		var manifest := {"schema_version":1,"id":id,"name":id,"assets":{"data.gameplay":"gameplay.json"}}
		var file := FileAccess.open(fixture.path_join(id).path_join("mod.json"),FileAccess.WRITE); file.store_string(JSON.stringify(manifest)); file.close()
		patch = {"schema_version":1,"tables":{"equipment":{"records":{"lights":{"Maximum":2 if id == "first" else 3}}}}}
		file = FileAccess.open(fixture.path_join(id).path_join("gameplay.json"),FileAccess.WRITE); file.store_string(JSON.stringify(patch)); file.close()
	Mods.initialize(false,fixture)
	var enabled: Array[String] = ["first","second"]
	Mods.apply(enabled,enabled,false)
	var modded := Data.load_catalogue(folder)
	check(Mods.packs.size() == 2 and Mods.candidates("data.gameplay").size() == 2,"Gameplay JSON replacements use the existing mod system")
	check(modded.tables.equipment.records.lights.Maximum == 3,"Later enabled mods win field conflicts")
	Mods.apply([],enabled,false)
	check(Data.load_catalogue(folder).tables.equipment.records.lights.Maximum == 1,"Disabling mods restores original values even with cached imports")
	var export_path := "res://tests/gameplay-data-fixtures/catalogue.json"
	check(Data.export_catalogue(base,export_path) == OK,"Extracted catalogue can be exported locally")
	var restored: Variant = JSON.parse_string(FileAccess.get_file_as_string(export_path))
	check(restored is Dictionary and restored.tables["database.missions"].records.size() == 85,"Exported JSON retains full mission records")
	DirAccess.remove_absolute(export_path)
	var missing := Data.load_catalogue(fixture,false)
	check(not missing.warnings.is_empty() and not missing.tables.has("equipment"),"Missing original files report warnings without inventing data")
	Mods.initialize(false)
	print("Original gameplay data: %d checks, %d failures; %d tables" % [checks,failures,base.tables.size()])
	quit(1 if failures else 0)
