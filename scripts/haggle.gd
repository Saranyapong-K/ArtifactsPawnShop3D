class_name Haggle
extends RefCounted
## Seller negotiation. Only GameState.purchase transfers money or owns an artifact.

signal anger_changed(anger: float)
signal ask_changed(new_ask: int)
signal finished(outcome: String, price: int)

const FLOOR_RATIO := 0.8
const MAX_LOWBALLS := 3
const PERSONALITIES := {
	"greedy": {"ask": Vector2(1.15, 1.40), "concessions": Vector2i(1, 1), "patience": Vector2i(5, 5), "anger": 1.0, "step": Vector2(0.03, 0.05)},
	"desperate": {"ask": Vector2(0.80, 1.00), "concessions": Vector2i(3, 3), "patience": Vector2i(6, 6), "anger": 0.8, "step": Vector2(0.04, 0.06)},
	"stubborn": {"ask": Vector2(0.95, 1.15), "concessions": Vector2i(1, 2), "patience": Vector2i(6, 6), "anger": 1.0, "step": Vector2(0.02, 0.04)},
	"easygoing": {"ask": Vector2(0.90, 1.10), "concessions": Vector2i(3, 3), "patience": Vector2i(5, 5), "anger": 0.6, "step": Vector2(0.04, 0.06)},
	"hothead": {"ask": Vector2(0.95, 1.20), "concessions": Vector2i(2, 2), "patience": Vector2i(5, 5), "anger": 1.8, "step": Vector2(0.03, 0.05)},
}

var artifact: ArtifactData
var personality: String
## Reference for generating seller asks, not the artifact's actual value.
var market_price: int
var start_ask: int
var ask: int
var floor_price: int
var satisfaction: float = 100.0
var concessions_used: int = 0
var concessions_max: int = 0
var patience: int = 5
var disagreements: int = 0
var lowballs: int = 0
var is_over: bool = false
var deal_price: int = 0
## Compatibility for the inactive old test. Neither field determines payouts.
var true_value: int = 0
var relic_scale: float = 1.0


func _init(p_market: int = 25, _obsolete_jackpot: bool = false, p_personality: String = "", p_artifact: ArtifactData = null) -> void:
	artifact = p_artifact
	if artifact == null:
		artifact = ArtifactData.create("res://assets/Relics/Goldcoin.glb", "Gold Coin")
	market_price = maxi(1, p_market)
	personality = p_personality if PERSONALITIES.has(p_personality) else String(PERSONALITIES.keys().pick_random())
	var traits: Dictionary = PERSONALITIES[personality]
	var ask_range: Vector2 = traits["ask"]
	var conc_range: Vector2i = traits["concessions"]
	var pat_range: Vector2i = traits["patience"]
	var prices := artifact.price_range()
	start_ask = clampi(roundi(market_price * randf_range(ask_range.x, ask_range.y)), prices.x, prices.y)
	if artifact.status == "broken":
		start_ask = maxi(1, roundi(start_ask * 0.8))
	ask = start_ask
	floor_price = maxi(1, roundi(start_ask * FLOOR_RATIO))
	concessions_max = randi_range(conc_range.x, conc_range.y)
	patience = randi_range(pat_range.x, pat_range.y)


func apply_cleanliness(bonus: float) -> void:
	# Snapshot the shop rating once on arrival. Intro broom stays exactly 20 G.
	if is_over or not artifact.tool_id.is_empty(): return
	var multiplier := 1.0 - clampf(bonus, 0.0, 0.06)
	ask = maxi(1, roundi(ask * multiplier))
	start_ask = ask
	floor_price = mini(ask, maxi(1, roundi(floor_price * multiplier)))

func make_offer(offer: int) -> Dictionary:
	if is_over:
		return _result("over")
	if offer >= ask:
		return _close_deal(ask)
	disagreements += 1
	if offer < floor_price:
		lowballs += 1
	var gap := float(ask - maxi(0, offer)) / maxi(1, ask)
	var anger_mult: float = PERSONALITIES[personality]["anger"]
	satisfaction = maxf(0.0, satisfaction - maxf(3.0, gap * 40.0) * anger_mult)
	anger_changed.emit(get_anger())
	if lowballs > MAX_LOWBALLS or disagreements >= patience or satisfaction <= 0.0:
		return _walk_out()
	if concessions_used < concessions_max and ask > floor_price:
		var step: Vector2 = PERSONALITIES[personality]["step"]
		ask = maxi(floor_price, roundi(ask * (1.0 - randf_range(step.x, step.y))))
		concessions_used += 1
		ask_changed.emit(ask)
		if offer >= ask:
			return _close_deal(ask)
		return _result("counter")
	return _result("firm")


func accept_ask() -> Dictionary:
	return _result("over") if is_over else _close_deal(ask)


func send_away() -> Dictionary:
	return _result("over") if is_over else _walk_out()


func get_anger() -> float:
	return 1.0 - satisfaction / 100.0


func get_profit() -> int:
	return 0 # Compatibility only: purchases have no realized profit.


func _close_deal(price: int) -> Dictionary:
	is_over = true
	deal_price = price
	finished.emit("deal", price)
	return _result("deal")


func _walk_out() -> Dictionary:
	is_over = true
	finished.emit("left", 0)
	return _result("left")


func _result(kind: String) -> Dictionary:
	return {"result": kind, "ask": ask, "price": deal_price, "satisfaction": satisfaction, "anger": get_anger(), "disagreements": disagreements}
