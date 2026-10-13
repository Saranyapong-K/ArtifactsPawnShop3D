extends SceneTree
## Run before exporting: include game resources and catalog models, not unused art.
var selected: Array[String] = []

func _init() -> void:
	for directory in ["res://scripts", "res://ui", "res://scenes", "res://assets/Audio"]:
		_collect(directory)
	for path in ["res://main_menu.tscn", "res://assets/Scene/main.tscn", "res://Day_manager.tscn", "res://npcs_1.tscn", "res://npcs_2.tscn", "res://npcs_3.tscn"]:
		_add(path)
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/data/artifact_catalog.json"))
	if catalog is Array:
		for item: Dictionary in catalog: _add(item.model_path)
	selected.sort()
	var config := ConfigFile.new()
	if config.load("res://export_presets.cfg") != OK: quit(1); return
	for section in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			config.set_value(section, "export_filter", "resources")
			config.set_value(section, "export_files", PackedStringArray(selected))
	var error := config.save("res://export_presets.cfg")
	print("RELEASE RESOURCES: ", selected.size(), "; save: ", error)
	quit(error)

func _add(path: String) -> void:
	if FileAccess.file_exists(path) and not selected.has(path): selected.append(path)

func _collect(path: String) -> void:
	var directory := DirAccess.open(path)
	if not directory: return
	for name in directory.get_directories():
		if not name.begins_with("."): _collect(path.path_join(name))
	var literal := RegEx.new()
	literal.compile('res://[^"\\\'\\s]+')
	for name in directory.get_files():
		if name.get_extension() in ["import", "uid", "md"]: continue
		var file := path.path_join(name)
		_add(file)
		if name.get_extension() == "gd":
			for found in literal.search_all(FileAccess.get_file_as_string(file)):
				_add(found.get_string())
