extends Node3D
## Camera-framed presentation, separate from the artifact's saved placement.
var _camera: Camera3D
var _visual: Node3D
var _pivot: Node3D
var _inspect := false
var _moving: Tween
var _rest_rotation := Vector3.ZERO
const INSPECTION_DISTANCE := 1.25
const MIN_DISTANCE := 0.85
const MAX_DISTANCE := 2.0
var _distance := INSPECTION_DISTANCE
var _pan := Vector2.ZERO
var _drag_button := 0
var _auto_turn := false
var _radius := 0.3

func setup(artifact: ArtifactData, camera: Camera3D) -> void:
	_camera = camera
	_pivot = Node3D.new(); add_child(_pivot)
	_visual = ArtifactVisual.create(artifact)
	_pivot.add_child(_visual)
	var bounds := ArtifactVisual.local_bounds(_visual)
	if bounds.size.y < maxf(bounds.size.x,bounds.size.z)*0.35: _visual.rotation.x=-PI*0.38
	_visual.rotation.y=0.22
	bounds = Transform3D(_visual.basis,Vector3.ZERO)*ArtifactVisual.local_bounds(_visual)
	var factor := 0.55/maxf(maxf(bounds.size.x,bounds.size.y),maxf(bounds.size.z,0.001))
	_visual.scale=Vector3.ONE*factor
	_visual.position=-bounds.get_center()*factor
	_radius=bounds.size.length()*factor*0.5
	_rest_rotation=Vector3.ZERO
	global_basis=camera.global_basis
	global_position=_position(false)

func _position(inspect: bool) -> Vector3:
	return _camera.to_global(Vector3(_pan.x,_pan.y,-_distance) if inspect else Vector3(-0.62,0.28,-2.0))

func set_inspection(inspect: bool, animate:=true) -> void:
	_inspect=inspect
	_drag_button=0
	_auto_turn=inspect
	_pan=Vector2.ZERO
	_distance=INSPECTION_DISTANCE
	if _moving and _moving.is_valid(): _moving.kill()
	var target := Transform3D(_camera.global_basis, _position(inspect))
	if animate:
		_moving=create_tween().set_parallel(true)
		_moving.tween_property(self,"global_transform",target,0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		if not inspect: _moving.tween_property(_pivot,"rotation",_rest_rotation,0.35)
	else:
		global_transform=target
		if not inspect: _pivot.rotation=_rest_rotation

func _process(delta: float) -> void:
	if _inspect and _auto_turn and _pivot: _pivot.rotation.y += delta*0.25

func _can_manipulate() -> bool:
	if not _inspect or not _camera or not _camera.current or get_tree().paused:
		return false
	if get_tree().get_first_node_in_group("active_game_modal"):
		return false
	var state := get_node_or_null("/root/GameState")
	return state == null or not bool(state.get("failed"))

func _begin_manipulation() -> void:
	_auto_turn=false
	if _moving and _moving.is_valid(): _moving.kill()
	global_position=_position(true)

func _clamp_pan() -> void:
	var screen := _camera.get_viewport().get_visible_rect().size
	var half_height := tan(deg_to_rad(_camera.fov)*0.5)*_distance
	var half_width := half_height*screen.x/maxf(screen.y,1)
	var limits := Vector2(minf(0.4,maxf(0,half_width-_radius-0.04)),minf(0.3,maxf(0,half_height-_radius-0.04)))
	_pan=_pan.clamp(-limits,limits)

func _unhandled_input(event: InputEvent) -> void:
	if not _can_manipulate():
		_drag_button=0
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				_begin_manipulation()
				_drag_button=event.button_index
			elif event.button_index==_drag_button:
				_drag_button=0
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_begin_manipulation()
			var direction := -1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0
			_distance=clampf(_distance+direction*0.12*maxf(event.factor,1),MIN_DISTANCE,MAX_DISTANCE)
			_clamp_pan()
			global_position=_position(true)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag_button!=0:
		var mask := MOUSE_BUTTON_MASK_LEFT if _drag_button==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		if (event.button_mask & mask)==0:
			_drag_button=0
			return
		if _drag_button==MOUSE_BUTTON_LEFT:
			_pivot.basis=(Basis(Vector3.RIGHT,event.relative.y*0.01)*Basis(Vector3.UP,event.relative.x*0.01)*_pivot.basis).orthonormalized()
		else:
			var height := maxf(_camera.get_viewport().get_visible_rect().size.y,1)
			var units := 2*tan(deg_to_rad(_camera.fov)*0.5)*_distance/height
			_pan+=Vector2(event.relative.x,-event.relative.y)*units
			_clamp_pan()
			global_position=_position(true)
		get_viewport().set_input_as_handled()
