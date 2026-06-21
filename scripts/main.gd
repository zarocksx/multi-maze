extends Node2D

const LOCAL_SERVER_URL := "ws://127.0.0.1:8080/ws"
const WALL_TOP := 1
const WALL_RIGHT := 2
const WALL_BOTTOM := 4
const WALL_LEFT := 8
const CELEBRATION_COLORS := ["#45d9ff", "#ff5c8a", "#ffd166", "#79e36a", "#b58cff"]

var socket := WebSocketPeer.new()
var player_id := ""
var host_id := ""
var room_code := ""
var maze: Dictionary = {}
var players: Array = []
var winner_id := ""
var race_complete := false
var pending_message: Dictionary = {}
var last_socket_state := WebSocketPeer.STATE_CLOSED

var panel: PanelContainer
var server_input: LineEdit
var name_input: LineEdit
var room_input: LineEdit
var status_label: Label
var copy_button: Button
var score_panel: PanelContainer
var score_rows: VBoxContainer
var score_restart_button: Button
var player_tooltip: Label
var held_direction := ""
var move_repeat_timer := 0.0
var animation_time := 0.0
var wall_hit_timer := 0.0
var visual_positions: Dictionary = {}
var trail_marks: Array = []
var celebration_particles: Array = []
var random := RandomNumberGenerator.new()
var last_maze_origin := Vector2.ZERO
var last_cell_size := 0.0
var hovered_player_id := ""


func _ready() -> void:
	random.randomize()
	_build_interface()
	server_input.text = _default_server_url()
	get_viewport().size_changed.connect(_on_viewport_resized)
	queue_redraw()


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Interface"
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_theme_font_size_override("font_size", 17)
	layer.add_child(root)

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 16
	panel.offset_top = 14
	panel.offset_right = -16
	panel.custom_minimum_size.y = 142
	root.add_child(panel)
	copy_button = Button.new()
	copy_button.text = "Copier le code"
	copy_button.visible = false
	copy_button.custom_minimum_size = Vector2(220, 44)
	copy_button.pressed.connect(_on_copy_pressed)
	root.add_child(copy_button)
	copy_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	copy_button.offset_left = -236
	copy_button.offset_top = 16
	copy_button.offset_right = -16
	copy_button.offset_bottom = 60

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 7)
	margin.add_child(rows)

	var title := Label.new()
	title.text = "A MAZE INC.  •  Course multijoueur"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("83e8ff"))
	rows.add_child(title)

	var server_row := HBoxContainer.new()
	server_row.add_theme_constant_override("separation", 8)
	rows.add_child(server_row)
	var server_caption := Label.new()
	server_caption.text = "Serveur"
	server_row.add_child(server_caption)
	server_input = LineEdit.new()
	server_input.placeholder_text = "wss://jeu.exemple.fr/ws"
	server_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_row.add_child(server_input)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Pseudo"
	name_input.max_length = 16
	name_input.custom_minimum_size.x = 145
	server_row.add_child(name_input)

	var play_row := HBoxContainer.new()
	play_row.add_theme_constant_override("separation", 8)
	rows.add_child(play_row)
	var create_button := Button.new()
	create_button.text = "Créer un salon"
	create_button.pressed.connect(_on_create_pressed)
	play_row.add_child(create_button)
	room_input = LineEdit.new()
	room_input.placeholder_text = "CODE"
	room_input.max_length = 4
	room_input.custom_minimum_size.x = 92
	room_input.text_changed.connect(_on_room_text_changed)
	room_input.text_submitted.connect(func(_text): _on_join_pressed())
	play_row.add_child(room_input)
	var join_button := Button.new()
	join_button.text = "Rejoindre"
	join_button.pressed.connect(_on_join_pressed)
	play_row.add_child(join_button)
	status_label = Label.new()
	status_label.text = "Créez un salon ou rejoignez-en un avec son code."
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	play_row.add_child(status_label)

	var help := Label.new()
	help.text = "Flèches • ZQSD • WASD    |    Atteignez la sortie dorée le plus vite possible"
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_left = 18
	help.offset_right = -18
	help.offset_top = -38
	help.offset_bottom = -12
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_color_override("font_color", Color("9aa9c2"))
	root.add_child(help)

	player_tooltip = Label.new()
	player_tooltip.visible = false
	player_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_tooltip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_tooltip.z_index = 5
	root.add_child(player_tooltip)

	score_panel = PanelContainer.new()
	score_panel.visible = false
	score_panel.z_index = 10
	score_panel.set_anchors_preset(Control.PRESET_CENTER)
	score_panel.offset_left = -270
	score_panel.offset_top = -205
	score_panel.offset_right = 270
	score_panel.offset_bottom = 205
	var score_style := StyleBoxFlat.new()
	score_style.bg_color = Color("101c2d")
	score_style.border_color = Color("ffd166")
	score_style.set_border_width_all(2)
	score_style.set_corner_radius_all(14)
	score_panel.add_theme_stylebox_override("panel", score_style)
	root.add_child(score_panel)

	var score_margin := MarginContainer.new()
	score_margin.add_theme_constant_override("margin_left", 24)
	score_margin.add_theme_constant_override("margin_top", 20)
	score_margin.add_theme_constant_override("margin_right", 24)
	score_margin.add_theme_constant_override("margin_bottom", 20)
	score_panel.add_child(score_margin)
	var score_content := VBoxContainer.new()
	score_content.add_theme_constant_override("separation", 12)
	score_margin.add_child(score_content)

	var score_title := Label.new()
	score_title.text = "TOUT LE MONDE EST ARRIVÉ !"
	score_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_title.add_theme_font_size_override("font_size", 25)
	score_title.add_theme_color_override("font_color", Color("ffd166"))
	score_content.add_child(score_title)
	var score_subtitle := Label.new()
	score_subtitle.text = "Classement de la course"
	score_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_subtitle.add_theme_color_override("font_color", Color("9aa9c2"))
	score_content.add_child(score_subtitle)
	score_content.add_child(HSeparator.new())

	var score_header := HBoxContainer.new()
	score_content.add_child(score_header)
	_add_score_label(score_header, "#", 48, HORIZONTAL_ALIGNMENT_LEFT, Color("9aa9c2"))
	_add_score_label(score_header, "Joueur", 280, HORIZONTAL_ALIGNMENT_LEFT, Color("9aa9c2"))
	_add_score_label(score_header, "Temps", 130, HORIZONTAL_ALIGNMENT_RIGHT, Color("9aa9c2"))

	score_rows = VBoxContainer.new()
	score_rows.add_theme_constant_override("separation", 6)
	score_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	score_content.add_child(score_rows)
	score_restart_button = Button.new()
	score_restart_button.text = "Nouvelle manche"
	score_restart_button.visible = false
	score_restart_button.pressed.connect(_on_score_restart_pressed)
	score_content.add_child(score_restart_button)


func _default_server_url() -> String:
	if OS.has_feature("web"):
		var javascript := (
			"(location.protocol === 'https:' ? 'wss://' : 'ws://')"
			+ " + location.host + '/ws'"
		)
		var value = JavaScriptBridge.eval(javascript)
		if value is String:
			return value
	return LOCAL_SERVER_URL


func _process(delta: float) -> void:
	_update_network()
	_update_movement(delta)
	_update_effects(delta)
	_update_player_tooltip()


func _update_network() -> void:
	var state := socket.get_ready_state()
	if state != WebSocketPeer.STATE_CLOSED:
		socket.poll()
		state = socket.get_ready_state()

	if state != last_socket_state:
		last_socket_state = state
		if state == WebSocketPeer.STATE_OPEN:
			status_label.text = "Connecté au serveur…"
			if not pending_message.is_empty():
				_send_json(pending_message)
				pending_message = {}
		elif state == WebSocketPeer.STATE_CLOSED and not room_code.is_empty():
			status_label.text = "Connexion perdue. Vérifiez le serveur."
			room_code = ""
			host_id = ""
			race_complete = false
			players.clear()
			maze.clear()
			visual_positions.clear()
			trail_marks.clear()
			celebration_particles.clear()
			_refresh_room_controls()
			_refresh_scoreboard()
			queue_redraw()

	while (
		socket.get_ready_state() == WebSocketPeer.STATE_OPEN
		and socket.get_available_packet_count() > 0
	):
		var packet := socket.get_packet().get_string_from_utf8()
		var message = JSON.parse_string(packet)
		if message is Dictionary:
			_handle_message(message)


func _connect_and_send(message: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send_json(message)
		return
	if socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		pending_message = message
		return

	socket = WebSocketPeer.new()
	last_socket_state = WebSocketPeer.STATE_CLOSED
	pending_message = message
	var url := server_input.text.strip_edges()
	if url.is_empty():
		url = _default_server_url()
	var error := socket.connect_to_url(url)
	if error != OK:
		pending_message = {}
		status_label.text = "Impossible de démarrer la connexion (%s)." % error_string(error)
	else:
		status_label.text = "Connexion à %s…" % url


func _send_json(message: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(message))


func _handle_message(message: Dictionary) -> void:
	match str(message.get("type", "")):
		"hello":
			player_id = str(message.get("playerId", ""))
		"room":
			room_code = str(message.get("room", ""))
			host_id = str(message.get("host", ""))
			maze = message.get("maze", {})
			_set_players(message.get("players", []))
			_set_winner(str(message.get("winner", "")))
			race_complete = bool(message.get("complete", false))
			status_label.text = "%d joueur(s) dans le salon." % players.size()
			_refresh_room_controls()
			_refresh_scoreboard()
			queue_redraw()
		"state":
			host_id = str(message.get("host", host_id))
			_set_players(message.get("players", []))
			_set_winner(str(message.get("winner", "")))
			race_complete = bool(message.get("complete", false))
			if not winner_id.is_empty():
				status_label.text = _winner_text()
			else:
				status_label.text = "%d joueur(s) • trouvez la sortie !" % players.size()
			_refresh_room_controls()
			_refresh_scoreboard()
			queue_redraw()
		"error":
			status_label.text = str(message.get("message", "Erreur du serveur."))


func _refresh_room_controls() -> void:
	var is_in_room := not room_code.is_empty()
	panel.visible = not is_in_room
	copy_button.visible = is_in_room
	if is_in_room:
		if winner_id.is_empty():
			copy_button.text = "Copier le code  •  %s" % room_code
		else:
			copy_button.text = "%s  •  Copier %s" % [_winner_text(), room_code]
	queue_redraw()


func _refresh_scoreboard() -> void:
	score_panel.visible = race_complete
	score_restart_button.visible = race_complete and host_id == player_id
	if not race_complete:
		return
	player_tooltip.visible = false
	for child in score_rows.get_children():
		score_rows.remove_child(child)
		child.queue_free()

	var ranked_players := players.duplicate()
	ranked_players.sort_custom(_sort_players_by_rank)
	for player in ranked_players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		score_rows.add_child(row)
		var color := Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE)
		_add_score_label(
			row,
			"%d." % int(player.get("rank", 0)),
			40,
			HORIZONTAL_ALIGNMENT_LEFT,
			color
		)
		_add_score_label(
			row,
			str(player.get("name", "Joueur")),
			280,
			HORIZONTAL_ALIGNMENT_LEFT,
			color
		)
		_add_score_label(
			row,
			_format_time(int(player.get("timeMs", 0))),
			130,
			HORIZONTAL_ALIGNMENT_RIGHT,
			Color("e8f1ff")
		)


func _add_score_label(
	parent: Container,
	text: String,
	minimum_width: float,
	alignment: HorizontalAlignment,
	color: Color
) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = minimum_width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = alignment
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _sort_players_by_rank(first: Dictionary, second: Dictionary) -> bool:
	return int(first.get("rank", 999)) < int(second.get("rank", 999))


func _format_time(time_ms: int) -> String:
	var minutes := int(time_ms / 60000)
	var seconds := int(time_ms / 1000) % 60
	var milliseconds := time_ms % 1000
	return "%02d:%02d.%03d" % [minutes, seconds, milliseconds]


func _winner_text() -> String:
	for player in players:
		if str(player.get("id", "")) == winner_id:
			if winner_id == player_id:
				return "Vous avez gagné !"
			return "%s a gagné !" % str(player.get("name", "Un joueur"))
	return "Partie terminée."


func _set_players(next_players: Array) -> void:
	var previous_targets: Dictionary = {}
	var previous_finished: Dictionary = {}
	for player in players:
		var previous_id := str(player.get("id", ""))
		previous_targets[previous_id] = Vector2(
			float(player.get("x", 0)),
			float(player.get("y", 0))
		)
		previous_finished[previous_id] = bool(player.get("finished", false))

	players = next_players
	var present_players: Dictionary = {}
	var player_just_finished := false
	for player in players:
		var id := str(player.get("id", ""))
		var target := Vector2(float(player.get("x", 0)), float(player.get("y", 0)))
		present_players[id] = true
		if not visual_positions.has(id):
			visual_positions[id] = target
		elif previous_targets.has(id) and previous_targets[id] != target:
			_spawn_trail(
				visual_positions[id],
				target,
				Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE)
			)
		if (
			previous_finished.has(id)
			and not bool(previous_finished[id])
			and bool(player.get("finished", false))
		):
			player_just_finished = true

	for id in visual_positions.keys():
		if not present_players.has(id):
			visual_positions.erase(id)
	if player_just_finished:
		_start_celebration()


func _set_winner(next_winner: String) -> void:
	winner_id = next_winner
	if winner_id.is_empty():
		celebration_particles.clear()


func _update_movement(delta: float) -> void:
	if room_code.is_empty() or _local_player_finished():
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		held_direction = ""
		return
	var direction := _input_direction()
	if direction.is_empty():
		held_direction = ""
		move_repeat_timer = 0.0
	elif direction != held_direction:
		held_direction = direction
		move_repeat_timer = 0.18
		_try_send_move(direction)
	else:
		move_repeat_timer -= delta
		if move_repeat_timer <= 0.0:
			move_repeat_timer = 0.085
			_try_send_move(direction)


func _local_player_finished() -> bool:
	for player in players:
		if str(player.get("id", "")) == player_id:
			return bool(player.get("finished", false))
	return false


func _try_send_move(direction: String) -> void:
	if _can_local_player_move(direction):
		_send_json({"type": "move", "direction": direction})
	elif wall_hit_timer <= 0.0:
		wall_hit_timer = 0.16


func _can_local_player_move(direction: String) -> bool:
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


func _spawn_trail(from: Vector2, to: Vector2, color: Color) -> void:
	for step in range(4):
		trail_marks.append(
			{
				"position": from.lerp(to, float(step) / 4.0),
				"color": color,
				"life": 0.22 + step * 0.035,
				"max_life": 0.36,
			}
		)


func _start_celebration() -> void:
	celebration_particles.clear()
	var goal: Dictionary = maze.get("exit", {})
	var origin := Vector2(float(goal.get("x", 0)) + 0.5, float(goal.get("y", 0)) + 0.5)
	for index in range(52):
		var angle := random.randf_range(0.0, TAU)
		var speed := random.randf_range(1.4, 4.8)
		celebration_particles.append(
			{
				"position": origin,
				"velocity": Vector2.from_angle(angle) * speed,
				"color": Color(CELEBRATION_COLORS[index % CELEBRATION_COLORS.size()]),
				"life": random.randf_range(0.75, 1.35),
				"max_life": 1.35,
			}
		)


func _update_effects(delta: float) -> void:
	animation_time += delta
	wall_hit_timer = maxf(0.0, wall_hit_timer - delta)

	var targets: Dictionary = {}
	for player in players:
		targets[str(player.get("id", ""))] = Vector2(
			float(player.get("x", 0)),
			float(player.get("y", 0))
		)
	var smoothing := 1.0 - exp(-delta * 18.0)
	for id in visual_positions.keys():
		if targets.has(id):
			visual_positions[id] = visual_positions[id].lerp(targets[id], smoothing)

	for index in range(trail_marks.size() - 1, -1, -1):
		var mark: Dictionary = trail_marks[index]
		mark["life"] = float(mark.get("life", 0.0)) - delta
		if float(mark["life"]) <= 0.0:
			trail_marks.remove_at(index)
		else:
			trail_marks[index] = mark

	for index in range(celebration_particles.size() - 1, -1, -1):
		var particle: Dictionary = celebration_particles[index]
		var velocity: Vector2 = particle.get("velocity", Vector2.ZERO)
		velocity.y += 3.2 * delta
		particle["velocity"] = velocity
		particle["position"] = particle.get("position", Vector2.ZERO) + velocity * delta
		particle["life"] = float(particle.get("life", 0.0)) - delta
		if float(particle["life"]) <= 0.0:
			celebration_particles.remove_at(index)
		else:
			celebration_particles[index] = particle

	queue_redraw()


func _update_player_tooltip() -> void:
	if maze.is_empty() or last_cell_size <= 0.0 or race_complete:
		player_tooltip.visible = false
		hovered_player_id = ""
		return

	var mouse_position := get_viewport().get_mouse_position()
	var hovered_player: Dictionary = {}
	var closest_distance := INF
	for player in players:
		var id := str(player.get("id", ""))
		var target := Vector2(float(player.get("x", 0)), float(player.get("y", 0)))
		var visual_position: Vector2 = visual_positions.get(id, target)
		var center := last_maze_origin + (visual_position + Vector2(0.5, 0.5)) * last_cell_size
		var distance := mouse_position.distance_to(center)
		if distance <= last_cell_size * 0.38 + 6.0 and distance < closest_distance:
			hovered_player = player
			closest_distance = distance

	if hovered_player.is_empty():
		player_tooltip.visible = false
		hovered_player_id = ""
		return

	var id := str(hovered_player.get("id", ""))
	var target := Vector2(
		float(hovered_player.get("x", 0)),
		float(hovered_player.get("y", 0))
	)
	var visual_position: Vector2 = visual_positions.get(id, target)
	var center := last_maze_origin + (visual_position + Vector2(0.5, 0.5)) * last_cell_size
	if hovered_player_id != id:
		hovered_player_id = id
		var color := Color.from_string(
			str(hovered_player.get("color", "#ffffff")),
			Color.WHITE
		)
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		player_tooltip.add_theme_stylebox_override("normal", style)
		var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
		var text_color := Color("07101b") if luminance > 0.58 else Color.WHITE
		player_tooltip.add_theme_color_override("font_color", text_color)
		player_tooltip.text = str(hovered_player.get("name", "Joueur"))
		player_tooltip.reset_size()
		player_tooltip.size = player_tooltip.get_combined_minimum_size()

	var tooltip_position := center - Vector2(
		player_tooltip.size.x * 0.5,
		last_cell_size * 0.38 + player_tooltip.size.y + 10.0
	)
	var viewport_size := get_viewport_rect().size
	tooltip_position.x = clampf(tooltip_position.x, 6.0, viewport_size.x - player_tooltip.size.x - 6.0)
	tooltip_position.y = maxf(6.0, tooltip_position.y)
	player_tooltip.position = tooltip_position
	player_tooltip.visible = true


func _input_direction() -> String:
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z):
		return "up"
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		return "right"
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		return "down"
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q):
		return "left"
	return ""


func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	_draw_background(viewport_size)
	if maze.is_empty():
		_draw_idle_mark(viewport_size)
		return

	var width := int(maze.get("width", 1))
	var height := int(maze.get("height", 1))
	var top_margin := 72.0
	if room_code.is_empty():
		top_margin = maxf(174.0, panel.size.y + 28.0 if panel else 174.0)
	var available := Vector2(viewport_size.x - 48.0, viewport_size.y - top_margin - 58.0)
	var cell_size := floorf(minf(available.x / width, available.y / height))
	cell_size = maxf(cell_size, 8.0)
	var maze_size := Vector2(width * cell_size, height * cell_size)
	var origin := Vector2(
		(viewport_size.x - maze_size.x) * 0.5,
		top_margin + (available.y - maze_size.y) * 0.5
	)
	if wall_hit_timer > 0.0:
		var shake := wall_hit_timer / 0.16 * 2.8
		origin += Vector2(sin(animation_time * 91.0), cos(animation_time * 77.0)) * shake
	last_maze_origin = origin
	last_cell_size = cell_size

	var maze_backing := Color("0d1b2d")
	if wall_hit_timer > 0.0:
		maze_backing = maze_backing.lerp(Color("54203a"), wall_hit_timer / 0.16 * 0.35)
	draw_rect(Rect2(origin - Vector2(7, 7), maze_size + Vector2(14, 14)), maze_backing, true)
	_draw_goal(origin, cell_size)
	_draw_trails(origin, cell_size)
	_draw_maze_walls(origin, cell_size, width, height)
	_draw_celebration(origin, cell_size)
	_draw_players(origin, cell_size)


func _draw_background(viewport_size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("07101b"))
	for index in range(28):
		var x := fmod(31.0 + index * 97.0, viewport_size.x)
		var y := fmod(
			47.0 + index * 61.0 + sin(animation_time * 0.35 + index) * 12.0,
			viewport_size.y
		)
		var alpha := 0.08 + (sin(animation_time * 0.8 + index * 1.7) + 1.0) * 0.035
		draw_circle(Vector2(x, y), 1.2 + index % 3 * 0.45, Color(0.4, 0.75, 0.95, alpha))


func _draw_idle_mark(viewport_size: Vector2) -> void:
	var center := Vector2(viewport_size.x * 0.5, maxf(360.0, viewport_size.y * 0.58))
	var pulse := 1.0 + sin(animation_time * 2.8) * 0.09
	draw_circle(center, 24.0 * pulse, Color(0.18, 0.75, 0.95, 0.08))
	draw_circle(center, 13.0 * pulse, Color("83e8ff"))
	draw_arc(
		center,
		34.0 * pulse,
		animation_time,
		animation_time + PI * 1.45,
		48,
		Color("3f6f91"),
		3.0,
		true
	)


func _draw_goal(origin: Vector2, cell_size: float) -> void:
	var goal: Dictionary = maze.get("exit", {})
	var center := origin + Vector2(
		(float(goal.get("x", 0)) + 0.5) * cell_size,
		(float(goal.get("y", 0)) + 0.5) * cell_size
	)
	var pulse := 1.0 + sin(animation_time * 4.2) * 0.1
	draw_circle(center, cell_size * 0.46 * pulse, Color(1.0, 0.75, 0.25, 0.09))
	draw_circle(center, cell_size * 0.31 * pulse, Color("ffd166"))
	draw_circle(center, cell_size * 0.15, Color("6b4e13"))
	draw_arc(
		center,
		cell_size * 0.39,
		-animation_time * 1.8,
		-animation_time * 1.8 + PI * 1.25,
		28,
		Color(1.0, 0.93, 0.62, 0.8),
		clampf(cell_size * 0.045, 1.2, 2.5),
		true
	)


func _draw_trails(origin: Vector2, cell_size: float) -> void:
	for mark in trail_marks:
		var position: Vector2 = mark.get("position", Vector2.ZERO)
		var life_ratio := clampf(
			float(mark.get("life", 0.0)) / float(mark.get("max_life", 1.0)),
			0.0,
			1.0
		)
		var color: Color = mark.get("color", Color.WHITE)
		color.a = life_ratio * 0.28
		var center := origin + (position + Vector2(0.5, 0.5)) * cell_size
		draw_circle(center, cell_size * 0.18 * life_ratio, color)


func _draw_celebration(origin: Vector2, cell_size: float) -> void:
	for particle in celebration_particles:
		var position: Vector2 = particle.get("position", Vector2.ZERO)
		var life_ratio := clampf(
			float(particle.get("life", 0.0)) / float(particle.get("max_life", 1.0)),
			0.0,
			1.0
		)
		var color: Color = particle.get("color", Color.WHITE)
		color.a = life_ratio
		var center := origin + position * cell_size
		var radius := clampf(cell_size * 0.085 * life_ratio, 1.5, 5.0)
		draw_circle(center, radius, color)


func _draw_maze_walls(origin: Vector2, cell_size: float, width: int, height: int) -> void:
	var cells: Array = maze.get("cells", [])
	var wall_color := Color("c6d5e8")
	var wall_width := clampf(cell_size * 0.085, 2.0, 5.0)
	for y in range(height):
		for x in range(width):
			var index := y * width + x
			if index >= cells.size():
				continue
			var walls := int(cells[index])
			var p := origin + Vector2(x * cell_size, y * cell_size)
			if walls & WALL_TOP:
				draw_line(p, p + Vector2(cell_size, 0), wall_color, wall_width, true)
			if walls & WALL_LEFT:
				draw_line(p, p + Vector2(0, cell_size), wall_color, wall_width, true)
			if y == height - 1 and walls & WALL_BOTTOM:
				draw_line(
					p + Vector2(0, cell_size),
					p + Vector2(cell_size, cell_size),
					wall_color,
					wall_width,
					true
				)
			if x == width - 1 and walls & WALL_RIGHT:
				draw_line(
					p + Vector2(cell_size, 0),
					p + Vector2(cell_size, cell_size),
					wall_color,
					wall_width,
					true
				)


func _draw_players(origin: Vector2, cell_size: float) -> void:
	for player in players:
		var id := str(player.get("id", ""))
		var target := Vector2(float(player.get("x", 0)), float(player.get("y", 0)))
		var visual_position: Vector2 = visual_positions.get(id, target)
		var center := origin + (visual_position + Vector2(0.5, 0.5)) * cell_size
		var color := Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE)
		var radius := clampf(cell_size * 0.27, 4.0, 14.0)
		var glow := color
		glow.a = 0.13 + (sin(animation_time * 5.0 + center.x) + 1.0) * 0.025
		draw_circle(center, radius + 8.0, glow)
		draw_circle(center + Vector2(0, 2), radius + 3.0, Color(0.01, 0.03, 0.06, 0.85))
		draw_circle(center, radius, color)
		draw_circle(center - Vector2(radius * 0.28, radius * 0.28), radius * 0.22, Color(1, 1, 1, 0.55))
		if id == player_id:
			draw_arc(
				center,
				radius + 5.0,
				animation_time * 2.2,
				animation_time * 2.2 + PI * 1.55,
				28,
				Color.WHITE,
				2.0,
				true
			)


func _on_create_pressed() -> void:
	_connect_and_send({"type": "create", "name": _player_name()})


func _on_join_pressed() -> void:
	var code := room_input.text.strip_edges().to_upper()
	if code.length() != 4:
		status_label.text = "Le code du salon doit contenir 4 caractères."
		return
	_connect_and_send({"type": "join", "room": code, "name": _player_name()})


func _player_name() -> String:
	var value := name_input.text.strip_edges()
	return value if not value.is_empty() else "Joueur"


func _on_room_text_changed(value: String) -> void:
	var caret := room_input.caret_column
	room_input.text = value.to_upper()
	room_input.caret_column = caret


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(room_code)
	status_label.text = "Code %s copié." % room_code


func _on_score_restart_pressed() -> void:
	_send_json({"type": "restart"})


func _on_viewport_resized() -> void:
	queue_redraw()
