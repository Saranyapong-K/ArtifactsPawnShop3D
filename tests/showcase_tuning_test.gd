extends SceneTree
## Private-profile checks for the classroom balance and dialogue lifecycle.
var checks := 0
var failures := 0

func _init() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func frames(count := 4) -> void:
	for i in count: await process_frame

func run() -> void:
	if not OS.get_user_data_dir().contains("showcase-tests"): quit(9); return
	var state: Node = root.get_node("GameState")
	state.new_game(); state.set_process(false)
	check(state.money == 1000, "New Game has showcase capital")
	state.money = 417
	check(state.save_game("user://showcase.json"), "Private save succeeds")
	state.new_game()
	check(state.load_game("user://showcase.json") and state.money == 417, "Loading preserves the saved wallet")
	state.new_game()
	var common := ArtifactData.create("res://assets/Relics/Goldcoin.glb", "Coin", "Common")
	var uncommon := ArtifactData.create("res://assets/Relics/Sword.glb", "Sword", "Uncommon")
	check(common.price_range() == Vector2i(20, 100) and common.max_sell_price() == 120, "Common range and listing cap doubled")
	check(uncommon.price_range() == Vector2i(102, 600) and uncommon.max_sell_price() == 720, "Uncommon range and listing cap doubled")
	var opening := DayQueue.build(6, 1)
	check(opening[0].market_price == 50 and opening[2].market_price == 200, "Opening offers use doubled references")
	check(opening[1].ask == 20 and opening[1].artifact.tool_id == "broom", "Intro broom stays 20 G")
	seed(20261014)
	var seen := {}
	var fixed_rarities_valid := true
	for i in 1000:
		var offer := DayQueue.walk_in(1)
		seen[offer.artifact.rarity] = true
		if offer.artifact.model_path.ends_with("ip17.glb"):
			fixed_rarities_valid = fixed_rarities_valid and offer.artifact.rarity == "Rare"
	check(seen.size() == 5, "Real Day 1 walk-ins include every rarity")
	check(fixed_rarities_valid, "Fixed rarity models keep their assigned tier")
	change_scene_to_file("res://assets/Scene/main.tscn")
	await frames(12)
	var manager: Node = current_scene.get_node("Day_manager")
	while manager.flow == null: await process_frame
	manager._epoch += 1; manager.flow.close_shop(); manager.flow.set_process(false)
	check(manager.flow.arrival_interval == Vector2(18, 28), "Actual crowd uses faster arrival interval")
	var ui: Node = manager.game_ui
	ui.open_panel("shop"); await frames()
	for entry: Dictionary in ui.EQUIPMENT:
		var card: Node = ui._shop.get_node("%Equipment").get_node(ui.EQUIPMENT_NODES[entry.id])
		check(card.get_node("%Price").text == "%d G" % entry.price, "Runtime equipment price: " + entry.id)
	for entry: Dictionary in ui.FURNITURE:
		check(entry.price <= 500, "Affordable furniture: " + entry.id)
	var roomba: Dictionary = ui.EQUIPMENT.filter(func(e): return e.id == "roomba")[0]
	ui._buy_equipment(roomba)
	check(state.money == 750 and state.owned_items.get("roomba", false), "Actual Roomba purchase costs 250 G")
	var detector: Dictionary = ui.EQUIPMENT.filter(func(e): return e.id == "curse_detector")[0]
	ui._buy_equipment(detector)
	check(state.money == 350 and state.owned_items.get("curse_detector", false), "Actual detector purchase costs 400 G")
	ui.close_panel()
	var sound: Node = root.get_node("Sfx")
	var talk: AudioStreamWAV = sound._cues.talk
	check(talk.get_length() < 0.06 and talk.data.decode_s16(100) != 0, "Talk cue contains a short nonzero waveform")
	manager.ui.say("A quick musical hello from your customer, with a little autumn warmth.")
	await create_timer(0.2).timeout
	check(sound._last_played.has("talk"), "Actual typewriter triggers chatter")
	paused = true
	var last: int = sound._last_played.talk
	await create_timer(0.15).timeout
	check(sound._last_played.talk == last, "Pause stops new dialogue blips")
	paused = false
	manager.ui._dlg_typing = false
	await frames()
	last = sound._last_played.talk
	await create_timer(0.15).timeout
	check(sound._last_played.talk == last, "Reveal-all does not produce skipped chatter")
	manager.ui.hide_dialogue(); await frames()
	check(not manager.ui._dlg_active, "Hidden dialogue finishes its pending coroutine")
	print("SHOWCASE TUNING TEST: ", checks, " checks, ", failures, " failures")
	current_scene.queue_free(); await frames(8)
	for audio in root.find_children("*", "AudioStreamPlayer", true, false): audio.stop(); audio.stream = null
	await create_timer(0.2).timeout
	quit(0 if failures == 0 else 1)
