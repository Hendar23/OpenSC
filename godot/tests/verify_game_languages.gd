extends SceneTree

const Game = preload("res://game.gd")
const Storage = preload("res://player_storage.gd")
const Language = preload("res://game_language.gd")
const Data = preload("res://original_game_data.gd")
const FMV = preload("res://fmv_library.gd")
const Audio = preload("res://legacy_audio.gd")
const Equipment = preload("res://equipment_shop.gd")
var checks := 0
var failures := 0

class FolderSetup extends Game:
	var opened_folder := ""

	func _bootstrap() -> void:
		_prompt_game_folder("Choose your Sub Culture game folder")

	func _start_game(folder: String) -> void:
		opened_folder = folder
		game_folder = folder

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func _run() -> void:
	var english := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	var multilingual := OS.get_environment("OPENSC_TEST_MULTILINGUAL_FOLDER")
	if english.is_empty() or multilingual.is_empty():
		push_error("Set OPENSC_TEST_GAME_FOLDER and OPENSC_TEST_MULTILINGUAL_FOLDER to the English and French/German original data folders.")
		quit(1)
		return
	preload("res://asset_cache.gd").enabled = false
	Storage.root_override = "user://language-test-" + str(OS.get_process_id())
	var game := FolderSetup.new()
	game.remember_preferences = false
	root.add_child(game)
	await process_frame
	game.folder_prompt.hide()
	await game._choose_game_folder(multilingual)
	_check(game.language_prompt.visible and game.opened_folder.is_empty(),"Setup waits for a choice before opening the multilingual folder")
	_check(game.language_options.item_count == 2 and game.language_options.get_item_text(0) == "Français" and game.language_options.get_item_text(1) == "Deutsch","Only the two supplied languages appear")
	game.language_prompt.hide()
	game._cancel_game_language()
	_check(game.folder_prompt.visible and game.opened_folder.is_empty(),"Back returns to original folder selection")
	game.folder_prompt.hide()
	await game._choose_game_folder(multilingual)
	game.language_options.select(0)
	game.language_prompt.hide()
	await game._confirm_game_language()
	_check(game.opened_folder == multilingual and TranslationServer.get_locale() == "fr","French selection opens the folder in French")
	_check(game.front_end.buttons.new_game.tr("New Game") == "Nouvelle partie","French UI catalog is active")
	await game._select_game_language(multilingual,"de")
	_check(not game.language_prompt.visible and TranslationServer.get_locale() == "de","A saved German choice bypasses the prompt")
	game.front_end.difficulty_menu.open_menu()
	_check(game.front_end.difficulty_menu.labels.disable_random_pirates.tr("Disable random pirates") == "Zufällige Piraten deaktivieren","Difficulty captions use the selected language")
	await game._choose_game_folder(english)
	_check(not game.language_prompt.visible and game.opened_folder == english and TranslationServer.get_locale() == "en","The English edition opens directly in English")
	_check(game.front_end.buttons.new_game.tr("New Game") == "New Game","English UI is restored")
	game.front_end.difficulty_menu.close_menu()
	game.front_end.show_menu(false)
	game.front_end._activate_button("options")
	game.front_end._activate_button("setup")
	game.folder_dialog.use_native_dialog = false
	game.front_end.buttons.choose_game_folder.grab_focus()
	game.front_end._activate_button("choose_game_folder")
	_check(game.folder_dialog.visible, "Setup reopens the existing folder chooser")
	game.folder_dialog.hide()
	game.folder_dialog.canceled.emit()
	_check(game.game_folder == english and game.front_end.buttons.choose_game_folder.has_focus(),"Cancel keeps the folder and restores Setup focus")
	game.has_started_game = true
	game.front_end._activate_button("choose_game_folder")
	_check(game.folder_switch_prompt.visible and not game.folder_dialog.visible,"Changing folders warns before interrupting an active session")
	game.folder_switch_prompt.hide()
	game.folder_switch_prompt.canceled.emit()
	_check(game.has_started_game and game.game_folder == english,"Cancel keeps the active session")
	game.has_started_game = false
	await game._choose_game_folder(english.path_join("CLUMPS"))
	_check(game.options_notice.visible and game.game_folder == english,"Invalid folder shows an error without changing the active installation")
	game.options_notice.hide()
	await game._choose_game_folder(multilingual)
	_check(game.language_prompt.visible and game.game_folder == english,"Switching to the French/German edition waits for a language choice")
	game.language_options.select(1)
	game.language_prompt.hide()
	await game._confirm_game_language()
	_check(game.game_folder == multilingual and game.game_language == "de","The Options flow switches to the German installation data")
	game.front_end._activate_button("choose_game_folder")
	var initial_folder := game.folder_dialog.current_dir.simplify_path().trim_suffix("/")
	_check(initial_folder == multilingual.replace("\\", "/").simplify_path().trim_suffix("/"), "The chooser starts at the selected original folder")
	game.folder_dialog.hide()
	_check(game.front_end.buttons.restore_defaults.disabled,"The source build protects its own defaults")
	game.remember_preferences = true
	_check(not game._can_restore_defaults(),"The reset stays unavailable in the source editor with persistence enabled")
	game.remember_preferences = false
	var english_data := Data.load_catalogue(english,false,"en")
	var french_data := Data.load_catalogue(multilingual,false,"fr")
	var german_data := Data.load_catalogue(multilingual,false,"de")
	for catalogue in [english_data,french_data,german_data]:
		var tables: Dictionary = catalogue.tables
		_check(tables.mission_text.records.size() == 67 and tables.mail_messages.records.size() == 97,"Every edition imports the original mission and bulletin IDs")
		_check(tables.city_info.records.size() == 6 and tables.radio_messages.records.size() == 452,"Every edition imports the six city relays and original radio IDs")
	_check(french_data.tables.mission_text.records.ore.text.contains("é"),"The French text keeps its accents")
	_check(german_data.tables.mission_text.records.ore.text.strip_edges().begins_with("Erz"),"The German catalogue contains the original German briefing")
	_check(french_data.tables.radio_messages.records.aa2.text != german_data.tables.radio_messages.records.aa2.text,"Changing languages changes radio text on the same folder")
	_check(german_data.tables.radio_messages.records.city1.text.begins_with("RELAISTURM:"),"German display localizes the retail English radio heading")
	_check(german_data.tables.source_texts.records["english.messages.txt"].text.contains("CITY RELAY TOWER"),"The raw retail archive is preserved")
	var german_equipment: Dictionary = german_data.tables.equipment_text.records
	for id in ["shield","zapper","depthl"]:
		var offer := Equipment.offer(german_data,"1",1,id)
		_check(not offer.description.is_empty() and offer.description == german_equipment[id].Desc,"German %s retains its retail equipment description" % id)
	_check(Equipment.offer(french_data,"1",1,"zapper").description == french_data.tables.equipment_text.records.zapper.Description,"French equipment still reads the Description column")
	var night_vision_names := {"fr":"Vision nocturne","de":"Nachtsicht"}
	TranslationServer.set_locale("en")
	var english_night_vision := Equipment.offer(english_data,"1",1,"night_vision")
	for locale in night_vision_names:
		TranslationServer.set_locale(locale)
		var offer := Equipment.offer(german_data if locale == "de" else french_data,"1",1,"night_vision")
		_check(offer.name == night_vision_names[locale] and not offer.description.is_empty() and offer.description != english_night_vision.description,"Night Vision offer text is localized for " + locale)
	TranslationServer.set_locale("en")
	var landmarks := preload("res://map_landmarks.gd").new()
	landmarks.setup(german_data)
	_check(not landmarks.markers.is_empty() and landmarks.markers[0].name == "KNOCHENBOGEN","The shared English landmark names are translated for display")
	for locale in ["fr","de"]:
		var voice := Language.asset(multilingual,"WAVES","AA2.RAW",locale)
		_check(voice.get_base_dir().get_file() == Language.DIRECTORIES[locale] and Audio.load_file(voice) != null,"Localized speech resolves and loads")
		var news := FMV.source_path(multilingual,"btvflat",locale)
		_check(news.get_base_dir().get_file().to_upper() == Language.DIRECTORIES[locale] and not FMV.smacker_info(news).is_empty(),"The localized news clip resolves")
		_check(FileAccess.file_exists(FMV.source_path(multilingual,"walkfail",locale)),"The shared walker FMV resolves")
		var artwork := Language.asset(multilingual,"GAMETEX","COMPLL.BMP",locale)
		_check(artwork.get_base_dir().get_file() == Language.DIRECTORIES[locale] and FileAccess.file_exists(artwork),"Localized mission-result artwork resolves")
	game.queue_free()
	await process_frame
	print("Game languages: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
