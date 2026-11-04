extends "res://tests/test_scene_tree.gd"
const Families = preload("res://mission_families.gd")
const Rules = preload("res://mission_rules.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func _initialize() -> void:
	var registered := {}
	for family in Families.FAMILIES:
		var entry: Dictionary = Families.FAMILIES[family]
		for id in entry.ids:
			check(not registered.has(id),"Encounter has exactly one family: " + id)
			check(id in Rules.IMPLEMENTED,"Registered encounter is available to the campaign: " + id)
			registered[id] = family
		if entry.script == null:
			check(family in ["bacau_rescue","prison_breakout","bohine_covert"],"Only original inline encounters use dispatcher-owned flows")
			continue
		var controller: Object = entry.script.new()
		for hook in ["step","clear","target_body"]:
			check(controller.has_method(hook),family + " supports " + hook)
		check(controller.has_method("setup") if controller is Node else controller.has_method("start"),family + " supports encounter startup")
		if controller is Node: controller.free()
	for id in Rules.IMPLEMENTED:
		check(registered.has(id) and Families.family_for(id) == registered.get(id),"Every implemented encounter can be dispatched: " + id)
	check(Families.family_for("unknown").is_empty(),"Unknown encounters cannot silently start another family")
	print("Mission dispatcher: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
