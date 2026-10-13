extends Control
## Autumn menu uses the player's original parallax artwork.

const GAMEPLAY := "res://assets/Scene/main.tscn"
const BACKGROUNDS := [
	"res://assets/01_far_landscape.png",
	"res://assets/02_town_and_lake.png",
	"res://assets/03_shop_foreground.png",
]
const AUTUMN := Color("872408")
const GOLD := Color("f7d475")
const BROWN := Color("4a230e")
@export_group("Menu music")
@export var menu_music: Array[AudioStream] = []
@export var music_placeholder := "Music coming soon"
@export_range(10, 100, 1) var music_scroll_speed := 24.0
var _music_index := -1
var _music_started := false
@onready var _music_player: AudioStreamPlayer=$MenuMusic
@onready var _music_clip: Control=$MusicTicker
@onready var _music_name: Label=$MusicTicker/TrackName

var _layers: Array[TextureRect] = []
var _continue: Button
var _book: CanvasLayer
var _message: Label
var _credits: Control
var _loading := false

func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for node_name: String in ["FarLandscape", "TownAndLake", "ShopForeground"]:
		_layers.append(find_child(node_name, true, false))
	_continue = find_child("ContinueButton", true, false)
	_message = find_child("SaveHint", true, false)
	_credits = find_child("CreditsMenu", true, false)
	_book = $SettingsMenu
	_connect_button("NewGameButton", _new_game)
	_connect_button("ContinueButton", _continue_game)
	_connect_button("OptionsButton", func(): _book.show_options(false))
	_connect_button("CreditsButton", _show_credits)
	_connect_button("ExitButton", _quit_game)
	find_child("ExitButton", true, false).visible = not OS.has_feature("web")
	_refresh_continue()
	_music_player.finished.connect(_next_track)
	_next_track()

func _quit_game() -> void:
	_release_music()
	# Let the mixer relinquish its playback before shutting down the engine.
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()

func _release_music() -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null

func _exit_tree() -> void:
	_release_music()

func _connect_button(node_name: String, action: Callable) -> void:
	var button: Button = find_child(node_name, true, false)
	button.pressed.connect(func():
		var sfx := get_node_or_null("/root/Sfx")
		if sfx: sfx.play("click")
		action.call())

func _process(delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	var centered := (get_viewport().get_mouse_position() - viewport_size * 0.5) / viewport_size.max(Vector2.ONE)
	for index in _layers.size():
		var strength := float([8.0, 18.0, 30.0][index])
		var target := Vector2(-45, -35) + centered * strength
		_layers[index].position = _layers[index].position.lerp(target, minf(1.0, delta * 2.0))
	_music_name.position.x-=music_scroll_speed*delta
	if _music_name.position.x+_music_name.size.x<0: _music_name.position.x=_music_clip.size.x
	# Browser audio may need the first click before playback can start.
	if _music_started and _music_player.stream and not _music_player.playing and not menu_music.is_empty(): _music_player.play()

func _next_track() -> void:
	var tracks: Array[AudioStream]=[]
	for stream in menu_music:
		if stream: tracks.append(stream)
	if tracks.is_empty():
		_music_name.text=music_placeholder
		_music_player.stop()
	else:
		_music_index=posmod(_music_index+1,tracks.size())
		var stream:=tracks[_music_index]
		_music_player.stream=stream
		var name_of_song:=stream.resource_path.get_file().get_basename()
		_music_name.text=name_of_song if not name_of_song.is_empty() else (stream.resource_name if not stream.resource_name.is_empty() else "Menu music")
		_music_player.play()
	_music_name.size=Vector2.ZERO
	_music_name.position.x=maxf(0.0,_music_clip.size.x-_music_name.get_minimum_size().x)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed or event is InputEventKey and event.pressed:
		_music_started=true

func _state() -> Node:
	return get_node_or_null("/root/GameState")

func _refresh_continue() -> void:
	var state := _state()
	_continue.disabled = not state or not state.has_save()
	_message.text = "Continue from your last night's sleep." if not _continue.disabled else "Start a new game!"

func _new_game() -> void:
	if _loading: return
	var state := _state()
	if not state:
		_message.text = "The game state could not be loaded."
		return
	state.new_game()
	_loading=true
	await AssetWarmup.prepare(1)
	get_tree().change_scene_to_file(GAMEPLAY)

func _continue_game() -> void:
	if _loading: return
	var state := _state()
	if state and state.load_game():
		_loading=true
		await AssetWarmup.prepare(state.day)
		get_tree().change_scene_to_file(GAMEPLAY)
	else:
		_message.text = "This save could not be loaded. Start a new game."

func _show_credits() -> void:
	_credits.open()
