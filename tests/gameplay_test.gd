extends SceneTree
## Integration checks use an isolated save path and real runtime UI scripts.

class PlayerFixture extends Node3D:
	var controls_enabled: bool = true
	func set_controls_enabled(enabled: bool) -> void:
		controls_enabled = enabled
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE

class ManagerFixture extends Node:
	var newspaper_delivered: bool = false
	var received_furniture: Dictionary = {}
	func can_wait() -> bool:
		return false
	func place_new_furniture(record: Dictionary) -> void:
		received_furniture = record

class CustomerFixture extends Node3D:
	signal interacted
	var can_interact: bool = false
	func walk_to(target: Vector3) -> void:
		await get_tree().create_timer(0.02, false).timeout
		if is_inside_tree(): global_position = target
	func play(_animation: String) -> void: pass
	func face_toward(_position: Vector3) -> void: pass
	func set_interactable(enabled: bool) -> void: can_interact = enabled
	func play_once(_animation: String, _next: String = "idle") -> void: pass
	func play_for(_animation: String, _seconds: float, _next: String = "idle") -> void: pass
	func show_happy(_texture: Texture2D = null) -> void: pass
	func set_anger(_anger: float) -> void: pass

var checks: int = 0
var failures: int = 0
var test_save: String
var original_save: String
var state: Node


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	state = root.get_node("GameState")
	original_save = state.save_path
	test_save = "user://gameplay_test_%d.json" % Time.get_ticks_usec()
	state.save_path = test_save
	await _test_game_ui()
	await _test_actual_main()
	await _test_continuous_customers()
	state.stop_clock()
	state.save_path = original_save
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save))
	print("GAMEPLAY TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_game_ui() -> void:
	state.new_game()
	state.start_clock()
	var fixture := Node.new()
	root.add_child(fixture)
	var player := PlayerFixture.new()
	var manager := ManagerFixture.new()
	fixture.add_child(player)
	fixture.add_child(manager)
	var ui: CanvasLayer = load("res://ui/game_ui.tscn").instantiate()
	fixture.add_child(ui)
	ui.player = player
	ui.manager = manager
	ui.open_panel("stock")
	_check(ui._open and ui.modal.visible and not player.controls_enabled, "stock book frees cursor and disables player")
	_check(state.is_time_paused(), "stock book pauses game time")
	var time_before: int = state.time_minutes
	state._process(20.0)
	_check(state.time_minutes == time_before, "stock book cannot consume shop minutes")
	ui.open_panel("shop")
	_check(ui._page == "shop" and not player.controls_enabled, "switching modal pages keeps player disabled")
	ui.close_panel()
	_check(not ui._open and player.controls_enabled and not state.is_time_paused(), "closing stock book restores controls and its own time pause")
	state._process(1.0)
	_check(state.time_minutes == time_before + 1, "time resumes after stock book closes")
	player.set_controls_enabled(false)
	ui.open_panel("stock")
	_check(not ui._open, "stock book cannot open over an active bargain")
	player.set_controls_enabled(true)
	ui.open_panel("shop")
	state.money = 1000
	state.set_item_owned("clock", false) # Buying a replacement after loss.
	var clock := {"id": "clock", "name": "Clock", "price": 350}
	ui._buy_equipment(clock)
	ui._buy_equipment(clock)
	_check(state.money == 650 and state.clock_owned and state.owned_items.has("clock"), "duplicate equipment accepts spend once and synchronize clock")
	_check(state.day_profit == 0, "equipment spending does not realize trading profit")
	await process_frame
	_check(not FileAccess.file_exists(test_save), "stock and equipment UI does not save mid-day")
	var furniture := {"id": "furn_shelf", "name": "Display shelf", "price": 200, "grid": [3, 1]}
	ui._buy_furniture(furniture)
	_check(state.money == 450 and state.furniture.size() == 1 and state.inventory.is_empty(), "shop furniture purchase debits wallet and stays separate from artifact stock")
	_check(not manager.received_furniture.is_empty() and manager.received_furniture == state.get_furniture(String(manager.received_furniture.get("id", ""))), "furniture placement receives authoritative owned record")
	_check(not ui._open and player.controls_enabled, "buy and place closes shop book and restores player")
	var book: CanvasLayer = load("res://ui/settings_menu.tscn").instantiate()
	fixture.add_child(book)
	ui.open_panel("stock")
	book.show_options(true)
	_check(paused and book._is_open, "settings book pauses the actual scene tree")
	book.close_options()
	_check(not paused and not player.controls_enabled and state.is_time_paused(), "closing settings restores previously open stock modal")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	book._input(escape)
	_check(not ui._open and player.controls_enabled and not book._is_open, "Escape closes stock modal before opening pause book")
	state.game_over.connect(ui.show_game_over)
	player.set_controls_enabled(false)
	state.end_game("Integration test closure")
	await process_frame
	await process_frame
	var buttons: Array[Node] = ui.content.find_children("*", "Button", true, false)
	var main_menu_present: bool = false
	for button in buttons:
		if (button as Button).text == "Main menu":
			main_menu_present = true
	_check(ui._page == "game_over" and main_menu_present, "game-over controls survive changed signals and deferred UI refresh")
	_check(not player.controls_enabled and state.failed, "game over keeps player controls disabled")
	_check(not FileAccess.file_exists(test_save), "game-over UI preserves prior checkpoint without new save")
	fixture.queue_free()
	await process_frame
	await process_frame


func _main_fixture() -> Node3D:
	var main := load("res://assets/Scene/main.tscn").instantiate() as Node3D
	var manager: Node = main.get_node("Day_manager")
	manager.first_customer_delay = 60000.0
	manager.crowd_enabled = false # Queue/browsing integration is covered by polish_test.
	manager.min_arrival_delay = 60000.0
	manager.max_arrival_delay = 60000.0
	var packed := PackedScene.new()
	var dummy := CustomerFixture.new()
	packed.pack(dummy)
	dummy.free()
	manager.customer_scenes = [packed] as Array[PackedScene]
	root.add_child(main)
	current_scene = main
	await physics_frame
	await process_frame
	await physics_frame
	return main


func _test_actual_main() -> void:
	state.new_game()
	var main: Node3D = await _main_fixture()
	var manager: Node = main.get_node("Day_manager")
	_check(manager.queue.size() == 3 and not manager._buyer, "actual main prepares three affordable opening sellers before later walk-ins")
	_check(manager.player != null and manager.ui != null and manager.placement != null, "actual main connects player, bargaining UI and placement")
	# Finish a seller through the same handlers used by actual bargain buttons.
	manager._epoch += 1
	manager.customer = null
	manager.current = manager.queue[0]
	manager._buyer = false
	manager._closed = false
	state.pause_time(&"bargain")
	manager._set_player_controls(false)
	manager._open_bargain_ui()
	var bought: ArtifactData = manager.current.artifact
	var purchase_price: int = manager.current.ask
	manager.ui.inspection_requested.emit("magnifier")
	_check(bought.inspections.is_empty(), "unowned tool cannot inspect a bargaining artifact")
	state.owned_items.magnifier = true
	manager.ui.inspection_requested.emit("magnifier")
	_check(bought.inspections.get("magnifier", false) and state.money == 200, "owned tool inspection reveals findings without transferring money")
	manager._on_accept()
	manager._on_accept()
	_check(state.money == 200 - purchase_price and state.inventory.size() == 1 and bought.cost == purchase_price, "real seller Accept charges once and records agreed cost")
	_check(ArtifactData.from_dict(bought.to_dict()).inspections.get("magnifier", false), "purchased artifact retains its pre-purchase inspection in save data")
	_check(state.day_profit == 0 and manager.phase == manager.Phase.RECEIPT, "real purchase enters receipt without realized profit")
	_check(manager.placement.items.has(bought.id) and bool(bought.placement.get("placed", false)), "real purchase creates a placed world artifact")
	manager._on_price_submitted(999999)
	_check(bought.sell_price == bought.max_sell_price() and manager._displayed_stock().has(bought), "real listing handler clamps rarity cap and exposes displayed stock")
	_check(not FileAccess.file_exists(test_save), "real purchase/listing do not write checkpoint")
	manager._end_bargain_view()
	manager._buyer = true
	manager.current = BuyerHaggle.new(bought)
	state.pause_time(&"bargain")
	manager._open_bargain_ui()
	var sale_price: int = manager.current.ask
	manager._on_accept()
	manager._on_accept()
	_check(state.day == 1 and state.money == 200 - purchase_price + sale_price and state.day_profit == sale_price - purchase_price, "real day-one buyer Accept credits one sale and original-cost profit")
	_check(state.inventory.is_empty() and not manager.placement.items.has(bought.id), "sold item leaves authoritative inventory and placement registry")
	await process_frame
	_check(not FileAccess.file_exists(test_save), "real sale does not write checkpoint")
	manager._end_bargain_view()
	# Keep another artifact to verify stock/position restoration after an actual sleep.
	var kept := ArtifactData.create("res://assets/Relics/Goldcoin.glb", "Checkpoint Coin", "Common")
	_check(state.purchase(kept, 20), "checkpoint stock fixture purchased")
	state.set_sell_price(kept.id, 35)
	manager.placement.spawn_artifact(kept, manager._stock_position())
	manager.phase = manager.Phase.FREE
	manager._closed = true
	state.time_minutes = 1380
	manager.request_sleep()
	_check(manager.phase == manager.Phase.SUMMARY and state.day == 1 and not FileAccess.file_exists(test_save), "real sleep request shows profit summary before saving or advancing")
	await manager.ui.count_finished
	await process_frame
	manager._on_next()
	manager._on_next()
	var sleep_deadline := Time.get_ticks_msec()+15000
	while state.day==1 and Time.get_ticks_msec()<sleep_deadline: await process_frame
	_check(state.day == 2 and state.time_minutes == 630 and FileAccess.file_exists(test_save), "summary Next saves and advances once to next day at10:30")
	_check(manager.queue.size() == 6, "later actual days prepare six opening sellers before later walk-ins")
	_check(state.last_day_profit == sale_price - purchase_price and state.day_profit == 0, "actual next-day transition preserves completed-day realized profit")
	var kept_id: String = kept.id
	var saved_position: Array = kept.placement["position"].duplicate()
	main.queue_free()
	await process_frame
	await process_frame


	_check(state.load_game(), "sleep checkpoint loads through authoritative state")
	main = await _main_fixture()
	manager = main.get_node("Day_manager")
	var restored: ArtifactData = state.get_artifact(kept_id)
	_check(restored != null and restored.cost == 20 and restored.sell_price == 35 and manager.placement.items.has(kept_id), "actual scene restart restores owned model, cost and listing")
	var restored_node: Node3D = manager.placement.items[kept_id]
	_check(restored_node.global_position.is_equal_approx(Vector3(float(saved_position[0]), float(saved_position[1]), float(saved_position[2]))), "actual scene restart restores world placement")
	# Close while an arrival walk is suspended; no null customer access or late deal.
	manager._epoch += 1
	manager.phase = manager.Phase.ARRIVING
	manager._closed = false
	manager._buyer = false
	manager.current = manager.queue[0]
	manager._customer_enters()
	manager._on_time_changed(20, 30)
	await create_timer(0.15, false).timeout
	_check(manager._closed and manager.phase == manager.Phase.CLOSED and manager.customer == null, "20:30 safely cancels an in-flight arrival and clears customer")
	var wallet_before: int = state.money
	manager.phase = manager.Phase.HAGGLING
	manager.current = manager.queue[1]
	manager._on_accept()
	_check(state.money == wallet_before and not manager.current.is_over, "late Accept cannot buy after forced close")
	manager._closed = false
	manager.phase = manager.Phase.INTRO
	state.pause_time(&"bargain")
	manager._set_player_controls(false)
	manager._on_time_changed(20, 30)
	await create_timer(0.9, false).timeout
	_check(manager.phase == manager.Phase.CLOSED and manager.player.controls_enabled and not state.is_time_paused(), "forced close during intro cleans interaction and releases bargain pause")
	main.queue_free()
	await process_frame
	await process_frame


func _wait_for_customer(manager: Node, expected: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if manager.phase == manager.Phase.WAITING and manager._visitor_index == expected:
			return true
		await process_frame
	return false


func _test_continuous_customers() -> void:
	seed(20261011)
	for day_number in [1, 2]:
		state.new_game()
		state.day = day_number
		var main: Node3D = await _main_fixture()
		var manager: Node = main.get_node("Day_manager")
		state.stop_clock() # Exercise many arrivals without reaching closing during the test.
		manager._epoch += 1 # Cancel the fixture's deliberately long first-arrival timer.
		manager.first_customer_delay = 0.001
		manager.min_arrival_delay = 0.001
		manager.max_arrival_delay = 0.001
		var variants: Array[PackedScene] = []
		for variant_name in ["WalkInA", "WalkInB"]:
			var dummy := CustomerFixture.new()
			dummy.name = variant_name
			var packed := PackedScene.new()
			packed.pack(dummy)
			dummy.free()
			variants.append(packed)
		manager.customer_scenes = variants
		var displayed: ArtifactData
		if day_number == 2:
			displayed = ArtifactData.create("res://assets/Relics/Goldcoin.glb", "Displayed Coin")
			state.purchase(displayed, 10)
			state.set_sell_price(displayed.id, 35)
			manager.placement.spawn_artifact(displayed, manager._stock_position())
		var seller_ids: Dictionary = {}
		var model_names: Dictionary = {}
		var buyers: int = 0
		var sellers: int = 0
		var uncommon_offers: int = 0
		manager._next_customer()
		var visitor_count: int = 18
		for visitor in range(1, visitor_count + 1):
			var arrived: bool = await _wait_for_customer(manager, visitor)
			_check(arrived, "day %d visitor %d arrives, including past the old cap" % [day_number, visitor])
			if not arrived:
				break
			_check(manager.customer != null and manager.customer.can_interact, "walk-in waits for player interaction")
			model_names[manager.customer.name] = true
			if manager._buyer:
				buyers += 1
				_check(manager.current.artifact == displayed, "buyer chooses only currently displayed stock, including on day one")
			else:
				sellers += 1
				_check(not seller_ids.has(manager.current.artifact.id), "each seller has a fresh artifact identity")
				seller_ids[manager.current.artifact.id] = true
				if day_number == 1:
					uncommon_offers += int(manager.current.artifact.rarity == "Uncommon")
					_check(manager.current.artifact.rarity in ["Common", "Uncommon"], "day one seller supply excludes higher rarities")
			# Reject via the actual bargain handler; its exit schedules the next arrival.
			state.pause_time(&"bargain")
			manager._open_bargain_ui()
			if day_number == 1 and visitor == 1:
				_check(not manager._buyer and state.inventory.is_empty(), "empty opening stock gets a seller rather than an impossible buyer")
				displayed = manager.current.artifact
				manager._on_accept()
				manager._on_price_submitted(35)
				_check(manager._displayed_stock().has(displayed), "buying and pricing the first artifact makes it available for same-day buyers")
				manager._on_next()
				continue
			if day_number == 1 and visitor == 2:
				_check(not manager._buyer and manager.current.artifact.tool_id == "broom" and manager.current.ask == 20, "second actual visitor sells the twenty-gold broom even with displayed stock")
				_check(state.cleaning.broom_available and not state.owned_items.get("broom", false), "declining the broom leaves a later purchase available without granting it free")
			manager._on_send_away()
		_check(manager._visitor_index == visitor_count, "continuous customer flow completes on day %d" % day_number)
		_check(model_names.size() == 2, "customer model selection uses both available variants")
		if day_number == 1:
			_check(buyers > 0 and sellers > 3 and uncommon_offers == 1, "day one mixes buyers with unlimited Common sellers and exactly one Uncommon offer")
		else:
			_check(buyers > 0 and sellers > 6, "later days mix buyers with sellers beyond the opening queue")
		# Finish the last departure and check waiting remains available in the arrival gap.
		manager.min_arrival_delay = 5.0 if day_number == 1 else 0.2
		manager.max_arrival_delay = manager.min_arrival_delay
		await create_timer(0.95, false).timeout
		_check(manager.can_wait(), "player can still wait between customers")
		if day_number == 1:
			state.set_sell_price(displayed.id, 0)
			var before_wait: int = state.time_minutes
			state.start_clock()
			manager.game_ui.open_panel("stock")
			var wait_key := InputEventKey.new()
			wait_key.physical_keycode = KEY_T
			wait_key.pressed = true
			manager.game_ui._unhandled_input(wait_key)
			for frame in 8:
				await process_frame
				if not manager._waiting: break
			_check(not manager.game_ui._open and not state.is_time_paused(), "T closes the stock book and releases its clock pause before waiting")
			state.stop_clock()
			_check(state.time_minutes > before_wait and state.time_minutes <= before_wait + 5 and not manager._waiting, "daytime waiting advances only the customer gap instead of skipping to evening")
			var arrived: bool = await _wait_for_customer(manager, visitor_count + 1)
			_check(arrived and not manager._buyer, "waiting bypasses the long arrival delay and unlisted day-one stock gets a seller")
			if arrived:
				state.pause_time(&"bargain")
				manager._open_bargain_ui()
				manager._on_send_away()
				await create_timer(0.95, false).timeout
		if day_number == 2:
			# Taking stock off display during the gap must not create a stale buyer.
			displayed.placement["held"] = true
			var arrived: bool = await _wait_for_customer(manager, visitor_count + 1)
			_check(arrived and not manager._buyer, "empty eligible stock still gets a fresh seller after the queue is exhausted")
			if arrived:
				state.pause_time(&"bargain")
				manager._open_bargain_ui()
				manager._on_send_away()
				await create_timer(0.95, false).timeout
		var before_close: int = manager._visitor_index
		if day_number == 2:
			state.time_minutes = 1229
			state.start_clock()
			await manager.wait_until_next_period()
			state.stop_clock()
			_check(state.time_minutes == 1230 and not manager._waiting, "waiting in the arrival gap advances to closing and releases its guard")
		else:
			state.time_minutes = 1230
			manager._on_time_changed(20, 30)
		await create_timer(0.3, false).timeout
		_check(manager._closed and manager.phase == manager.Phase.CLOSED and manager.customer == null and manager._visitor_index == before_close, "closing cancels the pending walk-in without a late arrival")
		main.queue_free()
		await process_frame
		await process_frame
