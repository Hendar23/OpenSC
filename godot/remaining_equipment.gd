extends Node3D
## Bubble Gun, Repellertron, flares, Strobe and finite-fuel Woosh Drive.
const Assets = preload("res://clump_loader.gd")
const Flare = preload("res://illuminating_flare.gd")
const BOOST := 1.666
const FUEL_PER_SECOND := 0.05*25.0
var equipment: Node3D
var folder := ""
var repel_audio: AudioStreamPlayer
var bubble_audio: AudioStreamPlayer
var flare_audio: AudioStreamPlayer
var strobe: SpotLight3D
var flare_cooldown := 0.0
var bubble_remaining := 0.0
var strobe_clock := 0.0
var field_clock := 0.0
var bubbles: Node3D
var flares: Array[Node3D] = []
var boost_on := false

func setup(context: Node3D, game_folder: String) -> void:
	equipment = context; folder = game_folder
	var tools: Node3D = equipment.support_tools
	tools._add_tool("bubble","Bubble Gun","BUBBLGUN",["BUBBLEWP"],Vector3(0,0.22,0.35))
	# Replacement models retain their previous fallback sockets. The original
	# submarine receives the source-derived transforms in submarine_mounts.gd.
	tools._add_tool("repel","Repellertron","ATTRACT",["REPPON","REPPOFF"],item("attract").mount.position)
	tools._add_tool("strobe","Strobe","STROBE",["STROBE1","STROBE2"],item("bigears").mount.position)
	tools._add_tool("flarel","FLR-1000","MISSILEL",["FLAREWP"],Vector3(0,0.3,0.05))
	tools._add_tool("sflarel","FLR-1500","MISSILEL",["STATFLR"],Vector3(0,0.3,0.05))
	tools._add_tool("woosh","Woosh Drive","MISSILEL",["TURBO"],item("attract").mount.position)
	for id in ["bubble","repel","strobe","flarel","sflarel","woosh"]:
		for mesh: MeshInstance3D in item(id).mount.find_children("*","MeshInstance3D",true,false): mesh.layers = 2
	repel_audio = _audio("audio.equipment.repel","REPELL",true)
	bubble_audio = _audio("audio.equipment.bubble","BUBGUN",true)
	flare_audio = _audio("audio.equipment.flare","FFISH4",false)
	strobe = SpotLight3D.new(); strobe.spot_range = 20; strobe.spot_angle = 70
	strobe.light_color = Color(0.9,0.96,1); strobe.light_energy = 0; strobe.shadow_enabled = true
	item("strobe").mount.add_child(strobe)
	if preload("res://submarine_mounts.gd").is_original(equipment.pilot.visual):
		# 0047ab70 uses a separate 45-degree light frame, just ahead of its housing.
		strobe.position = Vector3(0,-0.005,-0.05); strobe.rotation_degrees.x = -45
	bubbles = preload("res://propeller_bubbles.gd").new(); bubbles.capacity = 256; add_child(bubbles)
	bubbles.configure(Assets._load_texture(folder,"BUBBLE","BUBBLEM",{}))
	bubbles.surface_height = equipment.pilot.surface_height

func _audio(id: String, sample: String, loop: bool) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = preload("res://audio_loop.gd").prepare(preload("res://submarine_weapons.gd")._sound(folder,id,sample),loop,30)
	add_child(player); return player

func item(id: String) -> Dictionary:
	for entry in equipment.available:
		if entry.id == id: return entry
	return {}

func installed(id: String) -> bool:
	return equipment.mounted.any(func(entry: Dictionary) -> bool: return entry.id == id)

func on(id: String) -> bool:
	return installed(id) and bool(item(id).enabled)

func progress() -> Dictionary:
	var runtime: Node = equipment.support_tools.runtime()
	return runtime.game.player_progress if runtime != null else {}

func activate(id: String) -> void:
	if id == "bubble":
		if bubble_remaining <= 0: bubble_remaining = 4.0
		item(id).enabled = false
	elif id in ["flarel","sflarel"]:
		if flare_cooldown <= 0:
			for index in range(flares.size()-1,-1,-1):
				if not is_instance_valid(flares[index]): flares.remove_at(index)
			var mount: Node3D = item(id).mount
			var flare := Flare.new(); equipment.pilot.get_parent().add_child(flare)
			flare.setup(self,id == "sflarel",preload("res://submarine_mounts.gd").launch_point(mount,equipment.pilot.visual,id,Vector3(0,0,-0.3)),-mount.global_basis.z.normalized())
			flares.append(flare); flare_cooldown = 0.2
			if flare_audio.stream != null: flare_audio.play()
		item(id).enabled = false
	elif id == "woosh" and on(id):
		var state := progress()
		if not state.is_empty() and float(state.ammunition.get("woosh",99)) <= 0: item(id).enabled = false
	refresh()

func refresh() -> void:
	var pilot: Node3D = equipment.pilot
	var live: bool = pilot.active and pilot.controls_enabled and not pilot.dead and not pilot.remote_controlled
	boost_on = live and on("woosh")
	pilot.movement.boost_multiplier = BOOST if boost_on else 1.0
	var state := progress()
	if not state.is_empty(): state.status.top_speed = 166 if boost_on else 100
	if not installed("bubble"): bubble_remaining = 0
	pilot.set_meta("bubble_screened",live and installed("bubble") and bubble_remaining > 2.0)
	if not on("strobe") or not live: strobe.light_energy = 0; strobe_clock = 0
	if not on("repel") or not live: repel_audio.stop()
	if not bool(pilot.get_meta("bubble_screened",false)): bubble_audio.stop()

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	refresh()
	var pilot: Node3D = equipment.pilot
	var live: bool = pilot.active and pilot.controls_enabled and not pilot.dead and not pilot.remote_controlled
	flare_cooldown = maxf(0,flare_cooldown-delta)
	if not live: return
	var gain: float = -16.0 + (float(pilot.submarine_audio.tuning.settings.master_volume) if pilot.submarine_audio != null else 0)
	for player in [repel_audio,bubble_audio,flare_audio]: player.volume_db = gain
	if bubble_remaining > 0:
		bubble_remaining = maxf(0,bubble_remaining-delta)
		if bool(pilot.get_meta("bubble_screened",false)):
			if not bubble_audio.playing and bubble_audio.stream != null: bubble_audio.play()
			# Two bubbles per 25 Hz update, emitted aft of the hull as in retail.
			bubbles.emit_from(0,pilot.to_global(Vector3(0,0,0.6)),pilot.global_basis.z,1,50,delta)
	if boost_on:
		var state := progress()
		if not state.is_empty():
			state.ammunition.woosh = maxf(0,float(state.ammunition.get("woosh",99))-FUEL_PER_SECOND*delta)
			state.status.top_speed = 166
			if float(state.ammunition.woosh) < 1.0:
				item("woosh").enabled = false
				equipment.set_installed(equipment.mounted.filter(func(entry: Dictionary) -> bool: return entry.id != "woosh").map(func(entry: Dictionary) -> String: return str(entry.id)))
	else:
		var state := progress()
		if not state.is_empty(): state.status.top_speed = 100
	if on("strobe"):
		strobe_clock = fmod(strobe_clock+delta,21.0/25.0)
		strobe.light_energy = maxf(0,0.75-(strobe_clock*25.0)*0.05)*20.0
	if on("repel"):
		if not repel_audio.playing and repel_audio.stream != null: repel_audio.play()
		field_clock -= delta
		if field_clock <= 0:
			field_clock = 0.04
			for fish in get_tree().get_nodes_in_group("marine_life"):
				if fish.get_world_3d() == get_world_3d() and not fish.dead and fish.global_position.distance_squared_to(pilot.global_position) <= 25.0:
					fish.repel_from(pilot.to_global(Vector3(0,0,1.5)),0.12)
	refresh()

func count(id: String) -> int:
	var state := progress()
	return clampi(int(state.ammunition.get("woosh",99)),0,99) if id == "woosh" and not state.is_empty() else -1

func reset() -> void:
	for flare in flares:
		if is_instance_valid(flare): flare.free()
	flares.clear(); bubbles.clear(); bubble_remaining = 0; flare_cooldown = 0; strobe_clock = 0; field_clock = 0
	for id in ["bubble","repel","strobe","flarel","sflarel","woosh"]: item(id).enabled = false
	refresh()

func _exit_tree() -> void:
	if is_instance_valid(equipment) and is_instance_valid(equipment.pilot):
		equipment.pilot.movement.boost_multiplier = 1.0; equipment.pilot.set_meta("bubble_screened",false)
	for flare in flares:
		if is_instance_valid(flare) and not flare.is_queued_for_deletion(): flare.queue_free()
