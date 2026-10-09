extends SceneTree
const Document = preload("res://map_document.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
const FIXTURE := "res://tests/wildlife-mod-fixture.json"
const PRIORITY_FIXTURE := "res://tests/wildlife-mod-priority.json"
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	Mods.initialize(false)
	var base := Document.load_path(Document.DEFAULT_PATH)
	var species: Dictionary = base.species[0].duplicate(true)
	species.id = "fixture_fish"; species.model = "ANGEL"
	base.species.append(species)
	var replacement := species.duplicate(true); replacement.model = "JACKFISH"
	var file := FileAccess.open(FIXTURE,FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1,"species":[replacement]})); file.close()
	Mods.layers["data.wildlife"] = [{"path":FIXTURE,"name":"Fixture"}]
	var merged := Document._add_mod_wildlife(base)
	var matches: Array = merged.species.filter(func(item: Dictionary) -> bool: return item.id == "fixture_fish")
	check(matches.size() == 1 and matches[0].model == "JACKFISH","Active wildlife mod replaces a matching authored species ID")
	check(base.species[-1].model == "ANGEL","Mod merging does not mutate the authored map")
	var repeated := Document._add_mod_wildlife(merged)
	check(Document.valid(repeated) and repeated.species.size() == merged.species.size(),"Reloading a saved combined preview does not duplicate or reject mod species")
	var higher := replacement.duplicate(true); higher.model = "LIONFISH"
	var priority_file := FileAccess.open(PRIORITY_FIXTURE,FileAccess.WRITE)
	priority_file.store_string(JSON.stringify({"schema_version":1,"species":[higher]})); priority_file.close()
	Mods.layers["data.wildlife"].append({"path":PRIORITY_FIXTURE,"name":"Higher priority"})
	var prioritized := Document._add_mod_wildlife(base)
	check(prioritized.species[-1].model == "LIONFISH","Wildlife definition overrides follow the same priority as model and texture overrides")
	Mods.layers["data.wildlife"].pop_back()
	var invalid := FileAccess.open(FIXTURE,FileAccess.WRITE)
	invalid.store_string(JSON.stringify({"schema_version":1,"species":[replacement,replacement]})); invalid.close()
	var fallback := Document._add_mod_wildlife(base)
	check(fallback.species[-1].model == "ANGEL" and not Mods.runtime_warnings.is_empty(),"Duplicate definitions inside a mod remain invalid and preserve the map")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PRIORITY_FIXTURE))
	print("Wildlife mods: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
