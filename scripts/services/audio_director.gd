extends Node
class_name AudioDirector

const SAMPLE_RATE := 11025.0
const BUFFER_LENGTH := 0.45
const DEFAULT_POOL_SIZE := 8

var audio_players: Array[AudioStreamPlayer] = []
var audio_player_index := 0
var music_timer := 0.0
var music_note_index := 0
var random := RandomNumberGenerator.new()


func setup(pool_size: int = DEFAULT_POOL_SIZE) -> void:
	if not audio_players.is_empty():
		return
	random.randomize()
	for _index in range(pool_size):
		var player := AudioStreamPlayer.new()
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = SAMPLE_RATE
		stream.buffer_length = BUFFER_LENGTH
		player.stream = stream
		add_child(player)
		audio_players.append(player)


func play_tone(
	frequency: float,
	duration: float,
	volume: float = 0.16,
	waveform: String = "sine",
	slide: float = 0.0
) -> void:
	if audio_players.is_empty():
		return
	var player: AudioStreamPlayer = audio_players[audio_player_index % audio_players.size()]
	audio_player_index += 1
	player.stop()
	player.play()
	var playback = player.get_stream_playback()
	if not playback:
		return
	var frame_count := int(duration * SAMPLE_RATE)
	for frame in range(frame_count):
		var progress := float(frame) / maxf(1.0, frame_count - 1.0)
		var current_frequency := frequency + slide * progress
		var phase := TAU * current_frequency * float(frame) / SAMPLE_RATE
		var sample := sin(phase)
		if waveform == "square":
			sample = 1.0 if sample >= 0.0 else -1.0
		elif waveform == "noise":
			sample = random.randf_range(-1.0, 1.0)
		var envelope := minf(1.0, progress * 14.0) * minf(1.0, (1.0 - progress) * 8.0)
		var value := sample * volume * envelope
		playback.push_frame(Vector2(value, value))


func update_music(
	delta: float,
	can_move: bool,
	local_player_finished: bool,
	local_player: Dictionary,
	maze: Dictionary
) -> void:
	if not can_move or local_player_finished:
		music_timer = 0.0
		return
	if local_player.is_empty():
		return
	var goal: Dictionary = maze.get("exit", {})
	var distance := absf(float(goal.get("x", 0)) - float(local_player.get("x", 0)))
	distance += absf(float(goal.get("y", 0)) - float(local_player.get("y", 0)))
	var maximum_distance := maxf(1.0, float(maze.get("width", 1) + maze.get("height", 1) - 2))
	var progress := clampf(1.0 - distance / maximum_distance, 0.0, 1.0)
	music_timer -= delta
	if music_timer <= 0.0:
		var notes := [110.0, 138.6, 164.8, 220.0]
		play_tone(notes[music_note_index % notes.size()], 0.075, 0.025, "square")
		music_note_index += 1
		music_timer = lerpf(0.72, 0.23, progress)
