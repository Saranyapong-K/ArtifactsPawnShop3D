extends Node
## Runs the day:
## customer walks in -> haggle at cashier -> reveal -> customer leaves -> ... -> summary -> autosave.
## Put Day_manager.tscn inside the Main scene. It finds everything by name.
## Needs in Main: Player, Shop (with AnimationPlayer), and Marks > Door, ExitSpot, CashierSpot, RelicSpot.

signal customer_arrived(h: Haggle)
signal customer_anger_changed(anger: float)
signal deal_made(h: Haggle)            # hook: spawn the relic on RelicSpot, heart effect, coins
signal customer_left(h: Haggle)

const SAVE_PATH := "user://save.json"
const CUSTOMERS_PER_DAY := 5
const DOOR_ANIM := "DoorFront_Open"
const FALLBACK_CUSTOMER := "res://npcs_1.tscn"
const Lines = preload("res://scripts/dialogue_lines.gd")

enum Phase { WAITING, HAGGLING, REVEAL, SUMMARY, BUSY }   # WAITING = customer at cashier, waiting for E

## Drag customer scenes here later. Empty = uses res://npcs_1.tscn
@export var customer_scenes: Array[PackedScene] = []
## Drag your artifact scenes here. Empty = a gold placeholder cube.
@export var relic_scenes: Array[PackedScene] = []
## Seconds between one customer leaving and the next arriving (random between min and max).
@export var min_arrival_delay := 10.0
@export var max_arrival_delay := 15.0
## Wait before the very first customer of the day.
@export var first_customer_delay := 3.0
## Small PNG shown above the customer after a deal. Empty = a pink heart drawn in code.
@export var happy_texture: Texture2D

var ui: BargainUI
var money := 2000
var day := 1
var queue: Array[Haggle] = []
var index := -1
var day_profit := 0
var current: Haggle
var phase := Phase.BUSY

var customer   # the customer node (npcs_1 with customer.gd attached)
var player: Node3D
var door_spot: Node3D
var exit_spot: Node3D
var cashier_spot: Node3D
var relic_spot: Node3D
var door_anim: AnimationPlayer
var show_spot: Node3D          # optional Marks > ShowSpot: where the customer steps aside
var bargain_cam: Camera3D      # optional node named BargainCam
var relic_holder: Node3D
var hud   # always-visible money display (player_hud.gd)


func _ready() -> void:
	_find_scene_nodes()
	ui = BargainUI.new()
	add_child(ui)
	ui.offer_submitted.connect(_on_offer)
	ui.accept_pressed.connect(_on_accept)
	ui.send_away_pressed.connect(_on_send_away)
	ui.next_pressed.connect(_on_next)
	load_game()
	hud = load("res://scripts/player_hud.gd").new()
	add_child(hud)
	hud.set_money(money, false)
	start_day()


func _find_scene_nodes() -> void:
	var root := get_tree().root
	player = root.find_child("Player", true, false) as Node3D

	# Look inside "Marks" on purpose: the shop also has a mesh called "Door"
	var marks := root.find_child("Marks", true, false)
	if marks:
		door_spot = marks.get_node_or_null("Door") as Node3D
		exit_spot = marks.get_node_or_null("ExitSpot") as Node3D
		cashier_spot = marks.get_node_or_null("CashierSpot") as Node3D
		relic_spot = marks.get_node_or_null("RelicSpot") as Node3D
		show_spot = marks.get_node_or_null("ShowSpot") as Node3D

	bargain_cam = root.find_child("BargainCam", true, false) as Camera3D
	# Search the whole scene for the AnimationPlayer that owns the door animation
	door_anim = _find_anim_player(root, DOOR_ANIM)

func _find_anim_player(node: Node, anim_name: String) -> AnimationPlayer:
	if node is AnimationPlayer and node.has_animation(anim_name):
		return node
	for child in node.get_children():
		var found := _find_anim_player(child, anim_name)
		if found:
			return found
	return null


func _has_markers() -> bool:
	return door_spot != null and exit_spot != null and cashier_spot != null


func start_day() -> void:
	queue = DayQueue.build(CUSTOMERS_PER_DAY)
	index = -1
	day_profit = 0
	_next_customer()


func _next_customer() -> void:
	index += 1
	if index >= queue.size():
		_end_day()
		return
	current = queue[index]
	phase = Phase.BUSY
	ui.visible = false
	_set_player_controls(true)

	# breathing room: the player can walk around / pick up relics meanwhile
	var wait := first_customer_delay if index == 0 else randf_range(min_arrival_delay, max_arrival_delay)
	await get_tree().create_timer(wait).timeout

	await _customer_enters()

	current.anger_changed.connect(_on_haggle_anger)
	phase = Phase.WAITING
	customer_arrived.emit(current)
	if customer:
		# floating E appears; the bargain starts when the player presses E on the customer
		customer.interacted.connect(_start_bargain, CONNECT_ONE_SHOT)
		customer.set_interactable(true)
	else:
		_start_bargain()   # no 3D customer (test mode): go straight to the bargain


func _start_bargain() -> void:
	if phase != Phase.WAITING:
		return
	phase = Phase.BUSY            # intro is playing: ignore bargain input
	_set_player_controls(false)   # frees the mouse
	ui.visible = true
	if customer == null:          # test mode without a 3D customer
		_open_bargain_ui()
		return

	customer.set_interactable(false)
	if bargain_cam:
		bargain_cam.make_current()
	var look_pos: Vector3 = bargain_cam.global_position if bargain_cam else (player.global_position if player else cashier_spot.global_position)
	customer.face_toward(look_pos)

	# 1. greet
	customer.play("talk")
	await ui.say(Lines.GREET.pick_random())

	# 2. step aside and show the relic
	await customer.walk_to(_show_position())
	customer.face_toward(look_pos)
	customer.play("show_relic")
	_spawn_relic()
	await ui.say(Lines.SHOW.pick_random())

	# 3. bargain (idle while the player thinks; talks after each offer)
	customer.play("idle")
	_open_bargain_ui()


func _open_bargain_ui() -> void:
	phase = Phase.HAGGLING
	ui.visible = true
	ui.show_customer(index + 1, queue.size(), money, current.market_price, current.ask, "")


func _show_position() -> Vector3:
	if show_spot:
		return show_spot.global_position
	# no ShowSpot marker: step 0.7 m sideways from the cashier spot
	return cashier_spot.global_position + cashier_spot.global_transform.basis.x * 0.7


func _spawn_relic() -> void:
	if relic_spot == null:
		return
	_clear_relic()
	var holder: Node3D = load("res://scripts/relic_spinner.gd").new()
	add_child(holder)
	holder.global_position = relic_spot.global_position
	holder.scale = Vector3.ONE * current.relic_scale

	var model: Node3D
	if relic_scenes.is_empty():
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.25, 0.25, 0.25)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("f5c542")
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		model = mi
	else:
		model = relic_scenes.pick_random().instantiate() as Node3D
	holder.add_child(model)
	relic_holder = holder


## Turns the relic shown during the haggle into a real pick-up-able item on the counter.
func _drop_relic() -> void:
	if relic_holder == null or not is_instance_valid(relic_holder) or relic_spot == null:
		_clear_relic()
		return
	var model := relic_holder.get_child(0) as Node3D
	var item: RigidBody3D = load("res://scripts/relic_item.gd").new()
	get_parent().add_child(item)
	item.global_position = relic_spot.global_position + Vector3(randf_range(-0.1, 0.1), 0.35, randf_range(-0.1, 0.1))
	item.rotation.y = randf_range(0.0, TAU)
	model.reparent(item, false)
	model.transform = Transform3D.IDENTITY
	item.setup(model, current.relic_scale, current.true_value)
	relic_holder.queue_free()
	relic_holder = null


func _clear_relic() -> void:
	if relic_holder and is_instance_valid(relic_holder):
		relic_holder.queue_free()
	relic_holder = null


func _restore_player_cam() -> void:
	var cam = player.get("camera") if player else null
	if cam:
		cam.make_current()


## Called when the bargain is over (deal revealed or customer walked out).
func _end_bargain_view(keep_relic: bool = false) -> void:
	if keep_relic:
		_drop_relic()
	else:
		_clear_relic()
	_restore_player_cam()
	_set_player_controls(true)


func _end_day() -> void:
	phase = Phase.SUMMARY
	var finished_day := day
	day += 1
	save_game()   # autosave after each day
	_set_player_controls(false)
	ui.visible = true
	ui.show_summary(finished_day, day_profit, money)


# ---------- customer movement ----------

func _pick_customer_scene() -> PackedScene:
	if customer_scenes.is_empty():
		return load(FALLBACK_CUSTOMER) as PackedScene
	return customer_scenes[index % customer_scenes.size()]   # take turns: model 1, model 2, model 1...


func _customer_enters() -> void:
	if not _has_markers():
		await get_tree().create_timer(0.3).timeout
		return

	customer = _pick_customer_scene().instantiate()
	if not customer.has_method("walk_to"):
		customer.free()
		customer = null
		return
	add_child(customer)
	customer.global_position = exit_spot.global_position

	_open_door()
	await customer.walk_to(door_spot.global_position)
	await customer.walk_to(cashier_spot.global_position)
	_close_door()

	var look_at_pos := player.global_position if player else cashier_spot.global_position
	customer.face_toward(look_at_pos)
	customer.play("idle")   # waits for the player to press E


func _customer_exits() -> void:
	if customer == null or not _has_markers():
		return
	var c = customer
	customer = null
	_open_door()
	await c.walk_to(door_spot.global_position)
	await c.walk_to(exit_spot.global_position)
	_close_door()
	c.queue_free()


func _open_door() -> void:
	if door_anim and door_anim.has_animation(DOOR_ANIM):
		door_anim.play(DOOR_ANIM)


func _close_door() -> void:
	if door_anim and door_anim.has_animation(DOOR_ANIM):
		door_anim.play_backwards(DOOR_ANIM)


func _set_player_controls(enabled: bool) -> void:
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(enabled)


func _on_haggle_anger(anger: float) -> void:
	customer_anger_changed.emit(anger)
	if customer:
		customer.set_anger(anger)


# ---------- player actions ----------

func _on_offer(price: int) -> void:
	if phase != Phase.HAGGLING:
		return
	if price > money:
		ui.show_message("You can't afford that.")
		return
	if customer:
		customer.play("talk")
	_handle(current.make_offer(price))


func _on_accept() -> void:
	if phase != Phase.HAGGLING:
		return
	if current.ask > money:
		ui.show_message("You can't afford that.")
		return
	_handle(current.accept_ask())


func _on_send_away() -> void:
	if phase != Phase.HAGGLING:
		return
	_handle(current.send_away())


func _on_next() -> void:
	match phase:
		Phase.REVEAL:
			phase = Phase.BUSY
			ui.visible = false
			hud.set_money(money)   # money updates after the reveal, not before
			_end_bargain_view(true)   # the bought relic drops onto the counter
			await _customer_exits()
			_next_customer()
		Phase.SUMMARY:
			start_day()


func _handle(res: Dictionary) -> void:
	var rest := "angry" if current.get_anger() >= 0.6 else "idle"
	match res["result"]:
		"deal":
			_finish_deal()
		"counter":
			ui.update_state(current.ask, current.get_anger(), "Hmm... how about %d?" % current.ask)
			if customer:
				customer.play_for("talk", 1.5, rest)
		"firm":
			ui.update_state(current.ask, current.get_anger(), "No. My price is %d." % current.ask)
			if customer:
				customer.play_once("disagree", rest)
		"left":
			_customer_left()


func _finish_deal() -> void:
	phase = Phase.REVEAL
	var profit := current.get_profit()
	# PLACEHOLDER: relic is counted as sold at its true value right away.
	money += profit
	day_profit += profit
	if customer:
		customer.play_once("agree", "idle")
		customer.show_happy(happy_texture)
	deal_made.emit(current)
	ui.show_reveal(current.true_value, current.deal_price)


func _customer_left() -> void:
	phase = Phase.BUSY
	customer_left.emit(current)
	ui.set_controls_enabled(false)
	ui.update_state(current.ask, 1.0, "Tch! Forget it, I'm leaving!")
	if customer:
		customer.set_anger(1.0)
		customer.play("angry")
	await get_tree().create_timer(1.5).timeout
	ui.visible = false
	_end_bargain_view()
	await _customer_exits()
	_next_customer()


# ---------- save / load ----------

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not save: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify({"day": day, "money": money}))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary:
		day = int(data.get("day", 1))
		money = int(data.get("money", money))
