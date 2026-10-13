class_name DayQueue
extends RefCounted
## Opening sellers and fresh walk-ins. Buyers use current displayed stock.

const CATALOG_PATH := "res://scripts/data/artifact_catalog.json"
const DEFAULT_CATALOG := [
	{"name": "Gold Coin", "model_path": "res://assets/Relics/Goldcoin.glb", "grid_size": [1, 1]},
	{"name": "Sword", "model_path": "res://assets/Relics/Sword.glb", "grid_size": [1, 3]},
	{"name": "Guitar", "model_path": "res://assets/Relics/Guitar.glb", "grid_size": [1, 3]},
	{"name": "Surfboard", "model_path": "res://assets/Relics/Surfboard.glb", "grid_size": [1, 3]},
]


static func build(count: int = 5, day_number: int = 1) -> Array[Haggle]:
	var queue: Array[Haggle] = []
	var catalog := _catalog()
	if day_number <= 1:
		# Affordable introductions; the second seller still offers the 20 G broom.
		catalog.shuffle()
		catalog = _for_rarity(catalog, "Common")
		for i in 3:
			if i == 1:
				queue.append(broom_offer())
				continue
			var tier := "Common" if i < 2 else "Uncommon"
			var item := _artifact(catalog[i % catalog.size()], tier, "normal")
			queue.append(Haggle.new([50, 20, 200][i], false, "easygoing", item))
		return queue
	count = maxi(1, count)
	for i in count:
		var rarity := _roll_rarity(day_number)
		if i == 0 and day_number >= 3:
			rarity = "Rare"
		if i == count - 1 and day_number >= 5:
			rarity = "SSR"
		var item := _artifact(_for_rarity(catalog, rarity).pick_random(), rarity, _roll_status(rarity))
		var prices := item.price_range()
		# Most asks remain in the affordable lower part of each tier.
		var reference := randi_range(prices.x, prices.x + (prices.y - prices.x) / 3)
		queue.append(Haggle.new(reference, false, "", item))
	return queue

static func broom_offer() -> Haggle:
	var item := ArtifactData.create("res://assets/Cleaning/broom.tscn", "Broom", "Common", "normal", Vector2i.ONE)
	item.tool_id = "broom"
	var offer := Haggle.new(20, false, "easygoing", item)
	offer.ask = 20
	offer.start_ask = 20
	offer.floor_price = 16
	return offer


static func walk_in(day_number: int) -> Haggle:
	# Generate independently: exhausting the opening queue must not end the day.
	var rarity := _roll_rarity(day_number)
	var item := _artifact(_for_rarity(_catalog(), rarity).pick_random(), rarity, _roll_status(rarity))
	var prices := item.price_range()
	var reference := randi_range(prices.x, prices.x + (prices.y - prices.x) / 3)
	return Haggle.new(reference, false, "", item)


static func buyers_allowed(day_number: int) -> bool:
	return day_number >= 1


static func _catalog() -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []
	if FileAccess.file_exists(CATALOG_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if data is Array:
			for entry in data:
				if entry is Dictionary and ResourceLoader.exists(String(entry.get("model_path", ""))):
					catalog.append(entry)
	if catalog.is_empty():
		for entry in DEFAULT_CATALOG:
			catalog.append(entry)
	return catalog


static func _for_rarity(catalog: Array[Dictionary], tier: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in catalog:
		if String(entry.get("rarity", tier)) == tier: result.append(entry)
	return result

static func _artifact(entry: Dictionary, rarity: String, status: String) -> ArtifactData:
	var raw_grid: Variant = entry.get("grid_size", [1, 1])
	var grid := Vector2i.ONE
	if raw_grid is Array and raw_grid.size() == 2:
		grid = Vector2i(int(raw_grid[0]), int(raw_grid[1]))
	return ArtifactData.create(String(entry.get("model_path", "res://assets/Relics/Goldcoin.glb")), String(entry.get("name", "Artifact")), rarity, status, grid)


static func _roll_rarity(_day_number: int) -> String:
	var roll := randf()
	if roll < 0.03:
		return "SSR"
	if roll < 0.10:
		return "SR"
	if roll < 0.25:
		return "Rare"
	return "Common" if roll < 0.65 else "Uncommon"


static func _roll_status(rarity: String) -> String:
	var roll := randf()
	match rarity:
		"Common":
			return "stolen" if roll < 0.2 else ("broken" if roll < 0.4 else "normal")
		"Uncommon":
			return "stolen" if roll < 0.1 else ("broken" if roll < 0.3 else ("curse" if roll < 0.4 else "normal"))
		"Rare":
			return "stolen" if roll < 0.1 else ("curse" if roll < 0.3 else "normal")
		"SR":
			return "stolen" if roll < 0.1 else ("curse" if roll < 0.4 else "normal")
		"SSR":
			return "curse" if roll < 0.4 else "normal"
	return "normal"
