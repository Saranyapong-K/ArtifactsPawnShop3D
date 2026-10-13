extends StaticBody3D

signal activated
@export var title: String = "Interact"
var _label: Label3D

func setup(text: String, position: Vector3, color: Color) -> void:
	title = text
	global_position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.3, 0.35)
	shape.shape = box
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var model := BoxMesh.new()
	model.size = box.size
	mesh.mesh = model
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	add_child(mesh)
	_label = Label3D.new()
	_label.text = text + "\nE"
	_label.font_size = 26
	_label.pixel_size = 0.0026
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 0.35
	_label.visible = false
	add_child(_label)

func setup_book(position: Vector3, source: PackedScene) -> void:
	title = "Shop Management"
	global_position = position
	var data := ArtifactData.create(source.resource_path, title, "Common", "normal", Vector2i(2,1))
	var visual := ArtifactVisual.create(data, 0.18, 0.8, false)
	add_child(visual)
	var bounds := ArtifactVisual.local_bounds(visual)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3(0.15,0.08,0.15))
	collision.shape = box
	collision.position = bounds.get_center()
	add_child(collision)
	_label = Label3D.new()
	_label.font_size = 32
	_label.pixel_size = 0.0026
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = bounds.end.y + 0.14
	_label.hide()
	add_child(_label)

func interact(_player: Node) -> void:
	activated.emit()

func _process(_delta: float) -> void:
	if not _label:
		return
	_label.visible = false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var player: Node = get_tree().root.find_child("Player", true, false)
	_label.text = title + "\n" + GameSettings.key_name("interact")
	_label.visible = player != null and player.has_method("get_interaction_target") and player.get_interaction_target() == self
