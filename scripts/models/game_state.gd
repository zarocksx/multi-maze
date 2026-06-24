extends Node
class_name GameState

const WALL_TOP: int = 1
const WALL_RIGHT: int = 2
const WALL_BOTTOM: int = 4
const WALL_LEFT: int = 8

var player_id: String = ""
var host_id: String = ""
var room_code: String = ""
var maze: Dictionary = {}
var players: Array = []
var winner_id: String = ""
var race_complete: bool = false
var race_phase: String = "waiting"
var race_start_deadline_ms: int = 0
var go_flash_until_ms: int = 0
var power_ups: Array = []
var podium: Array = []
var maze_scale: int = 5
var current_round: int = 1
var last_event_id: String = ""
var effects_snapshot_local_ms: int = 0
var power_ups_snapshot_local_ms: int = 0


static func grid_position(entity: Dictionary) -> Vector2:
	return Vector2(float(entity.get("x", 0)), float(entity.get("y", 0)))


static func grid_center(entity: Dictionary) -> Vector2:
	return grid_position(entity) + Vector2(0.5, 0.5)


func apply_hello(message: Dictionary) -> void:
	player_id = str(message.get("playerId", ""))


func apply_room_snapshot(message: Dictionary) -> void:
	room_code = str(message.get("room", ""))
	host_id = str(message.get("host", ""))
	maze = message.get("maze", {})
	race_complete = bool(message.get("complete", false))


func apply_state_snapshot(message: Dictionary) -> void:
	host_id = str(message.get("host", host_id))
	race_complete = bool(message.get("complete", false))


func apply_race_metadata(message: Dictionary, local_ms: int) -> void:
	var previous_phase := race_phase
	effects_snapshot_local_ms = local_ms
	power_ups_snapshot_local_ms = local_ms
	race_phase = str(message.get("phase", race_phase))
	power_ups = message.get("powerUps", power_ups)
	podium = message.get("podium", podium)
	current_round = int(message.get("round", current_round))
	maze_scale = clampi(int(message.get("mazeScale", maze_scale)), 1, 10)
	if race_phase == "countdown":
		var server_now := int(message.get("serverNow", 0))
		var start_at := int(message.get("startAt", server_now))
		race_start_deadline_ms = local_ms + maxi(0, start_at - server_now)
	elif previous_phase == "countdown" and race_phase == "running":
		go_flash_until_ms = local_ms + 650
	if race_phase == "waiting":
		last_event_id = ""


func reset_room() -> void:
	room_code = ""
	host_id = ""
	maze.clear()
	players.clear()
	winner_id = ""
	race_complete = false
	race_phase = "waiting"
	race_start_deadline_ms = 0
	go_flash_until_ms = 0
	power_ups.clear()
	podium.clear()
	last_event_id = ""
	effects_snapshot_local_ms = 0
	power_ups_snapshot_local_ms = 0


func set_players(next_players: Array) -> void:
	players = next_players


func set_winner(next_winner: String) -> void:
	winner_id = next_winner


func accept_power_event(event) -> bool:
	if not event is Dictionary:
		return false
	var event_id := str(event.get("id", ""))
	if event_id.is_empty() or event_id == last_event_id:
		return false
	last_event_id = event_id
	return true


func discord_context(max_players: int) -> Dictionary:
	return {
		"room_code": room_code,
		"player_count": players.size(),
		"current_round": current_round,
		"max_players": max_players,
		"race_complete": race_complete,
		"race_phase": race_phase,
		"local_rank": local_player_rank(),
		"local_finished": local_player_finished(),
	}


func race_can_move(local_ms: int) -> bool:
	if race_phase == "running":
		return true
	return race_phase == "countdown" and local_ms >= race_start_deadline_ms


func local_player_finished() -> bool:
	for player in players:
		if str(player.get("id", "")) == player_id:
			return bool(player.get("finished", false))
	return false


func local_effect_active(effect_name: String, local_ms: int) -> bool:
	var player := get_local_player()
	if player.is_empty():
		return false
	return effect_active(player.get("effects", {}), effect_name, local_ms)


func get_local_player() -> Dictionary:
	for player in players:
		if str(player.get("id", "")) == player_id:
			return player
	return {}


func local_effect_remaining(effect_name: String, local_ms: int) -> float:
	var player := get_local_player()
	if player.is_empty():
		return 0.0
	var effects: Dictionary = player.get("effects", {})
	var elapsed := local_ms - effects_snapshot_local_ms
	return maxf(0.0, (int(effects.get("%sMs" % effect_name, 0)) - elapsed) / 1000.0)


func effect_active(effects: Dictionary, effect_name: String, local_ms: int) -> bool:
	if effect_name == "shield":
		return bool(effects.get("shield", false))
	var elapsed := local_ms - effects_snapshot_local_ms
	return int(effects.get("%sMs" % effect_name, 0)) > elapsed


func local_player_rank() -> int:
	var player := get_local_player()
	if player.is_empty():
		return 0
	return int(player.get("rank", 0))


func can_local_player_move(direction: String) -> bool:
	var cells: Array = maze.get("cells", [])
	var width := int(maze.get("width", 0))
	if cells.is_empty() or width <= 0:
		return true
	var wall := 0
	match direction:
		"up":
			wall = WALL_TOP
		"right":
			wall = WALL_RIGHT
		"down":
			wall = WALL_BOTTOM
		"left":
			wall = WALL_LEFT
		_:
			return false
	for player in players:
		if str(player.get("id", "")) != player_id:
			continue
		var index := int(player.get("y", 0)) * width + int(player.get("x", 0))
		return index >= 0 and index < cells.size() and (int(cells[index]) & wall) == 0
	return true
