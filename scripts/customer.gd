class_name Customer
extends Node3D
## Attach to the ROOT of npcs_1.tscn (the NPCS1 node).
## Finds AnimationPlayer and the Head mesh by name, so no wiring needed.

signal interacted   # player pressed E on this customer

# These animations are set to loop automatically
const LOOPING := ["idle", "walk", "talk", "angry"]

@export var walk_speed := 1.6
## glTF models usually face +Z. If the customer walks backward, untick this.
@export var model_faces_plus_z := true

## Height of the floating E above the customer's feet. Raise it if it's inside the head.
@export var prompt_height := 2.2
## Size of the happy image in metres (its longest side).
@export var happy_size := 0.4

var anim: AnimationPlayer
var head: MeshInstance3D
var can_interact := false
var _anger_mat: StandardMaterial3D
var _play_id := 0
var _prompt: Label3D
var _prompt_tween: Tween
var _heart_tex: ImageTexture


func _ready() -> void:
	anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	# any mesh whose name starts with "Head" (Blender renames duplicates to Head.001 etc.)
	var heads := find_children("Head*", "MeshInstance3D", true, false)
	head = heads[0] as MeshInstance3D if heads.size() > 0 else null

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
	else:
		push_warning("Customer: no node named Head found")

	_build_interact_body()
	_build_prompt()
	play("idle")


# ---------- E interaction ----------

## The player's ray hits this body, then finds interact() on this node.
func _build_interact_body() -> void:
	var body := StaticBody3D.new()
	body.name = "InteractBody"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.7
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.85
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
	if anim and anim.has_animation(anim_name):
		anim.play(anim_name, blend)


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


func walk_to(target: Vector3) -> void:
	var dist := global_position.distance_to(target)
	if dist < 0.05:
		return
	face_toward(target)
	play("walk")
	var t := create_tween()
	t.tween_property(self, "global_position", target, dist / walk_speed)
	await t.finished


func face_toward(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) < 0.01:
		return
	look_at(flat, Vector3.UP)
	if model_faces_plus_z:
		rotate_y(PI)
