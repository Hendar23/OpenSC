extends SceneTree
const UI = preload("res://dock_interface.gd")
var checks := 0
var failures := 0
var sounds: Array[String] = []
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
 if DisplayServer.get_name() == "headless": return
 await process_frame; await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://tests/dock-state-" + name + ".png")
func run() -> void:
 preload("res://input_bindings.gd").install()
 var folder := preload("res://asset_paths.gd").find_game_folder()
 var ui := UI.new(); root.add_child(ui)
 var race := 1
 var state := {"race":race,"city":"Touka Reef","status":{"credits":10000},"offers":{},"hold":{},"installed":{},"commodity_offers":{"thorium":{"name":"Thorium","buy_price":1000,"sell_price":724,"stock":20}},"cargo":{"thorium":3},"slots":[]}
 ui.setup(folder,func() -> Dictionary: return state)
 ui.menu_sound_played.connect(func(role: String) -> void: sounds.append(role))
 ui.open("home")
 check(sounds.is_empty(),"Opening does not play hover audio")
 for role in ui.MENU_SOUNDS:
  check(ui.sound_players[role].stream != null and ui.sound_players[role].stream.get_meta("asset_source").ends_with(ui.MENU_SOUNDS[role] + ".RAW"),"Original button sound " + role)
 var trade: Button = ui.layout.get_node("equipment")
 trade.mouse_entered.emit()
 check(sounds == ["off","over"],"Moving between buttons plays off and over once")
 trade.focus_entered.emit()
 check(sounds.size() == 2,"Mouse and controller focus do not double hover sound")
 check(trade.highlight_art.size() == 1 and trade.held_art.size() == 1,"Home button has original highlight and depressed graphics")
 check(trade._has_point(Vector2(125,40)) and not trade._has_point(Vector2(0,0)),"Home button follows diagonal panel hit area")
 await capture("hover")
 trade.button_down.emit()
 check(trade.held and sounds.back() == "activate","Holding the mouse depresses the button and plays activation")
 await capture("held")
 for frame in range(4): await process_frame
 check(trade.held,"Depressed artwork remains while held")
 trade.button_up.emit()
 check(not trade.held,"Mouse release removes depressed artwork")
 trade.pressed.emit()
 check(ui.page == "equipment" and sounds.count("activate") == 1,"Releasing activates exactly once")
 for name in ["BuyShieldRepair","SaleInfo","HoldInfo","SellShieldRepair"]:
  var button: Button = ui.layout.get_node(name)
  check(button.highlight_art.size() == 1 and button.held_art.size() == 1,"Equipment button state artwork: " + name)
 check(ui.layout.get_node("SaleInfo").position == Vector2(27,361),"Sale info overlay aligns with original background")
 var done: Button = ui.layout.get_node("home")
 check(done.highlight_art[0].rect.position + done.position == Vector2(82,434) and done.held_art[0].rect.position + done.position == Vector2(22,418),"Equipment Done overlay alignment")
 done.mouse_entered.emit(); done.button_down.emit()
 await capture("equipment-done")
 ui.open("missions")
 done = ui.layout.get_node("home")
 done.mouse_entered.emit(); done.button_down.emit()
 check(done.held_art[0].rect.position + done.position == Vector2(27,421),"Missions uses its own aligned pressed button")
 await capture("missions-done")
 for current_race in [1,2,4]:
  race = current_race; state.race = race; ui.open("home")
  for action in ["missions","equipment","save","launch"]:
   var button: Button = ui.layout.get_node(action)
   check(button.highlight_art.size() == 1 and button.held_art.size() == 1,"Race %d original home button: %s" % [race,action])
  ui.open("goods")
  var prefix: String = {1:"B",2:"P",4:"R"}[race]
  done = ui.layout.get_node("equipment")
  check(done.highlight_art[0].texture == ui._button_texture("ENGLISH/" + prefix + "DONG") and done.held_art[0].texture == ui._button_texture(prefix + "POPL"),"Goods uses its own faction's original Done artwork")
  if race == 4:
   done.mouse_entered.emit(); done.button_down.emit()
   await capture("refinery-done")
   done.button_up.emit(); done.mouse_exited.emit()
   for entry in [["BuyCommodity","BUY"],["SellCommodity","SELL"],["CommodityInfo","INFO"]]:
    var button: Button = ui.layout.get_node(entry[0])
    check(button.highlight_art[0].texture == ui._button_texture("ENGLISH/" + entry[1]) and button.held_art[0].texture == ui._button_texture("ENGLISH/" + entry[1] + "LIT"),"Refinery uses original green states: " + entry[1])
    button.mouse_entered.emit(); button.button_down.emit()
    await capture("refinery-" + str(entry[1]).to_lower())
    button.button_up.emit(); button.mouse_exited.emit()
   ui.open("missions")
   done = ui.layout.get_node("home")
   check(done.held_art[0].texture == ui._button_texture("MR-B1"),"Refinery missions use their own green Done artwork")
  ui.open("save")
  done = ui.layout.get_node("home")
  var save_prefix := "P" if race == 2 else "B"
  check(done.highlight_art[0].texture == ui._button_texture("ENGLISH/" + save_prefix + "STEXT1") and done.held_art[0].texture == ui._button_texture(save_prefix + "SLIT2"),"Save Done uses its own artwork for race %d" % race)
  check(done.highlight_art[0].rect.position + done.position == Vector2(94,427) and done.held_art[0].rect.position + done.position == Vector2(20,395),"Save Done artwork aligns with the original button")
  done.mouse_entered.emit(); done.button_down.emit()
  await capture("save-done-%d" % race)
 race = 1
 state.race = race
 ui.open("home")
 var save: Button = ui.layout.get_node("save"); save.grab_focus()
 var accept := InputEventJoypadButton.new(); accept.button_index = JOY_BUTTON_A; accept.pressed = true
 ui._input(accept)
 check(save.held and ui.page == "home","Controller confirm holds the depressed button until release")
 accept.pressed = false; ui._input(accept)
 check(ui.page == "save","Controller release activates the held button")
 ui.open("goods")
 check(ui.layout.get_node("BuyCommodity").highlight_art.size() == 1,"Commodity buttons share original states")
 ui.queue_free(); await process_frame
 print("Dock presentation: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
