extends Node
## Lightweight original tones. Replace with assets/Audio/<cue>.ogg when supplied.

signal radio_track_changed(title: String)
signal radio_playback_changed

const RATE := 22050
const VOICES := 6
const RADIO_NAMES := ["Autumn Window", "Copper Leaves"]

var _cues: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_index: int = 0
var _last_played: Dictionary = {}
var _radio: AudioStreamPlayer
var _radio_streams: Array[AudioStreamWAV] = []
var _radio_index: int = 0
var _radio_seconds: float = 0.0
var _radio_active: bool = false
var _poll_seconds: float = 0.0
var _songs: AudioStreamPlayer
var _song_streams: Array[AudioStream] = []
var _song_index := 0
var _song_was_owned := false
var song_state := "stopped"


func _ready() -> void:
	_build_cues()
	_ensure_bus("SFX")
	_ensure_bus("Music")
	for index in range(VOICES):
		var voice := AudioStreamPlayer.new()
		voice.bus = "SFX"
		voice.volume_db = -8.0
		add_child(voice)
		_voices.append(voice)
	_radio = AudioStreamPlayer.new()
	_radio.bus = "SFX"
	_radio.volume_db = -10.0
	add_child(_radio)
	_radio_streams.append(_tone([261.63, 329.63, 392.0, 329.63, 293.66, 349.23, 440.0, 349.23, 261.63, 329.63, 392.0, 523.25, 440.0, 392.0, 329.63, 293.66], 0.7, 0.12, true))
	_radio_streams.append(_tone([220.0, 261.63, 329.63, 392.0, 349.23, 293.66, 261.63, 220.0, 196.0, 246.94, 293.66, 392.0, 329.63, 293.66, 246.94, 196.0], 0.7, 0.12, true))
	_songs = AudioStreamPlayer.new(); _songs.bus="Music"; _songs.volume_db=-10
	add_child(_songs); _songs.finished.connect(_next_song)


func play(cue_name: String, pitch: float = 1.0) -> void:
	var cue := cue_name.to_lower()
	var aliases := {"jackpot": "reveal", "deal": "coin", "angry": "error", "tick": "count"}
	cue = String(aliases.get(cue, cue))
	if not _cues.has(cue) or _voices.is_empty():
		return
	var now := Time.get_ticks_msec()
	var gap := 220 if cue == "footstep" else 35
	if now - int(_last_played.get(cue, -1000)) < gap:
		return
	_last_played[cue] = now
	var voice := _voices[_voice_index]
	_voice_index = (_voice_index + 1) % _voices.size()
	voice.stream = _cues[cue]
	voice.pitch_scale = clampf(pitch, 0.6, 1.8)
	if DisplayServer.get_name() != "headless":
		voice.play()


func _process(delta: float) -> void:
	_poll_seconds += delta
	if _poll_seconds >= 0.25:
		_poll_seconds = 0.0
		_refresh_radio()
	if _radio_active:
		_radio_seconds += delta
		if _radio_seconds >= 67.2:
			_radio_index = (_radio_index + 1) % _radio_streams.size()
			_start_radio_track()


func _refresh_radio() -> void:
	var state := get_node_or_null("/root/GameState")
	var should_play := false
	if state != null:
		var items: Variant = state.get("owned_items")
		should_play = bool(state.get("clock_running")) and not bool(state.get("failed")) and get_tree().current_scene != null and get_tree().current_scene.get_node_or_null("Day_manager") != null
		var owned: bool = should_play and items is Dictionary and bool(items.get("radio", false))
		if owned and not _song_was_owned: play_radio()
		elif not owned and _song_was_owned: stop_radio()
		_song_was_owned=owned
	_radio.volume_db=-23 if song_state=="playing" else -10
	if should_play == _radio_active:
		return
	_radio_active = should_play
	if _radio_active:
		_start_radio_track()
	else:
		_radio.stop()


func _start_radio_track() -> void:
	_radio_seconds = 0.0
	_radio.stream = _radio_streams[_radio_index]
	if DisplayServer.get_name() != "headless":
		_radio.play()

func set_radio_songs(streams: Array[AudioStream]) -> void:
	stop_radio(); _song_streams.clear(); _song_index=0; _song_was_owned=false
	for stream in streams:
		if stream: _song_streams.append(stream)

func play_radio() -> void:
	var state:=get_node_or_null("/root/GameState")
	if not state or not state.owned_items.get("radio",false) or _song_streams.is_empty(): return
	if song_state=="paused":
		_songs.stream_paused=false
	else:
		_songs.stream_paused=false; _songs.stream=_song_streams[_song_index]
		if DisplayServer.get_name()!="headless": _songs.play()
		radio_track_changed.emit(song_name())
	song_state="playing"; radio_playback_changed.emit()

func pause_radio() -> void:
	if song_state!="playing": return
	_songs.stream_paused=true; song_state="paused"; radio_playback_changed.emit()

func stop_radio() -> void:
	if _songs: _songs.stop(); _songs.stream_paused=false
	song_state="stopped"; radio_playback_changed.emit()

func _next_song() -> void:
	if _song_streams.is_empty(): return
	_song_index=(_song_index+1)%_song_streams.size(); song_state="stopped"; play_radio()

func song_name() -> String:
	return _song_streams[_song_index].resource_path.get_file().get_basename() if not _song_streams.is_empty() else "No songs added"


func _build_cues() -> void:
	_cues = {
		"click": _tone([620.0], 0.045, 0.23),
		"coin": _tone([880.0, 1174.66], 0.085, 0.28),
		"door": _tone([100.0, 65.0], 0.09, 0.20),
		"error": _tone([220.0, 146.83], 0.12, 0.22),
		"footstep": _tone([75.0], 0.055, 0.17),
		"warning": _tone([130.81, 138.59, 130.81, 123.47], 0.19, 0.25),
		"count": _tone([740.0], 0.025, 0.16),
		"reveal": _tone([523.25, 659.25, 783.99, 1046.5], 0.10, 0.24),
		"catch": _tone([392.0, 523.25, 659.25], 0.07, 0.25),
		"clean": _tone([392.0, 493.88, 587.33], 0.09, 0.14),
	}
	for cue in _cues:
		var path := "res://assets/Audio/%s.ogg" % cue
		if ResourceLoader.exists(path):
			_cues[cue] = load(path)


func _tone(notes: Array, note_seconds: float, amplitude: float, looped: bool = false) -> AudioStreamWAV:
	var samples_per_note := int(float(RATE) * note_seconds)
	var total := samples_per_note * notes.size()
	var pcm := PackedByteArray()
	pcm.resize(total * 2)
	for index in range(total):
		var note_index := index / samples_per_note
		var phase := float(index % samples_per_note) / float(samples_per_note)
		var envelope := minf(phase * 16.0, 1.0) * pow(1.0 - phase, 1.6)
		var time := float(index) / float(RATE)
		var frequency := float(notes[note_index])
		var wave := sin(TAU * frequency * time) * 0.82 + sin(TAU * frequency * 2.0 * time) * 0.18
		pcm.encode_s16(index * 2, int(clampf(wave * envelope * amplitude, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = pcm
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = total
	return stream


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
