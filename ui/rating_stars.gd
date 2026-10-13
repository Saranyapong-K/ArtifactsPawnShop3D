@tool
extends Control
## Draw symbols directly so the six-star rating needs no platform font fallback.
@export_range(0, 6) var rating := 3:
	set(value):
		rating = clampi(value, 0, 6)
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var radius := minf(12.0, size.y * 0.36)
	for index in 6:
		var center := Vector2(radius + index * (radius * 2.3), size.y * 0.5)
		var points := PackedVector2Array()
		for corner in 10:
			var angle := -PI * 0.5 + corner * PI / 5.0
			points.append(center + Vector2(cos(angle),sin(angle)) * radius * (1.0 if corner % 2 == 0 else 0.44))
		if index < rating: draw_colored_polygon(points, Color("f7d475"))
		points.append(points[0])
		draw_polyline(points, Color("78451d") if index < rating else Color("ac8052"), 1.5, true)
