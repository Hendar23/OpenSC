extends SceneTree
const Game = preload("res://game.gd")
const Shop = preload("res://equipment_shop.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func press(ui: CanvasLayer, key: int) -> void:
 var event := InputEventJoypadButton.new(); event.button_index = key; event.pressed = true; ui._input(event)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var game := Game.new(); game.remember_preferences = false; root.add_child(game)
 for frame in range(2400):
  if game.startup_complete: break
  await physics_frame
 check(game.startup_complete,"Game starts")
 if not game.startup_complete: quit(1); return
 game._begin_new_game(); game.pilot.set_physics_process(false); game.docking.set_physics_process(false); game.pilot.freeze = true
 var magnet: Dictionary = game.equipment.available.filter(func(i: Dictionary) -> bool: return i.id == "magnet")[0]
 for index in range(3):
  var original := preload("res://legacy_bmp.gd").load_image("../Original Sub Culture/GAMETEX/GRAPPLE%d.RAS" % (index + 1))
  check(magnet.icons[index] != null and magnet.icons[index].get_image().get_data() == original.get_data(),"Magnet HUD loads exact GRAPPLE%d.RAS artwork" % (index + 1))
 var som: Dictionary = game.equipment.available.filter(func(i: Dictionary) -> bool: return i.id == "suckomat")[0]
 var expected_mount := Node3D.new(); expected_mount.transform = magnet.mount.get_meta("default_mount")
 preload("res://submarine_mounts.gd").apply(expected_mount,game.pilot.visual,"magnet")
 check(magnet.mount.transform.is_equal_approx(expected_mount.transform),"Magnet respects its current editor mounting profile")
 expected_mount.free()
 check(not magnet.mount.visible,"Uninstalled magnet is hidden")
 for port in game.docking.ports:
  game.docking.current = port
  var offer: Dictionary = game._dock_ui_model().offers.magnet
  var city := str(port.name)
  check(offer.available == (city.begins_with("Tryton") or city.begins_with("Velcova")),"Original initial magnet availability: " + city)
  if city.begins_with("Velcova"): check(offer.price == 2500,"Original Velcova magnet price")
 for port in game.docking.ports:
  game.docking.current = port
  if game._dock_ui_model().offers.magnet.available: break
 game.docking.stage = game.Docking.Stage.DOCKED; game.dock_interface_active = true
 game.player_progress.status.credits = 100000
 var ui: CanvasLayer = game.dock_interface; ui.open("equipment")
 ui.selected_sale = "magnet"; ui.rebuild()
 ui.layout.get_node("BuyShieldRepair").grab_focus(); ui.layout.get_node("BuyShieldRepair").pressed.emit()
 check(game.player_progress.hold.get("magnet",0) == 1 and Shop.installed(game.equipment,game.weapons)[3] == "suckomat","Buying stores the magnet without equipping it")
 check(root.gui_get_focus_owner() == ui.layout.get_node("BuyShieldRepair"),"Buy retains controller focus")
 check(ui.layout.get_node("BuyShieldRepair").disabled,"Original maximum prevents duplicate tools")
 ui.selected_hold = "magnet"; ui.rebuild()
 ui.sale_list.grab_focus(); press(ui,JOY_BUTTON_DPAD_RIGHT)
 check(root.gui_get_focus_owner() == ui.slot_buttons[0],"Controller enters the slot grid from the sale list")
 press(ui,JOY_BUTTON_DPAD_DOWN); press(ui,JOY_BUTTON_DPAD_RIGHT); press(ui,JOY_BUTTON_DPAD_RIGHT)
 check(root.gui_get_focus_owner() == ui.slot_buttons[7],"Controller moves directly between slot rows and columns")
 check(ui.slot_buttons[7].get_theme_stylebox("normal").border_width_left == 2 and ui.mount_dot.visible,"Compatible slot and submarine mount are highlighted")
 ui.slot_buttons[7].pressed.emit()
 check(Shop.installed(game.equipment,game.weapons)[3] == "magnet" and game.player_progress.hold.get("suckomat",0) == 1 and not game.player_progress.hold.has("magnet"),"Installing magnet swaps SOM into the hold")
 check(magnet.mount.visible and not som.mount.visible and not game.equipment.vacuum.enabled,"Only installed underside equipment is visible and active")
 ui.selected_hold = "suckomat"; ui.rebuild(); ui.slot_buttons[7].pressed.emit()
 check(Shop.installed(game.equipment,game.weapons)[3] == "suckomat" and game.player_progress.hold.get("magnet",0) == 1,"SOM swaps back without losing either item")
 game.player_progress.hold.shield = 2; ui.selected_hold = "shield"; ui.rebuild(); ui.slot_buttons[7].pressed.emit()
 check(not Shop.installed(game.equipment,game.weapons).has(3) and game.player_progress.hold.shield == 2 and game.player_progress.hold.suckomat == 1,"An incompatible selection removes installed equipment to the hold")
 ui.slot_buttons[7].pressed.emit()
 check(game.player_progress.hold.suckomat == 1,"Clicking an empty incompatible slot does nothing")
 ui.slot_buttons[0].pressed.emit()
 check(game.weapons.mounted.is_empty() and not game.weapons.muzzle.visible and game.player_progress.hold.zapper == 1,"Zapper can be removed to the hold")
 game.weapons.update_fire(true,0.1)
 check(not game.weapons.firing,"An uninstalled zapper cannot fire")
 ui.selected_hold = "magnet"; ui.rebuild(); ui.slot_buttons[7].pressed.emit()
 game.save_games.folder = "res://tests/equipment-swap-fixtures"
 check(game.save_games.write(0,game._save_snapshot("Equipment swap")) == OK,"Equipment layout saves")
 game.equipment.set_installed(["deep_sea_lights","suckomat"]); game.weapons.set_installed(["zapper"])
 check(await game._load_saved_game(0),"Equipment layout loads")
 check(Shop.installed(game.equipment,game.weapons).get(3) == "magnet" and game.weapons.mounted.is_empty() and game.player_progress.hold.zapper == 1 and game.player_progress.hold.suckomat == 1,"Save restores both installed equipment and hold contents")
 ui.open("equipment"); ui.selected_hold = "magnet"; ui.rebuild()
 check(ui.hold_list.item_count == 3,"Hold only lists actual stored items")
 var panel: PanelContainer = game.sound_panel
 panel.sliders.wildlife_zapper_volume.value = -7; panel.sliders.wildlife_splat_volume.value = -24; panel.sliders.master_volume.value = -3
 var sample := AudioStreamPlayer3D.new(); game.world_root.add_child(sample)
 preload("res://explosion_audio.gd").apply(sample,0,"wildlife_zapper_volume")
 check(sample.volume_db == -10,"Fish zapper gain combines with master volume")
 preload("res://explosion_audio.gd").apply(sample,0,"wildlife_splat_volume")
 check(sample.volume_db == -27,"Wildlife splat has an independent volume")
 panel.sliders.wildlife_splat_volume.value = -60; preload("res://explosion_audio.gd").apply(sample,0,"wildlife_splat_volume")
 check(sample.volume_db == -80,"Wildlife splat can be muted")
 sample.free()
 if DisplayServer.get_name() != "headless":
  ui.selected_hold = "suckomat"; ui.rebuild()
  for frame in range(6): await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://tests/equipment-swap-preview.png")
 game.docking.stage = game.Docking.Stage.IDLE; game.pilot.active = true; game.pilot.controls_enabled = true; game.pilot.visual.show()
 game.equipment.selected = game.equipment.mounted.find(magnet)
 game.equipment.toggle_selected()
 check(game.equipment.magnet.enabled and game.equipment.magnet.links.size() == 4,"Mounted magnet activation deploys four chain links")
 check(game.equipment.current().enabled,"Equipment HUD reflects deployed magnet state")
 check(game.equipment_controls.has("magnet_length") and game.equipment_controls.has("magnet_speed") and game.equipment_controls.has("magnet_volume_db"),"Developer equipment menu exposes magnet tuning")
 game.equipment.set_installed(["deep_sea_lights"])
 check(not game.equipment.magnet.enabled and game.equipment.magnet.target == null,"Unequipping switches the magnet off and releases its target")
 game.equipment.set_installed(["deep_sea_lights","magnet"]); game.equipment.selected = game.equipment.mounted.find(magnet); game.equipment.toggle_selected()
 game._begin_new_game()
 check(not game.equipment.magnet.enabled and not is_instance_valid(game.equipment.magnet.rig),"Starting a new game removes the magnet chain")
 check(Shop.installed(game.equipment,game.weapons).get(3) == "suckomat" and game.weapons.current().get("id") == "zapper" and game.player_progress.hold.is_empty(),"New game restores the original starter loadout")
 DirAccess.remove_absolute("res://tests/equipment-swap-fixtures/slot-0.json")
 paused = false; game.queue_free(); await process_frame
 print("Equipment swapping: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
