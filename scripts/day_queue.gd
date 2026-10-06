class_name DayQueue
extends RefCounted
## Builds the list of customers for one day.
## The last or second-to-last relic is always a jackpot.

const MARKET_PRICES := [80, 120, 200, 350, 500, 800]


static func build(count: int = 5) -> Array[Haggle]:
	var jackpot_index := count - 1 - randi_range(0, 1)
	var queue: Array[Haggle] = []
	for i in count:
		var market: int = MARKET_PRICES.pick_random()
		var is_jackpot := i == jackpot_index
		# jackpot customer is patient, so the big reveal isn't lost to a walk-out
		queue.append(Haggle.new(market, is_jackpot, "easygoing" if is_jackpot else ""))
	return queue
