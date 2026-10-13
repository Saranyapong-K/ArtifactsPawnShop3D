extends SceneTree
## Exercise the reported bugs with real physics, controls and imported materials.
var checks:=0
var failures:=0
func _init(): run.call_deferred()
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; push_error(message)
func frames(count:=3):
	for i in count: await physics_frame
func onscreen(control: Control,screen: Control) -> bool:
	# Control.get_global_rect ignores rotation; check the rendered corners.
	var bounds:=Rect2(Vector2.ZERO,screen.size).grow(0.1)
	for corner in [Vector2.ZERO,Vector2(control.size.x,0),control.size,Vector2(0,control.size.y)]:
		if not bounds.has_point(control.get_global_transform()*corner): return false
	return true
func run():
	if not OS.get_user_data_dir().contains("debug-tests"): push_error("Use an isolated debug-tests profile"); quit(1); return
	root.position=Vector2i(-16000,-16000)
	root.size=Vector2i(1152,648)
	AudioServer.set_bus_mute(0,true)
	var state: Node=root.get_node("GameState")
	state.save_path="user://debug-regression.json"
	state.new_game()
	var main: Node3D=load("res://assets/Scene/main.tscn").instantiate()
	var manager: Node=main.get_node("Day_manager")
	manager.first_customer_delay=3600
	root.add_child(main)
	current_scene=main
	await frames(4)
	manager._epoch+=1
	manager.flow.set_process(false)
	state.stop_clock()
	var player: CharacterBody3D=main.get_node("Player")
	player.set_physics_process(false)
	var cleaning: Node3D=manager.cleaning
	cleaning.set_process(false)
	state.purchase(DayQueue.broom_offer().artifact,20)
	var rubbish: Area3D
	for record in state.cleaning.mess:
		if record.kind=="rubbish": rubbish=cleaning.targets[record.id]; break
	player.global_position=rubbish.global_position+Vector3(0,0,1.0)
	check(cleaning.hold_tool("broom"),"Broom pickup still uses one hand")
	check(cleaning.start_cleaning(rubbish),"Cleaning starts nearby")
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	if DisplayServer.get_name()!="headless":
		Input.action_press("interact")
		player.camera.look_at(player.camera.global_position+Vector3.RIGHT)
		cleaning.advance_cleaning(2)
		check(cleaning.is_cleaning() and state.cleaning.get_mess(rubbish.record_id).progress==2,"Holding E continues cleaning after looking away")
		Input.action_release("interact")
		cleaning.advance_cleaning(1)
		check(not cleaning.is_cleaning() and state.cleaning.get_mess(rubbish.record_id).progress==2,"Releasing E retains unfinished cleaning")
	cleaning.start_cleaning(rubbish)
	player.global_position=rubbish.global_position+Vector3(0,0,cleaning.cleaning_reach+0.1)
	cleaning.advance_cleaning(1,false)
	check(not cleaning.is_cleaning(),"Walking beyond cleaning reach cancels")
	check(not cleaning.start_cleaning(rubbish),"Cleaning cannot start from outside reach")
	cleaning.put_tool_away()
	for id in ["broom","mop","feather_duster"]:
		var tool: Area3D=cleaning.tool_targets[id]
		tool.show_prompt(true)
		var label: Label3D=tool.get_node("InteractionLabel")
		check(label.font_size==32 and is_equal_approx(label.pixel_size,0.0026) and label.text.ends_with("E"),"Readable artifact-style world prompt for "+id)
	state.cleaning.bag_load=1
	cleaning.bag_target.show_prompt(true)
	check(cleaning.bag_target.get_node("InteractionLabel").text=="Trash bag (1/4)\nE","Trash bag shows capacity above E")
	state.cleaning.mop_uses=1
	cleaning.tool_targets.mop.show_prompt(true)
	check(cleaning.tool_targets.mop.get_node("InteractionLabel").text=="Mop (1/4)\nE","Mop shows used capacity above E")
	state.cleaning.bag_load=4
	cleaning.bag_target.show_prompt(true)
	check("Take the trash out first" in cleaning.bag_target.get_node("InteractionLabel").text,"Full bag explains disposal")
	state.cleaning.mop_uses=4
	cleaning.tool_targets.mop.show_prompt(true)
	check("Too dirty! Wash the mop inside the toilet" in cleaning.tool_targets.mop.get_node("InteractionLabel").text,"Dirty mop explains washing")
	player.global_position=Vector3(40,0,40)
	var doors:=get_nodes_in_group("automatic_doors")
	for door in doors: door.release("probe")
	await create_timer(1.5).timeout
	for door in doors:
		var start: Vector3=door.trigger_center+Vector3(0,0,0.9)
		start.y=0.04
		check(player.test_move(Transform3D(Basis.IDENTITY,start),Vector3(0,0,-1.8)),"Closed door blocks the actual player capsule: "+str(door.door.name))
		door.request_open("regression")
	await create_timer(1).timeout
	for door in doors:
		for side in [-1,1]:
			var start: Vector3=door.trigger_center+Vector3(0,0,side*0.9)
			start.y=0.04
			check(not player.test_move(Transform3D(Basis.IDENTITY,start),Vector3(0,0,-side*1.8)),"Open door permits actual player from either side: "+str(door.door.name))
		check(door.animator.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS,"Door physics follows its animation")
		door.release("regression")
	var ui: CanvasLayer=manager.ui
	ui.visible=true
	ui.show_customer(1,3,state.money,50,30,"")
	await frames()
	var buttons: Array[Button]=[ui._btn_offer,ui._btn_accept,ui._btn_away]
	for button in buttons:
		check(button.size.is_equal_approx(buttons[0].size) and is_equal_approx(button.global_position.y,buttons[0].global_position.y),"Offer/Accept/Reject have equal rectangles and baseline")
	check(is_equal_approx(buttons[1].get_global_rect().get_center().x,ui._bargain_panel.get_global_rect().get_center().x),"Accept is centered in the book")
	for size in [Vector2i(960,540),Vector2i(1152,648),Vector2i(1600,900)]:
		root.size=size
		await frames()
		ui._set_panel_hidden(true,false)
		var arrow: Control=ui._toggle.get_node("ArrowArtwork")
		check(onscreen(arrow,ui._root),"Hidden-book reveal artwork stays onscreen at "+str(size))
		ui._set_panel_hidden(false,false)
		check(onscreen(arrow,ui._root),"Shown-book toggle artwork stays onscreen at "+str(size))
	ui.visible=false
	state.start_clock()
	manager.phase=manager.Phase.WAITING
	manager._closed=false
	manager.current=Haggle.new(25,false,"easygoing",ArtifactData.create("res://assets/Relics/Goldcoin.glb","Test coin","Common"))
	manager.customer=null
	manager._start_bargain()
	await process_frame
	check(not state.is_time_paused() and not paused,"Bargain does not pause world or clock")
	var old_time: int=state.time_minutes
	state._process(1.0)
	check(state.time_minutes>old_time,"Game time advances during bargain dialogue")
	manager._epoch+=1
	manager._end_bargain_view()
	state.stop_clock()
	check(manager.navigation.grid.diagonal_mode==AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES,"Visitors can use eight directions without cutting blocked corners")
	check(manager.flow.arrival_interval.x>=28 and manager.flow.arrival_interval.y>=45,"Walk-ins are paced more slowly")
	var env: Environment=main.get_node("WorldEnvironment").environment
	check(env.sky!=null and env.reflected_light_source==Environment.REFLECTION_SOURCE_SKY,"Metal artifacts have a reflection source")
	for index in 3:
		var actor: Node3D=load("res://npcs_%d.tscn"%(index+1)).instantiate()
		root.add_child(actor)
		load("res://scripts/customer_appearance.gd").apply_to(actor,2,1)
		var hair: Color=actor.get_meta("hair_color")
		var colors:=0
		for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
			for surface in mesh.mesh.get_surface_count():
				var mat: Material=mesh.get_active_material(surface)
				if mat is StandardMaterial3D and mat.resource_name=="Hair": check(mat.albedo_color==hair,"NPC1 hair/tail share chosen hair colour"); colors+=1
				if mat is StandardMaterial3D and mat.resource_name=="Cape": check(mat.albedo_color==actor.get_meta("clothing_color"),"NPC1 cape gets its clothing recolour")
				if mat is ShaderMaterial and mat.get_shader_parameter("recolor_hair"):
					check(mat.get_shader_parameter("hair_color")==hair,"Textured head/tail use chosen hair colour")
					colors+=1
		check(colors>=1,"Hair recolour applies to NPC %d"%(index+1))
		# A short diagonal leg turns gradually and accelerates instead of snapping.
		actor.global_position=Vector3(0,0,4)
		actor.rotation.y=0
		actor._walk_path=PackedVector3Array([Vector3(1,0,5)])
		actor._walk_target = Vector3(1,0,5)
		actor._route_revision = main.get_node("Day_manager").navigation.revision
		main.get_node("Day_manager").navigation.dirty = false
		actor._walk_index=0
		actor.set_meta("shop_serving",true)
		actor._process(0.05)
		check(actor.global_position.x>0 and actor.global_position.z>4 and actor.rotation.y>0 and actor.rotation.y<PI/4,"Visitor moves diagonally and turns gradually")
		actor.queue_free()
	main.queue_free()
	await frames()
	var menu: Control=load("res://main_menu.tscn").instantiate()
	# Empty Inspector playlists must still support the original quiet placeholder.
	menu.menu_music.clear()
	root.add_child(menu)
	await frames()
	check(menu._music_name.text=="Music coming soon" and menu.menu_music.is_empty(),"Menu has a quiet empty-playlist placeholder")
	var old_x: float=menu._music_name.position.x
	menu._process(0.5)
	check(menu._music_name.position.x<old_x,"Menu song name scrolls slowly")
	var song:=AudioStreamWAV.new()
	song.mix_rate=22050
	var samples:=PackedByteArray(); samples.resize(22050*4); song.data=samples
	song.take_over_path("res://tests/Amber Rain.wav")
	menu.menu_music.append(song)
	menu._next_track()
	check(menu._music_name.text=="Amber Rain" and menu._music_player.stream==song,"Inspector playlist uses the audio filename for the ticker")
	check(menu._music_player.bus==&"Music","Menu music respects the Music volume bus")
	menu.queue_free()
	await frames()
	# Release active generated audio before quitting the test's dummy driver.
	for audio_player in root.find_children("*", "AudioStreamPlayer", true, false):
		audio_player.stop()
		audio_player.stream = null
	await frames()
	print("DEBUG REGRESSION: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
