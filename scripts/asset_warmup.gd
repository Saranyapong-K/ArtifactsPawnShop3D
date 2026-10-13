extends Node
## Cache models and draw them once before play, reducing first-appearance stalls.
const LoadingScene = preload("res://ui/loading_screen.tscn")
const CustomerAppearance = preload("res://scripts/customer_appearance.gd")
var prepared_day := 0
var busy := false
var resources: Dictionary = {}
var warmed: Dictionary = {}
var _screen: CanvasLayer

func prepare(day: int) -> void:
	while busy: await get_tree().process_frame
	if prepared_day >= mini(day,2): return
	busy=true
	var state := get_node_or_null("/root/GameState")
	if state: state.pause_time(&"asset_loading")
	_screen=LoadingScene.instantiate(); add_child(_screen)
	_screen.get_node("%Title").text="Preparing your shop…" if day<=1 else "Preparing the next day…"
	await get_tree().process_frame
	await get_tree().process_frame
	var paths: Array[String] = ["res://assets/Scene/main.tscn", "res://assets/Customers/NPCS1.glb", "res://assets/Customers/NPCS2.glb", "res://assets/Customers/NPCS3.glb", "res://assets/Customers/GoblinPolice.glb", "res://assets/Customers/Goblin.glb"]
	var entries:=DayQueue._catalog()
	for entry: Dictionary in entries:
		if day<=1 and String(entry.get("rarity","Common")) not in ["Common","Uncommon"]: continue
		var path:=String(entry.model_path)
		if not paths.has(path): paths.append(path)
	var stage := SubViewport.new()
	stage.size=Vector2i(64,64); stage.own_world_3d=true
	stage.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(stage)
	var camera:=Camera3D.new(); stage.add_child(camera)
	camera.position=Vector3(0,0.3,1.4); camera.look_at(Vector3(0,0.2,0)); camera.current=true
	var light:=DirectionalLight3D.new(); stage.add_child(light); light.rotation_degrees=Vector3(-45,-20,0)
	var headless:=DisplayServer.get_name()=="headless"
	var requests: Dictionary = {}
	for path: String in paths:
		if not resources.has(path): requests[path] = ResourceLoader.load_threaded_request(path)
	var batch: Array[Node3D] = []
	for index in paths.size():
		var path:=paths[index]
		_screen.get_node("%Progress").value=float(index)/paths.size()*100
		_screen.get_node("%Detail").text="Settling in · %d / %d" % [index+1,paths.size()]
		await get_tree().process_frame
		if not resources.has(path):
			var status: int = requests.get(path, ERR_CANT_OPEN)
			if status == OK:
				while ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					await get_tree().process_frame
				if ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_LOADED: resources[path]=ResourceLoader.load_threaded_get(path)
			if not resources.has(path): resources[path]=load(path)
		if warmed.has(path) or path.ends_with(".tscn"): continue
		var visual: Node3D
		if path.contains("Customers"):
			visual=(resources[path] as PackedScene).instantiate()
			# Warm the actual recolour shader and masked meshes before visitors arrive.
			CustomerAppearance.apply_to(visual, 0, 0)
			ArtifactVisual._strip_physics(visual)
			var bounds:=ArtifactVisual.local_bounds(visual)
			var factor:=0.6/maxf(bounds.size.y,0.01)
			visual.scale=Vector3.ONE*factor
			visual.position=-bounds.get_center()*factor+Vector3.UP*0.2
		else:
			visual=ArtifactVisual.create(ArtifactData.create(path,"Warmup","Common"))
		stage.add_child(visual)
		batch.append(visual)
		warmed[path]=true
		if batch.size() >= 4:
			await _draw_batch(stage, batch, headless)
	if not batch.is_empty(): await _draw_batch(stage, batch, headless)
	stage.queue_free()
	_screen.get_node("%Progress").value=100
	await get_tree().process_frame
	_screen.queue_free(); _screen=null
	prepared_day=mini(day,2); busy=false
	if state: state.resume_time(&"asset_loading")

func _draw_batch(stage: SubViewport, batch: Array[Node3D], headless: bool) -> void:
	stage.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	if not headless: await RenderingServer.frame_post_draw
	for visual in batch: visual.queue_free()
	batch.clear()
	await get_tree().process_frame
