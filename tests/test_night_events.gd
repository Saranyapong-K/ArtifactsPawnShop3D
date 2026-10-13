extends SceneTree
## Headless checks: catch/escape, curse counts, event window, police fines, pause.

const StateScript := preload("res://scripts/game_state.gd")
const ArtifactScript := preload("res://scripts/artifact_data.gd")
const NightScript := preload("res://scripts/night_events.gd")
const SfxScript := preload("res://scripts/sfx.gd")

var state: Node
var director: Node3D
var player: Node3D
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	state = root.get_node_or_null("GameState")
	if state == null:
		state = StateScript.new()
		state.name = "GameState"
		root.add_child(state)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	player = Node3D.new()
	scene.add_child(player)
	var door := Node3D.new()
	scene.add_child(door)
	var outside := Node3D.new()
	outside.position = Vector3(0, 0, 6)
	scene.add_child(outside)
	director = NightScript.new()
	scene.add_child(director)
	director.setup(player, door, outside)
	director.police_chance = 0.0
	director.thief_chance = 1.0

	state.new_game()
	state.start_clock()
	_add_artifact("normal")
	_set_time(20, 45)
	_check(director.selected_event == "thief", "thief warning selected")
	_set_time(21, 30)
	_check(director._actors.size() == 1, "one thief spawns")
	var thief = director._actors[0]
	_check(thief._visual.name == "NPCS1", "default thief uses the reused customer model")
	var wallet := int(state.money)
	player.global_position = thief.global_position
	thief.interact(player)
	_check(state.inventory.size() == 1 and state.money == wallet, "catch prevents theft and gives no wallet reward")
	_set_time(22, 0)
	_check(director._actors.is_empty(), "same night does not spawn a second event")
	await process_frame

	state.new_game()
	state.start_clock()
	_add_artifact("normal")
	_set_time(20, 45)
	_set_time(21, 30)
	thief = director._actors[0]
	wallet = state.money
	director._on_actor_escaped(thief)
	thief.queue_free()
	_check(state.inventory.is_empty() and state.money == wallet and state.day_profit == 0, "escape removes one artifact without credit or profit")
	await process_frame

	state.new_game()
	state.start_clock()
	_add_artifact("curse")
	_add_artifact("curse")
	state.set_item_owned("radio")
	_set_time(20, 45)
	_check(director.selected_event == "demon" and director.demon_count == 4, "two demons per cursed artifact override thief")
	_set_time(21, 30)
	_check(director._actors.size() == 4, "four demons spawned")
	_set_time(23, 0)
	_check(state.inventory.is_empty() and not state.owned_items.get("radio", false), "night end resolves bounded artifact and equipment theft")
	_check(state.day_profit == 0 and director.event_finished, "raid theft is not a sale")
	_set_time(23, 5)
	_check(director._actors.is_empty(), "no repeated theft after event end")
	await process_frame

	state.new_game()
	state.start_clock()
	_add_artifact("normal")
	_set_time(20, 45)
	_set_time(21, 30)
	thief = director._actors[0]
	var before: Vector3 = thief.global_position
	state.pause_time(&"night_test")
	thief._process(5.0)
	_check(thief.global_position == before, "intruder movement pauses with game time")
	state.resume_time(&"night_test")
	thief._process(0.5)
	_check(thief.global_position != before, "intruder movement resumes")
	await process_frame

	state.new_game()
	state.start_clock()
	state.day = 5
	state.money = 1000
	director.police_chance = 1.0
	_add_artifact("normal")
	for index in range(5):
		_add_artifact("stolen")
	_set_time(12, 0)
	_check(state.money == 500 and state.inventory.size() == 1 and state.inventory[0].status == "normal", "police confiscates all stolen goods and charges 500 G")
	_check(state.day_profit == 0 and not state.failed, "fine does not change trading profit")
	_set_time(12, 1)
	_check(state.money == 500, "one police roll per qualifying day")

	state.new_game()
	state.start_clock()
	state.day = 5
	state.money = 1000
	for index in range(4):
		_add_artifact("stolen")
	var purchase = ArtifactScript.create("res://assets/Relics/Goldcoin.glb", "New stolen artifact", "Common", "stolen")
	state.purchase(purchase, 10)
	_check(state.get_artifact(purchase.id) != null, "purchase finishes before deferred confiscation")
	await process_frame
	_check(state.inventory.is_empty() and state.money == 490, "deferred police confiscation follows purchase safely")

	state.new_game()
	state.start_clock()
	state.day = 5
	state.money = 499
	for index in range(5):
		_add_artifact("stolen")
	_set_time(12, 0)
	_check(state.failed and state.inventory.is_empty() and state.money == 499, "unpayable police fine ends game without negative wallet")

	state.new_game()
	state.start_clock()
	_add_artifact("normal")
	var custom_model := _custom_model()
	director.thief_model = custom_model
	director.demon_model = custom_model
	director._spawn_actor("thief", 0)
	director._spawn_actor("demon", 1)
	for intruder in director._actors:
		_check(intruder._visual is MeshInstance3D, "custom scene is used for " + intruder.kind)
		var custom_material: StandardMaterial3D = intruder._visual.mesh.surface_get_material(0)
		_check(custom_material.albedo_color.is_equal_approx(Color("65b89d")) and intruder._visual.get_surface_override_material(0) == null, "custom intruder materials are preserved")
		_check(is_equal_approx(intruder._visual.scale.y, 0.9 if intruder.kind == "demon" else 1.75), "custom model is fitted to the requested event character height")
	director._clear_actors()
	director.thief_model = null
	director.demon_model = null
	await process_frame

	var sfx = SfxScript.new()
	scene.add_child(sfx)
	_check(sfx._cues.has("coin") and sfx._cues.has("warning"), "procedural cues created")
	var tone: AudioStreamWAV = sfx._cues["coin"]
	_check(tone.data.size() > 0 and tone.format == AudioStreamWAV.FORMAT_16_BITS, "cue contains playable PCM")
	sfx.play("coin")
	_check(sfx._voices[0].stream == tone, "play selects a pooled audio voice")
	state.new_game()
	state.start_clock()
	var ambient_context:=Node.new(); ambient_context.name="Day_manager"; scene.add_child(ambient_context)
	current_scene=scene
	sfx._refresh_radio()
	_check(sfx._radio_active, "funky ambience starts in gameplay without owning a radio")
	state.set_item_owned("radio", false)
	sfx._refresh_radio()
	_check(sfx._radio_active and sfx.song_state=="stopped", "losing the radio retains ambience and stops songs")
	state.stop_clock(); sfx._refresh_radio()
	_check(not sfx._radio_active, "leaving gameplay stops ambience")
	for voice in sfx._voices:
		voice.stop()
		voice.stream = null
	sfx._radio.stop()
	sfx._radio.stream = null
	sfx.queue_free()
	for audio_player in root.find_children("*", "AudioStreamPlayer", true, false):
		audio_player.stop()
		audio_player.stream = null
	await process_frame
	# Allow queued AudioServer stop commands to retire their playback resources.
	await create_timer(0.15).timeout
	if errors.is_empty():
		print("NIGHT TESTS PASSED")
		quit(0)
	else:
		for error in errors:
			push_error(error)
		quit(1)


func _add_artifact(status: String) -> void:
	var artifact = ArtifactScript.create("res://assets/Relics/Goldcoin.glb", "Test artifact", "Common", status)
	artifact.cost = 10
	state.inventory.append(artifact)


func _set_time(hour: int, minute: int) -> void:
	state.time_minutes = hour * 60 + minute
	state.time_changed.emit(hour, minute)


func _check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


func _custom_model() -> PackedScene:
	var mesh_root := MeshInstance3D.new()
	mesh_root.name = "ReplacementModel"
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.resource_name = "Body"
	material.albedo_color = Color("65b89d")
	mesh.material = material
	mesh_root.mesh = mesh
	var packed := PackedScene.new()
	packed.pack(mesh_root)
	mesh_root.free()
	return packed
