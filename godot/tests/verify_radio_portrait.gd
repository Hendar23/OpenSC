extends SceneTree
const Portrait = preload("res://radio_portrait.gd")
const Radio = preload("res://docking_radio.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var folder := preload("res://asset_paths.gd").find_game_folder()
	var noise := Radio.static_frames(folder)
	check(noise.size() == 2,"Original radio static images load")
	var display := Portrait.new(); root.add_child(display)
	for race in [1,2,4]:
		var clear := Radio.portrait(folder,race)
		var distorted := Radio.distorted_portrait(folder,race)
		check(clear != null and distorted != null and clear.get_size() == distorted.get_size(),"Clear and distorted race portraits load at matching sizes")
		display.reset_signal()
		display.update_signal(clear,distorted,noise,0)
		check(display.visible and display.texture == noise[0],"Transmission starts with original static")
		display.update_signal(clear,distorted,noise,0.07)
		check(display.texture == distorted,"Receiver locks through the distorted portrait")
		display.update_signal(clear,distorted,noise,0.4)
		check(display.texture == clear and display.transition.is_empty(),"Established transmission holds the clear portrait")
		display.update_signal(null,null,noise,0)
		check(display.visible and display.transition == "outro","Disappearing message starts a short receiver drop sequence")
		display.update_signal(null,null,noise,0.1)
		check(display.texture == noise[1],"Receiver drop uses the original static variant")
		display.update_signal(clear,distorted,noise,0)
		check(display.transition == "intro" and display.modulate.a == 1,"A new transmission cleanly interrupts receiver drop")
		display.update_signal(null,null,noise,0.3)
		check(not display.visible and display.texture == null,"Receiver disappears after its outro finishes")
	# Missing optional frames still show the clear portrait without errors.
	var clear := Radio.portrait(folder,1)
	display.update_signal(clear,null,[],0)
	check(display.texture == clear,"Missing interference assets fall back to the clear portrait")
	display.queue_free(); await process_frame
	print("Radio portrait: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
