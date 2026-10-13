extends Node
## Coordinates customers with the authoritative wallet, stock, clock and placement.

signal customer_arrived(h)
signal customer_anger_changed(anger: float)
signal deal_made(h)
signal customer_left(h)

const DOOR_ANIM := "DoorFront_Open"
const Lines = preload("res://scripts/dialogue_lines.gd")
const Appearance = preload("res://scripts/customer_appearance.gd")
const PlacementScript = preload("res://scripts/placement_manager.gd")
const GameUIScene = preload("res://ui/game_ui.tscn")
const BargainScene = preload("res://ui/bargain_interface.tscn")
const StationScript = preload("res://scripts/world_station.gd")
const NightScript = preload("res://scripts/night_events.gd")
const CleaningScene = preload("res://scenes/cleaning_world.tscn")
const FlowScene = preload("res://scenes/customer_flow.tscn")
const NavigationScript = preload("res://scripts/shop_navigation.gd")
const BedScript = preload("res://scripts/bed_rest.gd")
enum Phase { FREE, ARRIVING, WAITING, INTRO, HAGGLING, RECEIPT, SUMMARY, BUSY, CLOSED }

@export var customer_scenes: Array[PackedScene] = []
@export var radio_songs: Array[AudioStream] = []
@export var relic_scenes: Array[PackedScene] = [] # Retained for the existing scene; catalog supplies identities.
@export var min_arrival_delay: float = 28.0
@export var max_arrival_delay: float = 45.0
@export var first_customer_delay: float = 3.0
@export var happy_texture: Texture2D
@export var thief_model: PackedScene
@export var demon_model: PackedScene
@export var police_model: PackedScene
@export var crowd_enabled := true

var ui: BargainUI
var game_ui: CanvasLayer
var placement: Node3D
var night: Node
var cleaning: Node3D
var flow: Node3D
var navigation: Node3D
var phase: Phase = Phase.FREE
var queue: Array[Haggle] = []
var current: RefCounted
var customer: Node3D
var player: Node3D
var door_spot: Node3D
var exit_spot: Node3D
var cashier_spot: Node3D
var show_spot: Node3D
var relic_spot: Node3D
var bargain_cam: Camera3D
var door_anim: AnimationPlayer
var relic_holder: Node3D
var _sleep_preparing := false
var newspaper_delivered: bool = false
var _newspaper_time: int = 645
var _seller_index: int = 0
var _visitor_index: int = 0
var _buyer: bool = false
var _epoch: int = 0
var _closed: bool = false
var _waiting: bool = false
var _arrival_timer: SceneTreeTimer
var _lights: Array[OmniLight3D] = []
var _light_energy: Array[float] = []
var _hallucination_seconds: float = 0.0
var _hallucinating: bool = false
var _bargain_camera_transform := Transform3D.IDENTITY
var _bargain_inspecting := false
var money: int:
	get: return GameState.money
var day: int:
	get: return GameState.day
var day_profit: int:
	get: return GameState.day_profit

func _ready() -> void:
	_find_scene_nodes()
	ui = BargainScene.instantiate()
	add_child(ui)
	ui.visible = false
	ui.offer_submitted.connect(_on_offer)
	ui.accept_pressed.connect(_on_accept)
	ui.send_away_pressed.connect(_on_send_away)
	ui.next_pressed.connect(_on_next)
	ui.price_submitted.connect(_on_price_submitted)
	ui.inspection_requested.connect(_on_inspection_requested)
	placement = PlacementScript.new()
	get_parent().add_child.call_deferred(placement)
	placement.player = player
	game_ui = GameUIScene.instantiate()
	add_child(game_ui)
	game_ui.player = player
	game_ui.manager = self
	game_ui.sleep_requested.connect(request_sleep)
	game_ui.wait_requested.connect(wait_until_next_period)
	placement.notice.connect(game_ui.show_notice)
	night = NightScript.new()
	night.thief_model = thief_model
	night.demon_model = demon_model
	night.police_model = police_model
	add_child(night)
	night.setup(player, door_spot, exit_spot)
	night.notice.connect(game_ui.show_notice)
	if night.has_signal("door_requested"):
		night.door_requested.connect(func(open: bool): _open_door() if open else _close_door())
	GameState.time_changed.connect(_on_time_changed)
	GameState.day_started.connect(_on_day_started)
	GameState.game_over.connect(_on_game_over)
	ui.panel_visibility_changed.connect(_on_bargain_panel_visibility_changed)
	GameState.hallucination_started.connect(_on_hallucination)
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx and sfx.has_method("set_radio_songs"): sfx.set_radio_songs(radio_songs)
	if sfx and sfx.has_signal("radio_track_changed"):
		sfx.radio_track_changed.connect(func(title: String):
			if GameSettings.radio_popup and _visitor_index > 0: game_ui.show_notice("Radio: " + title, 2.0))
	await get_tree().physics_frame
	placement.restore_stock(_stock_position())
	placement.restore_furniture(Vector3(-2, 0.1, 2))
	cleaning = CleaningScene.instantiate()
	cleaning.player = player
	cleaning.placement = placement
	cleaning.game_ui = game_ui
	cleaning.day_manager = self
	get_parent().add_child(cleaning)
	_build_stations()
	if crowd_enabled:
		navigation=NavigationScript.new()
		get_parent().add_child(navigation)
		flow=FlowScene.instantiate()
		flow.manager=self
		get_parent().add_child(flow)
	GameState.start_clock()
	GameState.changed.emit()
	start_day()

func _find_scene_nodes() -> void:
	var main: Node = get_parent()
	player = main.get_node_or_null("Player") as Node3D
	var marks: Node = main.get_node_or_null("Marks")
	if marks:
		door_spot = marks.get_node_or_null("Door") as Node3D
		exit_spot = marks.get_node_or_null("ExitSpot") as Node3D
		cashier_spot = marks.get_node_or_null("CashierSpot") as Node3D
		show_spot = marks.get_node_or_null("ShowSpot") as Node3D
		relic_spot = marks.get_node_or_null("RelicSpot") as Node3D
	bargain_cam = main.get_node_or_null("BargainCam") as Camera3D
	if bargain_cam: _bargain_camera_transform = bargain_cam.transform
	door_anim = _find_anim_player(main, DOOR_ANIM)
	for light in main.find_children("*", "OmniLight3D", true, false):
		_lights.append(light as OmniLight3D)
		_light_energy.append((light as OmniLight3D).light_energy)

func _find_anim_player(node: Node, animation_name: String) -> AnimationPlayer:
	if node is AnimationPlayer and (node as AnimationPlayer).has_animation(animation_name):
		return node as AnimationPlayer
	for child in node.get_children():
		var result: AnimationPlayer = _find_anim_player(child, animation_name)
		if result: return result
	return null

func start_day() -> void:
	_epoch += 1
	_closed = false
	_waiting = false
	_hallucinating = false
	newspaper_delivered = false
	_newspaper_time = 720 if GameState.day == 1 else randi_range(630, 660)
	queue = DayQueue.build(6, GameState.day)
	_seller_index = 0
	_visitor_index = 0
	phase = Phase.FREE
	if flow: flow.start_day()
	ui.visible = false
	ui.hide_dialogue()
	_restore_player_cam()
	_set_player_controls(true)
	_on_time_changed(GameState.time_minutes / 60, GameState.time_minutes % 60)
	game_ui.show_notice("Buy your first artifact at the counter." if GameState.day == 1 and GameState.inventory.is_empty() else "Day %d" % GameState.day, 4.0)
	_next_customer()

func _on_day_started(_day: int) -> void:
	start_day()

func _next_customer() -> void:
	if _closed or GameState.failed:
		phase = Phase.CLOSED
		return
	var token: int = _epoch
	phase = Phase.ARRIVING
	if not flow:
		var delay: float = first_customer_delay if _visitor_index == 0 else randf_range(min_arrival_delay, max_arrival_delay)
		var arrival_timer := get_tree().create_timer(delay, false)
		_arrival_timer = arrival_timer
		await arrival_timer.timeout
		if _arrival_timer == arrival_timer: _arrival_timer = null
	# Waiting can skip time during this quiet gap without spawning a visitor mid-skip.
	while _waiting and token == _epoch and not _closed and not GameState.failed:
		await get_tree().process_frame
	if token != _epoch or _closed or GameState.failed:
		return
	await _customer_enters()
	if token != _epoch or _closed or GameState.failed: return
	if flow and not is_instance_valid(customer):
		_next_customer.call_deferred()
		return
	# Check stock now, since the player may have moved or held it during the gap.
	var stock: Array[ArtifactData] = _displayed_stock()
	var opening_sellers: bool = GameState.day == 1 and _visitor_index < 2
	_buyer = not opening_sellers and DayQueue.buyers_allowed(GameState.day) and not stock.is_empty() and randf() < 0.5
	# Teach one completed resale before further random buying drains the wallet.
	if GameState.day == 1 and _visitor_index == 2 and not stock.is_empty() and not _has_made_sale(): _buyer = true
	if _buyer:
		current = BuyerHaggle.new(stock.pick_random())
	else:
		current = queue[_seller_index] if _seller_index < queue.size() else DayQueue.walk_in(GameState.day)
		_seller_index += 1
		if GameState.day > 1 and newspaper_delivered and _gold_artifact(current.artifact) and randf() < 0.65:
			current.artifact.status = "stolen"
	if not _buyer and current.artifact.tool_id == "broom":
		if cleaning and cleaning.broom_model and not cleaning.broom_model.resource_path.is_empty():
			current.artifact.model_path = cleaning.broom_model.resource_path
		GameState.cleaning.broom_available = true
		GameState.changed.emit()
	current.apply_cleanliness(GameState.cleaning.offer_bonus())
	_visitor_index += 1
	current.anger_changed.connect(_on_haggle_anger)
	phase = Phase.WAITING
	customer_arrived.emit(current)
	if customer:
		customer.interacted.connect(_start_bargain, CONNECT_ONE_SHOT)
		customer.set_interactable(true)
	else:
		_start_bargain()

func _has_made_sale() -> bool:
	for transaction in GameState.transactions:
		if transaction.get("type", "") == "sale": return true
	return false

func _displayed_stock() -> Array[ArtifactData]:
	var displayed: Array[ArtifactData] = []
	for artifact: ArtifactData in GameState.available_stock():
		if artifact.placement.get("placed", false) and placement.items.has(artifact.id):
			displayed.append(artifact)
	return displayed

func _start_bargain() -> void:
	if phase != Phase.WAITING or _closed:
		return
	var token: int = _epoch
	var interacting_customer: Node3D = customer
	phase = Phase.INTRO
	GameState.resume_time(&"bargain")
	_set_player_controls(false)
	ui.visible = true
	if customer:
		customer.set_interactable(false)
		if customer.has_method("set_at_counter"): customer.set_at_counter(true)
	if bargain_cam:
		bargain_cam.transform = _bargain_camera_transform
		if customer and float(customer.get_meta("character_height", 1.75)) < 1.2:
			bargain_cam.global_position.y = 1.4
			bargain_cam.look_at(customer.global_position + Vector3.UP * 0.15)
		bargain_cam.make_current()
	var look_position: Vector3 = bargain_cam.global_position if bargain_cam else player.global_position
	if customer:
		customer.face_toward(look_position)
		customer.play("talk")
	await ui.say("I'd like to buy one of your artifacts." if _buyer else String(Lines.GREET.pick_random()))
	if not _intro_active(token, interacting_customer): return
	if interacting_customer and show_spot and float(interacting_customer.get_meta("character_height", 1.75)) >= 1.2:
		await interacting_customer.walk_to(show_spot.global_position)
		if not _intro_active(token, interacting_customer): return
		interacting_customer.face_toward(look_position)
		interacting_customer.play("show_relic")
	_spawn_relic()
	var artifact: ArtifactData = current.artifact
	await ui.say("I'm interested in your %s. Let's agree on a price." % artifact.display_name if _buyer else "%s (%s). %s" % [artifact.display_name, artifact.rarity, String(Lines.SHOW.pick_random())])
	if not _intro_active(token, interacting_customer): return
	if interacting_customer: interacting_customer.play("idle")
	_open_bargain_ui()

func _intro_active(token: int, interacting_customer) -> bool:
	if token != _epoch or _closed or GameState.failed or phase != Phase.INTRO:
		return false
	return interacting_customer == null or (is_instance_valid(interacting_customer) and not interacting_customer.is_queued_for_deletion() and interacting_customer == customer)

func _open_bargain_ui() -> void:
	phase = Phase.HAGGLING
	_bargain_inspecting = false
	_set_player_controls(false)
	if bargain_cam: bargain_cam.make_current()
	ui.visible = true
	var artifact: ArtifactData = current.artifact
	if _buyer:
		ui.show_buyer(_visitor_index, 0, money, artifact.sell_price, current.ask, "", artifact.cost)
		ui._slider.max_value=mini(artifact.max_sell_price(),ceili(artifact.sell_price*1.1))
	else:
		ui.show_customer(_visitor_index, 0, money, current.market_price, current.ask, "%s • %s" % [artifact.display_name, artifact.rarity])

func _spawn_relic() -> void:
	_clear_relic()
	var artifact: ArtifactData = current.artifact
	var holder: Node3D = preload("res://scripts/bargain_artifact.gd").new()
	add_child(holder)
	if bargain_cam: holder.setup(artifact, bargain_cam)
	relic_holder = holder
	if _buyer: placement.highlight(artifact.id, true)

func _on_bargain_panel_visibility_changed(hidden: bool) -> void:
	if phase != Phase.HAGGLING or not ui.visible or GameState.failed:
		return
	# Layout resizing re-emits visibility; do not move the inspection target again.
	if hidden == _bargain_inspecting:
		return
	_bargain_inspecting = hidden
	_set_player_controls(false)
	if bargain_cam: bargain_cam.make_current()
	if is_instance_valid(relic_holder):
		relic_holder.set_inspection(hidden)
	game_ui._refresh_hint()

func is_inspecting_artifact() -> bool:
	return _bargain_inspecting and phase == Phase.HAGGLING and ui.visible

func _lock_bargain_view() -> void:
	# Receipts and closing must regain control even if the book was hidden.
	_bargain_inspecting = false
	game_ui._refresh_hint()
	_set_player_controls(false)
	if bargain_cam: bargain_cam.make_current()
	if is_instance_valid(relic_holder): relic_holder.set_inspection(false)

func _clear_relic() -> void:
	if relic_holder and is_instance_valid(relic_holder): relic_holder.queue_free()
	relic_holder = null

func _stock_position() -> Vector3:
	return relic_spot.global_position if relic_spot else Vector3(3.8, 1.2, 0.2)

func _on_offer(price: int) -> void:
	if phase != Phase.HAGGLING or _closed: return
	if _buyer and not _buyer_target_valid():
		game_ui.show_notice("That artifact is no longer on display.")
		_customer_left()
		return
	if not _buyer and not GameState.can_buy(price):
		ui.show_message("You cannot afford that offer.")
		return
	if customer: customer.play("talk")
	_handle(current.make_offer(price))

func _on_inspection_requested(tool: String) -> void:
	if phase != Phase.HAGGLING or current == null or not GameState.owned_items.get(tool, false): return
	if tool not in ["magnifier", "curse_detector"]: return
	var artifact: ArtifactData = current.artifact
	artifact.inspections[tool] = true
	var result: String = "Broken" if artifact.status == "broken" else "No damage found"
	if tool == "magnifier" and artifact.status == "stolen" and newspaper_delivered:
		artifact.inspections["stolen_found"] = true
		result = "Matches the newspaper's stolen artifact report"
	if tool == "curse_detector": result = "Curse detected" if artifact.status == "curse" else "No curse detected"
	ui.show_message(result)
	GameState.changed.emit()
	_play("click")

func _on_accept() -> void:
	if phase != Phase.HAGGLING or _closed: return
	if _buyer and current and not _buyer_target_valid():
		game_ui.show_notice("That artifact is no longer on display.")
		_customer_left()
		return
	if not _buyer and not GameState.can_buy(current.ask):
		ui.show_message("You cannot afford that artifact.")
		return
	_handle(current.accept_ask())

func _on_send_away() -> void:
	if phase == Phase.HAGGLING:
		_handle(current.send_away())

func _handle(result: Dictionary) -> void:
	match String(result.get("result", "")):
		"deal": _finish_deal()
		"counter", "firm":
			ui.update_state(current.ask, current.get_anger(), "How about %d G?" % current.ask)
			if customer: customer.play_for("talk", 1.2, "idle")
		"left": _customer_left()

func _finish_deal() -> void:
	if phase != Phase.HAGGLING: return
	_lock_bargain_view()
	var artifact: ArtifactData = current.artifact
	var price: int = current.deal_price
	phase = Phase.RECEIPT
	if _buyer:
		var profit: int = price - artifact.cost
		if not GameState.sell(artifact.id, price):
			game_ui.show_notice("That artifact is no longer available.")
			_customer_left()
			return
		ui.show_sale(price, profit, artifact.display_name)
	else:
		if not GameState.purchase(artifact, price):
			game_ui.show_notice("The purchase could not be completed.")
			_customer_left()
			return
		if artifact.tool_id.is_empty():
			placement.spawn_artifact(artifact, _stock_position())
			ui.show_price_editor(artifact)
		else:
			_on_next.call_deferred()
	if customer:
		customer.play_once("agree", "idle")
		customer.show_happy(happy_texture)
	deal_made.emit(current)
	_play("coin")

func _on_price_submitted(price: int) -> void:
	if phase != Phase.RECEIPT or _buyer or current == null: return
	var artifact: ArtifactData = current.artifact
	GameState.set_sell_price(artifact.id, price)
	if GameState.day == 1 and GameState.inventory.size() == 1 and not _has_made_sale():
		game_ui.show_notice("Your artifact is on display. Buyers can now visit.", 3.0)
	ui.hide_price_editor()
	_on_next()

func _on_next() -> void:
	if phase == Phase.SUMMARY:
		if _sleep_preparing: return
		_sleep_preparing=true
		await AssetWarmup.prepare(GameState.day+1)
		if not is_inside_tree(): return
		_sleep_preparing=false
		placement.finish_holding_before_sleep()
		if cleaning: cleaning.put_tool_away()
		if GameState.sleep():
			GameState.resume_time(&"summary")
			ui.visible = false
			_set_player_controls(true)
		elif not GameState.failed:
			ui.show_message("The save failed. Please try sleeping again.")
		return
	if phase != Phase.RECEIPT: return
	var token: int = _epoch
	phase = Phase.BUSY
	ui.visible = false
	_end_bargain_view()
	await _customer_exits()
	if token == _epoch: _next_customer()

func _customer_left() -> void:
	_lock_bargain_view()
	var token: int = _epoch
	phase = Phase.BUSY
	customer_left.emit(current)
	ui.set_controls_enabled(false)
	if customer: customer.play("angry")
	await get_tree().create_timer(0.8, false).timeout
	if token != _epoch: return
	ui.visible = false
	_end_bargain_view()
	await _customer_exits()
	if token == _epoch: _next_customer()

func _buyer_target_valid() -> bool:
	var artifact: ArtifactData = current.artifact
	return GameState.get_artifact(artifact.id) == artifact and artifact.sell_price > 0 and artifact.placement.get("placed", false) and not artifact.placement.get("held", false) and placement.items.has(artifact.id)

func _end_bargain_view() -> void:
	_bargain_inspecting = false
	game_ui._refresh_hint()
	if current and _buyer: placement.highlight(current.artifact.id, false)
	_clear_relic()
	ui.hide_dialogue()
	_restore_player_cam()
	if bargain_cam: bargain_cam.transform = _bargain_camera_transform
	GameState.resume_time(&"bargain")
	_set_player_controls(not GameState.failed)

func _customer_enters() -> void:
	if _closed or GameState.failed or not door_spot or not exit_spot or not cashier_spot: return
	if flow:
		var token: int = _epoch
		var entering: Node3D = await flow.take_next()
		if token == _epoch and not _closed: customer = entering
		return
	var token: int = _epoch
	var scene: PackedScene = customer_scenes.pick_random() if not customer_scenes.is_empty() else load("res://npcs_1.tscn") as PackedScene
	var entering: Node3D = scene.instantiate() as Node3D
	customer = entering
	entering.set_meta("shop_serving",true)
	add_child(entering)
	Appearance.apply_to(entering, randi_range(0, Appearance.CLOTHING_COLORS.size() - 1))
	entering.global_position = exit_spot.global_position
	_open_door()
	await entering.walk_to(door_spot.global_position)
	if not _arrival_allowed(entering, token):
		await _finish_interrupted_arrival(entering)
		return
	# Buyers take a brief look around before joining the same counter queue.
	if _buyer:
		var browse := cashier_spot.global_position + Vector3(-1.1, 0, 1.5)
		await entering.walk_to(browse)
		if not _arrival_allowed(entering, token):
			await _finish_interrupted_arrival(entering)
			return
		entering.play("idle")
		await get_tree().create_timer(1.0, false).timeout
		if not _arrival_allowed(entering, token):
			await _finish_interrupted_arrival(entering)
			return
	await entering.walk_to(cashier_spot.global_position)
	if not _arrival_allowed(entering, token):
		await _finish_interrupted_arrival(entering)
		return
	_close_door()
	entering.face_toward(player.global_position if player else cashier_spot.global_position)
	entering.play("idle")

func _arrival_allowed(entering: Node3D, token: int) -> bool:
	return token == _epoch and not _closed and not GameState.failed and is_instance_valid(entering) and not entering.is_queued_for_deletion() and customer == entering

func _finish_interrupted_arrival(entering: Node3D) -> void:
	if not is_instance_valid(entering) or entering.is_queued_for_deletion(): return
	if customer == entering:
		await _customer_exits()
	else:
		entering.queue_free()

func _customer_exits() -> void:
	if not customer or not is_instance_valid(customer): return
	var departing: Node3D = customer
	customer = null
	if departing.has_method("set_at_counter"): departing.set_at_counter(false)
	departing.set_interactable(false)
	if flow:
		await flow.depart(departing)
		return
	_open_door()
	if door_spot: await departing.walk_to(door_spot.global_position)
	if exit_spot: await departing.walk_to(exit_spot.global_position)
	_close_door()
	departing.queue_free()

func _open_door() -> void:
	for controller in get_tree().get_nodes_in_group("automatic_doors"):
		if controller.front: controller.request_open("day_manager"); return
	if door_anim and door_anim.has_animation(DOOR_ANIM):
		door_anim.play(DOOR_ANIM)
		_play("door")

func _close_door() -> void:
	for controller in get_tree().get_nodes_in_group("automatic_doors"):
		if controller.front: controller.release("day_manager"); return
	if door_anim and door_anim.has_animation(DOOR_ANIM): door_anim.play_backwards(DOOR_ANIM)

func _restore_player_cam() -> void:
	var camera: Camera3D = player.get("camera") as Camera3D if player else null
	if camera: camera.make_current()

func _set_player_controls(enabled: bool) -> void:
	if player and player.has_method("set_controls_enabled"): player.set_controls_enabled(enabled)

func _on_haggle_anger(anger: float) -> void:
	customer_anger_changed.emit(anger)
	if customer: customer.set_anger(anger)

func _on_time_changed(hour: int, minute: int) -> void:
	var time: int = hour * 60 + minute
	if not newspaper_delivered and time >= _newspaper_time:
		newspaper_delivered = true
		game_ui.show_notice("Newspaper: stolen artifacts reported. Inspect suspicious items with the magnifier.", 5.0)
	for index in _lights.size():
		_lights[index].light_energy = _light_energy[index] * (0.72 if time >= 1140 else 1.0)
	if time >= 1230 and not _closed:
		_closed = true
		if flow: flow.close_shop()
		game_ui.show_notice("The shop is closed. Clean up and watch for trouble tonight.", 7.0)
		if phase in [Phase.FREE, Phase.ARRIVING, Phase.WAITING]:
			var arrival_in_progress: bool = phase == Phase.ARRIVING
			phase = Phase.CLOSED
			_epoch += 1
			# Arrival finishes its current leg, then leaves; do not run competing walk tweens.
			if customer and not arrival_in_progress: _customer_exits()
			_close_door()
		elif phase in [Phase.HAGGLING, Phase.INTRO]:
			_epoch += 1
			ui.hide_dialogue()
			_customer_left()
		elif phase == Phase.RECEIPT:
			# Finish the paid transaction before intruders arrive; do not strand
			# movement in a price/receipt screen through the entire evening.
			if not _buyer:
				ui._price_spin.apply()
				_on_price_submitted(int(ui._price_spin.value))
			else: _on_next()
	if time == 1380:
		game_ui.show_notice("Bedtime",3.0)

func request_sleep() -> void:
	if not GameState.can_sleep():
		game_ui.show_notice("Sleep is available between 23:00 and midnight.")
		return
	if phase not in [Phase.FREE, Phase.CLOSED]:
		game_ui.show_notice("Finish the current interaction first.")
		return
	placement.finish_holding_before_sleep()
	phase = Phase.SUMMARY
	GameState.pause_time(&"summary")
	_set_player_controls(false)
	ui.visible = true
	ui.show_summary(GameState.day, GameState.day_profit, GameState.money)

func can_wait() -> bool:
	var between_customers: bool = phase == Phase.ARRIVING and customer == null
	return not _waiting and (phase in [Phase.FREE, Phase.CLOSED] or between_customers) and not GameState.failed and GameState.time_minutes < 1380 and not night.has_active_event() and (cleaning == null or not cleaning.is_cleaning())

func wait_until_next_period() -> void:
	if not can_wait():
		game_ui.show_notice("Finish your interaction or deal with the intruder before waiting.")
		return
	_waiting = true
	var token: int = _epoch
	var wait_for_customer: bool = GameState.time_minutes < 1230
	var arrival_timer: SceneTreeTimer = _arrival_timer
	var target: int = 1380
	if wait_for_customer:
		if flow:
			var minutes: int = maxi(0, ceili(flow.spawn_in)) if flow.waiting_visitors.is_empty() and flow.visitors.is_empty() else 0
			flow.skip_arrival_wait()
			target = mini(1230, GameState.time_minutes + minutes)
		if phase == Phase.FREE and arrival_timer == null:
			_next_customer()
			arrival_timer = _arrival_timer
		if not flow:
			var minutes: int = maxi(1, ceili(arrival_timer.time_left)) if arrival_timer else 1
			target = mini(1230, GameState.time_minutes + minutes)
	else:
		for boundary in [1245, 1260, 1380]:
			if GameState.time_minutes < boundary:
				target = boundary
				break
	while GameState.time_minutes < target and token == _epoch and not GameState.failed and not night.has_active_event():
		if GameState.is_time_paused(): break
		GameState._process(1.0)
		if GameState.time_minutes % 8 == 0: await get_tree().process_frame
	_waiting = false
	if night.has_active_event(): return
	if wait_for_customer and token == _epoch and not _closed and (flow or (arrival_timer == _arrival_timer and arrival_timer)):
		# Advance the quiet arrival delay without skipping the trading day or
		# bypassing the customer's normal entrance and interaction.
		if arrival_timer: arrival_timer.time_left = 0.0
		game_ui.show_notice("A customer is on the way.")
	else:
		game_ui.show_notice("Time passed. Check your stock and surroundings.")

func _build_stations() -> void:
	var bed_mesh := get_parent().find_child("Mattress",true,false) as MeshInstance3D
	if bed_mesh:
		var b: AABB=bed_mesh.global_transform*bed_mesh.get_aabb()
		var rest: Area3D=BedScript.new()
		rest.name="BedSleep"
		rest.manager=self
		rest.collision_layer=1
		rest.collision_mask=0
		get_parent().add_child(rest)
		rest.global_position=b.get_center()
		var collision:=CollisionShape3D.new()
		var box:=BoxShape3D.new()
		box.size=b.size+Vector3.ONE*0.08
		collision.shape=box
		rest.add_child(collision)
	var stock_book: StaticBody3D = StationScript.new()
	stock_book.name = "ShopManagementBook"
	get_parent().add_child(stock_book)
	var book_position := Vector3(3.1, 0.9, 0.1)
	var counter := get_parent().find_child("ATFCounter", true, false) as MeshInstance3D
	if counter:
		var biggest := 0.0
		for patch: Dictionary in counter.get_meta("placement_patches", []):
			var rect: Rect2 = patch.rect
			if float(patch.y) < 0.5 or float(patch.y) > 1.5 or rect.get_area() <= biggest: continue
			biggest = rect.get_area()
			var point := Vector2(clampf(3.1, rect.position.x + 0.35, rect.end.x - 0.35), rect.get_center().y)
			book_position = Vector3(point.x, patch.y + 0.015, point.y)
	stock_book.setup_book(book_position, load("res://assets/Relics/Book.glb"))
	stock_book.activated.connect(func(): game_ui.open_panel("stock"))
	var internet := preload("res://scripts/internet_station.gd").new()
	internet.name = "InternetShop"
	get_parent().add_child(internet)
	var internet_position := Vector3(7.2,1.35,-1.6)
	for node in get_parent().find_children("*", "Node3D", true, false):
		if String(node.name).to_lower().replace("_", "").replace(" ", "") == "internetspot":
			internet_position = node.global_position; break
	internet.setup(internet_position)
	internet.activated.connect(func(): game_ui.open_panel("shop"))

func place_new_furniture(record: Dictionary) -> void:
	var position: Vector3 = player.global_position - player.global_basis.z * 1.5 if player else Vector3(-2, 0, 2)
	position.y = 0.1
	var item: Node3D = placement.spawn_furniture(record, position)
	placement.pick_up(item)
	game_ui.show_notice("%s: place · %s: rotate · Q: cancel" % [GameSettings.key_name("interact"), GameSettings.key_name("rotate_item")])

func _on_hallucination() -> void:
	_hallucinating = true
	_hallucination_seconds = 0.0
	game_ui.show_notice("You stayed awake too long. The shop feels unreal…", 60.0)

func _process(delta: float) -> void:
	if not _hallucinating or GameState.failed: return
	_hallucination_seconds += delta
	for index in _lights.size():
		_lights[index].light_energy = _light_energy[index] * (0.5 + 0.35 * sin(_hallucination_seconds * 3.0 + index))
	if player:
		var camera: Camera3D = player.get("camera") as Camera3D
		if camera: camera.rotation.z = sin(_hallucination_seconds * 0.7) * 0.035

func _on_game_over(reason: String) -> void:
	_epoch += 1
	_bargain_inspecting = false
	ui.hide_dialogue()
	if flow: flow.close_shop()
	_set_player_controls(false)
	ui.visible = false
	game_ui.show_game_over(reason)

func _gold_artifact(artifact: ArtifactData) -> bool:
	var title: String = artifact.display_name.to_lower()
	return "gold" in title or "crown" in title or "goblet" in title

func _play(cue: String) -> void:
	var audio: Node = get_node_or_null("/root/Sfx")
	if audio: audio.play(cue)

func save_game() -> bool:
	return GameState.save_game()

func load_game() -> bool:
	return GameState.load_game()

func _exit_tree() -> void:
	_closed=true
	_epoch+=1
	if _arrival_timer: _arrival_timer.time_left=0
	GameState.stop_clock()
	GameState.resume_time(&"bargain")
	GameState.resume_time(&"summary")
	GameState.resume_time(&"stock_book")
