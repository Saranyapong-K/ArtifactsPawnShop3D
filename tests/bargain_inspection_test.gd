extends SceneTree
## The artifact moves in inspection; the player and bargain camera stay still.
const OUT := "C:/Users/Syrins/Documents/Codex/2026-10-10/hee/work/artifact-drag-inspection-2026-10-14/"
var checks := 0
var failures := 0
var state: Node
var main: Node3D
var manager: Node
var player: CharacterBody3D
var artifact: ArtifactData
var cursor := Vector2(576,324)
func _init(): run.call_deferred()
func check(ok: bool, message: String):
	checks+=1
	if not ok: failures+=1; push_error(message)
func frames(count:=4):
	for i in count: await process_frame
func key(code: int):
	var event:=InputEventKey.new(); event.physical_keycode=code; event.keycode=code; event.pressed=true; Input.parse_input_event(event)
	await process_frame
	event=InputEventKey.new(); event.physical_keycode=code; event.keycode=code; event.pressed=false; Input.parse_input_event(event)
	await frames()
func button(index: int, down:=true):
	var event:=InputEventMouseButton.new(); event.position=cursor; event.button_index=index; event.pressed=down
	Input.parse_input_event(event); await frames()
func motion(delta: Vector2, mask:=0):
	cursor+=delta
	var event:=InputEventMouseMotion.new(); event.position=cursor; event.relative=delta; event.button_mask=mask
	Input.parse_input_event(event); await frames()
func drag(index: int, delta: Vector2):
	await button(index)
	await motion(delta,MOUSE_BUTTON_MASK_LEFT if index==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT)
	await button(index,false)
func snap(name: String):
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
func prepare():
	if is_instance_valid(main): main.queue_free(); await frames(6)
	state.new_game(); state.set_process(false); state.owned_items.magnifier=true; state.money=1000
	change_scene_to_file("res://assets/Scene/main.tscn"); await frames(8)
	main=current_scene; manager=main.get_node("Day_manager"); player=manager.player
	manager._epoch+=1; manager.flow.close_shop(); manager.flow.set_process(false)
	await frames()
	var customer: Node3D=load("res://npcs_1.tscn").instantiate(); main.add_child(customer)
	customer.global_position=manager.cashier_spot.global_position; customer.play("idle")
	artifact=ArtifactData.create("res://assets/Relics/Iphone.glb","IP17","Rare","broken",Vector2i(1,2))
	manager.customer=customer; manager.current=Haggle.new(40,false,"easygoing",artifact); manager._buyer=false
	manager._spawn_relic(); manager._open_bargain_ui(); await create_timer(0.4).timeout
	cursor=Vector2(576,324)
func run():
	if not OS.get_user_data_dir().contains("artifact-drag-tests"): quit(9); return
	root.position=Vector2i(-16000,-16000); root.size=Vector2i(1152,648)
	state=root.get_node("GameState"); state.save_path="user://artifact-drag.json"
	await prepare()
	var holder: Node3D=manager.relic_holder
	var original:=holder.global_transform
	var price: float=manager.ui._slider.value
	await key(KEY_TAB); await create_timer(0.4).timeout
	var camera_pose: Transform3D=manager.bargain_cam.global_transform
	var body_position:=player.global_position
	var yaw:=player.rotation.y; var pitch: float=player.head.rotation.x
	check(manager.ui._panel_hidden and not player.controls_enabled and manager.bargain_cam.current and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Hiding the book keeps the player stationary, camera fixed and cursor available")
	check(not paused and not state.is_time_paused(),"Artifact inspection leaves the game and clock running")
	check(is_equal_approx(holder.global_position.distance_to(manager.bargain_cam.global_position),1.25) and manager.bargain_cam.unproject_position(holder.global_position).distance_to(Vector2(576,324))<2,"Artifact starts close and centered in the bargain view")
	check("Right-drag: move" in manager.game_ui._hint_label.text and "Scroll: zoom" in manager.game_ui._hint_label.text,"Existing footer explains artifact controls instead of walking")
	await snap("inspection-centered")
	await motion(Vector2(12,5))
	Input.action_press("move_right"); await create_timer(0.2).timeout; Input.action_release("move_right")
	check(Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(body_position.x,body_position.z))<0.01 and is_equal_approx(player.rotation.y,yaw) and is_equal_approx(player.head.rotation.x,pitch),"Mouse motion and WASD do not move or turn the player during inspection")
	var basis_before: Basis=holder._pivot.basis
	await drag(MOUSE_BUTTON_LEFT,Vector2(70,30))
	check(not holder._pivot.basis.is_equal_approx(basis_before),"Real left-drag rotates the offered artifact")
	var released: Basis=holder._pivot.basis
	await motion(Vector2(5,3)); await create_timer(0.2).timeout
	check(holder._pivot.basis.is_equal_approx(released),"After release the chosen artifact angle stays still")
	var pos_before:=holder.global_position
	await drag(MOUSE_BUTTON_RIGHT,Vector2(25,-20))
	check(holder.global_position.distance_to(pos_before)>0.03,"Real right-drag moves the artifact across the inspection view")
	check(holder._pivot.basis.is_equal_approx(released),"Moving the artifact preserves its chosen rotation")
	var depth_before: float=manager.bargain_cam.to_local(holder.global_position).z
	await button(MOUSE_BUTTON_WHEEL_UP); await button(MOUSE_BUTTON_WHEEL_UP,false)
	check(manager.bargain_cam.to_local(holder.global_position).z>depth_before,"Real scroll-up brings the artifact closer")
	await button(MOUSE_BUTTON_WHEEL_DOWN); await button(MOUSE_BUTTON_WHEEL_DOWN,false)
	check(absf(manager.bargain_cam.to_local(holder.global_position).z-depth_before)<0.01,"Scroll-down moves the artifact back out")
	for i in 8: await button(MOUSE_BUTTON_WHEEL_UP); await button(MOUSE_BUTTON_WHEEL_UP,false)
	check(-manager.bargain_cam.to_local(holder.global_position).z>=0.84,"Zoom cannot put the artifact inside the camera")
	for i in 12: await button(MOUSE_BUTTON_WHEEL_DOWN); await button(MOUSE_BUTTON_WHEEL_DOWN,false)
	check(-manager.bargain_cam.to_local(holder.global_position).z<=2.01,"Zoom cannot move the artifact too far to inspect")
	await snap("inspection-manipulated")
	check(manager.bargain_cam.global_transform.is_equal_approx(camera_pose) and not player.controls_enabled,"Dragging and zooming preserve the bargain camera and movement lock")
	var manipulated:=holder.global_transform
	root.size=Vector2i(1600,900); await frames(8)
	check(holder.global_transform.is_equal_approx(manipulated) and not player.controls_enabled,"Window resize preserves the manipulated artifact and stationary player")
	root.size=Vector2i(1152,648); await frames()
	await key(KEY_ESCAPE); check(paused,"Escape opens the real pause menu during inspection")
	await drag(MOUSE_BUTTON_LEFT,Vector2(10,10))
	check(holder._pivot.basis.is_equal_approx(released),"Pause blocks artifact dragging")
	await key(KEY_ESCAPE); check(not paused and not player.controls_enabled,"Resume returns to artifact inspection without enabling player movement")
	await key(KEY_TAB); await create_timer(0.4).timeout
	check(not manager.ui._panel_hidden and not player.controls_enabled and holder.global_transform.is_equal_approx(original) and holder._pivot.rotation.is_equal_approx(Vector3.ZERO),"Showing the book restores the artifact's position, distance and rotation")
	check(is_equal_approx(manager.ui._slider.value,price),"Inspecting does not change the current offer")
	basis_before=holder._pivot.basis
	await drag(MOUSE_BUTTON_LEFT,Vector2(25,10))
	check(holder._pivot.basis.is_equal_approx(basis_before),"Visible bargain panel disables artifact dragging")
	manager.ui.find_child("InspectDamageButton",true,false).pressed.emit()
	check(artifact.inspections.get("magnifier",false),"Existing inspection equipment still discovers damage")
	await key(KEY_TAB); await create_timer(0.4).timeout
	cursor=manager.ui._toggle.get_global_rect().get_center()
	await button(MOUSE_BUTTON_LEFT); await button(MOUSE_BUTTON_LEFT,false); await create_timer(0.4).timeout
	check(not manager.ui._panel_hidden,"Clicking the reveal arrow still shows the book instead of starting an artifact drag")
	manager.ui._btn_accept.pressed.emit(); await frames()
	check(manager.phase==manager.Phase.RECEIPT and not player.controls_enabled and manager.ui._price_overlay.visible,"Purchase still opens price editing with the player locked")
	manager.ui._price_spin.get_line_edit().text="80"; await frames()
	manager.ui._price_overlay.find_child("SavePriceButton",true,false).pressed.emit(); await frames()
	check(state.get_artifact(artifact.id)==artifact and artifact.sell_price==80 and player.controls_enabled and player.camera.current,"Saving the price restores normal gameplay with the purchased artifact intact")
	await prepare(); await key(KEY_TAB); await create_timer(0.4).timeout
	state.time_minutes=1230; state.time_changed.emit(20,30)
	check(not manager.is_inspecting_artifact() and not player.controls_enabled,"Closing safely disables artifact manipulation")
	var deadline:=Time.get_ticks_msec()+15000
	while manager.phase!=manager.Phase.CLOSED and Time.get_ticks_msec()<deadline: await process_frame
	check(manager.phase==manager.Phase.CLOSED and player.controls_enabled and player.camera.current,"After closing, normal player controls return")
	current_scene.queue_free(); await frames(6)
	for audio in root.find_children("*","AudioStreamPlayer",true,false): audio.stop(); audio.stream=null
	await create_timer(0.2).timeout
	print("ARTIFACT INSPECTION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
