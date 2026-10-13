extends Node3D
## Physical visitors browse independently, then join a bounded FIFO line or leave.
const Appearance = preload("res://scripts/customer_appearance.gd")
@export var max_visitors := 6
@export var max_queue := 3
@export_range(0,1) var leave_chance := 0.25
@export var browse_pause := Vector2(2.5,5.0)
@export var arrival_interval := Vector2(28.0,45.0)
var manager: Node
var visitors: Array[Node3D] = []
var waiting_visitors: Array[Node3D] = []
var queue_spots: Array[Vector3] = []
var browse_spots: Array[Vector3] = []
var open := false
var generation := 0
var spawn_in := 0.0

func _ready() -> void:
	add_to_group("customer_flow")
	var main := manager.get_parent()
	for marker in main.find_children("*","Marker3D",true,false):
		if is_ancestor_of(marker): continue
		if String(marker.name).begins_with("QueueSpot"): queue_spots.append(marker.global_position)
		if String(marker.name).begins_with("BrowseSpot"): browse_spots.append(marker.global_position)
	if queue_spots.is_empty():
		for marker: Marker3D in $QueueSpots.get_children(): queue_spots.append(manager.cashier_spot.global_position+marker.position)
	if browse_spots.is_empty():
		for marker: Marker3D in $BrowseSpots.get_children(): browse_spots.append(marker.global_position)

func start_day() -> void:
	generation += 1
	for actor in visitors:
		if is_instance_valid(actor): actor.queue_free()
	visitors.clear()
	waiting_visitors.clear()
	open = true
	spawn_in = manager.first_customer_delay

func _process(delta: float) -> void:
	if not open or GameState.failed or GameState.is_time_paused(): return
	spawn_in -= delta
	if spawn_in<=0:
		spawn_visitor()
		spawn_in = randf_range(arrival_interval.x,maxf(arrival_interval.x,arrival_interval.y))
	for actor in waiting_visitors.duplicate():
		if not is_instance_valid(actor): waiting_visitors.erase(actor); continue
		var waited := float(actor.get_meta("waited",0.0))+delta
		actor.set_meta("waited",waited)
		if waited>float(actor.get_meta("patience",120)) and manager._visitor_index>=2: depart(actor)

func ensure_customer() -> void:
	if not waiting_visitors.is_empty(): return
	for actor in visitors:
		if is_instance_valid(actor) and actor.get_meta("visit_phase","") in ["entering","browsing"]:
			actor.set_meta("must_queue",true)
			if actor.get_meta("visit_phase")=="browsing": join_queue(actor)
			return
	if spawn_in<=0:
		spawn_visitor(true)
		spawn_in=randf_range(arrival_interval.x,maxf(arrival_interval.x,arrival_interval.y))

func skip_arrival_wait() -> void:
	if not open: return
	spawn_in = 0.0
	ensure_customer()

func spawn_visitor(force_queue := false) -> Node3D:
	if not open or visitors.size()>=max_visitors: return null
	var scene: PackedScene = manager.customer_scenes.pick_random() if not manager.customer_scenes.is_empty() else load("res://npcs_1.tscn")
	var actor := scene.instantiate() as Node3D
	add_child(actor)
	actor.add_to_group("shop_visitors")
	actor.set_meta("visit_phase","entering")
	actor.set_meta("must_queue",force_queue or manager._visitor_index<2)
	actor.set_interactable(false)
	Appearance.apply_to(actor,randi_range(0,Appearance.CLOTHING_COLORS.size()-1))
	actor.global_position=manager.exit_spot.global_position
	visitors.append(actor)
	_wander(actor,generation)
	return actor

func _valid(actor,token: int) -> bool:
	return token==generation and is_instance_valid(actor) and not actor.is_queued_for_deletion() and visitors.has(actor)

func _browsing(actor,token: int) -> bool:
	return _valid(actor,token) and open and actor.get_meta("visit_phase","") in ["entering","browsing"]

func _wander(actor: Node3D,token: int) -> void:
	var arrived: Variant = await actor.walk_to(manager.door_spot.global_position)
	if not _valid(actor, token): return
	if arrived == false: depart(actor); return
	if not _browsing(actor,token): return
	actor.set_meta("visit_phase","browsing")
	if not bool(actor.get_meta("must_queue")):
		var previous := -1
		for stop in randi_range(1,3):
			var index := randi_range(0,browse_spots.size()-1)
			if index==previous: index=(index+1)%browse_spots.size()
			previous=index
			arrived = await actor.walk_to(browse_spots[index])
			if not _browsing(actor,token): return
			if arrived == false: depart(actor); return
			actor.play("idle")
			var remaining := randf_range(browse_pause.x,browse_pause.y)
			while remaining>0 and _browsing(actor,token):
				await get_tree().process_frame
				if not GameState.is_time_paused(): remaining-=get_process_delta_time()
			if not _browsing(actor,token): return
			if bool(actor.get_meta("must_queue")): break
	if not bool(actor.get_meta("must_queue")) and randf()<leave_chance: depart(actor)
	else: join_queue(actor)

func join_queue(actor: Node3D) -> bool:
	if not open or not is_instance_valid(actor) or waiting_visitors.has(actor): return false
	if waiting_visitors.size()>=mini(max_queue,queue_spots.size()): depart(actor); return false
	actor.set_meta("visit_phase","queued")
	actor.set_meta("waited",0.0)
	actor.set_meta("patience",randf_range(95,150))
	waiting_visitors.append(actor)
	_reflow()
	return true

func _reflow() -> void:
	for i in waiting_visitors.size():
		var actor: Node3D = waiting_visitors[i]
		if int(actor.get_meta("queue_slot",-1))==i: continue
		actor.set_meta("queue_slot",i)
		_move_in_line(actor,queue_spots[i])

func _move_in_line(actor: Node3D,point: Vector3) -> void:
	var arrived: Variant = await actor.walk_to(point)
	if is_instance_valid(actor) and actor.get_meta("visit_phase","")=="queued":
		var slot: int = int(actor.get_meta("queue_slot", -1))
		if slot < 0 or slot >= queue_spots.size() or not queue_spots[slot].is_equal_approx(point): return
		if arrived == false: depart(actor); return
		actor.face_toward(manager.cashier_spot.global_position)
		actor.play("idle")

func take_next() -> Node3D:
	if not is_inside_tree(): return null
	var token := generation
	var tree := get_tree()
	ensure_customer()
	while is_inside_tree() and waiting_visitors.is_empty() and open and token==generation and not GameState.failed:
		await tree.process_frame
	if not is_inside_tree() or not open or token!=generation or waiting_visitors.is_empty(): return null
	var actor: Node3D = waiting_visitors.pop_front()
	if not is_instance_valid(actor): return null
	actor.set_meta("visit_phase","approaching")
	actor.set_meta("shop_serving",true)
	manager.customer=actor
	_reflow()
	var arrived: Variant = await actor.walk_to(manager.cashier_spot.global_position)
	if not _valid(actor,token): return null
	if arrived == false:
		depart(actor)
		if manager.customer == actor: manager.customer = null
		if manager.game_ui: manager.game_ui.show_notice("Keep the route to the counter clear.", 3.0)
		return null
	actor.set_meta("visit_phase", "serving")
	if actor.has_method("set_at_counter"): actor.set_at_counter(true)
	actor.play("idle")
	actor.face_toward(manager.player.global_position)
	return actor

func _exit_tree() -> void:
	open=false
	generation+=1

func depart(actor: Node3D) -> void:
	if not is_instance_valid(actor) or actor.get_meta("visit_phase","")=="leaving": return
	actor.set_meta("visit_phase","leaving")
	if actor.has_method("set_at_counter"): actor.set_at_counter(false)
	actor.set_meta("shop_serving",true)
	actor.set_interactable(false)
	waiting_visitors.erase(actor)
	_reflow()
	await actor.walk_to(manager.door_spot.global_position)
	if not is_instance_valid(actor): return
	await actor.walk_to(manager.exit_spot.global_position)
	if not is_instance_valid(actor): return
	visitors.erase(actor)
	actor.queue_free()

func close_shop() -> void:
	open=false
	for actor in visitors.duplicate():
		if is_instance_valid(actor) and actor.get_meta("visit_phase","")!="serving": depart(actor)
