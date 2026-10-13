class_name Customer
extends Node3D
## Attach to the ROOT of npcs_1.tscn (the NPCS1 node).
## Finds AnimationPlayer and the Head mesh by name, so no wiring needed.

signal interacted   # player pressed E on this customer

# These animations are set to loop automatically
const LOOPING := ["idle", "walk", "talk", "angry"]

@export var walk_speed := 1.6
@export_range(1, 12, 0.5) var turn_speed := 5.0
@export_range(1, 12, 0.5) var walk_acceleration := 3.5
## glTF models usually face +Z. If the customer walks backward, untick this.
@export var model_faces_plus_z := true

## Height of the floating E above the customer's feet. Raise it if it's inside the head.
@export var prompt_height := 2.2
## Size of the happy image in metres (its longest side).
@export var happy_size := 0.4
@export_range(0, 2.5, 0.05) var target_height := 0.0
@export var walk_animation := "walk"
@export var idle_animation := "idle"

var anim: AnimationPlayer
var head: MeshInstance3D
var can_interact := false
var _anger_mat: StandardMaterial3D
var _play_id := 0
var _prompt: Label3D
var _prompt_tween: Tween
var _heart_tex: ImageTexture
var _walk_path := PackedVector3Array()
var _walk_index := 0
var _walk_ticket := 0
var _move_speed := 0.0
var _walk_target := Vector3.ZERO
var _walk_failed := false
var _route_revision := -1
var _repath_delay := 0.0
var _blocked_seconds := 0.0
var _counter_lift := 0.0
var _counter_step: MeshInstance3D


func _ready() -> void:
	add_to_group("shop_visitors")
	anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if target_height > 0:
		var bounds := ArtifactVisual.local_bounds(self)
		if bounds.size.y > 0.01: scale *= target_height / bounds.size.y
		prompt_height = (target_height + 0.25) / scale.y
	set_meta("character_height", target_height if target_height > 0 else 1.75)
	# any mesh whose name starts with "Head" (Blender renames duplicates to Head.001 etc.)
	var heads := find_children("Head*", "MeshInstance3D", true, false)
	head = heads[0] as MeshInstance3D if heads.size() > 0 else find_child("Goblin*", true, false) as MeshInstance3D

	if anim:
		for n in LOOPING:
			if anim.has_animation(n):
				anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	else:
		push_warning("Customer: no AnimationPlayer found")

	# Red tint laid over the head. Alpha 0 = invisible, grows with anger.
	_anger_mat = StandardMaterial3D.new()
	_anger_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_anger_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_anger_mat.albedo_color = Color(1.0, 0.1, 0.05, 0.0)
	if head:
		head.material_overlay = _anger_mat

	_build_interact_body()
	_build_prompt()
	play("idle")


# ---------- E interaction ----------

## The player's ray hits this body, then finds interact() on this node.
func _build_interact_body() -> void:
	var body := StaticBody3D.new()
	body.name = "InteractBody"
	var capsule := CapsuleShape3D.new()
	capsule.radius = (0.18 if target_height < 1.0 else 0.28) / scale.y if target_height > 0 else 0.4
	capsule.height = target_height / scale.y if target_height > 0 else 1.7
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	body.add_child(shape)
	add_child(body)


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.text = "E"
	_prompt.font_size = 80
	_prompt.pixel_size = 0.006
	_prompt.outline_size = 10
	_prompt.modulate = Color("ffffffff")
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.position = Vector3(0.0, prompt_height, 0.0)
	_prompt.visible = false
	add_child(_prompt)


## Show or hide the floating E (it bobs up and down).
func set_interactable(value: bool) -> void:
	can_interact = value
	_prompt.visible = value
	if _prompt_tween and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_prompt.position.y = prompt_height
	if value:
		_prompt_tween = create_tween().set_loops()
		_prompt_tween.tween_property(_prompt, "position:y", prompt_height + 0.12, 0.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_prompt_tween.tween_property(_prompt, "position:y", prompt_height, 0.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Called by player.gd when E is pressed while looking at this customer.
func interact(_player: Node) -> void:
	if can_interact:
		interacted.emit()


# ---------- animation / movement ----------

func play(anim_name: String, blend: float = 0.2) -> void:
	_play_id += 1
	var clip: String = walk_animation if anim_name == "walk" else idle_animation if anim_name == "idle" else anim_name
	if anim and not anim.has_animation(clip) and anim_name != "walk" and anim.has_animation(idle_animation):
		clip = idle_animation
	if anim and anim.has_animation(clip):
		if anim_name in LOOPING: anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		anim.play(clip, blend)
	elif anim:
		anim.stop() # Supplied goblins stand still when they have no idle/talk clip.


## One-shot animation (agree, disagree, show_relic), then back to another one.
func play_once(anim_name: String, then: String = "idle") -> void:
	if not anim or not anim.has_animation(anim_name):
		return
	play(anim_name)
	var id := _play_id
	await anim.animation_finished
	if id == _play_id:   # nothing else started meanwhile
		play(then)


## Loop an animation for a few seconds, then go to another one.
## (play_once can't be used for looping animations, they never "finish".)
func play_for(anim_name: String, seconds: float, then: String = "idle") -> void:
	if not anim or not anim.has_animation(anim_name):
		return
	play(anim_name)
	var id := _play_id
	await get_tree().create_timer(seconds).timeout
	if id == _play_id:
		play(then)


# ---------- happy effect ----------

## Small burst of hearts (or your own PNG) above the head.
func show_happy(tex: Texture2D = null, count: int = 3) -> void:
	for i in count:
		_spawn_heart(tex, i)
		await get_tree().create_timer(0.15).timeout


func _spawn_heart(tex: Texture2D, i: int) -> void:
	var t: Texture2D = tex if tex else _get_heart_texture()
	var sprite := Sprite3D.new()
	sprite.texture = t
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.pixel_size = happy_size / float(maxi(t.get_width(), t.get_height()))
	sprite.scale = Vector3.ZERO
	var x := (i - 1) * 0.25 + randf_range(-0.05, 0.05)
	sprite.position = Vector3(x, prompt_height - 0.2, 0.0)
	add_child(sprite)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "scale", Vector3.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position:y", sprite.position.y + 0.6, 1.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.5).set_delay(0.9)
	tw.chain().tween_callback(sprite.queue_free)


## Fallback pink heart drawn in code, used when no PNG is assigned.
func _get_heart_texture() -> ImageTexture:
	if _heart_tex:
		return _heart_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for py in n:
		for px in n:
			var x := (px / float(n - 1) - 0.5) * 2.6
			var y := (0.5 - py / float(n - 1)) * 2.6 + 0.1
			var v := pow(x * x + y * y - 1.0, 3.0) - x * x * y * y * y
			if v <= 0.0:
				img.set_pixel(px, py, Color("ff4d6d"))
	_heart_tex = ImageTexture.create_from_image(img)
	return _heart_tex


## 0.0 calm -> 1.0 furious. Connect to day_manager.customer_anger_changed.
func set_anger(anger: float) -> void:
	_anger_mat.albedo_color.a = clampf(anger, 0.0, 1.0) * 0.55


func walk_to(target: Vector3) -> bool:
	_walk_ticket+=1
	var token := _walk_ticket
	_walk_target = target
	_walk_failed = false
	_blocked_seconds = 0.0
	var navigation := get_tree().get_first_node_in_group("shop_navigation")
	_walk_path = navigation.route(global_position,target,self) if navigation else PackedVector3Array([target])
	_route_revision = navigation.revision if navigation else -1
	_walk_index=0
	_move_speed=0.0
	if _walk_path.is_empty(): return false
	play("walk")
	while token==_walk_ticket and _walk_index<_walk_path.size(): await get_tree().process_frame
	if token==_walk_ticket: play("idle")
	return token == _walk_ticket and not _walk_failed and Vector2(global_position.x - target.x, global_position.z - target.z).length() <= 0.45

func _process(delta: float) -> void:
	if _prompt: _prompt.text = GameSettings.key_name("interact")
	if _walk_index>=_walk_path.size(): return
	if GameState.is_time_paused() and not bool(get_meta("shop_serving",false)): return
	var navigation := get_tree().get_first_node_in_group("shop_navigation")
	_repath_delay = maxf(0.0, _repath_delay - delta)
	if navigation and _repath_delay == 0 and (navigation.dirty or navigation.revision != _route_revision):
		_replan(navigation)
		if _walk_path.is_empty(): return
	var target := _walk_path[_walk_index]
	var difference := target-global_position
	if difference.length()<0.04:
		_walk_index+=1
		return
	var angle:=atan2(difference.x,difference.z)+(0.0 if model_faces_plus_z else PI)
	rotation.y=lerp_angle(rotation.y,angle,1.0-exp(-turn_speed*delta))
	var remaining:=difference.length()
	for i in range(_walk_index,_walk_path.size()-1): remaining+=_walk_path[i].distance_to(_walk_path[i+1])
	var desired_speed:=minf(walk_speed,sqrt(2.0*walk_acceleration*remaining))
	_move_speed=move_toward(_move_speed,desired_speed,walk_acceleration*delta)
	# Consume short waypoints in the same frame instead of pausing at every cell.
	var distance_left:=_move_speed*delta
	while distance_left>0.0001 and _walk_index<_walk_path.size():
		var point:=_walk_path[_walk_index]
		var step:=global_position.distance_to(point)
		var next_position := global_position.move_toward(point, minf(step, distance_left))
		if navigation and not navigation.motion_clear(global_position, next_position, self):
			navigation.dirty = true
			_blocked_seconds += delta
			if _blocked_seconds > 2.0:
				_walk_failed = true; _walk_path.clear(); _walk_index = 0
			elif _repath_delay == 0: _replan(navigation)
			return
		_blocked_seconds = 0.0
		if step<=distance_left:
			global_position=point
			distance_left-=step
			_walk_index+=1
		else:
			global_position=global_position.move_toward(point,distance_left)
			distance_left=0.0

func _replan(navigation: Node) -> void:
	_repath_delay = 0.25
	_walk_path = navigation.route(global_position, _walk_target, self)
	_walk_index = 0
	_route_revision = navigation.revision
	if _walk_path.is_empty(): _walk_failed = true


func face_toward(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) < 0.01:
		return
	look_at(flat, Vector3.UP)
	if model_faces_plus_z:
		rotate_y(PI)

func set_at_counter(on: bool) -> void:
	if target_height <= 0 or target_height >= 1.2: return
	if on and _counter_lift == 0:
		# A half-height customer needs a step to see over the human-sized counter.
		_counter_lift = 0.45
		global_position.y += _counter_lift
		if _counter_step == null:
			_counter_step = MeshInstance3D.new()
			_counter_step.name = "CounterStep"
			var box := BoxMesh.new()
			box.size = Vector3(0.55, _counter_lift, 0.45) / scale.y
			_counter_step.mesh = box
			var wood := StandardMaterial3D.new()
			wood.albedo_color = Color("845135"); wood.roughness = 1.0
			_counter_step.material_override = wood
			add_child(_counter_step)
		_counter_step.position.y = -_counter_lift * 0.5 / scale.y
		_counter_step.show()
	elif not on and _counter_lift > 0:
		global_position.y -= _counter_lift
		_counter_lift = 0.0
		if _counter_step: _counter_step.hide()
