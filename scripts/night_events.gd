class_name NightEvents
extends Node3D
## One night event from 21:00 to 23:00; daytime stolen-goods inspections.
## Thief/police probabilities and intruder pacing are tunable release defaults.

signal notice(text: String)
signal inventory_changed
signal door_requested(open: bool)

const EVENT_ACTOR := preload("res://scripts/event_actor.gd")
const WARNING_TIME := 20 * 60 + 45
const EVENT_START := 21 * 60
const EVENT_END := 23 * 60

@export_range(0.0, 1.0) var thief_chance: float = 0.35
@export_range(0.0, 1.0) var police_chance: float = 0.20
@export var intruder_wait_seconds: float = 22.0
@export var police_min_day: int = 5
@export var stolen_threshold: int = 5
@export var thief_model: PackedScene
@export var demon_model: PackedScene
@export var police_model: PackedScene

var selected_event: String = ""
var event_started: bool = false
var event_finished: bool = false
var demon_count: int = 0
var _warned: bool = false
var _police_checked: bool = false
var _arrival_time: int = EVENT_START
var _state: Node
var _player: Node3D
var _door: Node3D
var _exit: Node3D
var _eyes: Node3D
var _actors: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _police_actor: Node3D


func setup(player: Node3D, door_spot: Node3D, exit_spot: Node3D) -> void:
	_player = player
	_door = door_spot
	_exit = exit_spot
	_state = get_node_or_null("/root/GameState")
	_rng.randomize()
	if _state == null:
		return
	_state.connect("time_changed", _on_time_changed)
	_state.connect("day_started", _on_day_started)
	_state.connect("changed", _on_inventory_changed)
	_state.connect("game_over", _on_game_over)
	_on_day_started(int(_state.get("day")))
	_on_time_changed(int(_state.get("time_minutes")) / 60, int(_state.get("time_minutes")) % 60)


func _on_day_started(_day: int) -> void:
	if is_instance_valid(_police_actor): _police_actor.queue_free()
	_police_actor = null
	_clear_actors()
	_clear_eyes()
	selected_event = ""
	event_started = false
	event_finished = false
	demon_count = 0
	_warned = false
	_police_checked = false
	_arrival_time = EVENT_START


func has_active_event() -> bool:
	return event_started and not event_finished


func _on_time_changed(hour: int, minute: int) -> void:
	if _state == null or bool(_state.get("failed")):
		return
	var now := hour * 60 + minute
	if now < 19 * 60:
		_maybe_police()
	if now >= WARNING_TIME and now < EVENT_END and not _warned:
		_prepare_night()
	if now >= _arrival_time and now < EVENT_END and _warned and not event_started and not selected_event.is_empty():
		_start_event()
	if now >= EVENT_END and not event_finished:
		# The event window has ended; any uncaught intruders leave with their theft.
		for actor in _actors.duplicate():
			if is_instance_valid(actor) and not bool(actor.get("resolved")):
				actor.set("resolved", true)
				_on_actor_escaped(actor)
				actor.queue_free()
		event_finished = true
		_clear_eyes()


func _prepare_night() -> void:
	_warned = true
	var cursed := _items_with_status("curse").size()
	if cursed > 0:
		selected_event = "demon"
		demon_count = cursed * 2
		notice.emit("Cursed artifacts attracted %d goblins. Approach and press %s to repel them." % [demon_count, _interact_key()])
		_flicker_lights()
		_play_sound("warning")
	elif _rng.randf() < thief_chance:
		selected_event = "thief"
		_show_eyes()
		notice.emit("Yellow eyes outside. Approach and press %s to catch the thief." % _interact_key())
		_play_sound("warning")
	else:
		selected_event = ""
		event_finished = true


func _start_event() -> void:
	if event_started or event_finished:
		return
	event_started = true
	_clear_eyes()
	door_requested.emit(true)
	if selected_event == "demon":
		# Count again at arrival: removing a curse during the warning can prevent a raid.
		demon_count = _items_with_status("curse").size() * 2
		for index in range(demon_count):
			_spawn_actor("demon", index)
		if demon_count > 0:
			notice.emit("Goblins entered. Approach and press %s to repel each one." % _interact_key())
	else:
		_spawn_actor("thief", 0)
		notice.emit("A thief entered. Approach and press %s to catch them." % _interact_key())
	if _actors.is_empty():
		event_finished = true
		door_requested.emit(false)
	_play_sound("door")


func _spawn_actor(kind: String, index: int) -> void:
	if _door == null or _exit == null:
		return
	var actor := EVENT_ACTOR.new()
	actor.name = "%s_%d" % [kind, index]
	add_child(actor)
	actor.caught.connect(_on_actor_caught)
	actor.escaped.connect(_on_actor_escaped)
	var outside := _exit.global_position
	var door := _door.global_position
	var target := door + Vector3(0, 0, -1.5)
	var stock: Array = _state.get("inventory")
	if not stock.is_empty():
		var item = stock[index % stock.size()]
		var placement: Dictionary = item.placement
		var position_data: Variant = placement.get("position", [])
		if position_data is Array and position_data.size() == 3:
			target = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
			target.y = door.y
			target.z += 0.6
	elif _player != null:
		target = _player.global_position
		target.y = door.y
	# Spread demon arrivals without teleporting their collision bodies onto one another.
	var offset := Vector3(float(index % 3 - 1) * 0.45, 0, float(index / 3) * 0.5)
	var route: Array[Vector3] = [outside + offset, door + offset * 0.2, target + offset * 0.25, door, outside]
	var model: PackedScene = thief_model if kind == "thief" else demon_model
	if kind == "thief" and model == null and ResourceLoader.exists("res://npcs_1.tscn"):
		model = load("res://npcs_1.tscn") as PackedScene
	actor.setup(kind, route, model, intruder_wait_seconds + float(index % 4) * 3.0)
	_actors.append(actor)


func _on_actor_caught(actor: Node3D) -> void:
	if not actor in _actors:
		return
	_actors.erase(actor)
	var kind := String(actor.get("kind"))
	notice.emit("Thief caught. Your stock is safe." if kind == "thief" else "Demon repelled. Keep the remaining artifacts safe.")
	_play_sound("catch")
	_finish_if_empty()


func _on_actor_escaped(actor: Node3D) -> void:
	if not actor in _actors:
		return
	_actors.erase(actor)
	var stolen_name := _steal_one(String(actor.get("kind")))
	if stolen_name.is_empty():
		notice.emit("An intruder escaped with nothing.")
	else:
		notice.emit("An intruder escaped with %s." % stolen_name)
		_play_sound("error")
	_finish_if_empty()


func _steal_one(kind: String) -> String:
	if _state == null or bool(_state.get("failed")):
		return ""
	var stock: Array = _state.get("inventory")
	if not stock.is_empty():
		var artifact = stock[_rng.randi_range(0, stock.size() - 1)]
		var item_name := String(artifact.display_name)
		_state.call("remove_artifact", String(artifact.id))
		inventory_changed.emit()
		return item_name
	if kind == "demon":
		var equipment: Dictionary = _state.get("owned_items")
		var owned: Array[String] = []
		for item_id in equipment:
			# Keep core cleaning tools available; valuables remain stealable.
			if item_id in ["magnifier","curse_detector","clock","radio"] and bool(equipment[item_id]):
				owned.append(String(item_id))
		if not owned.is_empty():
			var item_id := owned[_rng.randi_range(0, owned.size() - 1)]
			_state.call("set_item_owned", item_id, false)
			inventory_changed.emit()
			return item_id.replace("_", " ")
	return ""


func _finish_if_empty() -> void:
	if event_started and _actors.is_empty():
		event_finished = true
		door_requested.emit(false)


func _on_inventory_changed() -> void:
	if _state != null and int(_state.get("time_minutes")) < 19 * 60:
		# Let a purchase finish spawning its model before a confiscation removes it.
		call_deferred("_maybe_police")


func _maybe_police() -> void:
	if _police_checked or _state == null or bool(_state.get("failed")) or int(_state.get("day")) < police_min_day or int(_state.get("time_minutes")) >= 19 * 60:
		return
	var stolen := _items_with_status("stolen")
	if stolen.size() < stolen_threshold:
		return
	_police_checked = true
	if _rng.randf() >= police_chance:
		return
	_show_police()
	for artifact in stolen:
		_state.call("remove_artifact", String(artifact.id))
	inventory_changed.emit()
	if not bool(_state.call("spend", 500)):
		notice.emit("Police confiscated every stolen artifact. You cannot pay the 500 G fine.")
		_state.call("end_game", "You could not pay the 500 G stolen-goods fine.")
	else:
		notice.emit("Police confiscated every stolen artifact and fined you 500 G.")
	_play_sound("warning")

func _show_police() -> void:
	if police_model == null or _exit == null or _door == null: return
	_police_actor = EVENT_ACTOR.new()
	_police_actor.name = "GoblinPoliceRaid"
	add_child(_police_actor)
	var main := _door.get_parent().get_parent()
	var counter := main.get_node_or_null("Marks/CashierSpot") as Node3D
	var inspection_point := counter.global_position if counter else _door.global_position + Vector3(0, 0, -1.5)
	var route: Array[Vector3] = [_exit.global_position, _door.global_position, inspection_point, _door.global_position, _exit.global_position]
	_police_actor.setup("police", route, police_model, 8.0)
	# Police are a visual visit; confiscation/fines still use the existing rules.


func _items_with_status(status: String) -> Array:
	var found: Array = []
	if _state != null:
		for artifact in _state.get("inventory"):
			if String(artifact.status) == status:
				found.append(artifact)
	return found


func _show_eyes() -> void:
	if _door == null or _exit == null:
		return
	_eyes = Node3D.new()
	add_child(_eyes)
	_eyes.global_position = _door.global_position.lerp(_exit.global_position, 0.45) + Vector3.UP * 1.5
	var window := get_tree().current_scene.find_child("Window", true, false) as MeshInstance3D if get_tree().current_scene else null
	if window:
		var bounds: AABB = window.global_transform * window.get_aabb()
		_eyes.global_position = Vector3(bounds.get_center().x, bounds.get_center().y, bounds.position.z - 0.085)
	if _player != null:
		_eyes.look_at(_player.global_position + Vector3.UP * 1.5, Vector3.UP, true)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ffd447")
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.07
		mesh.height = 0.085
		mesh.radial_segments = 6
		mesh.rings = 3
		eye.mesh = mesh
		eye.material_override = material
		eye.position.x = side * 0.12
		_eyes.add_child(eye)


func _flicker_lights() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for light in scene.find_children("*", "OmniLight3D", true, false):
		var energy := float(light.light_energy)
		var tween := create_tween()
		for pulse in range(3):
			tween.tween_property(light, "light_energy", energy * 0.2, 0.15)
			tween.tween_property(light, "light_energy", energy, 0.2)


func _clear_eyes() -> void:
	if is_instance_valid(_eyes):
		_eyes.queue_free()
	_eyes = null


func _clear_actors() -> void:
	for actor in _actors:
		if is_instance_valid(actor):
			actor.queue_free()
	_actors.clear()


func _on_game_over(_reason: String) -> void:
	if is_instance_valid(_police_actor): _police_actor.queue_free()
	_clear_actors()
	_clear_eyes()


func _play_sound(cue: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.call("play", cue)

func _interact_key() -> String:
	var settings := get_node_or_null("/root/GameSettings")
	return settings.key_name("interact") if settings else "E"
