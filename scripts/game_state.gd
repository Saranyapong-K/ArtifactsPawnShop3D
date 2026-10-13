extends Node
## Wallet, owned artifacts, time and rent. Persistent saves happen when sleeping.

signal changed
signal time_changed(hour: int, minute: int)
signal day_started(day: int)
signal game_over(reason: String)
signal hallucination_started

const SAVE_PATH := "user://save_v2.json"
const SAVE_VERSION := 2
const START_MONEY := 1000
const WAKE_TIME := 10 * 60 + 30
const RENT := 800
const RENT_INTERVAL := 5
const CleaningData = preload("res://scripts/cleaning_state.gd")

var save_path: String = SAVE_PATH
var money: int = START_MONEY
var day: int = 1
var day_profit: int = 0
var total_profit: int = 0
var last_day_profit: int = 0
var inventory: Array[ArtifactData] = []
var furniture: Array[Dictionary] = []
var transactions: Array[Dictionary] = []
var time_minutes: int = WAKE_TIME
var clock_owned: bool = true
var owned_items: Dictionary = {"mop": true, "feather_duster": true, "clock": true}
var cleaning = CleaningData.new()
var clock_running: bool = false
var next_rent_day: int = RENT_INTERVAL
var rent_due_amount: int = 0
var failed: bool = false
var failure_reason: String = ""

var _minute_fraction: float = 0.0
var _midnight_seconds: float = 0.0
var _pause_owners: Dictionary = {}


func _process(delta: float) -> void:
	if not clock_running or not _pause_owners.is_empty() or failed:
		return
	if time_minutes >= 24 * 60:
		_midnight_seconds += delta
		if _midnight_seconds >= 60.0:
			_fail("You stayed awake past midnight.")
		return
	_minute_fraction += delta
	while _minute_fraction >= 1.0 and time_minutes < 24 * 60:
		_minute_fraction -= 1.0
		time_minutes += 1
		_emit_time()
		if time_minutes == 24 * 60:
			_minute_fraction = 0.0
			hallucination_started.emit()


func new_game() -> void:
	money = START_MONEY
	day = 1
	day_profit = 0
	total_profit = 0
	last_day_profit = 0
	inventory.clear()
	furniture.clear()
	transactions.clear()
	time_minutes = WAKE_TIME
	clock_owned = true
	owned_items.clear()
	cleaning = CleaningData.new()
	owned_items["mop"] = true
	owned_items["feather_duster"] = true
	owned_items["clock"] = true
	clock_running = false
	next_rent_day = RENT_INTERVAL
	rent_due_amount = 0
	failed = false
	failure_reason = ""
	_minute_fraction = 0.0
	_midnight_seconds = 0.0
	_pause_owners.clear()
	changed.emit()
	_emit_time()
	day_started.emit(day)


func start_clock() -> void:
	clock_running = true


func stop_clock() -> void:
	clock_running = false


func set_time_paused(paused: bool) -> void:
	if paused:
		pause_time()
	else:
		resume_time()


func pause_time(owner: StringName = &"manual") -> void:
	_pause_owners[owner] = true


func resume_time(owner: StringName = &"manual") -> void:
	_pause_owners.erase(owner)


func is_time_paused() -> bool:
	return not _pause_owners.is_empty() or not clock_running or failed


func is_night() -> bool:
	return time_minutes >= 19 * 60


func is_shop_open() -> bool:
	return not failed and time_minutes < 20 * 60 + 30


func can_buy(price: int) -> bool:
	return not failed and price > 0 and price <= money

func can_buy_upgrade(price: int) -> bool:
	# Keep enough capital for the opening artifact and broom when stock is empty.
	return can_buy(price) and (not inventory.is_empty() or money - price >= 50)


func purchase(artifact: ArtifactData, price: int) -> bool:
	if artifact == null or artifact.id.is_empty() or not can_buy(price) or get_artifact(artifact.id) != null:
		return false
	if not artifact.tool_id.is_empty() and owned_items.get(artifact.tool_id, false):
		return false
	artifact.cost = price
	artifact.sell_price = 0
	money -= price
	if artifact.tool_id.is_empty(): inventory.append(artifact)
	else: owned_items[artifact.tool_id] = true
	transactions.append({"type": "purchase", "day": day, "time": time_minutes, "id": artifact.id, "name": artifact.display_name, "price": price})
	changed.emit()
	return true


func set_sell_price(artifact_id: String, price: int) -> int:
	var artifact := get_artifact(artifact_id)
	if artifact == null or failed:
		return -1
	artifact.sell_price = clampi(price, 0, artifact.max_sell_price())
	changed.emit()
	return artifact.sell_price


func purchase_furniture(record: Dictionary, price: int) -> bool:
	var normalized := _validated_furniture(record)
	if normalized.is_empty() or not can_buy(price) or not get_furniture(String(normalized["id"])).is_empty():
		return false
	normalized["cost"] = price
	money -= price
	furniture.append(normalized)
	transactions.append({"type": "furniture", "day": day, "time": time_minutes, "id": normalized["id"], "name": normalized["name"], "price": price})
	changed.emit()
	return true


func get_furniture(furniture_id: String) -> Dictionary:
	for record in furniture:
		if String(record.get("id", "")) == furniture_id:
			return record
	return {}


func sell(artifact_id: String, price: int) -> bool:
	var artifact := get_artifact(artifact_id)
	if failed or artifact == null or artifact.sell_price <= 0 or price <= 0 or price > artifact.max_sell_price():
		return false
	var profit := price - artifact.cost
	inventory.erase(artifact)
	money += price
	day_profit += profit
	total_profit += profit
	transactions.append({"type": "sale", "day": day, "time": time_minutes, "id": artifact.id, "name": artifact.display_name, "cost": artifact.cost, "price": price, "profit": profit})
	changed.emit()
	return true


func get_artifact(artifact_id: String) -> ArtifactData:
	for artifact in inventory:
		if artifact.id == artifact_id:
			return artifact
	return null


func remove_artifact(artifact_id: String) -> ArtifactData:
	var artifact := get_artifact(artifact_id)
	if artifact == null:
		return null
	inventory.erase(artifact)
	transactions.append({"type": "removed", "day": day, "time": time_minutes, "id": artifact.id, "name": artifact.display_name})
	changed.emit()
	return artifact


func adjust_money(amount: int) -> bool:
	if failed or money + amount < 0:
		return false
	money += amount
	changed.emit()
	return true


func spend(amount: int) -> bool:
	return amount >= 0 and adjust_money(-amount)


func set_item_owned(item_id: String, owned: bool = true) -> void:
	var key := item_id.to_lower()
	if owned:
		owned_items[key] = true
	else:
		owned_items.erase(key)
	if key == "clock":
		clock_owned = owned
	changed.emit()


func end_game(reason: String) -> void:
	_fail(reason)


func available_stock() -> Array[ArtifactData]:
	var stock: Array[ArtifactData] = []
	for artifact in inventory:
		if artifact.sell_price > 0 and not bool(artifact.placement.get("held", false)):
			stock.append(artifact)
	return stock


func rent_days_left() -> int:
	return maxi(0, next_rent_day - day)


func pay_rent() -> bool:
	if failed or rent_due_amount <= 0 or money < rent_due_amount:
		return false
	var paid := rent_due_amount
	money -= paid
	transactions.append({"type": "rent", "day": day, "time": time_minutes, "price": paid})
	rent_due_amount = 0
	next_rent_day += RENT_INTERVAL
	changed.emit()
	return true


func can_sleep() -> bool:
	return not failed and time_minutes >= 23 * 60 and time_minutes < 24 * 60


func sleep() -> bool:
	if not can_sleep():
		return false
	var old_day := day
	var old_profit := day_profit
	var old_last_profit := last_day_profit
	var old_time := time_minutes
	var old_fraction := _minute_fraction
	var old_midnight := _midnight_seconds
	var old_rent := rent_due_amount
	last_day_profit = day_profit
	day += 1
	day_profit = 0
	time_minutes = WAKE_TIME
	_minute_fraction = 0.0
	_midnight_seconds = 0.0
	if day >= next_rent_day + 2:
		# Keep the previous playable checkpoint when unpaid rent ends the game.
		_fail("Unpaid rent led to jail. The shop is closed.")
		return false
	_update_rent()
	if not save_game():
		day = old_day
		day_profit = old_profit
		last_day_profit = old_last_profit
		time_minutes = old_time
		_minute_fraction = old_fraction
		_midnight_seconds = old_midnight
		rent_due_amount = old_rent
		return false
	changed.emit()
	_emit_time()
	day_started.emit(day)
	return true


func _update_rent() -> void:
	if day < next_rent_day:
		return
	if day >= next_rent_day + 2:
		_fail("Unpaid rent led to jail. The shop is closed.")
		return
	rent_due_amount = RENT + (100 if day > next_rent_day else 0)


func _fail(reason: String) -> void:
	if failed:
		return
	failed = true
	failure_reason = reason
	clock_running = false
	game_over.emit(reason)
	changed.emit()


func _emit_time() -> void:
	time_changed.emit(time_minutes / 60, time_minutes % 60)


func has_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	return data is Dictionary and int(data.get("version", 0)) == SAVE_VERSION


func save_game(path: String = "") -> bool:
	var target := save_path if path.is_empty() else path
	var items: Array[Dictionary] = []
	for artifact in inventory:
		items.append(artifact.to_dict())
	var data := {"version": SAVE_VERSION, "money": money, "day": day,
		"day_profit": day_profit, "total_profit": total_profit,
		"last_day_profit": last_day_profit, "inventory": items, "furniture": furniture,
		"transactions": transactions, "time_minutes": time_minutes,
		"clock_owned": clock_owned, "owned_items": owned_items, "next_rent_day": next_rent_day,
		"rent_due_amount": rent_due_amount, "failed": failed,
		"failure_reason": failure_reason, "cleaning": cleaning.to_dict()}
	var temporary := target + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_error("Could not save the game: %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		push_error("Could not finish writing the game save: %s" % write_error)
		return false
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(target))
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		push_error("Could not replace the game save: %s" % rename_error)
		return false
	return true


func load_game(path: String = "") -> bool:
	var target := save_path if path.is_empty() else path
	if not FileAccess.file_exists(target):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(target))
	if not data is Dictionary or int(data.get("version", 0)) != SAVE_VERSION:
		return false
	var raw_inventory: Variant = data.get("inventory", [])
	if not raw_inventory is Array or int(data.get("money", -1)) < 0 or int(data.get("day", 0)) < 1:
		return false
	var loaded_inventory: Array[ArtifactData] = []
	var ids: Dictionary = {}
	for entry in raw_inventory:
		if not entry is Dictionary:
			return false
		var artifact := ArtifactData.from_dict(entry)
		if artifact == null or ids.has(artifact.id):
			return false
		ids[artifact.id] = true
		loaded_inventory.append(artifact)
	var loaded_transactions: Array[Dictionary] = []
	var loaded_furniture: Array[Dictionary] = []
	var raw_furniture: Variant = data.get("furniture", [])
	if not raw_furniture is Array:
		return false
	var furniture_ids: Dictionary = {}
	for entry in raw_furniture:
		if not entry is Dictionary:
			return false
		var record := _validated_furniture(entry)
		if record.is_empty() or furniture_ids.has(record["id"]):
			return false
		furniture_ids[record["id"]] = true
		loaded_furniture.append(record)
	var raw_transactions: Variant = data.get("transactions", [])
	if not raw_transactions is Array:
		return false
	for entry in raw_transactions:
		if entry is Dictionary:
			loaded_transactions.append(entry.duplicate(true))
	var loaded_cleaning = CleaningData.from_dict(data.get("cleaning", {}))
	if loaded_cleaning == null: return false
	money = int(data["money"])
	day = int(data["day"])
	day_profit = int(data.get("day_profit", 0))
	total_profit = int(data.get("total_profit", 0))
	last_day_profit = int(data.get("last_day_profit", 0))
	inventory = loaded_inventory
	furniture = loaded_furniture
	transactions = loaded_transactions
	time_minutes = clampi(int(data.get("time_minutes", WAKE_TIME)), WAKE_TIME, 24 * 60)
	clock_owned = bool(data.get("clock_owned", false))
	var raw_items: Variant = data.get("owned_items", {})
	owned_items = raw_items.duplicate(true) if raw_items is Dictionary else {}
	# Existing checkpoints predate cleaning; starting tools are not purchases.
	owned_items["mop"] = true
	owned_items["feather_duster"] = true
	# Basic time remains available; radio ownership is a paid song unlock.
	clock_owned = true
	owned_items["clock"] = true
	cleaning = loaded_cleaning
	if day > 1: cleaning.broom_available = true
	if clock_owned:
		owned_items["clock"] = true
	next_rent_day = maxi(RENT_INTERVAL, int(data.get("next_rent_day", RENT_INTERVAL)))
	rent_due_amount = maxi(0, int(data.get("rent_due_amount", 0)))
	failed = bool(data.get("failed", false))
	failure_reason = String(data.get("failure_reason", ""))
	clock_running = false
	_minute_fraction = 0.0
	_midnight_seconds = 0.0
	_pause_owners.clear()
	_update_rent()
	changed.emit()
	_emit_time()
	return true


func _validated_furniture(record: Dictionary) -> Dictionary:
	for key in ["id", "name", "model_path"]:
		if not record.get(key) is String or String(record[key]).is_empty():
			return {}
	if not String(record["model_path"]).begins_with("res://"):
		return {}
	var raw_grid: Variant = record.get("grid_size", [1, 1])
	if not ArtifactData._valid_vector(raw_grid, 2):
		return {}
	for dimension in raw_grid:
		if float(dimension) != float(int(dimension)) or int(dimension) < 1 or int(dimension) > 16:
			return {}
	var placement: Variant = record.get("placement", {})
	if not placement is Dictionary:
		return {}
	if placement.has("position") and not ArtifactData._valid_vector(placement["position"], 3):
		return {}
	if placement.has("rotation") and not ArtifactData._valid_rotation(placement["rotation"]):
		return {}
	if placement.has("cell") and not ArtifactData._valid_vector(placement["cell"], 2):
		return {}
	var normalized := record.duplicate(true)
	normalized["grid_size"] = [int(raw_grid[0]), int(raw_grid[1])]
	normalized["cost"] = maxi(0, int(record.get("cost", 0)))
	normalized["placement"] = placement.duplicate(true)
	return normalized
