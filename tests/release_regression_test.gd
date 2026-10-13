extends SceneTree
var checks := 0
var failures := 0
func _init(): run.call_deferred()
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; push_error(message)
func frames(count:=4):
	for i in count: await process_frame
func run():
	if not OS.get_user_data_dir().contains("release-fix-tests"): quit(9); return
	root.position=Vector2i(-16000,-16000); root.size=Vector2i(1152,648)
	var state: Node=root.get_node("GameState")
	state.new_game(); state.set_process(false)
	change_scene_to_file("res://assets/Scene/main.tscn")
	await frames(12)
	var manager: Node=current_scene.get_node("Day_manager")
	while manager.flow==null: await process_frame
	manager._epoch+=1; manager.flow.close_shop(); manager.flow.set_process(false)
	var player: CharacterBody3D=manager.player
	var bed: Node3D=current_scene.get_node("BedSleep")
	var goal:=bed.global_position+Vector3(0,0,1.1)
	var route: PackedVector3Array=manager.navigation.approach_route(player.global_position,goal,player)
	check(not route.is_empty(),"Bed has a route through the real doorway")
	for index in range(1,route.size()):
		check(manager.navigation.motion_clear(route[index-1],route[index],player),"Bed path segment is physically clear")
	var deadline:=Time.get_ticks_msec()+15000
	for point in route:
		while Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(point.x,point.z))>0.15 and Time.get_ticks_msec()<deadline:
			var direction: Vector3=point-player.global_position
			player.rotation.y=atan2(-direction.x,-direction.z)
			Input.action_press("move_forward"); await physics_frame
		Input.action_release("move_forward")
	check(Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(goal.x,goal.z))<0.5,"Actual player follows bed route without a wall collision")
	manager.game_ui.open_panel("stock"); await frames()
	var stars: Control=manager.game_ui._stock.get_node("%RatingStars")
	check(stars.get_script()!=null and stars.rating==state.cleaning.stars(),"Six-star display uses the cleanliness value without font glyphs")
	manager.game_ui.close_panel()
	manager.ui.show_buyer(1,0,200,100,50,"",60)
	check("Loss: 10 G" in manager.ui._sub_label.text,"Buyer acceptance explains a loss")
	manager.ui.update_state(80,0.0,"")
	check("Accept: 80 G" in manager.ui._sub_label.text and "Profit: 20 G" in manager.ui._sub_label.text,"Buyer counteroffer updates amount and profit")
	print("RELEASE REGRESSION TEST: ",checks," checks, ",failures," failures")
	current_scene.queue_free(); await frames(8)
	for audio in root.find_children("*","AudioStreamPlayer",true,false): audio.stop(); audio.stream=null
	await create_timer(0.2).timeout
	quit(0 if failures==0 else 1)
