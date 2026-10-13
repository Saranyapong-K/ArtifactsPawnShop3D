extends SceneTree
## Meaningful rules, persistence, carrying exclusion, and runtime interactions.
class PlayerFixture extends Node3D:
	var controls_enabled := true
	var camera := Camera3D.new()
	var ray: RayCast3D
	func _init(): add_child(camera)
	func set_controls_enabled(value: bool): controls_enabled = value
class NoticeFixture extends CanvasLayer:
	var last_notice := ""
	func show_notice(value: String): last_notice = value
var checks := 0
var failures := 0
var state: Node
func _init(): _run.call_deferred()
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; push_error(message)

func _run():
	root.position = Vector2i(-16000, -16000)
	if not OS.get_user_data_dir().contains("cleaning-tests"):
		push_error("Use isolated APPDATA containing cleaning-tests."); quit(1); return
	state = root.get_node("GameState")
	state.save_path = "user://cleaning-test.json"
	_test_rules()
	_test_offers()
	_test_persistence()
	await _test_world()
	print("CLEANING TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_rules():
	var dirt := CleaningState.new()
	check(dirt.stars() == 6, "empty shop is six stars")
	for index in 12: check(dirt.add_mess("rubbish", "floor-%d" % index, Vector3.ZERO), "bounded unique floor mess can be added")
	check(dirt.stars() == 0 and not dirt.add_mess("spill", "extra", Vector3.ZERO), "twelve messes are zero stars and cap further spawning")
	check(not dirt.add_mess("rubbish", "floor-0", Vector3.ZERO), "occupied marker cannot spawn duplicate mess")
	var id: String = dirt.mess[0].id
	check(not dirt.clean(id, "mop", 1).ok and dirt.mess.size() == 12, "wrong tool leaves rubbish and rating unchanged")
	check(not dirt.clean(id, "broom", 1).ok, "instant clean cannot bypass the eight-second requirement")
	check(dirt.advance(id, "broom", 8.0, 1).completed and not dirt.advance(id, "broom", 8.0, 1).ok, "rubbish is cleaned exactly once")
	dirt = CleaningState.new()
	for index in 5: dirt.add_mess("spill", "spill-%d" % index, Vector3.ZERO)
	for index in 4:
		check(dirt.advance(dirt.mess[0].id, "mop", 8.0, 1).completed, "clean mop handles its first four spills")
	check(dirt.mop_uses == 4 and dirt.mess.size() == 1 and not dirt.clean(dirt.mess[0].id, "mop", 1).ok, "dirty mop blocks fifth clean without erasing the spill")
	dirt.mop_uses = 0
	check(dirt.advance(dirt.mess[0].id, "mop", 8.0, 1).completed and dirt.mop_uses == 1, "washing restores mop capacity")
	dirt.add_mess("dust", "shelf", Vector3.ZERO)
	check(dirt.advance(dirt.mess[0].id, "feather_duster", 8.0, 2).completed and dirt.dusted_days.shelf == 2, "duster clears a shelf and remembers its dust-free day")
	check(CleaningState.from_dict({"mess": [{"id":"x", "kind":"spill", "spot":"y", "position":[0, NAN, 0]}]}) == null, "malformed mess coordinates cannot enter the world")
	dirt = CleaningState.new()
	dirt.add_mess("rubbish", "resume", Vector3.ZERO)
	id = dirt.mess[0].id
	check(not dirt.advance(id, "broom", 3.0, 1).completed and dirt.bag_load == 0, "partial clean consumes no bag capacity")
	check(is_equal_approx(dirt.get_mess(id).progress, 3.0), "cancelled progress remains on its own mess record")
	var restored := CleaningState.from_dict(JSON.parse_string(JSON.stringify(dirt.to_dict())))
	check(restored.advance(id, "broom", 5.0, 1).completed and restored.bag_load == 1, "saved partial progress resumes for just its remaining five seconds")
	for index in 4:
		dirt.add_mess("rubbish", "bag-%d" % index, Vector3.ZERO)
		var next_id: String = dirt.mess.back().id
		check(dirt.advance(next_id, "broom", 8.0, 1).completed, "bag accepts one capacity unit per completed rubbish pile")
	check(dirt.bag_load == 4 and not dirt.advance(id, "broom", 8.0, 1).ok and dirt.get_mess(id).progress == 3.0, "full bag blocks further rubbish and preserves partial progress")
	check(dirt.empty_bag() and not dirt.empty_bag() and dirt.bag_load == 0, "dumpster empties a bag exactly once")
	check(dirt.advance(id, "broom", 5.0, 1).completed, "emptying bag enables the unfinished rubbish to resume")
	check(CleaningState.from_dict({"mess": [{"id":"x", "kind":"spill", "spot":"y", "position":[0, 0, 0], "progress": INF}]}) == null, "invalid progress cannot enter a save")

func _test_offers():
	var item := ArtifactData.create("res://assets/Relics/Goldcoin.glb", "Offer coin", "Uncommon")
	item.sell_price = 300
	for index in 100:
		seed(1200 + index)
		var seller := Haggle.new(200, false, "easygoing", item)
		var original_ask := seller.ask
		seller.apply_cleanliness(0.06)
		check(seller.ask < original_ask and seller.floor_price <= seller.ask, "six stars improves seller ask and preserves negotiation floor")
		var buyer := BuyerHaggle.new(item)
		var original_offer := buyer.ask
		buyer.apply_cleanliness(0.06)
		check(buyer.ask >= original_offer and buyer.max_budget >= buyer.ask and buyer.max_budget <= item.max_sell_price(), "cleanliness improves buyer offer within legal tier cap")
	var broom := DayQueue.broom_offer()
	broom.apply_cleanliness(0.06)
	check(broom.ask == 20 and broom.artifact.tool_id == "broom", "opening broom price remains exactly twenty gold")
	check(ArtifactData.from_dict(broom.artifact.to_dict()).tool_id == "broom", "special tool identity survives artifact serialization")

func _test_persistence():
	var standalone_state: Node = load("res://scripts/game_state.gd").new()
	check(standalone_state.owned_items.get("mop", false) and standalone_state.owned_items.get("feather_duster", false), "running Main directly also starts with mop and duster")
	standalone_state.free()
	state.new_game()
	check(state.owned_items.get("mop", false) and state.owned_items.get("feather_duster", false) and not state.owned_items.get("broom", false), "mop and duster start available while broom must be bought")
	var money: int = state.money
	check(state.purchase(DayQueue.broom_offer().artifact, 20) and state.money == money - 20, "broom purchase charges actual wallet")
	check(state.owned_items.get("broom", false) and state.inventory.is_empty(), "bought broom becomes permanent cleaning equipment instead of resale stock")
	check(not state.purchase(DayQueue.broom_offer().artifact, 20) and state.money == money - 20, "duplicate broom purchase cannot charge twice")
	state.cleaning.initialized = true
	state.cleaning.broom_available = true
	state.cleaning.mop_uses = 4
	state.cleaning.mop_wash_progress = 2.5
	state.cleaning.bag_load = 3
	state.cleaning.dusted_days = {"shelf": 1}
	state.cleaning.add_mess("spill", "floor", Vector3(1, 0, 2))
	state.cleaning.mess[0].progress = 3.25
	state.cleaning.schedule_day = 1
	state.cleaning.next_mess_minute = 900
	state.time_minutes = 1380
	check(state.sleep(), "sleep checkpoints cleaning state with the next day")
	state.new_game()
	check(state.load_game() and state.day == 2 and state.cleaning.mop_uses == 4 and state.cleaning.mess.size() == 1, "dirty mop and uncleaned mess persist across load")
	check(state.cleaning.bag_load == 3 and is_equal_approx(state.cleaning.mop_wash_progress, 2.5) and is_equal_approx(state.cleaning.mess[0].progress, 3.25), "bag load, partial wash and partial cleaning survive sleeping and loading")
	check(state.owned_items.get("broom", false) and state.cleaning.broom_available and state.cleaning.dusted_days.shelf == 1, "tool ownership, broom fallback, and dust age persist")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state.save_path))
	saved.erase("cleaning")
	saved.owned_items.erase("mop")
	saved.owned_items.erase("feather_duster")
	var file := FileAccess.open(state.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved)); file.close()
	check(state.load_game() and not state.cleaning.initialized and state.owned_items.get("mop", false), "old version-two saves acquire cleaning defaults safely")

func _test_world():
	state.new_game()
	var main := Node3D.new()
	root.add_child(main)
	var player := PlayerFixture.new()
	main.add_child(player)
	var placement: Node3D = load("res://scripts/placement_manager.gd").new()
	placement.player = player
	main.add_child(placement)
	var ui := NoticeFixture.new()
	main.add_child(ui)
	var world: Node3D = load("res://scenes/cleaning_world.tscn").instantiate()
	world.player = player; world.placement = placement; world.game_ui = ui
	main.add_child(world)
	await process_frame
	check(state.cleaning.mess.size() == 6 and state.cleaning.stars() == 3 and world.targets.size() == 6, "shop starts with three rubbish, two spills, and shelf dust at three stars")
	check(not world.tool_targets.broom.visible and world.tool_targets.mop.visible and world.tool_targets.feather_duster.visible, "broom is hidden until its seller while other tools are available")
	state.cleaning.broom_available = true
	state.changed.emit()
	var broom_target: Area3D = world.tool_targets.broom
	player.global_position = broom_target.global_position
	world.interact_target(broom_target, player)
	check(state.money == 180 and state.owned_items.get("broom", false), "rejected broom remains purchasable at its stand for twenty gold")
	check(world.hold_tool("broom") and not world.hold_tool("mop"), "player can hold only one cleaning tool")
	check(world.held_visual.get_parent() == player.camera and not broom_target.visible, "held model follows camera and disappears from its stand")
	var artifact := ArtifactData.create("res://assets/Relics/Goldcoin.glb", "Carry coin")
	state.purchase(artifact, 10)
	var relic: Node3D = placement.spawn_artifact(artifact, Vector3.ZERO)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	placement.pick_up(relic)
	check(placement.held == null, "holding a cleaning tool blocks artifact carrying")
	var rubbish_id := ""
	for record in state.cleaning.mess:
		if record.kind == "rubbish": rubbish_id = record.id; break
	var target: Area3D = world.targets[rubbish_id]
	player.global_position = target.global_position
	world.interact_target(target, player)
	world.advance_cleaning(3.0, false)
	check(world.is_cleaning() and world.hud.progress_panel.visible and is_equal_approx(world.hud.progress_bar.value, 37.5), "active rubbish shows the rounded progress bar after three of eight seconds")
	check(world.held_visual.get_parent() == world._cleaning_pivot and not world._cleaning_pivot.rotation.is_zero_approx(), "broom moves and rotates on the active rubbish")
	world.stop_cleaning()
	check(not world.hud.progress_panel.visible and world.held_visual.get_parent() == player.camera and state.cleaning.get_mess(rubbish_id).progress == 3.0, "cancelling hides the bar, returns the tool to the camera, and retains progress")
	world.interact_target(target, player)
	world.advance_cleaning(5.0, false)
	check(not world.targets.has(rubbish_id) and state.cleaning.mess.size() == 5 and state.cleaning.bag_load == 1, "resuming completes rubbish once and fills bag one-quarter")
	var q := InputEventKey.new(); q.physical_keycode = KEY_Q; q.pressed = true
	world._unhandled_input(q)
	check(world.held_tool.is_empty() and broom_target.visible, "Q puts tool back at its stand")
	placement.pick_up(relic)
	# Headless Godot has no pointer lock. The GPU run exercises actual pickup;
	# here use a carried artifact fixture to test the shared hands exclusion.
	if DisplayServer.get_name() == "headless": placement.held = relic
	check(placement.held == relic and not world.hold_tool("mop"), "carrying an artifact blocks cleaning tool pickup (held=%s, mode=%s, tool=%s)" % [placement.held, Input.mouse_mode, world.held_tool])
	placement.cancel_placement()
	check(world.hold_tool("mop"), "mop pickup succeeds after artifact is put down")
	state.cleaning.mop_uses = 4
	var wash: Area3D
	for node in world.get_children():
		if node is Area3D and node.kind == "wash": wash = node
	player.global_position = wash.global_position
	world.interact_target(wash, player)
	world.advance_cleaning(8.0, false)
	check(state.cleaning.mop_uses == 0 and world.held_tool == "mop", "toilet washing cleans the held mop without dropping it")
	world.put_tool_away()
	state.cleaning.bag_load = 4
	state.changed.emit()
	check(world.bag_target.visible and world.bag_target.collision_layer == 1, "full bag is available at its home")
	world.put_tool_away()
	check(world.hold_tool("trash_bag") and not world.bag_target.visible and not world.hold_tool("broom"), "carried bag shares the one-item limit and leaves its home")
	player.global_position = world.dumpster_target.global_position
	world.interact_target(world.dumpster_target, player)
	check(state.cleaning.bag_load == 0 and world.held_tool.is_empty() and not world.bag_target.visible, "carrying bag to rear dumpster empties it and releases hands")
	state.cleaning.bag_load = 2
	world.interact_target(world.dumpster_target, player)
	check(state.cleaning.bag_load == 2, "dumpster cannot empty a bag the player is not carrying")
	state.cleaning.bag_load = 0
	# An actual opaque wall blocks the world ray, while the viewport waypoint stays visible.
	player.global_position = world.dumpster_target.global_position + Vector3(0, 0, 2.5)
	player.camera.position = Vector3(0, 1.6, 0)
	player.camera.make_current()
	var dumpster_point: Vector3 = world.dumpster_target.global_position + Vector3.UP * 0.8
	player.camera.look_at(dumpster_point)
	var wall := StaticBody3D.new()
	main.add_child(wall)
	wall.global_position = (player.camera.global_position + dumpster_point) * 0.5
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new(); wall_box.size = Vector3(2, 3, 0.4)
	wall_shape.shape = wall_box; wall.add_child(wall_shape)
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, dumpster_point)
	var obstruction: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(query)
	world.hud.update_dumpster(player.camera, dumpster_point, true)
	check(obstruction.get("collider") == wall and world.hud.indicator.visible, "dumpster arrow remains visible through a real opaque wall")
	player.camera.rotate_y(PI)
	world.hud.update_dumpster(player.camera, dumpster_point, true)
	var arrow_position: Vector2 = world.hud.indicator.position
	check(world.hud.indicator.visible and root.get_visible_rect().has_point(arrow_position), "dumpster behind the camera gets a visible screen-edge direction arrow")
	wall.queue_free()
	if DisplayServer.get_name() != "headless":
		world.set_process(false)
		var spill_id := ""
		for record in state.cleaning.mess:
			if record.kind == "spill": spill_id = record.id; break
		var spill: Area3D = world.targets[spill_id]
		player.global_position = spill.global_position + Vector3(0, 0, 1)
		player.camera.look_at(spill.global_position + Vector3.UP * 0.05)
		player.ray = RayCast3D.new()
		player.ray.target_position = Vector3(0, 0, -3)
		player.ray.collide_with_areas = true
		player.camera.add_child(player.ray)
		await physics_frame
		check(world.hold_tool("mop"), "real hold-input fixture picks up mop")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Input.action_press("interact")
		world.interact_target(spill, player)
		world.advance_cleaning(2.0)
		check(world.is_cleaning() and state.cleaning.get_mess(spill_id).progress == 2.0 and state.cleaning.mop_uses == 0, "held E and a real ray advance cleaning without charging a partial mop use")
		Input.action_release("interact")
		world.advance_cleaning(1.0)
		check(not world.is_cleaning() and state.cleaning.get_mess(spill_id).progress == 2.0, "releasing E pauses progress without adding cleaning time")
		world.put_tool_away()
		world.set_process(true)
	var before: int = state.cleaning.mess.size()
	state.cleaning.next_mess_minute = 631
	world._on_time_changed(10, 31)
	check(state.cleaning.mess.size() == before + 1 and state.cleaning.next_mess_minute > 631, "occasional daytime mess uses free markers and schedules the next event")
	before = state.cleaning.mess.size()
	state.cleaning.next_mess_minute = 1230
	world._on_time_changed(20, 30)
	check(state.cleaning.mess.size() == before, "shop closing stops new floor mess")
	var dust_id := ""
	for record in state.cleaning.mess:
		if record.kind == "dust": dust_id = record.id; break
	state.cleaning.advance(dust_id, "feather_duster", 8.0, 1)
	state.day = 3; world._day_schedule()
	check(not state.cleaning.occupied("DustSurfaces/CounterDust"), "shelf stays dust-free for the next two days")
	state.day = 4; world._day_schedule()
	check(state.cleaning.occupied("DustSurfaces/CounterDust"), "stationary shelf collects dust after three days")
	main.queue_free()
	await process_frame
	await process_frame
