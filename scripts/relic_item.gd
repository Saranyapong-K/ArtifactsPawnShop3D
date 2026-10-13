extends StaticBody3D
## A persistent artifact occupying a snapped footprint; E transfers it to placement.

var artifact: ArtifactData
var visual: Node3D
var highlighted: bool = false
var _label: Label3D

func setup_artifact(data: ArtifactData) -> void:
	artifact = data
	name = "Relic_" + artifact.id
	add_to_group("relic_items")
	visual = ArtifactVisual.create(artifact)
	add_child(visual)
	var shape := CollisionShape3D.new()
	shape.name = "InteractionCollision"
	var box := BoxShape3D.new()
	var height: float = float(visual.get_meta("height", 0.3))
	box.size = Vector3(artifact.grid_size.x * ArtifactVisual.CELL_SIZE * 0.92, height, artifact.grid_size.y * ArtifactVisual.CELL_SIZE * 0.92)
	shape.shape = box
	shape.position.y = height * 0.5
	add_child(shape)
	_label = Label3D.new()
	_label.text = "%s\nCost %d G • Listed %d G\n%s / Pick up" % [artifact.display_name, artifact.cost, artifact.sell_price, GameSettings.key_name("interact")]
	_label.font_size = 32
	_label.pixel_size = 0.0026
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = height + 0.12
	_label.visible = false
	add_child(_label)

func interact(_player: Node) -> void:
	var placement: Node = get_tree().get_first_node_in_group("artifact_placement")
	if placement:
		placement.pick_up(self)

func set_highlighted(value: bool) -> void:
	highlighted = value
	if not value and visual:
		visual.rotation.y = 0.0

func _process(delta: float) -> void:
	if visual and highlighted:
		visual.rotation.y += delta * 0.8
	if not _label or not artifact:
		return
	_label.text = "%s\nCost %d G • Listed %d G\n%s / Pick up" % [artifact.display_name, artifact.cost, artifact.sell_price, GameSettings.key_name("interact")]
	_label.visible = false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or collision_layer == 0:
		return
	var player: Node = get_tree().root.find_child("Player", true, false)
	_label.visible = player != null and player.has_method("get_interaction_target") and player.get_interaction_target() == self
