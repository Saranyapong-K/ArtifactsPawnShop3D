extends SceneTree
## Regression coverage for the audit failures, real geometry and new appliances.
const OUT := "C:/Users/Syrins/Documents/Codex/2026-10-10/hee/work/fix-pass-2026-10-13/"
var state: Node
var main: Node3D
var manager: Node
var checks := 0
var failures := 0
func _init(): run.call_deferred()
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; push_error(message)
func frames(count:=3):
	for i in count: await process_frame
func snap(name: String):
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
func fresh(delay:=3600.0, fixture:=true):
	if is_instance_valid(main): main.queue_free(); await frames()
	state.new_game(); state.set_process(false)
	main=load("res://assets/Scene/main.tscn").instantiate()
	manager=main.get_node("Day_manager"); manager.first_customer_delay=delay
	root.add_child(main); current_scene=main
	await create_timer(0.2).timeout
	manager.player.set_physics_process(false)
	if fixture:
		manager._epoch+=1; manager.flow.start_day(); manager.flow.set_process(false)
		manager.phase=manager.Phase.FREE
		await frames()
func key():
	var e:=InputEventKey.new(); e.physical_keycode=KEY_E; e.pressed=true; Input.parse_input_event(e)
	await process_frame
	e=InputEventKey.new(); e.physical_keycode=KEY_E; e.pressed=false; Input.parse_input_event(e)
func run():
	if not OS.get_user_data_dir().contains("fix-tests"): quit(9); return
	root.position=Vector2i(-16000,-16000); root.size=Vector2i(1152,648)
	state=root.get_node("GameState"); state.save_path="user://integration-fixes.json"
	await fresh()
	check(state.clock_owned and not state.owned_items.get("radio",false),"Basic time is free; songs use the paid radio unlock")
	check(not state.can_buy_upgrade(200) and state.can_buy_upgrade(150),"Empty stock retains working capital")
	manager.game_ui.open_panel("shop")
	manager.game_ui._shop.get_node("%Furniture/DisplayShelf/%BuyButton").pressed.emit()
	check(state.money==200 and state.furniture.is_empty(),"UI cannot spend all starting money on a shelf")
	for name in ["WindowCloseButton","MinimizeButton"]:
		manager.game_ui.open_panel("shop")
		manager.game_ui._shop.find_child(name).pressed.emit()
		check(not manager.game_ui._open,"Shop window button closes: "+name)
	state.day=5; state.money=1000; state.rent_due_amount=800
	manager.game_ui.open_panel("stock"); await frames()
	var rent: Button=manager.game_ui._stock.get_node("%PayRentButton")
	check(rent.visible and not rent.disabled,"Due rent has an accessible enabled control")
	rent.pressed.emit(); await frames()
	check(state.money==200 and state.next_rent_day==10 and state.rent_due_amount==0,"Actual rent button pays once and advances schedule")
	await snap("management-fixed")
	manager.game_ui.close_panel()
	for size in [Vector2i(960,540),Vector2i(1152,648),Vector2i(1920,1080)]:
		root.size=size; await frames()
		manager.game_ui.show_game_over("A test recovery message."); await frames()
		check(root.get_visible_rect().encloses(manager.game_ui._game_over.get_node("%MainMenuButton").get_global_rect()),"Game-over return button fits "+str(size))
	await fresh(); root.size=Vector2i(1152,648); await frames()
	var book: Node3D=main.get_node("ShopManagementBook")
	check(book.find_child("Model",true,false)!=null or book.get_child_count()>2,"Management station uses supplied book visual")
	var counter: Node3D=main.find_child("ATFCounter",true,false)
	var supported:=false
	for patch: Dictionary in counter.get_meta("placement_patches",[]):
		var rect: Rect2=patch.rect
		if rect.size.x < 0.3 or rect.size.y < 0.3: continue
		if absf(book.global_position.y-float(patch.y)-0.015)<0.01 and rect.grow(-0.15).has_point(Vector2(book.global_position.x,book.global_position.z)): supported=true
	check(supported,"Book lies inside a supported counter patch, away from its edge")
	var customer_paths := PackedStringArray()
	for scene: PackedScene in manager.customer_scenes: customer_paths.append(scene.resource_path)
	check(customer_paths.has("res://scenes/goblin_police_customer.tscn"), "Police goblin can trade as a customer")
	check(not customer_paths.has("res://scenes/goblin_customer.tscn") and not customer_paths.has("res://assets/Customers/Goblin.glb"), "Regular goblin is excluded from buying and selling")
	check(manager.demon_model.resource_path == "res://assets/Customers/Goblin.glb" and manager.police_model.resource_path == "res://assets/Customers/GoblinPolice.glb", "Regular goblin is the demon; uniformed goblin is the police")
	for source in ["res://npcs_1.tscn","res://npcs_2.tscn","res://npcs_3.tscn","res://scenes/goblin_police_customer.tscn"]:
		var actor: Node3D=load(source).instantiate(); root.add_child(actor)
		var height: float=ArtifactVisual.local_bounds(actor).size.y
		check(absf(height-actor.target_height)<0.015,"NPC fitted to requested height: "+source)
		if "goblin" in source:
			actor.play("walk")
			check(actor.anim.current_animation=="Running","Goblin uses imported running animation for walking")
			actor.play("idle")
			check(actor.anim.current_animation == "Idle", "Police goblin uses supplied idle animation at rest")
			actor.play("talk")
			check(actor.anim.current_animation == "Idle", "Police goblin keeps idle during dialogue without a talk animation")
			actor.play("walk")
			check(actor.anim.current_animation == "Running", "Police goblin resumes running after idle")
		actor.queue_free()
	await frames()
	# Real physical approach while opening, from both sides of both doors.
	manager.game_ui.close_panel()
	var player: CharacterBody3D=manager.player
	for door in get_nodes_in_group("automatic_doors"):
		for side in [-1,1]:
			player.set_physics_process(false); player.global_position=Vector3(40,0,40)
			door.requests.clear(); door._set_open(false); await create_timer(1.2).timeout
			var center: Vector3=door.trigger_center
			player.global_position=Vector3(center.x,0.04,center.z+side*2.1)
			player.rotation.y=PI if side<0 else 0.0; player.velocity=Vector3.ZERO
			player.set_physics_process(true); Input.action_press("move_forward")
			await create_timer(1.15).timeout
			Input.action_release("move_forward"); await frames()
			check((player.global_position.z-center.z)*side<0 and absf(player.global_position.x-center.x)<0.20,"Closed-door approach crosses without sideways push: "+str(door.front)+" "+str(side))
			player.set_physics_process(false)
	await fresh()
	var artifact:=ArtifactData.create("res://assets/Relics/Goldcoin.glb","Gold Coin","Common","stolen")
	state.purchase(artifact,10); state.set_item_owned("magnifier")
	manager.newspaper_delivered=true; manager.game_ui._inspect_artifact(artifact.id,"magnifier")
	manager.newspaper_delivered=false
	check(manager.game_ui._inspection(artifact).contains("Stolen"),"Known stolen finding survives the next newspaper reset")
	check(ArtifactData.from_dict(artifact.to_dict()).inspections.get("stolen_found",false),"Discovered stolen finding survives serialization")
	var non_gold:=ArtifactData.create("res://assets/Relics/Sword.glb","Sword","Common","stolen")
	state.purchase(non_gold,10); manager.newspaper_delivered=true
	manager.game_ui._inspect_artifact(non_gold.id,"magnifier")
	check(non_gold.inspections.get("stolen_found",false),"Newspaper plus inspection identifies stolen goods beyond gold")
	check(manager.game_ui._inspection(ArtifactData.create("res://assets/Relics/Sword.glb","Unknown Sword","Common","stolen")).contains("Normal"),"Uninspected stolen goods stay hidden")
	var settings: Node=root.get_node("GameSettings"); settings.bind_key("interact",KEY_F)
	var mop: Node=manager.cleaning.tool_targets.mop; mop.show_prompt(true)
	check(mop._label.text.ends_with("F") and manager.game_ui._hint_label.text.contains("F Interact"),"Remapped interact key reaches world and HUD prompts")
	settings.bind_key("interact",KEY_E)
	manager.cleaning.wash_target.show_prompt(true); manager.cleaning.dumpster_target.show_prompt(true)
	# One target owns both the prompt and interaction on a dusty display surface.
	var dust: Node
	for record in state.cleaning.mess:
		if record.kind=="dust": dust=manager.cleaning.targets[record.id]; break
	if dust:
		var coin:=ArtifactData.create("res://assets/Relics/Goldcoin.glb","Prompt Coin","Common")
		state.purchase(coin,10); state.set_sell_price(coin.id,20)
		var body: Node3D=manager.placement.spawn_artifact(coin,dust.global_position)
		manager.player.global_position=body.global_position+Vector3(0,-body.global_position.y,1.6)
		manager.player.camera.global_position=manager.player.global_position+Vector3.UP*1.6
		manager.player.camera.look_at(body.global_position+Vector3.UP*0.05)
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED; await frames()
		check(manager.player.get_interaction_target(true)==body,"Dust does not hide an artifact pickup without the duster")
		body._process(0); manager.cleaning._process(0)
		check(body._label.visible and not dust._label.visible,"Artifact and dust prompts cannot overlap")
	await fresh()
	# Newly inserted geometry must interrupt/replan a live actor's real walk.
	var walker: Node3D=load("res://npcs_3.tscn").instantiate(); manager.flow.add_child(walker)
	walker.global_position=manager.exit_spot.global_position; walker.set_meta("shop_serving",true)
	walker.walk_to(manager.cashier_spot.global_position)
	var route: PackedVector3Array=walker._walk_path
	check(route.size()>3,"Real entrance-to-counter route exists")
	if route.size()>3:
		var box:=StaticBody3D.new(); var shape:=CollisionShape3D.new(); var geometry:=BoxShape3D.new()
		geometry.size=Vector3(0.8,2,0.8); shape.shape=geometry; box.add_child(shape); main.add_child(box)
		box.global_position=route[route.size()/2]+Vector3.UP
		state.changed.emit(); await frames()
		var crossed:=false
		var bounds:=AABB(box.global_position-geometry.size*0.5,geometry.size)
		var limit:=Time.get_ticks_msec()+12000
		while walker._walk_index<walker._walk_path.size() and Time.get_ticks_msec()<limit:
			if bounds.has_point(walker.global_position+Vector3.UP*0.8): crossed=true
			await process_frame
		check(not crossed,"Walking NPC does not cross newly placed solid geometry")
		check(walker._walk_failed or Vector2(walker.global_position.x-manager.cashier_spot.global_position.x,walker.global_position.z-manager.cashier_spot.global_position.z).length()<0.45,"Dynamic route replans or reports failure rather than remote arrival")
	await fresh()
	# A real blocked grid must never return a remotely serving visitor.
	var nav: Node=manager.navigation
	for x in nav.grid.region.size.x:
		for y in nav.grid.region.size.y: nav.grid.set_point_solid(Vector2i(x,y),true)
	nav.dirty=false
	var actor: Node3D=load("res://npcs_1.tscn").instantiate(); manager.flow.add_child(actor)
	actor.global_position=manager.exit_spot.global_position; actor.set_meta("visit_phase","queued")
	manager.flow.visitors.append(actor); manager.flow.waiting_visitors.append(actor)
	var served: Node3D=await manager.flow.take_next()
	check(served==null,"Failed real route does not begin service")
	await fresh()
	manager.flow.spawn_in=36; manager.phase=manager.Phase.ARRIVING
	var before: int=state.time_minutes
	await manager.wait_until_next_period()
	check(manager.flow.visitors.size()==1,"T creates the physical visitor instead of retaining the old countdown")
	check(state.time_minutes-before==36,"T advances matching game minutes")
	await fresh()
	# Robot duration/capacities and persistence, then its real walking/cleaning.
	for kind in ["rubbish","spill","dust"]:
		var data:=CleaningState.new(); data.bag_load=4; data.mop_uses=4
		data.add_mess(kind,"test",Vector3.ZERO)
		var id: String=data.mess[0].id
		check(not data.advance_robot(id,19.0,2).completed,"Robot cannot finish fresh "+kind+" before 20 seconds")
		data=CleaningState.from_dict(data.to_dict())
		check(data.advance_robot(id,1.01,2).completed and data.mess.is_empty(),"Robot resumes and completes "+kind)
		check(data.bag_load==4 and data.mop_uses==4,"Robot does not consume manual capacities")
	state.money=3000
	manager.game_ui.open_panel("shop")
	manager.game_ui._shop.get_node("%Equipment/Roomba/%BuyButton").pressed.emit()
	check(state.money==500 and state.owned_items.get("roomba",false),"Roomba bought from the actual shop for 2500 G")
	manager.game_ui.close_panel(); await frames()
	check(is_instance_valid(manager.cleaning.robot),"Buying Roomba spawns the supplied model")
	state.cleaning.mess.clear(); state.cleaning.add_mess("rubbish","robot-test",Vector3(2.6,-0.02,3.5))
	state.changed.emit(); await frames()
	var robot: Node=manager.cleaning.robot
	robot.global_position=Vector3(2.6,-0.02,3.0)
	var deadline:=Time.get_ticks_msec()+35000
	while not state.cleaning.mess.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(state.cleaning.mess.is_empty(),"Real Roomba routes to a mess and cleans it")
	check(state.save_game(),"Isolated checkpoint saves robot ownership")
	state.owned_items.erase("roomba"); state.load_game()
	check(state.owned_items.get("roomba",false),"Robot ownership restored from checkpoint")
	await snap("roomba-shop-world")
	manager.night._show_police(); await frames()
	check(is_instance_valid(manager.night._police_actor) and manager.night._police_actor._height==0.9,"Police raid displays the half-height goblin police model")
	manager.night.selected_event="demon"; manager.night.event_finished=false
	var cursed:=ArtifactData.create("res://assets/Relics/Goldcoin.glb","Cursed Coin","Uncommon","curse")
	state.purchase(cursed,10)
	manager.night._start_event(); await frames()
	check(manager.night._actors.size()==2,"Cursed item spawns two goblins using existing event rules")
	for intruder in manager.night._actors.duplicate():
		check(intruder._height==0.9 and intruder._animation!=null,"Demon event uses supplied small animated goblin")
		manager.player.global_position=intruder.global_position+Vector3(0,0,1)
		intruder.interact(manager.player)
	check(manager.night.event_finished,"Small goblins remain catchable using the existing interaction")
	await fresh(0.1,false)
	var limit:=Time.get_ticks_msec()+20000
	while manager.phase!=manager.Phase.WAITING and Time.get_ticks_msec()<limit: await process_frame
	check(manager.phase==manager.Phase.WAITING,"Real customer reaches the counter")
	if manager.phase==manager.Phase.WAITING:
		manager.customer.interact(manager.player); await create_timer(0.4).timeout
		state.time_minutes=1229; state._process(1)
		check(not manager.ui._dlg_active,"Closing cancels pending intro immediately")
		await create_timer(8).timeout
		state.time_minutes=1380; state.sleep()
		limit=Time.get_ticks_msec()+20000
		while manager.phase!=manager.Phase.WAITING and Time.get_ticks_msec()<limit: await process_frame
		if manager.phase==manager.Phase.WAITING:
			manager.customer.interact(manager.player)
			for i in 12:
				await create_timer(0.4).timeout; await key()
				if manager.phase==manager.Phase.HAGGLING: break
		check(manager.phase==manager.Phase.HAGGLING,"Next-day conversation works after closing interruption")
	await snap("lighting-goblin-book")
	await fresh()
	var small: Node3D=load("res://scenes/goblin_police_customer.tscn").instantiate(); main.add_child(small)
	small.global_position=manager.cashier_spot.global_position
	manager.customer=small; manager.current=manager.queue[0]; manager._buyer=false; manager.phase=manager.Phase.WAITING
	manager._start_bargain(); await create_timer(0.3).timeout
	check(manager.bargain_cam.global_position.y<=1.41,"Bargain camera adjusts to see the half-height goblin over the counter")
	for i in 12:
		await create_timer(0.35).timeout; await key()
		if manager.phase==manager.Phase.HAGGLING: break
	var face_point: Vector2 = manager.bargain_cam.unproject_position(small.global_position + Vector3.UP * 0.75)
	check(manager.phase == manager.Phase.HAGGLING and small.anim.current_animation == "Idle" and small.anim.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR, "Real police-goblin bargaining stage loops the supplied idle animation")
	check(face_point.y < manager.ui._toggle.get_global_rect().position.y - 20 and root.get_visible_rect().has_point(face_point), "Goblin face stays visible above the bargain hide button")
	await snap("small-goblin-bargain")
	manager._epoch+=1; manager.ui.hide_dialogue(); manager._end_bargain_view()
	check(manager.bargain_cam.transform.is_equal_approx(manager._bargain_camera_transform),"Bargain camera restores its authored transform afterwards")
	main.queue_free(); await frames(5)
	for audio_player in root.find_children("*", "AudioStreamPlayer", true, false):
		audio_player.stop(); audio_player.stream=null
	await frames()
	await create_timer(0.2).timeout
	print("INTEGRATION FIX TEST: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
