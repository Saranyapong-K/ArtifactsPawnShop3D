extends SceneTree
## Run with --headless --path PROJECT --script res://tests/placement_test.gd.
## Saves only to a dedicated verifier file under the Codex workspace.

const SAVE_FILE := "C:/Users/Syrins/Documents/Codex/2026-10-10/hee/work/placement-test-save.json"
const CELL := 0.4
const SIZES := [Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(2, 2), Vector2i(3, 3)]

var state: Node
var world: Node3D
var placement: Node3D
var camera: Camera3D
var failures: Array[String] = []
var checks := 0
var original_save_path := ""

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func _wait_physics() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _run() -> void:
	state = root.get_node_or_null("GameState")
	if not state:
		state = load("res://scripts/game_state.gd").new()
		state.name = "GameState"
		root.add_child(state)
	original_save_path = String(state.save_path)
	state.save_path = SAVE_FILE
	state.new_game()
	state.money = 100000
	world = Node3D.new()
	world.name = "PlacementTestWorld"
	root.add_child(world)
	world.add_child(_box("Floor", Vector3(0, -0.1, 0), Vector3(30, 0.2, 30)))
	world.add_child(_box("Table", Vector3(0, 0.9, 0), Vector3(3, 0.2, 3)))
	camera = Camera3D.new()
	camera.name = "Camera"
	world.add_child(camera)
	camera.current = true
	placement = load("res://scripts/placement_manager.gd").new()
	placement.name = "Placement"
	world.add_child(placement)
	await _wait_physics()
	await _test_sizes_and_support()
	await _test_occupancy_rotation_and_sale()
	await _test_holding_and_interaction()
	await _test_models()
	await _test_furniture_models()
	await _test_furniture()
	await _test_save_restore()
	state.save_path = original_save_path
	if failures.is_empty():
		print("PLACEMENT_TEST_PASS: ", checks, " checks")
		quit(0)
	else:
		print("PLACEMENT_TEST_FAILED: ", failures.size(), " of ", checks, " checks")
		quit(1)

func _artifact(size := Vector2i.ONE, label := "Test artifact", model := "res://assets/Relics/Sword.glb") -> ArtifactData:
	return ArtifactData.create(model, label, "Common", "normal", size)

func _stock(size: Vector2i, position: Vector3, rotation := 0) -> Node3D:
	var artifact := _artifact(size)
	_check(state.purchase(artifact, 20), "Artifact purchase succeeds in test wallet")
	state.set_sell_price(artifact.id, 40)
	artifact.placement = {"position": [position.x, position.y, position.z], "rotation": rotation, "surface": "test", "placed": true, "held": false}
	return placement.spawn_artifact(artifact, position)

func _clear_stock() -> void:
	for artifact: ArtifactData in state.inventory.duplicate():
		state.remove_artifact(artifact.id)
	await _wait_physics()

func _test_sizes_and_support() -> void:
	for size: Vector2i in SIZES:
		var artifact := _artifact(size)
		for rotation in 4:
			_check(placement.can_place(artifact, Vector3(0, 1.012, 0), rotation), "%s rotation %d fits a clear table" % [size, rotation])
			_check(placement.can_place(artifact, Vector3(4, 0.012, 4), rotation), "%s rotation %d fits the floor" % [size, rotation])
	_check(not placement.can_place(_artifact(Vector2i(3, 3)), Vector3(1.2, 1.012, 0), 0), "A 3x3 artifact cannot overhang the table")
	_check(not placement.can_place(_artifact(), Vector3(4, 1.0, 4), 0), "Artifacts cannot float above the floor")
	# Four corners have support, but the footprint's center is an open gap.
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			world.add_child(_box("SmallPost", Vector3(7 + x_sign * 0.565, 0.9, z_sign * 0.565), Vector3(0.12, 0.2, 0.12)))
	await _wait_physics()
	_check(not placement.can_place(_artifact(Vector2i(3, 3)), Vector3(7, 1.012, 0), 0), "A 3x3 artifact cannot bridge four tiny corner posts with no central support")

func _test_occupancy_rotation_and_sale() -> void:
	var item := _stock(Vector2i(1, 3), Vector3(4, 0.012, 0))
	var artifact: ArtifactData = item.artifact
	_check(not placement.can_place(_artifact(), Vector3(4, 0.012, 0), 0), "Occupied cells reject another artifact")
	_check(placement.can_place(_artifact(), Vector3(4.4, 0.012, 0), 0), "Adjacent cells fit beside a 1x3 artifact before rotation")
	item.rotation.y = PI * 0.5
	placement._record(item, 1, "test")
	_check(not placement.can_place(_artifact(), Vector3(4.4, 0.012, 0), 0), "Rotating 1x3 swaps its occupied width and depth")
	_check(placement.can_place(_artifact(), Vector3(4, 0.012, 0.4), 0), "The rotated item frees its former long-axis cell")
	_check(state.sell(artifact.id, 35), "Selling stocked artifact succeeds")
	_check(not placement.items.has(artifact.id), "Sale immediately frees the placement registry")
	await _wait_physics()
	_check(placement.can_place(_artifact(), Vector3(4, 0.012, 0), 0), "Sale frees the grid cells")

func _test_holding_and_interaction() -> void:
	var item := _stock(Vector2i(1, 2), Vector3(0, 1.012, 0))
	var artifact: ArtifactData = item.artifact
	var previous: Dictionary = artifact.placement.duplicate(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		print("SKIP: hold / hologram input needs a display driver supporting captured mouse; run this verifier with Compatibility rendering")
		await _clear_stock()
		return
	placement.pick_up(item)
	_check(placement.held == item and not item.visible, "Held artifact is invisible")
	_check(item.collision_layer == 0, "Held artifact no longer blocks placement rays")
	_check(placement.ghost != null, "Picking up an artifact creates a model hologram")
	_check(not state.available_stock().has(artifact), "Held invisible artifacts are unavailable to buyers")
	if placement.held != item or placement.ghost == null:
		await _clear_stock()
		return
	camera.global_position = Vector3(0.8, 2.4, 1.6)
	camera.look_at(Vector3(0.8, 1.0, 0))
	await _wait_physics()
	_check(placement._valid, "Looking at a clear table yields a valid placement")
	var valid_material: StandardMaterial3D = placement.footprint_mesh.material_override
	_check(valid_material.albedo_color.g > valid_material.albedo_color.r and valid_material.albedo_color.a < 1, "Valid footprint is translucent green")
	var rotate_event := InputEventAction.new()
	rotate_event.action = "rotate_item"
	rotate_event.pressed = true
	placement._unhandled_input(rotate_event)
	await _wait_physics()
	_check(placement._rotation == 1, "R rotates the held multi-cell footprint")
	var target: Vector3 = placement._candidate
	var place_event := InputEventAction.new()
	place_event.action = "interact"
	place_event.pressed = true
	placement._unhandled_input(place_event)
	_check(placement.held == null and placement.ghost == null, "E commits placement and clears the hologram")
	_check(item.visible and item.collision_layer == 1 and item.global_position.is_equal_approx(target), "Placed artifact appears in its snapped cell with interaction restored")
	_check(int(artifact.placement.get("rotation", 0)) == 1 and not bool(artifact.placement.get("held", false)), "Committed placement stores rotation and clears held status")
	_check(state.available_stock().has(artifact), "Placed listed artifact becomes available to buyers again")
	previous = artifact.placement.duplicate(true)
	placement.pick_up(item)
	camera.global_position = Vector3(4, 2.4, 4)
	camera.look_at(Vector3(4, 2.4, 0))
	world.add_child(_box("VerticalWall", Vector3(4, 2.4, 1), Vector3(2, 2, 0.2)))
	await _wait_physics()
	_check(not placement._valid, "Looking at a vertical wall rejects placement")
	var invalid_material: StandardMaterial3D = placement.footprint_mesh.material_override
	_check(invalid_material.albedo_color.r > invalid_material.albedo_color.g, "Invalid footprint is red")
	placement.cancel_placement()
	_check(placement.held == null and placement.ghost == null, "Cancel clears the held item and hologram")
	_check(item.visible and item.collision_layer == 1, "Cancel restores visibility and interaction collision")
	_check(artifact.placement == previous, "Cancel restores the previous saved placement exactly")
	# Hit the actual relic interaction body through a first-person player ray.
	var player: CharacterBody3D = load("res://assets/Scene/player.tscn").instantiate()
	player.name = "Player"
	world.add_child(player)
	player.set_physics_process(false)
	player.camera.global_position = Vector3(0, 1.5, 2)
	player.camera.look_at(item.get_node("InteractionCollision").global_position)
	placement.player = player
	await _wait_physics()
	player._try_interact()
	_check(placement.held == item, "Player's E ray can reach and pick up the artifact")
	placement.cancel_placement()
	player.queue_free()
	placement.player = null
	camera.current = true
	await _clear_stock()

func _test_models() -> void:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/data/artifact_catalog.json"))
	var entries: Array = catalog if catalog is Array else catalog.get("artifacts", [])
	_check(entries.size() >= 39, "Expanded artifact catalog contains at least 39 models")
	for entry: Dictionary in entries:
		var model: String = String(entry.get("model_path", entry.get("scene", "")))
		if model.is_empty():
			model = "res://assets/Relics/Expanded/%s.glb" % String(entry.get("id", ""))
		var grid: Array = entry.get("grid_size", [1, 1])
		var artifact := _artifact(Vector2i(int(grid[0]), int(grid[1])), String(entry.get("name", model)), model)
		_check(ResourceLoader.exists(model), "Catalog model exists: " + model)
		var visual := ArtifactVisual.create(artifact)
		var bounds := ArtifactVisual.local_bounds(visual)
		_check(bounds.size.y <= 0.8001, "Artifact height cap: " + artifact.display_name)
		_check(bounds.size.x <= artifact.grid_size.x * CELL * 0.8401 and bounds.size.z <= artifact.grid_size.y * CELL * 0.8401, "Artifact fixed footprint cap: " + artifact.display_name)
		_check(absf(bounds.position.y) < 0.001, "Artifact bottom is normalized to its placement surface: " + artifact.display_name)
		visual.free()

func _test_furniture() -> void:
	if not placement.has_method("spawn_furniture"):
		_check(false, "Placement manager implements spawn_furniture for persistent furniture")
		return
	var record := {"id": "placement-verifier-shelf", "name": "Test shelf", "model_path": "res://assets/Relics/Expanded/Furniture/furn_shelf.glb", "cost": 200, "grid_size": [3, 1], "placement": {"position": [-4.0, 0.012, 0.0], "rotation": 0, "surface": "test", "placed": true, "held": false}}
	_check(state.purchase_furniture(record, 200), "Furniture purchase records stock and deducts cost")
	var stored: Dictionary = state.get_furniture(record.id)
	var furniture: Node3D = placement.spawn_furniture(stored, Vector3(-4, 0.012, 0))
	await _wait_physics()
	var bounds := ArtifactVisual.local_bounds(furniture.visual)
	_check(bounds.size.y <= 2.0001, "Furniture models use the 2m height cap")
	_check(not placement.can_place(furniture.artifact, Vector3(0, 1.012, 0), 0, furniture.artifact.id), "Furniture cannot be placed on a counter")
	_check(placement.can_place(furniture.artifact, Vector3(-6, 0.012, 0), 0, furniture.artifact.id), "Furniture can be placed on clear floor")
	_check(not placement.can_place(_artifact(), furniture.global_position, 0), "Furniture's occupied floor footprint blocks overlapping artifacts")
	# Find a real shelf plane using the mesh's own collision shape.
	var shelf_candidate := Vector3.ZERO
	var shelf_found := false
	var shelf_hits := 0
	var rejected_supports: Array[String] = []
	for x in range(-2, 3):
		for z in range(-2, 3):
			var point := furniture.global_position + Vector3(x * 0.08, 0.0, z * 0.08)
			var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.2, point + Vector3.UP * 0.1)
			var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and hit["collider"] == furniture and (hit["normal"] as Vector3).dot(Vector3.UP) > 0.9:
				shelf_hits += 1
				shelf_candidate = hit["position"] + Vector3.UP * 0.012
				if placement.can_place(_artifact(), shelf_candidate, 0):
					shelf_found = true
				else:
					rejected_supports.append(str(shelf_candidate))
	_check(shelf_found, "Artifacts can be supported by the actual furniture shelf geometry")
	if not shelf_found:
		print("SHELF_DIAGNOSTIC: bounds=", bounds, " horizontal hits=", shelf_hits, " rejected positions=", rejected_supports)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	placement.pick_up(furniture)
	_check(not furniture.visible and placement.held == furniture, "Furniture uses the same invisible hold / hologram flow")
	_check(furniture.get_node("InteractionArea").collision_layer == 0, "Held furniture also disables its interaction area")
	placement.cancel_placement()
	furniture.global_position = Vector3(-6, 0.012, 0)
	furniture.rotation.y = PI * 0.5
	placement._record(furniture, 1, "test-floor")
	var stored_position: Array = stored.placement.position
	_check(Vector3(float(stored_position[0]), float(stored_position[1]), float(stored_position[2])).is_equal_approx(Vector3(-6, 0.012, 0)) and int(stored.placement.rotation) == 1, "Furniture placement writes through to its persistent record")

func _test_furniture_models() -> void:
	var menu_script: Script = load("res://scripts/game_ui.gd")
	var furniture_script: Script = load("res://scripts/furniture_item.gd")
	for product: Dictionary in menu_script.FURNITURE:
		var record := {"id": "visual-test-" + String(product.id), "name": product.name, "model_path": "res://assets/Relics/Expanded/Furniture/%s.glb" % product.id, "cost": product.price, "grid_size": product.grid, "placement": {}}
		var furniture: Node3D = furniture_script.new()
		world.add_child(furniture)
		furniture.setup_furniture(record)
		var expected_grid := Vector2i(int(product.grid[0]), int(product.grid[1]))
		_check(furniture.artifact.grid_size == expected_grid, "Furniture retains catalog footprint: " + String(product.name))
		var bounds := ArtifactVisual.local_bounds(furniture.visual)
		_check(bounds.size.y <= 2.0001, "Furniture height cap: " + String(product.name))
		_check(bounds.size.x <= expected_grid.x * CELL * 1.0001 and bounds.size.z <= expected_grid.y * CELL * 1.0001, "Furniture fixed footprint cap: " + String(product.name))
		_check(absf(bounds.position.y) < 0.001, "Furniture bottom normalized to floor: " + String(product.name))
		furniture.queue_free()
	await _wait_physics()

func _test_save_restore() -> void:
	await _clear_stock()
	var item := _stock(Vector2i(1, 3), Vector3(3.2, 0.012, -2), 1)
	var artifact_id: String = item.artifact.id
	var expected: Dictionary = item.artifact.placement.duplicate(true)
	var furniture_before: Array = state.furniture.duplicate(true)
	state.time_minutes = 23 * 60
	_check(state.save_game(SAVE_FILE), "Verifier writes only its dedicated save file")
	state.new_game()
	await _wait_physics()
	_check(state.load_game(SAVE_FILE), "Saved stock and furniture reload")
	var restored: ArtifactData = state.get_artifact(artifact_id)
	var expected_position := Vector3(float(expected.position[0]), float(expected.position[1]), float(expected.position[2]))
	var restored_position := Vector3.ZERO
	if restored != null:
		var values: Array = restored.placement.get("position", [0, 0, 0])
		restored_position = Vector3(float(values[0]), float(values[1]), float(values[2]))
	_check(restored != null and restored_position.is_equal_approx(expected_position) and int(restored.placement.rotation) == int(expected.rotation), "Artifact multi-cell rotation / position persists through save and load")
	var furniture_restored: bool = state.furniture.size() == furniture_before.size()
	for before: Dictionary in furniture_before:
		var after: Dictionary = state.get_furniture(String(before.id))
		if after.is_empty():
			furniture_restored = false
			continue
		var old_position: Array = before.placement.get("position", [0, 0, 0])
		var new_position: Array = after.placement.get("position", [0, 0, 0])
		furniture_restored = furniture_restored and String(after.model_path) == String(before.model_path) and after.grid_size == before.grid_size and int(after.placement.get("rotation", 0)) == int(before.placement.get("rotation", 0))
		furniture_restored = furniture_restored and Vector3(float(old_position[0]), float(old_position[1]), float(old_position[2])).is_equal_approx(Vector3(float(new_position[0]), float(new_position[1]), float(new_position[2])))
	_check(furniture_restored, "Furniture records and placement persist through save and load")
	placement.restore_furniture(Vector3(-4, 0.012, 0))
	placement.restore_stock(Vector3(0, 1.012, 0))
	await _wait_physics()
	for furniture_record: Dictionary in state.furniture:
		var restored_furniture: Node3D = placement.items.get(String(furniture_record.id))
		var coordinates: Array = furniture_record.placement.get("position", [0, 0, 0])
		var expected_furniture_position := Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
		_check(restored_furniture != null and restored_furniture.global_position.is_equal_approx(expected_furniture_position), "Restored furniture appears at its saved position")
		_check(restored_furniture != null and is_equal_approx(restored_furniture.rotation.y, int(furniture_record.placement.get("rotation", 0)) * PI * 0.5), "Restored furniture retains saved rotation")
	var restored_item: Node3D = placement.items.get(artifact_id)
	_check(restored_item != null and restored_item.global_position.is_equal_approx(Vector3(3.2, 0.012, -2)), "Restored artifact appears at its exact saved world position")
	_check(restored_item != null and is_equal_approx(restored_item.rotation.y, PI * 0.5), "Restored artifact retains its saved rotation")
	_check(not placement.can_place(_artifact(), Vector3(3.6, 0.012, -2), 0), "Restored rotated artifact reserves its grid cells")

func _box(label: String, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body
