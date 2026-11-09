extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
# REWARD1.CSV from the released original, plus the owner's miners2 correction.
const REWARDS := {
	"aquatraz":10000,"aquatraz2":10000,"aquatraz3":10000,"aquatraz4":10000,
	"endgame":666,"endgame2":666,"endgame3":666,"endgame4":666,
	"filters":8500,"filters2":8500,"filters3":8500,"filters4":8500,
	"canister":6000,"canister2":6000,"canister3":6000,"canister4":6000,
	"backstab":2000,"backstab2":2000,"backstab3":2000,"backstab4":2000,
	"puffa":4000,"puffa2":4000,
	"pwalker":8000,"pwalker2":8000,
	"tradetrad":0,"tradetrad2":0,"tradetech":0,"tradetech2":0,
	"stranded":2000,"spytrad":5000,"spytrad2":5000,"bigherd":3500,"fishing":3000,
	"breakout":3500,"breakout2":3500,"spytech":3500,"spytech2":3500,
	"escort":3500,"escort2":3500,"tagtech":3000,"eel":5000,"recontech":5000,"recontech2":5000,
	"walktrad":7000,"walktrad2":7000,"walktech":7000,"walktech2":7000,
	"minefield":7500,"disperse":6000,"rovrtn":8700,"fumehole":4000,"fumehole2":4000,
	"defect":5500,"defect2":5500,"miners":4500,"miners2":4500,"bomb":4500,
	"aliens":7000,"aliens2":7000,"diptrad":8000,"diptrad2":8000,"diptech":8000,"diptech2":8000}
var checks := 0
var failures := 0
var game: Node
func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-mission-rewards-fixtures"
	storage.ensure_parent(storage.preferences_path())
	var config := ConfigFile.new()
	config.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER"))
	config.save(storage.preferences_path())
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func prepare(id: String) -> void:
	game.player_progress = Progress.restore({"campaign_stage":Rules.mission_stage(id) if id in Rules.IMPLEMENTED else 1})
	game.player_progress.status.credits = 12345
	game.player_progress.missions.active = {"id":id,"city":Rules.offering_city(id) if id in Rules.IMPLEMENTED else 1}
func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	while not game.startup_complete: await process_frame
	game.front_end.gameplay_menu.fmvs_enabled = false
	game.set_process(false); game.pilot.freeze = true
	var runtime: Node = game.mission_runtime
	var expected_ids: Array = Rules.IMPLEMENTED.duplicate(); expected_ids.append_array(runtime.IDS.values())
	check(expected_ids.size() == REWARDS.size() and expected_ids.all(func(id: String) -> bool: return REWARDS.has(id)),"Audit covers every implemented city-specific offer")
	var rows: Dictionary = game.gameplay_catalogue.tables.mission_rewards.records
	for id: String in REWARDS:
		check(not rows.has(id) if id == "miners2" else rows.has(id) and int(rows[id].credits) == REWARDS[id],"Imported original reward matches independent expected amount: "+id)
		for score in [1.0,0.5]:
			prepare(id)
			runtime.finish(true,score)
			check(game.player_progress.status.credits == 12345+REWARDS[id],"Exact fixed success payout at score %s: %s" % [score,id])
			runtime.finish(true,score); runtime.docked(1)
			check(game.player_progress.status.credits == 12345+REWARDS[id],"Repeated completion and later docking cannot pay twice: "+id)
		prepare(id)
		runtime.finish(false,0.0)
		check(game.player_progress.status.credits == 12345,"Failure pays no success reward: "+id)
		runtime.finish(true)
		check(game.player_progress.status.credits == 12345,"Late success callback after failure pays nothing: "+id)
	rows.miners2 = {"credits":6789,"success":0.0,"fail":0.0,"enemy":0.0}
	prepare("miners2"); runtime.finish(true)
	check(game.player_progress.status.credits == 12345+6789,"Explicit modded miners2 reward overrides approved default")
	rows.erase("miners2")
	await process_frame
	game.free(); await process_frame
	print("Mission rewards: %d offers, %d checks, %d failures" % [REWARDS.size(),checks,failures])
	quit(1 if failures else 0)
