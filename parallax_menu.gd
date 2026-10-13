extends Node2D

@onready var bg: Node2D = $Parallax2D_BG
@onready var mid: Node2D = $Parallax2D_Mid
@onready var fore: Node2D = $Parallax2D_Fore

@export var back_factor: float = 15.0
@export var mid_factor: float = 35.0
@export var front_factor: float = 60.0

func _process(delta: float) -> void:
	var center = get_viewport_rect().size / 2.0
	var mouse_pos = get_viewport().get_mouse_position()
	var offset = (mouse_pos - center) / center
	
	bg.position = bg.position.lerp(offset * back_factor, delta * 2.0)
	mid.position = mid.position.lerp(offset * mid_factor, delta * 0.5)
	fore.position = fore.position.lerp(offset * front_factor, delta * 0.05)
