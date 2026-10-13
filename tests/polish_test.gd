extends SceneTree
class FastVisitor extends Node3D:
	var can_interact := false
	func set_interactable(on: bool): can_interact=on
	func play(_animation: String): pass
	func face_toward(_point: Vector3): pass
	func walk_to(point: Vector3):
		global_position=point
		await get_tree().process_frame
var checks := 0
var failures := 0
func _init(): _run.call_deferred()
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; push_error(message)
func frames(count := 3):
	for i in count: await physics_frame
func _run():
	if not OS.get_user_data_dir().contains("polish-tests"): push_error("Use isolated polish-tests APPDATA."); quit(1); return
	var state: Node=root.get_node("GameState")
	state.save_path="user://polish-test.json"
	state.new_game()
	var main: Node3D=load("res://assets/Scene/main.tscn").instantiate()
	var manager: Node=main.get_node("Day_manager")
	manager.first_customer_delay=3600.0
	root.add_child(main)
	current_scene=main
	await frames(4)
	state.stop_clock()
	manager._epoch+=1
	var player: Node3D=manager.player
	player.set_physics_process(false)
	var cleaning: Node3D=manager.cleaning
	cleaning.set_process(false)
	var flow: Node3D=manager.flow
	flow.set_process(false)
	check(cleaning.floor_spots.size()==8,"User's TrashSpot/TrashDrink markers are recognized")
	check(cleaning._marker("DumpsterSpot").is_equal_approx(main.get_node("Marks/Dumbster spot").global_position),"Dumpster alias uses user's actual marker")
	check(cleaning.wash_target.global_position.is_equal_approx(main.get_node("Marks/MopCleanerSpot2").global_position),"Toilet wash alias uses user's actual marker")
	check(main.get_node_or_null("BedSleep")!=null and main.find_child("Rest journal",true,false)==null,"Sleep interaction belongs to bed rather than the counter")
	var bed: MeshInstance3D=main.find_child("Mattress",true,false)
	var bed_bounds: AABB=bed.global_transform*bed.get_aabb()
	check(main.get_node("BedSleep").global_position.is_equal_approx(bed_bounds.get_center()),"Bed target follows the actual imported mattress")
	check(get_nodes_in_group("automatic_doors").size()==2,"Front and back have separate automatic doors")
	var doors: Array=get_nodes_in_group("automatic_doors")
	player.global_position=Vector3(50,0,50)
	for door in doors: door.request_open("test")
	await create_timer(1.0).timeout
	for door in doors: check(door.opened and absf(door.door.rotation.y)>1.8,"Original door opening animation plays independently")
	for door in doors: door.release("test")
	await create_timer(1.5).timeout
	for door in doors: check(not door.opened and absf(door.door.rotation.y)<0.02,"Unoccupied door closes again")
	player.global_position=doors[0].trigger_center-Vector3(0,1.0,0.8)
	await frames(2)
	check(doors[0].opened,"Player approaching either side opens a door")
	var route: PackedVector3Array=manager.navigation.route(manager.exit_spot.global_position,manager.cashier_spot.global_position)
	check(route.size()>1,"Navigation has a supported route from outside to the counter")
	for title in ["Floor","ATFCounter","SmallTable"]:
		var mesh: MeshInstance3D=main.find_child(title,true,false)
		check(not mesh.get_meta("placement_patches",[]).is_empty(),"Real horizontal placement patches exist on "+title)
	var counter: MeshInstance3D=main.find_child("ATFCounter",true,false)
	var coin:=ArtifactData.create("res://assets/Relics/Goldcoin.glb","Placement coin","Common")
	var supported:=0
	for patch in counter.get_meta("placement_patches",[]):
		var rect: Rect2=patch.rect
		if rect.size.x<0.34 or rect.size.y<0.34: continue
		var center:=rect.get_center()
		var hit:=Vector3(center.x,float(patch.y),center.y)
		var result: Dictionary=manager.placement.resolve_candidate(coin,hit,0,"",counter)
		if result.valid: supported+=1
	check(supported>0,"Actual updated shop has valid snapped display positions")
	var rotations: Dictionary={}
	for record in state.cleaning.mess: rotations[record.rotation]=true
	check(rotations.size()>1,"New messes use random rotations")
	var restored:=CleaningState.from_dict(state.cleaning.to_dict())
	check(restored.mess[0].rotation==state.cleaning.mess[0].rotation,"Mess orientation survives a checkpoint")
	for kind in ["broom","mop","feather_duster","trash_bag","rubbish","spill"]:
		var visual: Node3D=cleaning._visual(kind)
		var bounds:=ArtifactVisual.local_bounds(visual)
		check(absf(bounds.get_center().x)<0.001 and absf(bounds.get_center().z)<0.001 and absf(bounds.position.y)<0.001,"GLB/FBX origin is centered and bottom-aligned for "+kind)
		if kind=="trash_bag": check(bounds.size.y<0.7,"FBX bag is normalized to a usable size")
		root.add_child(visual)
		await process_frame
		await process_frame
		visual.queue_free()
		await process_frame
	state.cleaning.mop_uses=4
	state.changed.emit()
	check(cleaning.hold_tool("mop"),"Imported mop can be held")
	check(cleaning.held_visual.get_parent()==player.camera,"Real held tool follows camera")
	var head_materials:=0
	for mesh: MeshInstance3D in cleaning.held_visual.find_children("*","MeshInstance3D",true,false):
		for i in mesh.mesh.get_surface_count():
			var material: Material=mesh.get_active_material(i)
			if material.resource_name.to_lower()=="mop": head_materials+=1; check(material.albedo_color.r<0.3,"Dirty colour affects mop head")
	check(head_materials>0,"Mop head is found by its actual material")
	var spill: Area3D
	for record in state.cleaning.mess:
		if record.kind=="spill": spill=cleaning.targets[record.id]; break
	player.global_position=spill.global_position
	check(not cleaning.start_cleaning(spill) and cleaning.hud.feedback.text=="Too dirty! Wash the mop inside the toilet","Maximum dirt blocks cleaning and explains where to wash")
	check(player._shake_left>0,"Dirty-tool attempt causes a gentle camera shake")
	state.cleaning.bag_load=4
	cleaning._process(0)
	check(cleaning.hud.indicator.visible and cleaning.hud.wash_indicator.visible,"Full bag and dirty mop show both location arrows")
	check(not cleaning.hud.distance_label.visible and not cleaning.hud.holding_label.visible,"Cleaning instructions and waypoint distance stay hidden")
	var arrow_position: Vector2=cleaning.hud.indicator.position
	player.camera.look_at(cleaning.dumpster_arrow_point)
	cleaning._process(0)
	arrow_position=cleaning.hud.indicator.position
	cleaning.hud.bob_seconds+=0.2
	cleaning._process(0)
	check(not arrow_position.is_equal_approx(cleaning.hud.indicator.position),"Waypoint arrow bobs above its world spot")
	player.global_position=cleaning.wash_target.global_position
	check(cleaning.start_cleaning(cleaning.wash_target),"Mop washing starts at the toilet")
	cleaning.advance_cleaning(4,false)
	check(cleaning.hud.progress_bar.value==50 and not cleaning.hud.progress_label.visible,"Cleaning uses only the rounded progress bar")
	cleaning.stop_cleaning()
	check(state.cleaning.mop_wash_progress==4,"Cancel keeps unfinished washing")
	cleaning.start_cleaning(cleaning.wash_target)
	cleaning.advance_cleaning(4,false)
	check(state.cleaning.mop_uses==0,"Resuming finishes washing and restores mop")
	cleaning.put_tool_away()
	# Real player rays must reach the bed, toilet and bin, not just their markers.
	player.global_position=Vector3(5.2,0.04,-4.5)
	player.camera.global_position=player.global_position+Vector3.UP*1.6
	player.camera.look_at(main.get_node("BedSleep").global_position)
	await frames(2)
	player.ray.force_raycast_update()
	check(player.ray.get_collider()==main.get_node("BedSleep"),"Player can target the actual bed from its accessible side")
	player.global_position=Vector3(8.4,0.04,-2.6)
	player.camera.global_position=player.global_position+Vector3.UP*1.6
	player.camera.look_at(cleaning.wash_target.global_position+Vector3.UP*0.55)
	await frames(2)
	player.ray.force_raycast_update()
	check(player.ray.get_collider()==cleaning.wash_target,"Player ray reaches toilet washing")
	check(cleaning.hold_tool("trash_bag"),"Full FBX bag can be carried")
	player.global_position=Vector3(-1.9,0.04,-2.322)
	player.camera.global_position=player.global_position+Vector3.UP*1.6
	player.camera.look_at(cleaning.dumpster_target.global_position+Vector3.UP*0.9)
	await frames(2)
	player.ray.force_raycast_update()
	check(player.ray.get_collider()==cleaning.dumpster_target,"Player ray reaches the actual imported dumpster")
	player._try_interact()
	check(state.cleaning.bag_load==0 and cleaning.held_tool.is_empty(),"E empties the full bag at the real dumpster")
	var player_ui: Control=main.get_node("PlayerUi/PlayerUI")
	player_ui.toggle_hud()
	check(not manager.game_ui._hint_label.visible,"Tab hides the bottom controls with the HUD")
	player_ui.toggle_hud()
	check(manager.game_ui._hint_label.visible,"Tab restores the bottom controls")
	var actor:=FastVisitor.new()
	actor.name="QueueTest"
	var scene:=PackedScene.new()
	scene.pack(actor)
	actor.free()
	manager.customer_scenes=[scene] as Array[PackedScene]
	flow.start_day()
	flow.set_process(false)
	var first: Node3D=flow.spawn_visitor(true)
	var second: Node3D=flow.spawn_visitor(true)
	var third: Node3D=flow.spawn_visitor(true)
	await frames(4)
	await create_timer(0.08).timeout
	check(flow.waiting_visitors.size()==3,"Three visitors form a line")
	if flow.waiting_visitors.size()!=3: main.queue_free(); await process_frame; quit(1); return
	check(flow.waiting_visitors[0]==first and flow.waiting_visitors[1]==second,"Queue preserves arrival order")
	var served: Node3D=await flow.take_next()
	check(served==first and flow.waiting_visitors[0]==second,"Serving removes the first visitor and advances the line")
	check(second.get_meta("queue_slot")==0 and third.get_meta("queue_slot")==1,"Waiting visitors receive their new slots")
	check(not second.can_interact,"Waiting visitors cannot steal the current negotiation")
	await flow.depart(served)
	await frames(2)
	check(not is_instance_valid(first),"Served visitor leaves through the entrance")
	flow.close_shop()
	await frames(6)
	check(flow.waiting_visitors.is_empty(),"Closing clears queued visitors")
	flow.start_day()
	flow.set_process(false)
	manager._visitor_index=2
	state.start_clock()
	flow.leave_chance=1.0
	flow.browse_pause=Vector2(0.01,0.01)
	var browser: Node3D=flow.spawn_visitor()
	await create_timer(0.4).timeout
	check(not is_instance_valid(browser) and flow.waiting_visitors.is_empty(),"A browsing visitor can look around and leave without a transaction")
	flow.close_shop()
	print("POLISH TEST: %d checks, %d failures"%[checks,failures])
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
