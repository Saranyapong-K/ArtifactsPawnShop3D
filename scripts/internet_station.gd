extends Area3D
## Floating website icon; reuses the existing computer-shop UI.
var _base_y := 0.0
var _seconds := 0.0
var _visual: Node3D
var _label: Label3D
signal activated

func setup(at: Vector3) -> void:
	global_position = at; _base_y = at.y
	collision_layer = 1; collision_mask = 0
	var data := ArtifactData.create("res://ui/Internet.glb", "Internet", "Common", "normal", Vector2i(2,2))
	_visual = ArtifactVisual.create(data, 0.5, 0.8, false)
	add_child(_visual)
	var bounds := ArtifactVisual.local_bounds(_visual)
	_visual.position = -bounds.get_center()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = bounds.size + Vector3.ONE*0.08
	shape.shape = box; add_child(shape)
	_label = Label3D.new(); _label.font_size = 32; _label.outline_size=6
	_label.pixel_size = 0.0026; _label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = bounds.size.y*0.5+0.16
	_label.hide(); add_child(_label)

func interact(_player: Node) -> void: activated.emit()

func _process(delta: float) -> void:
	_seconds += delta
	position.y = _base_y + sin(_seconds*1.4)*0.045
	if _visual: _visual.rotation.y += delta*0.35
	if not _label: return
	_label.text = "Press %s to browse" % GameSettings.key_name("interact")
	var player := get_tree().get_first_node_in_group("shop_player")
	_label.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player and player.get_interaction_target() == self
