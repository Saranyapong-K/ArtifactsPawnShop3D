class_name Haggle
extends RefCounted
## One customer selling ONE relic to the player.
## No UI in here. UI listens to the signals and calls make_offer().

signal anger_changed(anger: float)      # 0.0 calm -> 1.0 furious (use for red head)
signal ask_changed(new_ask: int)        # NPC lowered its price
signal finished(outcome: String, price: int)  # "deal" or "left"

const FLOOR_RATIO := 0.8   # NPC never goes lower than 80% of its opening ask
const MAX_LOWBALLS := 3    # 4th lowball and the NPC leaves

# ask = ask range vs market price | concessions = how many times NPC may lower
# patience = disagreements before leaving | anger = how fast satisfaction drops
# step = % the ask drops per concession
const PERSONALITIES := {
	"greedy":    {"ask": Vector2(1.15, 1.40), "concessions": Vector2i(1, 1), "patience": Vector2i(5, 5), "anger": 1.0, "step": Vector2(0.03, 0.05)},
	"desperate": {"ask": Vector2(0.80, 1.00), "concessions": Vector2i(3, 3), "patience": Vector2i(6, 6), "anger": 0.8, "step": Vector2(0.04, 0.06)},
	"stubborn":  {"ask": Vector2(0.95, 1.15), "concessions": Vector2i(1, 2), "patience": Vector2i(6, 6), "anger": 1.0, "step": Vector2(0.02, 0.04)},
	"easygoing": {"ask": Vector2(0.90, 1.10), "concessions": Vector2i(3, 3), "patience": Vector2i(5, 5), "anger": 0.6, "step": Vector2(0.04, 0.06)},
	"hothead":   {"ask": Vector2(0.95, 1.20), "concessions": Vector2i(2, 2), "patience": Vector2i(5, 5), "anger": 1.8, "step": Vector2(0.03, 0.05)},
}

var personality: String
var market_price: int      # public baseline, player can see it
var true_value: int        # HIDDEN until the reveal
var start_ask: int
var ask: int               # NPC's current asking price
var floor_price: int
var satisfaction := 100.0
var concessions_used := 0
var concessions_max := 0
var patience := 5
var disagreements := 0
var lowballs := 0
var is_over := false
var deal_price := 0
var relic_scale := 1.0     # how big the relic looks (pricier = more bizarre)


func _init(p_market: int, jackpot: bool = false, p_personality: String = "") -> void:
	market_price = p_market
	if p_personality != "":
		personality = p_personality
	else:
		personality = String(PERSONALITIES.keys().pick_random())

	var p: Dictionary = PERSONALITIES[personality]
	var ask_range: Vector2 = p["ask"]
	var conc_range: Vector2i = p["concessions"]
	var pat_range: Vector2i = p["patience"]

	start_ask = roundi(market_price * randf_range(ask_range.x, ask_range.y))
	ask = start_ask
	floor_price = roundi(start_ask * FLOOR_RATIO)
	concessions_max = randi_range(conc_range.x, conc_range.y)
	patience = randi_range(pat_range.x, pat_range.y)
	true_value = roundi(market_price * _roll_multiplier(jackpot))
	var tier := clampf((market_price - 80.0) / 720.0, 0.0, 1.0)
	relic_scale = clampf(pow(2.0, randf_range(-1.0, 1.0) * (0.3 + 1.2 * tier)), 0.3, 2.5)


func _roll_multiplier(jackpot: bool) -> float:
	if jackpot:
		return randf_range(2.5, 5.0)
	var r := randf()
	if r < 0.3:
		return randf_range(0.3, 0.7)   # dud / fake
	elif r < 0.8:
		return randf_range(0.8, 1.3)   # normal
	return randf_range(1.5, 2.2)       # nice find


## Player proposes a price. Returns a Dictionary, read ["result"]:
## "deal" | "counter" (NPC lowered ask) | "firm" (NPC refuses to move) | "left"
func make_offer(offer: int) -> Dictionary:
	if is_over:
		return _result("over")

	if offer >= ask:
		return _close_deal(ask)

	# Player offered less than the ask
	disagreements += 1
	var is_lowball := offer < floor_price
	if is_lowball:
		lowballs += 1

	var gap := float(ask - offer) / ask
	var anger_mult: float = PERSONALITIES[personality]["anger"]
	satisfaction = maxf(0.0, satisfaction - maxf(3.0, gap * 40.0) * anger_mult)
	anger_changed.emit(get_anger())

	if lowballs > MAX_LOWBALLS or disagreements >= patience or satisfaction <= 0.0:
		return _walk_out()

	# NPC may lower its ask
	if concessions_used < concessions_max and ask > floor_price:
		var step: Vector2 = PERSONALITIES[personality]["step"]
		ask = maxi(floor_price, roundi(ask * (1.0 - randf_range(step.x, step.y))))
		concessions_used += 1
		ask_changed.emit(ask)
		if offer >= ask:
			return _close_deal(ask)
		return _result("counter")

	return _result("firm")


## Player clicks "Accept" on the NPC's current ask.
func accept_ask() -> Dictionary:
	if is_over:
		return _result("over")
	return _close_deal(ask)


## Player clicks "Reject / send away".
func send_away() -> Dictionary:
	if is_over:
		return _result("over")
	return _walk_out()


func get_anger() -> float:
	return 1.0 - satisfaction / 100.0


## Call AFTER the deal for the reveal.
func get_profit() -> int:
	return true_value - deal_price


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
	return {
		"result": kind,
		"ask": ask,
		"satisfaction": satisfaction,
		"anger": get_anger(),
		"disagreements": disagreements,
	}
