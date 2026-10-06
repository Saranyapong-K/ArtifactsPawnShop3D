extends Node
## TEMPORARY test. Simulates a day with a bot player and prints the result.


func _ready() -> void:
	var queue := DayQueue.build(5)
	var total := 0

	for i in queue.size():
		var h: Haggle = queue[i]
		print("--- Customer %d (%s) market=%d ask=%d floor=%d" % [i + 1, h.personality, h.market_price, h.ask, h.floor_price])

		var offer := int(h.market_price * 0.6)
		while not h.is_over:
			var res := h.make_offer(offer)
			print("  offer %d -> %s | ask %d | anger %.2f" % [offer, res["result"], res["ask"], res["anger"]])
			offer = int(offer * 1.1)

		if h.deal_price > 0:
			var profit := h.get_profit()
			total += profit
			print("  REVEAL true=%d paid=%d profit=%d" % [h.true_value, h.deal_price, profit])
		else:
			print("  customer left")

	print("DAY TOTAL: %d" % total)
