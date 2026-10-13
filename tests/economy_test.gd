extends SceneTree
## Run headless with --script res://tests/economy_test.gd. Uses a private test save.

const StateScript := preload("res://scripts/game_state.gd")
var checks: int = 0
var failures: int = 0
var test_path: String


func _init() -> void:
	test_path = "user://economy_test_%d.json" % Time.get_ticks_usec()
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)


func _state() -> Node:
	var state := StateScript.new()
	state.save_path = test_path
	return state


func _item(rarity: String = "Uncommon") -> ArtifactData:
	return ArtifactData.create("res://assets/Relics/Sword.glb", "Test Sword", rarity, "normal", Vector2i(3, 1))


func _run() -> void:
	seed(20261010)
	_test_transactions()
	_test_save_and_sleep()
	_test_furniture()
	_test_clock_and_rent()
	_test_schedule_and_buyers()
	if "--skip-simulation" not in OS.get_cmdline_user_args():
		_simulate_rent()
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	print("ECONOMY TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_transactions() -> void:
	var state := _state()
	_check(state.money == 200 and state.day == 1, "fresh economy is 200 G on day 1")
	var item := _item()
	_check(state.purchase(item, 80), "purchase succeeds")
	_check(state.money == 120 and item.cost == 80 and state.day_profit == 0, "buy deducts cost immediately, without realizing profit")
	_check(not state.purchase(item, 80) and state.money == 120, "duplicate purchase is rejected")
	_check(not state.purchase(_item(), 121) and state.inventory.size() == 1, "insufficient funds preserve inventory")
	_check(not state.purchase(_item(), 0) and not state.purchase(_item(), -10), "nonpositive costs cannot mint artifacts")
	_check(not state.sell(item.id, 95), "unlisted artifact cannot be sold")
	_check(state.set_sell_price(item.id, 100) == 100, "listing stored")
	_check(state.sell(item.id, 95), "buyer transaction succeeds")
	_check(state.money == 215 and state.day_profit == 15 and state.total_profit == 15, "sale credits proceeds and realizes sale minus original cost")
	_check(state.inventory.is_empty() and not state.sell(item.id, 95), "sold artifact leaves inventory, cannot sell twice")
	_check(not FileAccess.file_exists(test_path), "transactions do not autosave mid-day")
	var tiers := ["Common", "Uncommon", "Rare", "SR", "SSR"]
	var caps := [60, 360, 1200, 3600, 24000]
	for i in tiers.size():
		var capped := _item(tiers[i])
		_check(state.purchase(capped, 1), "cap fixture purchase")
		_check(state.set_sell_price(capped.id, 999999) == caps[i], "rarity cap " + tiers[i])
		_check(not state.sell(capped.id, caps[i] + 1), "above-cap actual sale rejected")
		_check(state.set_sell_price(capped.id, -20) == 0, "negative listing becomes unlisted")
	_check(not state.adjust_money(-999999) and state.money >= 0, "spending never makes wallet negative")
	var held := state.inventory[0] as ArtifactData
	state.set_sell_price(held.id, 50)
	held.placement["held"] = true
	_check(not state.available_stock().has(held), "held artifacts are unavailable to buyers")
	var profit_before: int = state.day_profit
	_check(state.remove_artifact(held.id) == held and state.day_profit == profit_before, "theft removal does not count as a sale")
	state.free()


func _test_save_and_sleep() -> void:
	var state := _state()
	var item := _item()
	state.purchase(item, 80)
	state.set_sell_price(item.id, 100)
	item.placement = {"position": [1.2, 0.9, -3.0], "rotation": 1, "surface": "counter", "cell": [2, 1]}
	state.set_item_owned("Clock")
	_check(not state.sleep() and state.day == 1, "sleep before 23:00 rejected")
	state.time_minutes = 23 * 60
	_check(state.sleep() and state.day == 2 and state.time_minutes == 630, "sleep saves, advances exactly once, wakes at 10:30")
	_check(state.has_save(), "sleep creates versioned save")
	var loaded := _state()
	_check(loaded.load_game(), "new save loads")
	_check(loaded.money == 120 and loaded.day == 2 and loaded.inventory.size() == 1, "money/day/unsold stock persist")
	var restored: ArtifactData = loaded.get_artifact(item.id)
	_check(restored != null and restored.cost == 80 and restored.sell_price == 100 and restored.grid_size == Vector2i(3, 1), "stable identity, original cost, listing, fixed size round-trip")
	var restored_position: Array = restored.placement.get("position", [])
	var original_position: Array = item.placement.get("position", [])
	_check(restored_position.size() == 3 and is_equal_approx(float(restored_position[0]), float(original_position[0])) and is_equal_approx(float(restored_position[1]), float(original_position[1])) and is_equal_approx(float(restored_position[2]), float(original_position[2])), "world placement coordinates survive JSON numeric conversion")
	_check(restored.placement.get("surface") == "counter" and int(restored.placement["cell"][0]) == 2 and int(restored.placement["cell"][1]) == 1, "grid placement survives JSON numeric conversion")
	_check(int(restored.placement["rotation"]) == 1, "quarter-turn scalar matches placement-manager save contract")
	_check(loaded.clock_owned and loaded.owned_items.has("clock"), "equipment round-trip")
	var malformed := item.to_dict()
	malformed["placement"] = {"position": [0, 1]}
	_check(ArtifactData.from_dict(malformed) == null, "malformed placement vector rejected")
	malformed["placement"] = {"position": [0, NAN, 0]}
	_check(ArtifactData.from_dict(malformed) == null, "non-finite placement vector rejected")
	malformed["placement"] = {"rotation": [0, 1, 0]}
	_check(ArtifactData.from_dict(malformed) == null, "rotation format that would crash placement manager rejected")
	_check(loaded.sell(restored.id, 95) and loaded.day_profit == 15, "sale next day uses prior-day cost")
	loaded.time_minutes = 23 * 60
	_check(loaded.sleep() and loaded.last_day_profit == 15 and loaded.day_profit == 0 and loaded.total_profit == 15, "realized daily profit resets after sleep, cumulative profit remains")
	var invalid := FileAccess.open(test_path, FileAccess.WRITE)
	invalid.store_string(JSON.stringify({"day": 10, "money": 2000}))
	invalid.close()
	_check(not loaded.load_game() and loaded.money == 215, "legacy save cannot restore obsolete 2000 G wallet")
	invalid = FileAccess.open(test_path, FileAccess.WRITE)
	invalid.store_string(JSON.stringify({"version": 2, "day": 1, "money": 200, "inventory": [item.to_dict(), item.to_dict()]}))
	invalid.close()
	_check(not loaded.load_game() and loaded.money == 215, "duplicate identities in invalid save cause no partial load")
	loaded.save_path = "user://nonexistent_economy_test_directory_%d/save.json" % Time.get_ticks_usec()
	loaded.time_minutes = 1380
	loaded.day_profit = 27
	print("EXPECTED SAVE FAILURE follows; verifying rollback without touching a real save.")
	_check(not loaded.sleep() and loaded.day == 3 and loaded.time_minutes == 1380 and loaded.day_profit == 27, "failed sleep save rolls back day/time/profit")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	state.free()
	loaded.free()


func _test_clock_and_rent() -> void:
	var state := _state()
	state._process(2.0)
	_check(state.time_minutes == 630, "menu clock remains stopped")
	state.start_clock()
	state._process(0.4)
	state._process(0.6)
	_check(state.time_minutes == 631, "one real second advances one in-game minute")
	state.pause_time(&"bargain")
	state.pause_time(&"pause_menu")
	state.resume_time(&"bargain")
	state._process(20.0)
	_check(state.time_minutes == 631, "independent pause owners cannot resume each other")
	state.resume_time(&"pause_menu")
	state._process(2.0)
	_check(state.time_minutes == 633, "clock resumes after all pauses removed")
	state.time_minutes = 19 * 60
	_check(state.is_night() and state.is_shop_open(), "night at 19:00 keeps shop open")
	state.time_minutes = 20 * 60 + 30
	_check(not state.is_shop_open(), "20:30 forced close boundary")
	state.time_minutes = 24 * 60 - 1
	state._process(1.0)
	_check(state.time_minutes == 1440 and not state.can_sleep(), "midnight stops clock and closes sleep window")
	state._process(59.0)
	_check(not state.failed, "one minute hallucination grace")
	state._process(1.0)
	_check(state.failed, "one minute after midnight ends the game")
	state.new_game()
	state.day = 4
	state.time_minutes = 1380
	state.sleep()
	_check(state.day == 5 and state.rent_due_amount == 800 and state.rent_days_left() == 0, "rent first due on day 5")
	state.time_minutes = 1380
	state.sleep()
	_check(state.day == 6 and state.rent_due_amount == 900 and not state.failed, "late day 6 adds exactly 100 G")
	var checkpoint := FileAccess.get_file_as_string(test_path)
	state.time_minutes = 1380
	state.sleep()
	_check(state.day == 7 and state.failed, "unpaid rent fails on day 7")
	_check(FileAccess.get_file_as_string(test_path) == checkpoint, "rent game-over preserves previous playable checkpoint")
	state.new_game()
	state.day = 5
	state._update_rent()
	state.money = 1000
	_check(state.pay_rent() and state.money == 200 and state.next_rent_day == 10 and state.rent_due_amount == 0, "paying rent advances anchored schedule to day 10")
	_check(not state.pay_rent(), "same rent cannot be paid twice")
	state.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))


func _test_furniture() -> void:
	var state := _state()
	var record := {"id": "shelf-fixture", "name": "Shelf", "model_path": "res://assets/Relics/Sword.glb", "grid_size": [2, 1], "placement": {"position": [1, 0, 2], "rotation": 0}}
	_check(state.purchase_furniture(record, 80), "furniture purchase succeeds")
	_check(state.money == 120 and state.furniture.size() == 1 and state.inventory.is_empty() and state.day_profit == 0, "furniture deducts cost and stays separate from buyer stock and profit")
	_check(not state.purchase_furniture(record, 80) and state.money == 120, "duplicate furniture purchase rejected")
	state.get_furniture("shelf-fixture")["placement"]["position"] = [3, 0, 4]
	state.time_minutes = 1380
	_check(state.sleep(), "furniture saved at sleep")
	var loaded := _state()
	_check(loaded.load_game() and loaded.furniture.size() == 1 and loaded.money == 120, "furniture and wallet round-trip")
	var saved: Dictionary = loaded.get_furniture("shelf-fixture")
	_check(saved.get("cost") == 80 and int(saved["placement"]["position"][0]) == 3, "authoritative furniture cost/placement persist")
	var invalid := record.duplicate(true)
	invalid["id"] = "bad-fixture"
	invalid["grid_size"] = [0, 2]
	_check(not loaded.purchase_furniture(invalid, 20) and loaded.money == 120, "invalid furniture cannot spend money")
	loaded.new_game()
	_check(loaded.furniture.is_empty(), "new game resets furniture")
	state.free()
	loaded.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))


func _test_schedule_and_buyers() -> void:
	for _i in 100:
		var first := DayQueue.build(6, 1)
		var total_ask: int = 0
		var common: int = 0
		var uncommon: int = 0
		for seller in first:
			total_ask += seller.ask
			common += int(seller.artifact.rarity == "Common")
			uncommon += int(seller.artifact.rarity == "Uncommon")
			_check(seller.artifact.status == "normal" and seller.relic_scale == 1.0, "day 1 normal status, no random size")
		_check(first.size() == 3 and common == 2 and uncommon == 1 and total_ask <= 200, "day 1 exact affordable rarity mix")
	_check(DayQueue.buyers_allowed(1) and DayQueue.buyers_allowed(2), "buyers are allowed from day 1")
	for _i in 100:
		_check(DayQueue.walk_in(1).artifact.rarity == "Common", "later day 1 sellers cannot add another Uncommon or a higher tier")
	for day_number in [3, 4, 5, 6]:
		var queue := DayQueue.build(6, day_number)
		_check(queue.any(func(h: Haggle) -> bool: return h.artifact.rarity == "Rare"), "guaranteed Rare from day 3")
		if day_number >= 5:
			_check(queue.any(func(h: Haggle) -> bool: return h.artifact.rarity == "SSR"), "guaranteed SSR from day 5")
	var item := _item()
	item.cost = 80
	item.sell_price = 100
	var accepted: int = 0
	var generous: int = 0
	for _i in 2000:
		var buyer := BuyerHaggle.new(item)
		_check(buyer.ask > 0 and buyer.ask <= item.max_sell_price(), "buyer price always legal")
		generous += int(buyer.ask > 100)
		accepted += int(buyer.make_offer(100)["result"] == "deal")
	_check(accepted > 1720 and accepted < 1940, "roughly 90 percent accept legal full listing")
	_check(generous > 40 and generous < 180, "above-list offers exist but are rare")
	item.sell_price = item.max_sell_price()
	for _i in 100:
		_check(BuyerHaggle.new(item).ask <= item.max_sell_price(), "above-list offers cannot exceed rarity cap")
	var settled := BuyerHaggle.new(item)
	_check(settled.accept_ask()["result"] == "deal" and settled.accept_ask()["result"] == "over", "buyer acceptance is idempotent")


func _simulate_rent() -> void:
	for markup in [1.30, 1.50, 1.75, 2.00]:
		var affordable_runs: int = 0
		var total_cash: int = 0
		for run in 200:
			seed(10000 + run)
			var state := _state()
			for day_number in range(1, 6):
				state.day = day_number
				var sellers := DayQueue.build(6, day_number)
				for seller in sellers:
					_simulate_buyer(state)
					if state.purchase(seller.artifact, seller.ask):
						state.set_sell_price(seller.artifact.id, roundi(seller.ask * markup))
				state.day_profit = 0
			affordable_runs += int(state.money >= 800)
			total_cash += state.money
			state.free()
		print("RENT SIMULATION: listing %.2fx cost, %d/200 can pay by end day 5; mean cash %d G" % [markup, affordable_runs, total_cash / 200])


func _simulate_buyer(state: Node) -> void:
	var stock: Array[ArtifactData] = state.available_stock()
	if stock.is_empty():
		return
	var item: ArtifactData = stock[0]
	var buyer := BuyerHaggle.new(item)
	# Conservative player accepts opening offers rather than asking for full listing.
	buyer.accept_ask()
	state.sell(item.id, buyer.deal_price)
