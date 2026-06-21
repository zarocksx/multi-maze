extends Node2D

const LOCAL_SERVER_URL := "ws://127.0.0.1:8080/ws"
const WALL_TOP := 1
const WALL_RIGHT := 2
const WALL_BOTTOM := 4
const WALL_LEFT := 8

var socket := WebSocketPeer.new()
var player_id := ""
var host_id := ""
var room_code := ""
var maze: Dictionary = {}
var players: Array = []
var winner_id := ""
var pending_message: Dictionary = {}
var last_socket_state := WebSocketPeer.STATE_CLOSED

var panel: PanelContainer
var server_input: LineEdit
var name_input: LineEdit
var room_input: LineEdit
var status_label: Label
var room_label: Label
var restart_button: Button
var copy_button: Button
var held_direction := ""
var move_repeat_timer := 0.0


func _ready() -> void:
	build_interface()
	server_input.text = default_server_url()
	get_viewport().size_changed.connect(_on_viewport_resized)
	queue_redraw()


func build_interface() -> void:
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
	room_label = Label.new()
	room_label.text = ""
	room_label.add_theme_color_override("font_color", Color("ffd166"))
	play_row.add_child(room_label)
	copy_button = Button.new()
	copy_button.text = "Copier le code"
	copy_button.visible = false
	copy_button.pressed.connect(_on_copy_pressed)
	play_row.add_child(copy_button)
	restart_button = Button.new()
	restart_button.text = "Nouveau labyrinthe"
	restart_button.visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	play_row.add_child(restart_button)
	status_label = Label.new()
	status_label.text = "Créez un salon ou rejoignez-en un avec son code."
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	play_row.add_child(status_label)

	var help := Label.new()
	help.text = "Flèches • ZQSD • WASD    |    Premier point à la sortie dorée = victoire"
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_left = 18
	help.offset_right = -18
	help.offset_top = -38
	help.offset_bottom = -12
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_color_override("font_color", Color("9aa9c2"))
	root.add_child(help)


func default_server_url() -> String:
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
	update_network()
	update_movement(delta)


func update_network() -> void:
	var state := socket.get_ready_state()
	if state != WebSocketPeer.STATE_CLOSED:
		socket.poll()
		state = socket.get_ready_state()

	if state != last_socket_state:
		last_socket_state = state
		if state == WebSocketPeer.STATE_OPEN:
			status_label.text = "Connecté au serveur…"
			if not pending_message.is_empty():
				send_json(pending_message)
				pending_message = {}
		elif state == WebSocketPeer.STATE_CLOSED and not room_code.is_empty():
			status_label.text = "Connexion perdue. Vérifiez le serveur."
			room_code = ""
			players.clear()
			maze.clear()
			refresh_room_controls()
			queue_redraw()

	while (
		socket.get_ready_state() == WebSocketPeer.STATE_OPEN
		and socket.get_available_packet_count() > 0
	):
		var packet := socket.get_packet().get_string_from_utf8()
		var message = JSON.parse_string(packet)
		if message is Dictionary:
			handle_message(message)


func connect_and_send(message: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		send_json(message)
		return
	if socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		pending_message = message
		return

	socket = WebSocketPeer.new()
	last_socket_state = WebSocketPeer.STATE_CLOSED
	pending_message = message
	var url := server_input.text.strip_edges()
	if url.is_empty():
		url = default_server_url()
	var error := socket.connect_to_url(url)
	if error != OK:
		pending_message = {}
		status_label.text = "Impossible de démarrer la connexion (%s)." % error_string(error)
	else:
		status_label.text = "Connexion à %s…" % url


func send_json(message: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(message))


func handle_message(message: Dictionary) -> void:
	match str(message.get("type", "")):
		"hello":
			player_id = str(message.get("playerId", ""))
		"room":
			room_code = str(message.get("room", ""))
			host_id = str(message.get("host", ""))
			maze = message.get("maze", {})
			players = message.get("players", [])
			winner_id = str(message.get("winner", ""))
			status_label.text = "%d joueur(s) dans le salon." % players.size()
			refresh_room_controls()
			queue_redraw()
		"state":
			host_id = str(message.get("host", host_id))
			players = message.get("players", [])
			winner_id = str(message.get("winner", ""))
			if not winner_id.is_empty():
				status_label.text = winner_text()
			else:
				status_label.text = "%d joueur(s) • trouvez la sortie !" % players.size()
			queue_redraw()
		"error":
			status_label.text = str(message.get("message", "Erreur du serveur."))


func refresh_room_controls() -> void:
	room_label.text = "Salon : %s" % room_code if not room_code.is_empty() else ""
	copy_button.visible = not room_code.is_empty()
	restart_button.visible = not room_code.is_empty() and host_id == player_id


func winner_text() -> String:
	for player in players:
		if str(player.get("id", "")) == winner_id:
			if winner_id == player_id:
				return "Vous avez gagné !"
			return "%s a gagné !" % str(player.get("name", "Un joueur"))
	return "Partie terminée."


func update_movement(delta: float) -> void:
	if room_code.is_empty() or not winner_id.is_empty():
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		held_direction = ""
		return
	var direction := input_direction()
	if direction.is_empty():
		held_direction = ""
		move_repeat_timer = 0.0
	elif direction != held_direction:
		held_direction = direction
		move_repeat_timer = 0.18
		send_json({"type": "move", "direction": direction})
	else:
		move_repeat_timer -= delta
		if move_repeat_timer <= 0.0:
			move_repeat_timer = 0.085
			send_json({"type": "move", "direction": direction})


func input_direction() -> String:
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
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("07101b"))
	if maze.is_empty():
		draw_idle_mark(viewport_size)
		return

	var width := int(maze.get("width", 1))
	var height := int(maze.get("height", 1))
	var top_margin := maxf(174.0, panel.size.y + 28.0 if panel else 174.0)
	var available := Vector2(viewport_size.x - 48.0, viewport_size.y - top_margin - 58.0)
	var cell_size := floorf(minf(available.x / width, available.y / height))
	cell_size = maxf(cell_size, 8.0)
	var maze_size := Vector2(width * cell_size, height * cell_size)
	var origin := Vector2(
		(viewport_size.x - maze_size.x) * 0.5,
		top_margin + (available.y - maze_size.y) * 0.5
	)

	draw_rect(Rect2(origin - Vector2(7, 7), maze_size + Vector2(14, 14)), Color("0d1b2d"), true)
	draw_goal(origin, cell_size)
	draw_maze_walls(origin, cell_size, width, height)
	draw_players(origin, cell_size)


func draw_idle_mark(viewport_size: Vector2) -> void:
	var center := Vector2(viewport_size.x * 0.5, maxf(360.0, viewport_size.y * 0.58))
	draw_circle(center, 13.0, Color("83e8ff"))
	draw_arc(center, 34.0, 0.0, TAU, 64, Color("26435e"), 3.0, true)


func draw_goal(origin: Vector2, cell_size: float) -> void:
	var goal: Dictionary = maze.get("exit", {})
	var center := origin + Vector2(
		(float(goal.get("x", 0)) + 0.5) * cell_size,
		(float(goal.get("y", 0)) + 0.5) * cell_size
	)
	draw_circle(center, cell_size * 0.31, Color("ffd166"))
	draw_circle(center, cell_size * 0.17, Color("6b4e13"))


func draw_maze_walls(origin: Vector2, cell_size: float, width: int, height: int) -> void:
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


func draw_players(origin: Vector2, cell_size: float) -> void:
	for player in players:
		var center := origin + Vector2(
			(float(player.get("x", 0)) + 0.5) * cell_size,
			(float(player.get("y", 0)) + 0.5) * cell_size
		)
		var color := Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE)
		var radius := clampf(cell_size * 0.27, 4.0, 14.0)
		draw_circle(center, radius + 3.0, Color("07101b"))
		draw_circle(center, radius, color)
		if str(player.get("id", "")) == player_id:
			draw_arc(center, radius + 5.0, 0.0, TAU, 32, Color.WHITE, 2.0, true)


func _on_create_pressed() -> void:
	connect_and_send({"type": "create", "name": player_name()})


func _on_join_pressed() -> void:
	var code := room_input.text.strip_edges().to_upper()
	if code.length() != 4:
		status_label.text = "Le code du salon doit contenir 4 caractères."
		return
	connect_and_send({"type": "join", "room": code, "name": player_name()})


func player_name() -> String:
	var value := name_input.text.strip_edges()
	return value if not value.is_empty() else "Joueur"


func _on_room_text_changed(value: String) -> void:
	var caret := room_input.caret_column
	room_input.text = value.to_upper()
	room_input.caret_column = caret


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(room_code)
	status_label.text = "Code %s copié." % room_code


func _on_restart_pressed() -> void:
	send_json({"type": "restart"})


func _on_viewport_resized() -> void:
	queue_redraw()
