class_name BuyerHaggle
extends RefCounted
## Buyer offers use the player's listing, without a hidden artifact value.

signal anger_changed(anger: float)
signal ask_changed(new_ask: int)
signal finished(outcome: String, price: int)

var artifact: ArtifactData
var market_price: int
var ask: int
var start_ask: int
var max_budget: int
var deal_price: int = 0
var satisfaction: float = 100.0
var disagreements: int = 0
var patience: int = 5
var is_over: bool = false
var personality: String = "buyer"


func _init(item: ArtifactData) -> void:
	artifact = item
	market_price = clampi(item.sell_price, 1, item.max_sell_price())
	var ratio := randf_range(0.50, 0.60)
	ask = clampi(roundi(market_price * ratio), 1, item.max_sell_price())
	start_ask = ask
	# Low opening offers, but most buyers accept the listing without extra rounds.
	max_budget = roundi(market_price * (randf_range(1.0, 1.10) if randf() < 0.90 else randf_range(0.90, 1.0)))
	max_budget = clampi(maxi(max_budget, ask), 1, item.max_sell_price())


func apply_cleanliness(bonus: float) -> void:
	if is_over: return
	var multiplier := 1.0 + clampf(bonus, 0.0, 0.06)
	ask = clampi(roundi(ask * multiplier), 1, mini(artifact.max_sell_price(),maxi(1,roundi(market_price*0.60))))
	start_ask = ask
	max_budget = clampi(maxi(ask, roundi(max_budget * multiplier)), 1, mini(artifact.max_sell_price(),maxi(1,roundi(market_price*1.10))))

func make_offer(price: int) -> Dictionary:
	if is_over:
		return _result("over")
	if price > 0 and price <= max_budget and price <= artifact.max_sell_price():
		return _close_deal(price)
	disagreements += 1
	satisfaction = maxf(0.0, satisfaction - 15.0)
	anger_changed.emit(get_anger())
	if disagreements >= patience:
		return _walk_out()
	if ask < max_budget:
		ask = mini(max_budget, ask + maxi(1, ceili(float(max_budget - ask) * 0.5)))
		ask_changed.emit(ask)
		return _result("counter")
	return _result("firm")


func accept_ask() -> Dictionary:
	return _result("over") if is_over else _close_deal(ask)


func send_away() -> Dictionary:
	return _result("over") if is_over else _walk_out()


func get_anger() -> float:
	return 1.0 - satisfaction / 100.0


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
