extends SceneTree
## Actual scene/input checks, using a private profile and prepared scenarios.
const OUT := "C:/Users/Syrins/Documents/Codex/2026-10-10/hee/work/submission-fixes-2026-10-14/"
var state: Node
var main: Node3D
var manager: Node
var checks := 0
var failures := 0
func _init(): run.call_deferred()
func check(ok: bool, description: String):
	checks+=1
	if not ok: failures+=1; push_error(description)
func frames(count:=3):
	for i in count: await process_frame
func snap(name: String):
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
func key(code: int):
	var event:=InputEventKey.new(); event.physical_keycode=code; event.keycode=code; event.pressed=true; Input.parse_input_event(event)
	await process_frame
	event=InputEventKey.new(); event.physical_keycode=code; event.keycode=code; event.pressed=false; Input.parse_input_event(event)
	await frames()
func run():
	if not OS.get_user_data_dir().contains("submission-tests"): quit(9); return
	root.position=Vector2i(-16000,-16000); root.size=Vector2i(1152,648)
	state=root.get_node("GameState"); state.save_path="user://submission-checkpoint.json"
	change_scene_to_file("res://main_menu.tscn"); await frames(8)
	var menu: Node=current_scene
	check(menu.menu_music.size()==6,"All six songs are assigned in the main-menu Inspector array")
	check(menu._music_player.playing and menu._music_name.text=="2 AM","Menu plays an actual added song and displays its filename")
	menu.find_child("NewGameButton",true,false).pressed.emit()
	await frames(3)
	var warmer: Node=root.get_node("AssetWarmup")
	check(warmer.busy and warmer._screen!=null,"New Game shows loading before switching to the shop")
	await key(KEY_ESCAPE)
	await key(KEY_TAB)
	check(not paused and not menu.find_child("SettingsMenu",true,false)._is_open,"Escape during model loading cannot pause or open settings")
	await snap("loading-screen")
	var launch_time:=Time.get_ticks_msec()
	while current_scene==menu and Time.get_ticks_msec()-launch_time<30000: await process_frame
	check(current_scene!=menu,"New Game completes its staged loading")
	main=current_scene; manager=main.get_node("Day_manager")
	if not manager.get_script(): quit(1); return
	await create_timer(0.7).timeout
	state.set_process(false); manager._epoch+=1; manager.phase=manager.Phase.FREE
	manager.flow.close_shop(); manager.flow.set_process(false)
	check(warmer.prepared_day==1 and not warmer.warmed.has("res://assets/Relics/Iphone.glb"),"Day 1 warms starting models while deferring Rare-only IP17")
	check(warmer.warmed.has("res://assets/Customers/GoblinPolice.glb"),"Customer model is drawn before the first shop visit")
	var sound: Node=root.get_node("Sfx"); sound._refresh_radio()
	check(sound._radio_active and not state.owned_items.get("radio",false),"Funky ambience plays without buying the song radio")
	check(sound._song_streams.size()==6,"In-game radio receives all six real songs")
	var dust: Node3D=manager.cleaning._visual("dust"); main.add_child(dust)
	var dust_bounds: AABB=ArtifactVisual.local_bounds(dust)
	check(dust_bounds.size.x<=0.481 and dust_bounds.size.z<=0.481 and dust_bounds.size.y<=0.171,"Supplied dust fits a small shelf patch")
	dust.queue_free()
	# Real capsule walk across both raised curbs; no jump or teleport mid-crossing.
	var player: CharacterBody3D=manager.player
	player.set_controls_enabled(true); player.global_position=Vector3(6.7,0.4,9); player.rotation.y=PI; player.velocity=Vector3.ZERO
	Input.action_press("move_forward"); await create_timer(6.2).timeout; Input.action_release("move_forward")
	check(player.global_position.z>29,"Player physically walks across the road and far curb without jumping")
	print("ROAD FAR ",player.global_position)
	player.rotation.y=0
	Input.action_press("move_forward"); await create_timer(6.4).timeout; Input.action_release("move_forward")
	check(player.global_position.z<10,"Player physically crosses the road back toward the shop")
	print("ROAD RETURN ",player.global_position)
	player.global_position=Vector3(14,0.4,13); player.rotation.y=-PI*0.5; player.velocity=Vector3.ZERO
	Input.action_press("move_forward"); await create_timer(0.9).timeout; Input.action_release("move_forward")
	check(player.global_position.x<14.8,"Right-side fence-to-road gap cannot be crossed")
	player.global_position=Vector3(-17,0.4,13); player.rotation.y=PI*0.5; player.velocity=Vector3.ZERO
	Input.action_press("move_forward"); await create_timer(0.9).timeout; Input.action_release("move_forward")
	check(player.global_position.x> -17.9,"Left-side fence-to-road gap cannot be crossed")
	player.set_physics_process(false); player.global_position=Vector3(40,0,40)
	var actor: Node3D=load("res://scenes/goblin_police_customer.tscn").instantiate(); manager.flow.add_child(actor)
	actor.global_position=manager.exit_spot.global_position; actor.set_meta("shop_serving",true)
	var arrived: bool=await actor.walk_to(manager.cashier_spot.global_position)
	check(arrived and actor.global_position.distance_to(manager.cashier_spot.global_position)<0.5,"Actual customer walks from outside through the door to the counter with world collisions")
	actor.queue_free(); await frames()
	var thief:=preload("res://scripts/event_actor.gd").new(); main.add_child(thief)
	thief.setup("thief",[])
	check(thief.walk_speed>player.sprint_speed and thief.walk_speed<player.sprint_speed*1.12,"Thief runs slightly faster than the player's sprint")
	thief.queue_free()
	manager.night._show_eyes()
	var window: MeshInstance3D=main.find_child("Window",true,false)
	var window_bounds: AABB=window.global_transform*window.get_aabb()
	check(absf(manager.night._eyes.global_position.x-window_bounds.get_center().x)<0.1 and absf(manager.night._eyes.global_position.y-window_bounds.get_center().y)<0.1,"Yellow warning eyes are centered at the window")
	player.global_position=Vector3(1.2,0.03,5.4); player.camera.global_position=Vector3(1.2,1.65,5.4)
	player.camera.look_at(manager.night._eyes.global_position); player.camera.make_current()
	await snap("window-eyes"); manager.night._clear_eyes()
	manager.cleaning.hold_tool("mop"); manager.cleaning._process(0)
	check(manager.cleaning.holding_label.visible and manager.cleaning.holding_label.text=="Press Q to drop","Held cleaning tool shows the short Q hint")
	await key(KEY_Q); check(manager.cleaning.held_tool.is_empty(),"Q releases the held cleaning tool")
	# Real ray and Interact key at the floating website icon.
	var internet: Area3D=main.get_node("InternetShop")
	player.global_position=internet.global_position+Vector3(0,-internet.global_position.y,1.5)
	player.camera.global_position=internet.global_position+Vector3(0,0.15,1.5); player.camera.look_at(internet.global_position)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED; await frames()
	check(player.get_interaction_target(true)==internet,"Internet model is an actual reachable interaction target")
	await snap("internet-shop-spot"); await key(KEY_E)
	check(manager.game_ui._open and manager.game_ui._page=="shop","E on Internet opens the existing computer shop")
	manager.game_ui.close_panel()
	# Prepared funds exercise the actual radio purchase and controls.
	state.money=650
	manager.game_ui.open_panel("shop")
	manager.game_ui._shop.get_node("%Equipment/Radio/%BuyButton").pressed.emit()
	check(state.money==450 and state.owned_items.get("radio",false),"Radio purchase pays exactly 200 G")
	sound._refresh_radio(); manager.game_ui.open_panel("stock"); await frames()
	check(sound.song_state=="playing" and manager.game_ui._stock.get_node("%RadioControls").visible,"Paid radio unlocks real songs and visible management controls")
	manager.game_ui._stock.get_node("%PauseRadio").pressed.emit()
	check(sound.song_state=="paused" and sound._songs.stream_paused,"Pause preserves song playback")
	manager.game_ui._stock.get_node("%PlayRadio").pressed.emit()
	check(sound.song_state=="playing" and not sound._songs.stream_paused,"Play resumes the song")
	manager.game_ui._stock.get_node("%StopRadio").pressed.emit(); sound._refresh_radio()
	check(sound.song_state=="stopped" and not sound._songs.playing and sound._radio_active,"Stop leaves funky ambience and does not auto-restart the song")
	await snap("radio-controls"); manager.game_ui.close_panel()
	# Buyers open low but listing acceptance remains easy and legal.
	var listed:=ArtifactData.create("res://assets/Relics/Iphone.glb","IP17","Rare","normal",Vector2i(1,2)); listed.sell_price=800
	var accepted:=0
	for i in 1000:
		var buyer:=BuyerHaggle.new(listed); buyer.apply_cleanliness(0.06)
		if buyer.ask<400 or buyer.ask>480: failures+=1; push_error("Buyer opening outside 50–60%")
		if buyer.max_budget<720 or buyer.max_budget>880: failures+=1; push_error("Buyer budget outside listing ±10%")
		if buyer.make_offer(800).result=="deal": accepted+=1
	check(accepted>=880,"Most buyers accept one offer at the legal listing price")
	print("BUYER LISTING ACCEPTS ",accepted,"/1000")
	for day in [1,2,3,5]:
		for i in 100:
			var offer:=DayQueue.walk_in(day)
			if offer.artifact.model_path.ends_with("Iphone.glb"): check(offer.artifact.rarity=="Rare" and day>=3,"IP17 is Rare-only and respects existing tier unlock days")
	var entries:=DayQueue._for_rarity(DayQueue._catalog(),"Rare")
	check(entries.any(func(entry): return entry.get("id")=="ip17"),"IP17 is available in the Rare pool")
	check(not DayQueue._for_rarity(DayQueue._catalog(),"Common").any(func(entry): return entry.get("id")=="ip17"),"IP17 cannot appear as an opening Common artifact")
	# Offered models stay above UI; Tab moves them to a useful inspection distance.
	var cop: Node3D=load("res://scenes/goblin_police_customer.tscn").instantiate(); main.add_child(cop)
	cop.global_position=manager.cashier_spot.global_position; cop.set_at_counter(true)
	manager.customer=cop; manager.current=Haggle.new(500,false,"easygoing",listed); manager._buyer=false; manager.phase=manager.Phase.HAGGLING
	manager.bargain_cam.make_current(); manager._spawn_relic(); manager._open_bargain_ui()
	await create_timer(0.5).timeout
	var offered: Node3D=manager.relic_holder
	var old_position:=offered.global_position
	await snap("artifact-ui-visible"); await key(KEY_TAB); await create_timer(0.45).timeout
	var toggle: Button=manager.ui._toggle
	var hint: Label=manager.ui._toggle_hint
	check(toggle.tooltip_text.is_empty() and hint.visible and hint.text=="Tab · Show panel" and hint.get_global_rect().end.x<root.size.x and hint.get_global_rect().end.y<root.size.y-26,"Hidden-panel hint uses the outlined UI label and stays inside the screen above the controls")
	var view_point: Vector2=manager.bargain_cam.unproject_position(offered.global_position)
	check(manager.ui._panel_hidden and not player.controls_enabled and manager.bargain_cam.current and offered.global_position.distance_to(manager.bargain_cam.global_position)>1.1 and offered.global_position.distance_to(manager.bargain_cam.global_position)<1.4 and view_point.distance_to(Vector2(576,324))<3,"Tab centers the artifact for mouse manipulation while the player stays stationary")
	await snap("artifact-inspection"); await key(KEY_TAB); await create_timer(0.45).timeout
	check(not manager.ui._panel_hidden and offered.global_position.distance_to(old_position)<0.01,"Showing bargain UI returns the artifact to its previous position")
	manager.ui.visible=false; manager._end_bargain_view(); cop.queue_free(); manager.customer=null; manager.phase=manager.Phase.CLOSED; manager._closed=true
	# Real bed ray -> summary button -> warm next-day assets -> saved Day 2.
	state.time_minutes=1380; state.inventory.clear(); state.purchase(listed,100); state.set_sell_price(listed.id,800)
	state.cleaning.mop_uses=3; state.cleaning.bag_load=2
	var bed: Area3D=main.get_node("BedSleep")
	player.set_controls_enabled(true); player.global_position=bed.global_position+Vector3(0,-bed.global_position.y,1.4)
	player.camera.global_position=bed.global_position+Vector3(0,0.5,1.4); player.camera.look_at(bed.global_position); player.camera.make_current()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED; await frames()
	check(player.get_interaction_target(true)==bed,"Actual bed is reachable by the player interaction ray")
	await key(KEY_E); check(manager.phase==manager.Phase.SUMMARY,"Bed E opens the sleep summary")
	manager.ui._summary_overlay.find_child("NextButton",true,false).pressed.emit()
	var sleep_start:=Time.get_ticks_msec()
	while state.day==1 and Time.get_ticks_msec()-sleep_start<15000: await process_frame
	check(state.day==2 and state.time_minutes==630 and state.has_save(),"Sleep advances exactly one day, wakes at 10:30 and saves")
	check(warmer.prepared_day==2 and warmer.warmed.has("res://assets/Relics/Iphone.glb"),"Next-day transition loads and draws the remaining Rare model")
	var saved_money: int=state.money
	state.stop_clock(); change_scene_to_file("res://main_menu.tscn"); await frames(8)
	current_scene.find_child("ContinueButton",true,false).pressed.emit(); await create_timer(0.7).timeout
	check(state.day==2 and state.money==saved_money and state.inventory.size()==1 and state.cleaning.mop_uses==3 and state.cleaning.bag_load==2 and state.owned_items.get("radio",false),"Continue restores day, wallet, artifact, cleaning capacities and paid radio ownership")
	await snap("sleep-reload")
	current_scene.queue_free(); await frames(5)
	for p in root.find_children("*","AudioStreamPlayer",true,false): p.stop(); p.stream=null
	await create_timer(0.2).timeout
	print("SUBMISSION TEST: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
