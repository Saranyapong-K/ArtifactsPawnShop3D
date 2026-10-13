class_name ArtifactData
extends RefCounted
## Persistent information for one artifact. Cost is its actual purchase price.

const RARITY_RANGES := {
	"Common": Vector2i(10, 50), "Uncommon": Vector2i(51, 300),
	"Rare": Vector2i(301, 1000), "SR": Vector2i(1000, 3000),
	"SSR": Vector2i(3000, 20000),
}
const STATUSES := ["normal", "broken", "stolen", "curse"]
const GRID_SIZES := [Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 1), Vector2i(1, 3), Vector2i(3, 1), Vector2i(2, 2), Vector2i(3, 3)]

var id: String = ""
var display_name: String = "Artifact"
var model_path: String = "res://assets/Relics/Goldcoin.glb"
var rarity: String = "Common"
var status: String = "normal"
var cost: int = 0
var sell_price: int = 0
var grid_size: Vector2i = Vector2i.ONE
var tool_id: String = ""
## Findings are per artifact; merely owning an inspection tool reveals nothing.
var inspections: Dictionary = {}
## World position/rotation arrays and surface/cell identifiers once placed.
var placement: Dictionary = {}


static func create(p_model_path: String, p_name: String = "Artifact", p_rarity: String = "Common", p_status: String = "normal", p_grid_size: Vector2i = Vector2i.ONE) -> ArtifactData:
	var artifact := ArtifactData.new()
	artifact.id = "%x-%x-%x" % [int(Time.get_unix_time_from_system() * 1000000.0), Time.get_ticks_usec(), randi()]
	artifact.model_path = p_model_path
	artifact.display_name = p_name
	artifact.rarity = p_rarity if RARITY_RANGES.has(p_rarity) else "Common"
	artifact.status = p_status.to_lower() if p_status.to_lower() in STATUSES else "normal"
	artifact.grid_size = p_grid_size if p_grid_size in GRID_SIZES else Vector2i.ONE
	return artifact


func price_range() -> Vector2i:
	return RARITY_RANGES.get(rarity, Vector2i(10, 50))


func max_sell_price() -> int:
	return price_range().y * 120 / 100


func to_dict() -> Dictionary:
	return {"id": id, "name": display_name, "model_path": model_path,
		"rarity": rarity, "status": status, "cost": cost,
		"sell_price": sell_price, "grid_size": [grid_size.x, grid_size.y],
		"placement": placement.duplicate(true), "inspections": inspections.duplicate(), "tool_id": tool_id}


static func from_dict(data: Dictionary) -> ArtifactData:
	var raw_grid: Variant = data.get("grid_size", [1, 1])
	var grid := Vector2i.ONE
	if raw_grid is Array and raw_grid.size() == 2:
		grid = Vector2i(int(raw_grid[0]), int(raw_grid[1]))
	var artifact := create(String(data.get("model_path", "res://assets/Relics/Goldcoin.glb")), String(data.get("name", "Artifact")), String(data.get("rarity", "Common")), String(data.get("status", "normal")), grid)
	artifact.id = String(data.get("id", artifact.id))
	if artifact.id.is_empty():
		return null
	artifact.cost = maxi(0, int(data.get("cost", 0)))
	artifact.tool_id = String(data.get("tool_id", ""))
	if artifact.tool_id not in ["", "broom"]: return null
	artifact.sell_price = clampi(int(data.get("sell_price", 0)), 0, artifact.max_sell_price())
	var saved_inspections: Variant = data.get("inspections", {})
	if saved_inspections is Dictionary:
		for tool: String in ["magnifier", "curse_detector", "stolen_found"]:
			if saved_inspections.get(tool, false) == true:
				artifact.inspections[tool] = true
	var raw_placement: Variant = data.get("placement", {})
	if raw_placement is Dictionary:
		if raw_placement.has("position") and not _valid_vector(raw_placement["position"], 3):
			return null
		if raw_placement.has("rotation") and not _valid_rotation(raw_placement["rotation"]):
			return null
		if raw_placement.has("cell") and not _valid_vector(raw_placement["cell"], 2):
			return null
		artifact.placement = raw_placement.duplicate(true)
		# A loaded artifact returns to its saved place; hands are transient state.
		artifact.placement["held"] = false
	else:
		return null
	return artifact


static func _valid_vector(value: Variant, length: int) -> bool:
	if not value is Array or value.size() != length:
		return false
	for coordinate in value:
		if typeof(coordinate) != TYPE_INT and typeof(coordinate) != TYPE_FLOAT:
			return false
		if is_nan(float(coordinate)) or is_inf(float(coordinate)):
			return false
	return true


static func _valid_rotation(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	if is_nan(float(value)) or is_inf(float(value)):
		return false
	return float(value) == float(int(value)) and int(value) >= 0 and int(value) <= 3
