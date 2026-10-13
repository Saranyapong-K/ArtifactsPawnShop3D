extends SceneTree
## Exercise real meshes, physics rays and E placement on every purchased display.
const Furniture = preload("res://scripts/furniture_item.gd")
var checks := 0
var failures := 0
var world: Node3D
var placement: Node3D
var camera: Camera3D
var state: Node

func _init(): run.call_deferred()
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; push_error(message)
func settle():
	await physics_frame; await physics_frame; await process_frame

func make_world():
	world = Node3D.new(); root.add_child(world)
	var floor_body := StaticBody3D.new(); world.add_child(floor_body)
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(40,0.2,40); shape.shape=box; shape.position.y=-0.1; floor_body.add_child(shape)
	placement = load("res://scripts/placement_manager.gd").new(); world.add_child(placement)
	camera = Camera3D.new(); world.add_child(camera); camera.current=true

func run():
	if not OS.get_user_data_dir().contains("furniture-tests"): quit(9); return
	root.position=Vector2i(-16000,-16000); root.size=Vector2i(1152,648)
	state=root.get_node("GameState"); state.new_game(); state.set_process(false); state.money=100000
	make_world(); await settle()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var input_supported := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var menu: Script=load("res://scripts/game_ui.gd")
	for product: Dictionary in menu.FURNITURE:
		var record := {"id":"surface-"+product.id,"name":product.name,"model_path":"res://assets/Relics/Expanded/Furniture/%s.glb" % product.id,"cost":product.price,"grid_size":product.grid,"display_sizing_version":1,"placement":{"position":[0.137,0.012,0.123],"rotation":0,"placed":true}}
		check(state.purchase_furniture(record,product.price), "Buy " + product.id)
		var item: Node3D=placement.spawn_furniture(state.get_furniture(record.id),Vector3.ZERO)
		var bounds:=ArtifactVisual.local_bounds(item.visual)
		check(bounds.size.y>1.0 and bounds.size.y<=2.001, "Human-scale height: " + product.id)
		check(bounds.size.x<=item.artifact.grid_size.x*0.4+0.001 and bounds.size.z<=item.artifact.grid_size.y*0.4+0.001, "Floor footprint contains visual: " + product.id)
		var preview:=Furniture.create_visual(item.artifact)
		check(ArtifactVisual.local_bounds(preview).size.is_equal_approx(bounds.size), "Placement ghost has final furniture dimensions: " + product.id)
		preview.free()
		for turn in 4:
			item.global_position=Vector3(0.137+turn*0.157,0.012,0.123-turn*0.113)
			item.rotation.y=turn*PI*0.5; placement._record(item,turn,"test-floor"); await settle()
			var artifact:=ArtifactData.create("res://assets/Relics/Goldcoin.glb","Display coin","Common")
			var positions: Array[Vector3]=[]
			for patch: Dictionary in item.get_placement_patches():
				var rect: Rect2=patch.rect
				if rect.size.x<0.33 or rect.size.y<0.33: continue
				var hit:=Vector3(rect.get_center().x,patch.y,rect.get_center().y)
				var result: Dictionary=placement.resolve_candidate(artifact,hit,0,"",item)
				if result.valid and result.position.y>item.global_position.y+0.1: positions.append(result.position)
			check(not positions.is_empty(), "Usable artifact grid: %s rotation %d" % [product.id,turn])
			check(positions.any(func(p): return p.y < item.global_position.y+bounds.size.y-0.1), "Usable lower/display shelf: %s rotation %d" % [product.id,turn])
			check(not placement.can_place(artifact,item.global_position,0), "Furniture still blocks its floor cells")
			if positions.is_empty(): continue
			positions.sort_custom(func(a,b): return a.y<b.y)
			var target: Vector3=positions[0]
			if target.y<0.3 and positions.size()>1: target=positions[1]
			check(not placement.can_place(ArtifactData.create(artifact.model_path,"Oversized","Common","normal",Vector2i(3,3)),target,0), "Oversized artifact rejected")
			check(state.purchase(artifact,20), "Buy placement fixture")
			artifact.placement={"position":[-3.0,0.012,-3.0],"placed":true,"rotation":0}
			var relic: Node3D=placement.spawn_artifact(artifact,Vector3.ZERO)
			if input_supported:
				placement.pick_up(relic)
				camera.global_position=target+item.global_basis*Vector3(0,0.25,1.8)
				camera.look_at(target-Vector3.UP*0.012); await settle(); await settle()
				if not placement._valid:
					# Imported shelves face different directions; solid backs must block rays.
					camera.global_position=target+item.global_basis*Vector3(0,0.25,-1.8)
					camera.look_at(target-Vector3.UP*0.012); await settle(); await settle()
				check(placement._valid, "Real camera ray finds green grid: %s rotation %d" % [product.id,turn])
				var press:=InputEventAction.new(); press.action="interact"; press.pressed=true
				placement._unhandled_input(press)
				check(placement.held==null and artifact.placement.get("placed",false), "E commits furniture display placement")
				if placement.held: placement.cancel_placement()
			else:
				relic.global_position=target; placement._record(relic,0,str(item.get_path()))
			check(not placement.can_place(artifact,relic.global_position,0), "Occupied display cell rejects overlap")
			check(placement._has_displayed_artifacts(item), "Occupied furniture is protected from pickup")
			state.remove_artifact(artifact.id); await settle()
		state.furniture.clear(); state.changed.emit(); await settle()
	await legacy_roundtrip()
	print("FURNITURE SURFACE TEST: ",checks," checks, ",failures," failures; real input=",input_supported)
	world.queue_free(); await settle()
	for audio in root.find_children("*","AudioStreamPlayer",true,false): audio.stop(); audio.stream=null
	quit(0 if failures==0 else 1)

func legacy_roundtrip():
	var record: Dictionary={"id":"legacy-shelf","name":"Existing shelf","model_path":"res://assets/Relics/Expanded/Furniture/furn_shelf.glb","cost":200,"grid_size":[3,1],"placement":{"position":[1.137,0.012,1.123],"rotation":1,"placed":true}}
	state.purchase_furniture(record,200)
	var coin:=ArtifactData.create("res://assets/Relics/Goldcoin.glb","Saved shelf coin","Common")
	state.purchase(coin,20)
	coin.placement={"position":[1.137,1.624,1.123],"rotation":0,"placed":true,"surface":"old-furniture"}
	var relic: Node3D=placement.spawn_artifact(coin,Vector3.ZERO)
	var item: Node3D=placement.spawn_furniture(state.get_furniture(record.id),Vector3.ZERO)
	await settle()
	check(absf(relic.global_position.y-1.824)<0.002, "Saved artifact follows resized shelf, without changing its own scale")
	check(placement.can_place(coin,relic.global_position,0,coin.id), "Migrated artifact remains physically supported")
	check(item.record.grid_size==[4,2] and item.record.display_sizing_version==1, "Legacy furniture stores updated dimensions")
	var expected:=relic.global_position
	check(state.save_game("user://furniture-roundtrip.json"), "Private save succeeds")
	world.queue_free(); await settle()
	state.new_game(); state.set_process(false)
	check(state.load_game("user://furniture-roundtrip.json"), "Save with furniture loads")
	make_world(); placement.restore_stock(Vector3.ZERO); placement.restore_furniture(); await settle()
	relic=placement.items[coin.id]; item=placement.items[record.id]
	check(relic.global_position.is_equal_approx(expected), "Reload does not apply resizing twice")
	check(placement.resolve_candidate(relic.artifact,relic.global_position-Vector3.UP*0.012,0,coin.id,item).valid, "Restored furniture retains usable grid")
