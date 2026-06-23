extends Node2D

const LOCAL_SERVER_URL := "ws://127.0.0.1:8080/ws"
const WALL_TOP := 1
const WALL_RIGHT := 2
const WALL_BOTTOM := 4
const WALL_LEFT := 8
const CELEBRATION_COLORS := ["#45d9ff", "#ff5c8a", "#ffd166", "#79e36a", "#b58cff"]
const SETTINGS_PATH := "user://settings.cfg"
const GAMEPAD_DEADZONE := 0.42

var socket := WebSocketPeer.new()
var auth_request: HTTPRequest
var auth_request_action := ""
var discord_user: Dictionary = {}
var discord_session_token := ""
var discord_activity_mode := false
var discord_activity_ready := false
var discord_login_pending := false
var discord_bridge_error := ""
var discord_bridge_poll_timer := 0.0
var avatar_textures: Dictionary = {}
var player_id := ""
var host_id := ""
var room_code := ""
var maze: Dictionary = {}
var players: Array = []
var winner_id := ""
var race_complete := false
var race_phase := "waiting"
var race_start_deadline_ms := 0
var go_flash_until_ms := 0
var power_ups: Array = []
var podium: Array = []
var maze_scale := 5
var current_round := 1
var last_event_id := ""
var effects_snapshot_local_ms := 0
var power_ups_snapshot_local_ms := 0
var pending_message: Dictionary = {}
var last_socket_state := WebSocketPeer.STATE_CLOSED

var panel: PanelContainer
var server_input: LineEdit
var name_input: LineEdit
var room_input: LineEdit
var status_label: Label
var discord_button: Button
var discord_status_label: Label
var create_button: Button
var join_button: Button
var copy_button: Button
var start_race_button: Button
var waiting_label: Label
var maze_size_controls: VBoxContainer
var maze_size_label: Label
var maze_size_slider: HSlider
var countdown_label: Label
var event_toast: Label
var event_toast_timer := 0.0
var rank_label: Label
var effect_hud_label: Label
var score_panel: PanelContainer
var score_rows: VBoxContainer
var podium_rows: VBoxContainer
var score_subtitle: Label
var score_restart_button: Button
var wall_shake_toggle: CheckButton
var player_tooltip: Label
var held_direction := ""
var move_repeat_timer := 0.0
var animation_time := 0.0
var wall_hit_timer := 0.0
var visual_positions: Dictionary = {}
var trail_marks: Array = []
var movement_ripples: Array = []
var pickup_particles: Array = []
var celebration_particles: Array = []
var random := RandomNumberGenerator.new()
var last_maze_origin := Vector2.ZERO
var last_cell_size := 0.0
var hovered_player_id := ""
var finish_slow_timer := 0.0
var power_down_flash_timer := 0.0
var power_down_flash_color := Color.TRANSPARENT
var active_power_downs: Dictionary = {}
var direction_hint_until_ms := 0
var last_countdown_value := ""
var music_timer := 0.0
var music_note_index := 0
var audio_players: Array = []
var audio_player_index := 0
var scoreboard_animated_round := 0
var wall_shake_enabled := true
var touchscreen_available := false
var touch_controls: PanelContainer
var touch_direction := ""


func _ready() -> void:
	random.randomize()
	_load_settings()
	_setup_audio()
	touchscreen_available = _detect_touchscreen()
	_build_interface()
	server_input.text = _default_server_url()
	_check_discord_session()
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

	server_input = LineEdit.new()
	server_input.visible = false
	root.add_child(server_input)

	panel = PanelContainer.new()
	panel.set_anchor(SIDE_LEFT, 0.5)
	panel.set_anchor(SIDE_TOP, 0.5)
	panel.set_anchor(SIDE_RIGHT, 0.5)
	panel.set_anchor(SIDE_BOTTOM, 0.5)
	panel.custom_minimum_size.y = 220
	var lobby_style := StyleBoxFlat.new()
	lobby_style.bg_color = Color("0d1929")
	lobby_style.border_color = Color(0.32, 0.79, 0.95, 0.42)
	lobby_style.set_border_width_all(2)
	lobby_style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", lobby_style)
	root.add_child(panel)
	_layout_lobby_panel()
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
	start_race_button = Button.new()
	start_race_button.text = "Lancer le départ"
	start_race_button.visible = false
	start_race_button.custom_minimum_size = Vector2(220, 42)
	start_race_button.pressed.connect(_on_start_race_pressed)
	root.add_child(start_race_button)
	start_race_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	start_race_button.offset_left = -236
	start_race_button.offset_top = 68
	start_race_button.offset_right = -16
	start_race_button.offset_bottom = 110
	_apply_button_style(
		start_race_button,
		Color("1d6b48"),
		Color("278c60"),
		Color("e8fff3")
	)
	waiting_label = Label.new()
	waiting_label.text = "En attente du départ de l’hôte…"
	waiting_label.visible = false
	waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_label.add_theme_color_override("font_color", Color("9fb3c8"))
	waiting_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	waiting_label.offset_left = -286
	waiting_label.offset_top = 72
	waiting_label.offset_right = -16
	waiting_label.offset_bottom = 108
	root.add_child(waiting_label)
	maze_size_controls = VBoxContainer.new()
	maze_size_controls.visible = false
	maze_size_controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	maze_size_controls.offset_left = -236
	maze_size_controls.offset_top = 118
	maze_size_controls.offset_right = -16
	maze_size_controls.offset_bottom = 178
	root.add_child(maze_size_controls)
	maze_size_label = Label.new()
	maze_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	maze_size_label.add_theme_color_override("font_color", Color("b9d5ec"))
	maze_size_controls.add_child(maze_size_label)
	maze_size_slider = HSlider.new()
	maze_size_slider.min_value = 1
	maze_size_slider.max_value = 10
	maze_size_slider.step = 1
	maze_size_slider.value = maze_scale
	maze_size_slider.tick_count = 10
	maze_size_slider.ticks_on_borders = true
	maze_size_slider.value_changed.connect(_on_maze_size_changed)
	maze_size_controls.add_child(maze_size_slider)
	_update_maze_size_label()

	countdown_label = Label.new()
	countdown_label.visible = false
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 96)
	countdown_label.add_theme_color_override("font_color", Color("ffd166"))
	countdown_label.add_theme_color_override("font_outline_color", Color("07101b"))
	countdown_label.add_theme_constant_override("outline_size", 12)
	countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	countdown_label.offset_left = -180
	countdown_label.offset_top = -110
	countdown_label.offset_right = 180
	countdown_label.offset_bottom = 110
	countdown_label.z_index = 20
	root.add_child(countdown_label)

	event_toast = Label.new()
	event_toast.visible = false
	event_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_toast.add_theme_font_size_override("font_size", 19)
	event_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	event_toast.offset_left = -270
	event_toast.offset_top = 18
	event_toast.offset_right = 270
	event_toast.offset_bottom = 58
	event_toast.z_index = 15
	root.add_child(event_toast)

	effect_hud_label = Label.new()
	effect_hud_label.visible = false
	effect_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_hud_label.add_theme_font_size_override("font_size", 16)
	effect_hud_label.add_theme_color_override("font_color", Color("eaf6ff"))
	var effect_style := StyleBoxFlat.new()
	effect_style.bg_color = Color(0.04, 0.08, 0.13, 0.88)
	effect_style.border_color = Color(0.32, 0.79, 0.95, 0.42)
	effect_style.set_border_width_all(1)
	effect_style.set_corner_radius_all(8)
	effect_style.content_margin_left = 11
	effect_style.content_margin_right = 11
	effect_style.content_margin_top = 6
	effect_style.content_margin_bottom = 6
	effect_hud_label.add_theme_stylebox_override("normal", effect_style)
	effect_hud_label.position = Vector2(16, 16)
	effect_hud_label.z_index = 8
	root.add_child(effect_hud_label)

	rank_label = Label.new()
	rank_label.visible = false
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_label.add_theme_font_size_override("font_size", 20)
	rank_label.add_theme_color_override("font_color", Color("ffd166"))
	rank_label.position = Vector2(16, 62)
	rank_label.z_index = 8
	root.add_child(rank_label)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	margin.add_child(rows)

	var title := Label.new()
	title.text = "A MAZE INC."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("83e8ff"))
	rows.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Créez une course ou rejoignez vos amis avec leur code"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("8fa5bd"))
	rows.add_child(subtitle)

	var discord_row := HBoxContainer.new()
	discord_row.alignment = BoxContainer.ALIGNMENT_CENTER
	discord_row.add_theme_constant_override("separation", 10)
	rows.add_child(discord_row)
	discord_button = Button.new()
	discord_button.text = "Connexion Discord…"
	discord_button.disabled = true
	discord_button.custom_minimum_size = Vector2(210, 40)
	discord_button.pressed.connect(_on_discord_pressed)
	_apply_button_style(discord_button, Color("5865f2"), Color("6875f5"), Color.WHITE)
	discord_row.add_child(discord_button)
	discord_status_label = Label.new()
	discord_status_label.text = "Vérification du compte…"
	discord_status_label.add_theme_color_override("font_color", Color("9aa9c2"))
	discord_row.add_child(discord_status_label)

	auth_request = HTTPRequest.new()
	auth_request.timeout = 8.0
	auth_request.request_completed.connect(_on_auth_request_completed)
	add_child(auth_request)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(name_row)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Votre pseudo"
	name_input.max_length = 16
	name_input.virtual_keyboard_enabled = true
	name_input.custom_minimum_size = Vector2(280, 42)
	name_input.text_changed.connect(_on_name_text_changed)
	name_row.add_child(name_input)

	var play_row := HFlowContainer.new()
	play_row.alignment = FlowContainer.ALIGNMENT_CENTER
	play_row.add_theme_constant_override("h_separation", 9)
	play_row.add_theme_constant_override("v_separation", 7)
	rows.add_child(play_row)
	create_button = Button.new()
	create_button.text = "Créer la course"
	create_button.custom_minimum_size = Vector2(150, 42)
	create_button.pressed.connect(_on_create_pressed)
	_apply_button_style(create_button, Color("15546c"), Color("1e718e"), Color("e7fbff"))
	play_row.add_child(create_button)
	var or_label := Label.new()
	or_label.text = "OU"
	or_label.custom_minimum_size.x = 34
	or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	or_label.add_theme_color_override("font_color", Color("60758d"))
	play_row.add_child(or_label)
	room_input = LineEdit.new()
	room_input.placeholder_text = "CODE"
	room_input.max_length = 4
	room_input.virtual_keyboard_enabled = true
	room_input.custom_minimum_size = Vector2(94, 42)
	room_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_input.text_changed.connect(_on_room_text_changed)
	room_input.text_submitted.connect(func(_text): _on_join_pressed())
	play_row.add_child(room_input)
	join_button = Button.new()
	join_button.text = "Rejoindre"
	join_button.custom_minimum_size = Vector2(125, 42)
	join_button.pressed.connect(_on_join_pressed)
	_apply_button_style(join_button, Color("594619"), Color("745c22"), Color("fff1bd"))
	play_row.add_child(join_button)
	status_label = Label.new()
	status_label.text = "Prêt pour une nouvelle course."
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color("8fa5bd"))
	rows.add_child(status_label)

	var help := Label.new()
	help.text = "Clavier • Manette • Tactile    |    Atteignez la sortie dorée"
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_left = 18
	help.offset_right = -18
	help.offset_top = -38
	help.offset_bottom = -12
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_color_override("font_color", Color("9aa9c2"))
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help)

	wall_shake_toggle = CheckButton.new()
	wall_shake_toggle.text = "Secousse écran"
	wall_shake_toggle.tooltip_text = "Secouer le labyrinthe lors d'une collision avec un mur"
	wall_shake_toggle.button_pressed = wall_shake_enabled
	wall_shake_toggle.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	wall_shake_toggle.offset_left = 16
	wall_shake_toggle.offset_top = -52
	wall_shake_toggle.offset_right = 196
	wall_shake_toggle.offset_bottom = -10
	wall_shake_toggle.toggled.connect(_on_wall_shake_toggled)
	root.add_child(wall_shake_toggle)

	touch_controls = PanelContainer.new()
	touch_controls.name = "TouchControls"
	touch_controls.visible = false
	touch_controls.z_index = 9
	touch_controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	touch_controls.offset_left = 16
	touch_controls.offset_top = -212
	touch_controls.offset_right = 212
	touch_controls.offset_bottom = -16
	var touch_panel_style := StyleBoxFlat.new()
	touch_panel_style.bg_color = Color(0.025, 0.06, 0.1, 0.48)
	touch_panel_style.border_color = Color(0.51, 0.91, 1.0, 0.28)
	touch_panel_style.set_border_width_all(2)
	touch_panel_style.set_corner_radius_all(28)
	touch_controls.add_theme_stylebox_override("panel", touch_panel_style)
	root.add_child(touch_controls)
	var dpad_surface := Control.new()
	dpad_surface.custom_minimum_size = Vector2(196, 196)
	dpad_surface.mouse_filter = Control.MOUSE_FILTER_PASS
	touch_controls.add_child(dpad_surface)
	_add_touch_direction_button(dpad_surface, "↑", "up", Vector2(68, 6))
	_add_touch_direction_button(dpad_surface, "←", "left", Vector2(6, 68))
	_add_touch_direction_button(dpad_surface, "→", "right", Vector2(130, 68))
	_add_touch_direction_button(dpad_surface, "↓", "down", Vector2(68, 130))

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
	score_panel.offset_left = -290
	score_panel.offset_top = -270
	score_panel.offset_right = 290
	score_panel.offset_bottom = 270
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
	score_subtitle = Label.new()
	score_subtitle.text = "Classement de la course"
	score_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_subtitle.add_theme_color_override("font_color", Color("9aa9c2"))
	score_content.add_child(score_subtitle)
	score_content.add_child(HSeparator.new())

	var score_header := HBoxContainer.new()
	score_content.add_child(score_header)
	_add_score_label(score_header, "#", 40, HORIZONTAL_ALIGNMENT_LEFT, Color("9aa9c2"))
	var avatar_header_spacer := Control.new()
	avatar_header_spacer.custom_minimum_size.x = 36
	score_header.add_child(avatar_header_spacer)
	_add_score_label(score_header, "Joueur", 270, HORIZONTAL_ALIGNMENT_LEFT, Color("9aa9c2"))
	_add_score_label(score_header, "Temps", 130, HORIZONTAL_ALIGNMENT_RIGHT, Color("9aa9c2"))

	score_rows = VBoxContainer.new()
	score_rows.add_theme_constant_override("separation", 6)
	score_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	score_content.add_child(score_rows)
	score_content.add_child(HSeparator.new())
	var podium_title := Label.new()
	podium_title.text = "PODIUM GÉNÉRAL"
	podium_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	podium_title.add_theme_font_size_override("font_size", 19)
	podium_title.add_theme_color_override("font_color", Color("83e8ff"))
	score_content.add_child(podium_title)
	podium_rows = VBoxContainer.new()
	podium_rows.add_theme_constant_override("separation", 5)
	score_content.add_child(podium_rows)
	score_restart_button = Button.new()
	score_restart_button.text = "Préparer un nouveau labyrinthe"
	score_restart_button.visible = false
	score_restart_button.pressed.connect(_on_score_restart_pressed)
	score_content.add_child(score_restart_button)
	_configure_focus_navigation()


func _layout_lobby_panel() -> void:
	if not panel:
		return
	var viewport_width := get_viewport_rect().size.x
	var panel_width := minf(680.0, viewport_width - 24.0)
	var panel_height := 330.0 if panel_width < 520.0 else 278.0
	panel.offset_left = -panel_width * 0.5
	panel.offset_right = panel_width * 0.5
	panel.offset_top = -panel_height * 0.5
	panel.offset_bottom = panel_height * 0.5


func _apply_button_style(
	button: Button,
	normal_color: Color,
	hover_color: Color,
	font_color: Color
) -> void:
	var colors := {
		"normal": normal_color,
		"hover": hover_color,
		"pressed": hover_color.darkened(0.14),
	}
	for state in colors:
		var style := StyleBoxFlat.new()
		style.bg_color = colors[state]
		style.set_corner_radius_all(8)
		style.content_margin_left = 12
		style.content_margin_right = 12
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", font_color)
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color.TRANSPARENT
	focus_style.border_color = Color("eafcff")
	focus_style.set_border_width_all(3)
	focus_style.set_corner_radius_all(9)
	focus_style.set_expand_margin_all(3)
	button.add_theme_stylebox_override("focus", focus_style)


func _add_touch_direction_button(
	parent: Control,
	symbol: String,
	direction: String,
	button_position: Vector2
) -> void:
	var button := Button.new()
	button.text = symbol
	button.position = button_position
	button.size = Vector2(60, 60)
	button.custom_minimum_size = Vector2(60, 60)
	button.focus_mode = Control.FOCUS_NONE
	button.keep_pressed_outside = true
	button.add_theme_font_size_override("font_size", 30)
	_apply_touch_button_style(button)
	button.button_down.connect(_on_touch_direction_pressed.bind(direction))
	button.button_up.connect(_on_touch_direction_released.bind(direction))
	parent.add_child(button)


func _apply_touch_button_style(button: Button) -> void:
	var colors := {
		"normal": Color(0.08, 0.18, 0.27, 0.78),
		"hover": Color(0.1, 0.27, 0.38, 0.9),
		"pressed": Color(0.2, 0.66, 0.78, 0.94),
	}
	for state in colors:
		var style := StyleBoxFlat.new()
		style.bg_color = colors[state]
		style.border_color = Color(0.51, 0.91, 1.0, 0.52)
		style.set_border_width_all(2)
		style.set_corner_radius_all(18)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("eafcff"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("07101b"))


func _configure_focus_navigation() -> void:
	discord_button.focus_neighbor_bottom = discord_button.get_path_to(name_input)
	name_input.focus_neighbor_top = name_input.get_path_to(discord_button)
	name_input.focus_neighbor_bottom = name_input.get_path_to(create_button)
	create_button.focus_neighbor_top = create_button.get_path_to(name_input)
	create_button.focus_neighbor_right = create_button.get_path_to(room_input)
	room_input.focus_neighbor_left = room_input.get_path_to(create_button)
	room_input.focus_neighbor_right = room_input.get_path_to(join_button)
	room_input.focus_neighbor_top = room_input.get_path_to(name_input)
	join_button.focus_neighbor_left = join_button.get_path_to(room_input)
	join_button.focus_neighbor_top = join_button.get_path_to(name_input)
	copy_button.focus_neighbor_bottom = copy_button.get_path_to(start_race_button)
	start_race_button.focus_neighbor_top = start_race_button.get_path_to(copy_button)
	start_race_button.focus_neighbor_bottom = start_race_button.get_path_to(maze_size_slider)
	maze_size_slider.focus_neighbor_top = maze_size_slider.get_path_to(start_race_button)


func _detect_touchscreen() -> bool:
	if DisplayServer.is_touchscreen_available():
		return true
	if OS.has_feature("web"):
		var detected = JavaScriptBridge.eval(
			"navigator.maxTouchPoints > 0 || ('ontouchstart' in window)"
		)
		return bool(detected)
	return false


func _setup_audio() -> void:
	for _index in range(8):
		var player := AudioStreamPlayer.new()
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = 11025.0
		stream.buffer_length = 0.45
		player.stream = stream
		add_child(player)
		audio_players.append(player)


func _play_tone(
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
	var sample_rate := 11025.0
	var frame_count := int(duration * sample_rate)
	for frame in range(frame_count):
		var progress := float(frame) / maxf(1.0, frame_count - 1.0)
		var current_frequency := frequency + slide * progress
		var phase := TAU * current_frequency * float(frame) / sample_rate
		var sample := sin(phase)
		if waveform == "square":
			sample = 1.0 if sample >= 0.0 else -1.0
		elif waveform == "noise":
			sample = random.randf_range(-1.0, 1.0)
		var envelope := minf(1.0, progress * 14.0) * minf(1.0, (1.0 - progress) * 8.0)
		var value := sample * volume * envelope
		playback.push_frame(Vector2(value, value))


func _default_server_url() -> String:
	if OS.has_feature("web"):
		var javascript := (
			"(function(){"
			+ "const explicit = window.mazeDiscord && window.mazeDiscord.getServerBaseUrl"
			+ " ? window.mazeDiscord.getServerBaseUrl() : window.location.origin;"
			+ "const url = new URL(explicit);"
			+ "url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';"
			+ "url.pathname = '/ws';"
			+ "url.search = '';"
			+ "url.hash = '';"
			+ "return url.toString();"
			+ "})()"
		)
		var value = JavaScriptBridge.eval(javascript)
		if value is String:
			return value
	return LOCAL_SERVER_URL


func _http_url(endpoint: String) -> String:
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval(
			"window.mazeDiscord && window.mazeDiscord.getServerBaseUrl"
			+ " ? window.mazeDiscord.getServerBaseUrl() : window.location.origin"
		)
		if origin is String:
			return str(origin) + endpoint
	var base := server_input.text.strip_edges()
	if base.is_empty():
		base = LOCAL_SERVER_URL
	if base.begins_with("wss://"):
		base = "https://" + base.substr(6)
	elif base.begins_with("ws://"):
		base = "http://" + base.substr(5)
	if base.ends_with("/ws"):
		base = base.left(base.length() - 3)
	while base.ends_with("/"):
		base = base.left(base.length() - 1)
	return base + endpoint


func _discord_auth_headers() -> PackedStringArray:
	var headers := PackedStringArray()
	if not discord_session_token.is_empty():
		headers.append("Authorization: Bearer %s" % discord_session_token)
	return headers


func _discord_bridge_state() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var raw = JavaScriptBridge.eval(
		"window.mazeDiscord && window.mazeDiscord.getStateJson ? window.mazeDiscord.getStateJson() : ''"
	)
	if raw is String and not raw.is_empty():
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


func _should_use_discord_activity_flow() -> bool:
	if not OS.has_feature("web"):
		return false
	if discord_activity_mode:
		return true
	var direct_host_check = JavaScriptBridge.eval(
		"(function(){"
		+ "const params=new URLSearchParams(window.location.search);"
		+ "return window.location.hostname.endsWith('.discordsays.com')"
		+ "|| params.has('instance_id')"
		+ "|| params.has('launch_id')"
		+ "|| params.has('frame_id')"
		+ "|| params.has('guild_id')"
		+ "|| params.has('channel_id');"
		+ "})()"
	)
	if bool(direct_host_check):
		return true
	var raw = JavaScriptBridge.eval(
		"window.mazeDiscord && window.mazeDiscord.shouldUseActivityFlow ? window.mazeDiscord.shouldUseActivityFlow() : false"
	)
	return bool(raw)


func _request_discord_session_check() -> void:
	auth_request_action = "check"
	var error := auth_request.request(_http_url("/api/auth/me"), _discord_auth_headers())
	if error != OK:
		_show_discord_unavailable()


func _sync_discord_bridge_state(force_refresh: bool = false) -> void:
	var state := _discord_bridge_state()
	if state.is_empty():
		return
	discord_activity_mode = bool(state.get("isActivity", false))
	discord_activity_ready = bool(state.get("sdkReady", false))
	discord_login_pending = bool(state.get("loginInFlight", false))
	discord_bridge_error = str(state.get("error", ""))
	var next_session_token := str(state.get("sessionToken", ""))
	var session_changed := next_session_token != discord_session_token
	discord_session_token = next_session_token
	if discord_activity_mode and (session_changed or force_refresh):
		if discord_session_token.is_empty():
			discord_user = {}
			_refresh_discord_controls(bool(state.get("enabled", false)))
		else:
			_request_discord_session_check()
	elif discord_activity_mode and discord_user.is_empty():
		_refresh_discord_controls(bool(state.get("enabled", false)))


func _update_discord_bridge(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	discord_bridge_poll_timer -= delta
	if discord_bridge_poll_timer > 0.0:
		return
	discord_bridge_poll_timer = 0.5
	_sync_discord_bridge_state()


func _check_discord_session() -> void:
	if not OS.has_feature("web"):
		discord_button.text = "Discord : version Web"
		discord_button.disabled = true
		discord_status_label.text = "Connexion disponible dans l’export Web"
		return
	JavaScriptBridge.eval("window.mazeDiscord && window.mazeDiscord.init && window.mazeDiscord.init()")
	_sync_discord_bridge_state(true)
	_request_discord_session_check()


func _on_discord_pressed() -> void:
	if _should_use_discord_activity_flow():
		discord_button.disabled = true
		discord_status_label.text = "Connexion Discord non disponible dans l’Activity pour le moment."
		return
	if not discord_user.is_empty():
		auth_request_action = "logout"
		discord_button.disabled = true
		var error := auth_request.request(
			_http_url("/api/auth/logout"),
			_discord_auth_headers(),
			HTTPClient.METHOD_POST
		)
		if error != OK:
			discord_button.disabled = false
			discord_status_label.text = "Déconnexion impossible."
		return
	discord_button.disabled = true
	discord_status_label.text = "Ouverture de Discord…"
	if _should_use_discord_activity_flow():
		discord_button.disabled = true
		discord_status_label.text = "Autorisation Discord..."
		discord_login_pending = true
		JavaScriptBridge.eval(
			"window.mazeDiscord && window.mazeDiscord.beginLogin && window.mazeDiscord.beginLogin()"
		)
		return
	JavaScriptBridge.eval("window.location.assign('/auth/discord')")


func _on_auth_request_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var payload = JSON.parse_string(body.get_string_from_utf8())
	if response_code != 200 or not payload is Dictionary:
		_show_discord_unavailable()
		return
	var enabled := bool(payload.get("enabled", false))
	if bool(payload.get("authenticated", false)):
		var user = payload.get("user", {})
		discord_user = user if user is Dictionary else {}
		discord_login_pending = false
	else:
		discord_user = {}
		if auth_request_action == "logout":
			discord_session_token = ""
	_refresh_discord_controls(enabled)
	if auth_request_action == "logout":
		status_label.text = "Compte Discord déconnecté."
	auth_request_action = ""


func _refresh_discord_controls(enabled: bool) -> void:
	if not discord_user.is_empty():
		var display_name := str(discord_user.get("displayName", "Joueur Discord"))
		discord_button.text = "Se déconnecter"
		discord_button.disabled = false
		discord_status_label.text = "Connecté : %s" % display_name
		discord_status_label.add_theme_color_override("font_color", Color("79e36a"))
		name_input.text = display_name.left(16)
		name_input.editable = false
		name_input.tooltip_text = "Le pseudo Discord est utilisé pendant la connexion."
		return
	name_input.editable = true
	name_input.tooltip_text = ""
	if _should_use_discord_activity_flow():
		discord_status_label.add_theme_color_override("font_color", Color("9aa9c2"))
		discord_button.text = "Discord indisponible ici"
		discord_button.disabled = true
		discord_status_label.text = "Connexion Discord non disponible dans l’Activity pour le moment."
		return
	discord_status_label.add_theme_color_override("font_color", Color("9aa9c2"))
	if enabled:
		discord_button.text = "Se connecter avec Discord"
		discord_button.disabled = false
		discord_status_label.text = "Utiliser votre photo de profil"
	else:
		discord_button.text = "Discord non configuré"
		discord_button.disabled = true
		discord_status_label.text = "Configuration serveur requise"


func _show_discord_unavailable() -> void:
	discord_user = {}
	discord_login_pending = false
	discord_button.text = "Discord indisponible"
	discord_button.disabled = true
	discord_status_label.text = "Le serveur d’authentification ne répond pas"
	discord_status_label.add_theme_color_override("font_color", Color("ff8fa3"))


func _ensure_avatar_loaded(player: Dictionary) -> void:
	var avatar_url := str(player.get("avatarUrl", ""))
	if (
		avatar_url.is_empty()
		or not avatar_url.begins_with("/api/discord/avatar/")
		or avatar_textures.has(avatar_url)
	):
		return
	avatar_textures[avatar_url] = null
	var request := HTTPRequest.new()
	request.timeout = 10.0
	request.request_completed.connect(
		_on_avatar_request_completed.bind(avatar_url, request)
	)
	add_child(request)
	var error := request.request(_http_url(avatar_url))
	if error != OK:
		avatar_textures.erase(avatar_url)
		request.queue_free()


func _on_avatar_request_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	avatar_url: String,
	request: HTTPRequest
) -> void:
	if response_code == 200:
		var image := Image.new()
		var error := image.load_png_from_buffer(body)
		if error == OK:
			image.resize(96, 96, Image.INTERPOLATE_LANCZOS)
			image.convert(Image.FORMAT_RGBA8)
			var center := Vector2(47.5, 47.5)
			var radius := 47.5
			for y in range(96):
				for x in range(96):
					var pixel := image.get_pixel(x, y)
					var edge := radius - Vector2(x, y).distance_to(center)
					pixel.a *= clampf(edge + 0.5, 0.0, 1.0)
					image.set_pixel(x, y, pixel)
			avatar_textures[avatar_url] = ImageTexture.create_from_image(image)
			if race_complete:
				_refresh_scoreboard()
			queue_redraw()
		else:
			avatar_textures.erase(avatar_url)
	else:
		avatar_textures.erase(avatar_url)
	request.queue_free()


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		wall_shake_enabled = bool(
			config.get_value("accessibility", "wall_shake_enabled", true)
		)


func _on_wall_shake_toggled(enabled: bool) -> void:
	wall_shake_enabled = enabled
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("accessibility", "wall_shake_enabled", wall_shake_enabled)
	config.save(SETTINGS_PATH)


func _process(delta: float) -> void:
	_update_discord_bridge(delta)
	_update_network()
	_update_movement(delta)
	_update_effects(delta)
	_update_countdown_ui()
	_update_music(delta)
	_update_race_hud()
	_update_player_tooltip()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		if not event.pressed:
			return
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) < GAMEPAD_DEADZONE:
			return
	else:
		return

	if get_viewport().gui_get_focus_owner() != null:
		return
	if score_restart_button.is_visible_in_tree():
		score_restart_button.grab_focus()
	elif start_race_button.is_visible_in_tree():
		start_race_button.grab_focus()
	elif room_code.is_empty() and create_button.is_visible_in_tree():
		create_button.grab_focus()
	elif copy_button.is_visible_in_tree():
		copy_button.grab_focus()


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
			race_phase = "waiting"
			race_start_deadline_ms = 0
			power_ups.clear()
			podium.clear()
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
	if OS.has_feature("web") and not discord_session_token.is_empty():
		url += ("%ssession=%s" % ["&" if url.contains("?") else "?", discord_session_token])
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
			_apply_race_metadata(message)
			status_label.text = "%d joueur(s) dans le salon." % players.size()
			_refresh_room_controls()
			_refresh_scoreboard()
			queue_redraw()
		"state":
			host_id = str(message.get("host", host_id))
			_set_players(message.get("players", []))
			_set_winner(str(message.get("winner", "")))
			race_complete = bool(message.get("complete", false))
			_apply_race_metadata(message)
			if not winner_id.is_empty():
				status_label.text = _winner_text()
			else:
				status_label.text = "%d joueur(s) • trouvez la sortie !" % players.size()
			_refresh_room_controls()
			_refresh_scoreboard()
			queue_redraw()
		"error":
			status_label.text = str(message.get("message", "Erreur du serveur."))


func _apply_race_metadata(message: Dictionary) -> void:
	var previous_phase := race_phase
	effects_snapshot_local_ms = Time.get_ticks_msec()
	power_ups_snapshot_local_ms = effects_snapshot_local_ms
	race_phase = str(message.get("phase", race_phase))
	power_ups = message.get("powerUps", power_ups)
	podium = message.get("podium", podium)
	current_round = int(message.get("round", current_round))
	maze_scale = clampi(int(message.get("mazeScale", maze_scale)), 1, 10)
	maze_size_slider.set_value_no_signal(maze_scale)
	_update_maze_size_label()
	if race_phase == "countdown":
		var server_now := int(message.get("serverNow", 0))
		var start_at := int(message.get("startAt", server_now))
		race_start_deadline_ms = Time.get_ticks_msec() + maxi(0, start_at - server_now)
	elif previous_phase == "countdown" and race_phase == "running":
		go_flash_until_ms = Time.get_ticks_msec() + 650
	if race_phase == "waiting":
		last_event_id = ""
	_handle_power_event(message.get("event", {}))


func _refresh_room_controls() -> void:
	var is_in_room := not room_code.is_empty()
	panel.visible = not is_in_room
	copy_button.visible = is_in_room
	var is_host_waiting := is_in_room and race_phase == "waiting" and host_id == player_id
	start_race_button.visible = is_host_waiting
	maze_size_controls.visible = is_host_waiting
	waiting_label.visible = is_in_room and race_phase == "waiting" and host_id != player_id
	_refresh_touch_controls()
	if is_in_room:
		if winner_id.is_empty():
			copy_button.text = "Copier le code  •  %s" % room_code
		else:
			copy_button.text = "%s  •  Copier %s" % [_winner_text(), room_code]
	queue_redraw()


func _refresh_touch_controls() -> void:
	if not touch_controls:
		return
	var active_phase := race_phase == "countdown" or race_phase == "running"
	var show_controls := (
		touchscreen_available
		and not room_code.is_empty()
		and active_phase
		and not race_complete
		and not _local_player_finished()
	)
	touch_controls.visible = show_controls
	wall_shake_toggle.visible = not (touchscreen_available and not room_code.is_empty())
	if not show_controls:
		touch_direction = ""


func _on_touch_direction_pressed(direction: String) -> void:
	touch_direction = direction
	held_direction = ""
	move_repeat_timer = 0.0


func _on_touch_direction_released(direction: String) -> void:
	if touch_direction == direction:
		touch_direction = ""


func _refresh_scoreboard() -> void:
	score_panel.visible = race_complete
	score_restart_button.visible = race_complete and host_id == player_id
	if not race_complete:
		return
	var animate_rows := scoreboard_animated_round != current_round
	if animate_rows:
		scoreboard_animated_round = current_round
	score_subtitle.text = "Classement de la manche %d" % current_round
	player_tooltip.visible = false
	for child in score_rows.get_children():
		score_rows.remove_child(child)
		child.queue_free()

	var ranked_players := players.duplicate()
	ranked_players.sort_custom(_sort_players_by_rank)
	for index in range(ranked_players.size()):
		var player: Dictionary = ranked_players[index]
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
		_add_score_avatar(row, player, color)
		_add_score_label(
			row,
			str(player.get("name", "Joueur")),
			270,
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
		if animate_rows:
			_animate_score_row(row, index * 0.09)

	for child in podium_rows.get_children():
		podium_rows.remove_child(child)
		child.queue_free()
	for index in range(podium.size()):
		var standing: Dictionary = podium[index]
		var podium_row := HBoxContainer.new()
		podium_row.add_theme_constant_override("separation", 8)
		podium_rows.add_child(podium_row)
		var color := Color.from_string(str(standing.get("color", "#ffffff")), Color.WHITE)
		_ensure_avatar_loaded(standing)
		_add_score_label(
			podium_row,
			"%d" % (index + 1),
			40,
			HORIZONTAL_ALIGNMENT_LEFT,
			Color("ffd166") if index == 0 else Color("c6d5e8")
		)
		_add_score_avatar(podium_row, standing, color)
		_add_score_label(
			podium_row,
			str(standing.get("name", "Joueur")),
			235,
			HORIZONTAL_ALIGNMENT_LEFT,
			color
		)
		_add_score_label(
			podium_row,
			"%d pts  •  %d victoire(s)" % [
				int(standing.get("points", 0)),
				int(standing.get("wins", 0)),
			],
			155,
			HORIZONTAL_ALIGNMENT_RIGHT,
			Color("9fb3c8")
		)
		if animate_rows:
			_animate_score_row(podium_row, 0.22 + index * 0.14)


func _animate_score_row(row: Control, delay: float) -> void:
	row.modulate = Color(1.0, 1.0, 1.0, 0.0)
	row.scale = Vector2(0.92, 0.92)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(row, "modulate:a", 1.0, 0.28).set_delay(delay)
	tween.tween_property(row, "scale", Vector2.ONE, 0.34).set_delay(delay).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)


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
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _add_score_avatar(parent: Container, player: Dictionary, color: Color) -> void:
	var avatar_slot := Control.new()
	avatar_slot.custom_minimum_size = Vector2(36, 32)
	avatar_slot.tooltip_text = "Avatar de %s" % str(player.get("name", "Joueur"))
	parent.add_child(avatar_slot)

	var avatar_url := str(player.get("avatarUrl", ""))
	var avatar_texture = avatar_textures.get(avatar_url)
	if avatar_texture is Texture2D:
		var border := Label.new()
		border.text = "●"
		border.position = Vector2.ZERO
		border.size = Vector2(32, 32)
		border.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		border.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		border.add_theme_font_size_override("font_size", 31)
		border.add_theme_color_override("font_color", color)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar_slot.add_child(border)

		var portrait := TextureRect.new()
		portrait.texture = avatar_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.position = Vector2(4, 4)
		portrait.size = Vector2(24, 24)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar_slot.add_child(portrait)
		return

	var fallback := Label.new()
	fallback.text = "●"
	fallback.position = Vector2.ZERO
	fallback.size = Vector2(32, 32)
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_font_size_override("font_size", 24)
	fallback.add_theme_color_override("font_color", color)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_slot.add_child(fallback)


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
	var newly_finished_players: Array = []
	for player in players:
		var id := str(player.get("id", ""))
		_ensure_avatar_loaded(player)
		var target := Vector2(float(player.get("x", 0)), float(player.get("y", 0)))
		present_players[id] = true
		if not visual_positions.has(id):
			visual_positions[id] = target
		elif previous_targets.has(id) and previous_targets[id] != target:
			var effects: Dictionary = player.get("effects", {})
			_spawn_trail(
				visual_positions[id],
				target,
				Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE),
				int(effects.get("speedMs", 0)) > 0
			)
		if (
			previous_finished.has(id)
			and not bool(previous_finished[id])
			and bool(player.get("finished", false))
		):
			newly_finished_players.append(player)

	for id in visual_positions.keys():
		if not present_players.has(id):
			visual_positions.erase(id)
	for finished_player in newly_finished_players:
		var finish_color := Color.from_string(
			str(finished_player.get("color", "#ffffff")),
			Color.WHITE
		)
		_start_celebration(finish_color)
		_play_tone(520.0, 0.3, 0.18, "square", 520.0)
		if str(finished_player.get("id", "")) == player_id:
			finish_slow_timer = 0.48


func _set_winner(next_winner: String) -> void:
	winner_id = next_winner
	if winner_id.is_empty():
		celebration_particles.clear()


func _update_movement(delta: float) -> void:
	if (
		room_code.is_empty()
		or not _race_can_move()
		or _local_player_finished()
		or _local_effect_active("frozen")
	):
		return
	var allow_keyboard := not (get_viewport().gui_get_focus_owner() is LineEdit)
	var direction := _input_direction(allow_keyboard)
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
			if _local_effect_active("speed"):
				move_repeat_timer = 0.04
			elif _local_effect_active("slow"):
				move_repeat_timer = 0.14
			_try_send_move(direction)


func _race_can_move() -> bool:
	if race_phase == "running":
		return true
	return race_phase == "countdown" and Time.get_ticks_msec() >= race_start_deadline_ms


func _local_player_finished() -> bool:
	for player in players:
		if str(player.get("id", "")) == player_id:
			return bool(player.get("finished", false))
	return false


func _local_effect_active(effect_name: String) -> bool:
	var player := _get_local_player()
	if player.is_empty():
		return false
	return _effect_active(player.get("effects", {}), effect_name)


func _get_local_player() -> Dictionary:
	for player in players:
		if str(player.get("id", "")) == player_id:
			return player
	return {}


func _local_effect_remaining(effect_name: String) -> float:
	var player := _get_local_player()
	if player.is_empty():
		return 0.0
	var effects: Dictionary = player.get("effects", {})
	var elapsed := Time.get_ticks_msec() - effects_snapshot_local_ms
	return maxf(0.0, (int(effects.get("%sMs" % effect_name, 0)) - elapsed) / 1000.0)


func _effect_active(effects: Dictionary, effect_name: String) -> bool:
	if effect_name == "shield":
		return bool(effects.get("shield", false))
	var elapsed := Time.get_ticks_msec() - effects_snapshot_local_ms
	return int(effects.get("%sMs" % effect_name, 0)) > elapsed


func _try_send_move(direction: String) -> void:
	if _can_local_player_move(direction):
		_send_json({"type": "move", "direction": direction})
	elif wall_hit_timer <= 0.0:
		wall_hit_timer = 0.16
		_play_tone(95.0, 0.09, 0.11, "noise")


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


func _spawn_trail(from: Vector2, to: Vector2, color: Color, boosted: bool = false) -> void:
	var mark_count := 7 if boosted else 4
	for step in range(mark_count):
		trail_marks.append(
			{
				"position": from.lerp(to, float(step) / mark_count),
				"color": color,
				"life": (0.38 if boosted else 0.22) + step * 0.035,
				"max_life": 0.58 if boosted else 0.36,
			}
		)
	movement_ripples.append(
		{"position": to, "color": color, "life": 0.38, "max_life": 0.38}
	)


func _start_celebration(dominant_color: Color = Color.TRANSPARENT) -> void:
	celebration_particles.clear()
	var goal: Dictionary = maze.get("exit", {})
	var origin := Vector2(float(goal.get("x", 0)) + 0.5, float(goal.get("y", 0)) + 0.5)
	for index in range(52):
		var angle := random.randf_range(0.0, TAU)
		var speed := random.randf_range(1.4, 4.8)
		var particle_color := Color(CELEBRATION_COLORS[index % CELEBRATION_COLORS.size()])
		if dominant_color.a > 0.0 and index < 34:
			particle_color = dominant_color
		celebration_particles.append(
			{
				"position": origin,
				"velocity": Vector2.from_angle(angle) * speed,
				"color": particle_color,
				"life": random.randf_range(0.75, 1.35),
				"max_life": 1.35,
			}
		)


func _update_effects(delta: float) -> void:
	finish_slow_timer = maxf(0.0, finish_slow_timer - delta)
	power_down_flash_timer = maxf(0.0, power_down_flash_timer - delta)
	var power_down_colors := {
		"slow": Color("9b64e8"),
		"confused": Color("ff5ca8"),
		"frozen": Color("8fe7ff"),
	}
	for effect in power_down_colors:
		var is_active := _local_effect_active(effect)
		if is_active and not bool(active_power_downs.get(effect, false)):
			power_down_flash_timer = 0.46
			power_down_flash_color = power_down_colors[effect]
		active_power_downs[effect] = is_active
	var visual_delta := delta * (0.28 if finish_slow_timer > 0.0 else 1.0)
	animation_time += visual_delta
	wall_hit_timer = maxf(0.0, wall_hit_timer - delta)
	if event_toast_timer > 0.0:
		event_toast_timer = maxf(0.0, event_toast_timer - delta)
		event_toast.visible = event_toast_timer > 0.0

	var targets: Dictionary = {}
	for player in players:
		targets[str(player.get("id", ""))] = Vector2(
			float(player.get("x", 0)),
			float(player.get("y", 0))
		)
	var smoothing := 1.0 - exp(-visual_delta * 18.0)
	for id in visual_positions.keys():
		if targets.has(id):
			visual_positions[id] = visual_positions[id].lerp(targets[id], smoothing)

	for index in range(trail_marks.size() - 1, -1, -1):
		var mark: Dictionary = trail_marks[index]
		mark["life"] = float(mark.get("life", 0.0)) - visual_delta
		if float(mark["life"]) <= 0.0:
			trail_marks.remove_at(index)
		else:
			trail_marks[index] = mark

	for index in range(movement_ripples.size() - 1, -1, -1):
		var ripple: Dictionary = movement_ripples[index]
		ripple["life"] = float(ripple.get("life", 0.0)) - visual_delta
		if float(ripple["life"]) <= 0.0:
			movement_ripples.remove_at(index)
		else:
			movement_ripples[index] = ripple

	for index in range(pickup_particles.size() - 1, -1, -1):
		var pickup_particle: Dictionary = pickup_particles[index]
		pickup_particle["life"] = float(pickup_particle.get("life", 0.0)) - visual_delta
		if float(pickup_particle["life"]) <= 0.0:
			pickup_particles.remove_at(index)
		else:
			pickup_particles[index] = pickup_particle

	for index in range(celebration_particles.size() - 1, -1, -1):
		var particle: Dictionary = celebration_particles[index]
		var velocity: Vector2 = particle.get("velocity", Vector2.ZERO)
		velocity.y += 3.2 * visual_delta
		particle["velocity"] = velocity
		particle["position"] = particle.get("position", Vector2.ZERO) + velocity * visual_delta
		particle["life"] = float(particle.get("life", 0.0)) - visual_delta
		if float(particle["life"]) <= 0.0:
			celebration_particles.remove_at(index)
		else:
			celebration_particles[index] = particle

	queue_redraw()


func _update_countdown_ui() -> void:
	var now := Time.get_ticks_msec()
	if race_phase == "countdown":
		var remaining := race_start_deadline_ms - now
		if remaining > 0:
			countdown_label.text = str(clampi(int(ceil(remaining / 1000.0)), 1, 3))
			countdown_label.visible = true
		else:
			countdown_label.text = "GO !"
			countdown_label.visible = remaining > -700
	elif now < go_flash_until_ms:
		countdown_label.text = "GO !"
		countdown_label.visible = true
	else:
		countdown_label.visible = false
	if countdown_label.visible and countdown_label.text != last_countdown_value:
		last_countdown_value = countdown_label.text
		if countdown_label.text == "GO !":
			_play_tone(440.0, 0.22, 0.2, "square", 440.0)
			direction_hint_until_ms = now + 3200
		else:
			_play_tone(280.0, 0.11, 0.13, "square")
	elif not countdown_label.visible:
		last_countdown_value = ""


func _update_music(delta: float) -> void:
	if not _race_can_move() or _local_player_finished():
		music_timer = 0.0
		return
	var local_player := _get_local_player()
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
		_play_tone(notes[music_note_index % notes.size()], 0.075, 0.025, "square")
		music_note_index += 1
		music_timer = lerpf(0.72, 0.23, progress)


func _update_race_hud() -> void:
	var show_race_hud := not room_code.is_empty() and not race_complete and race_phase != "waiting"
	rank_label.visible = show_race_hud
	if show_race_hud:
		var ordered_players := players.duplicate()
		ordered_players.sort_custom(_sort_live_race)
		for index in range(ordered_players.size()):
			if str(ordered_players[index].get("id", "")) == player_id:
				rank_label.text = "%d%s / %d" % [
					index + 1,
					"er" if index == 0 else "e",
					ordered_players.size(),
				]
				break

	var effect_texts: Array[String] = []
	for effect in ["speed", "slow", "confused", "frozen"]:
		var remaining := _local_effect_remaining(effect)
		if remaining <= 0.0:
			continue
		var names := {
			"speed": "TURBO",
			"slow": "RALENTI",
			"confused": "COMMANDES INVERSÉES",
			"frozen": "GELÉ",
		}
		effect_texts.append("%s  %.1fs" % [names[effect], remaining])
	if _local_effect_active("shield"):
		effect_texts.append("BOUCLIER")
	effect_hud_label.visible = not effect_texts.is_empty()
	effect_hud_label.text = "  •  ".join(effect_texts)


func _sort_live_race(first: Dictionary, second: Dictionary) -> bool:
	var first_finished := bool(first.get("finished", false))
	var second_finished := bool(second.get("finished", false))
	if first_finished != second_finished:
		return first_finished
	if first_finished:
		return int(first.get("rank", 999)) < int(second.get("rank", 999))
	var goal: Dictionary = maze.get("exit", {})
	var first_distance := absf(float(goal.get("x", 0)) - float(first.get("x", 0)))
	first_distance += absf(float(goal.get("y", 0)) - float(first.get("y", 0)))
	var second_distance := absf(float(goal.get("x", 0)) - float(second.get("x", 0)))
	second_distance += absf(float(goal.get("y", 0)) - float(second.get("y", 0)))
	return first_distance < second_distance


func _handle_power_event(event) -> void:
	if not event is Dictionary:
		return
	var event_id := str(event.get("id", ""))
	if event_id.is_empty() or event_id == last_event_id:
		return
	last_event_id = event_id
	var kind := str(event.get("kind", ""))
	var color := Color("83e8ff")
	if kind == "shield":
		color = Color("ffd166")
	elif kind == "slow_all" or kind == "confuse_all":
		color = Color("b58cff")
	elif kind == "freeze_all":
		color = Color("8fe7ff")
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.92)
	style.set_corner_radius_all(9)
	style.content_margin_left = 14
	style.content_margin_right = 14
	event_toast.add_theme_stylebox_override("normal", style)
	var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	event_toast.add_theme_color_override(
		"font_color",
		Color("07101b") if luminance > 0.58 else Color.WHITE
	)
	event_toast.text = str(event.get("message", "Objet mystère activé !"))
	event_toast_timer = 3.0
	event_toast.visible = true
	if kind == "speed":
		_play_tone(420.0, 0.2, 0.18, "square", 380.0)
	elif kind == "shield":
		_play_tone(660.0, 0.24, 0.15, "sine", 220.0)
	else:
		_play_tone(180.0, 0.28, 0.15, "square", -80.0)
	_spawn_pickup_particles(event, color)


func _spawn_pickup_particles(event: Dictionary, color: Color) -> void:
	var start := Vector2(float(event.get("x", 0)) + 0.5, float(event.get("y", 0)) + 0.5)
	for index in range(14):
		pickup_particles.append(
			{
				"start": start + Vector2.from_angle(index * TAU / 14.0) * 0.28,
				"target_id": str(event.get("actorId", "")),
				"color": color,
				"life": 0.65,
				"max_life": 0.65,
				"curve": random.randf_range(-0.3, 0.3),
			}
		)


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


func _input_direction(allow_keyboard: bool = true) -> String:
	var direction := ""
	if allow_keyboard:
		if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z):
			direction = "up"
		elif Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
			direction = "right"
		elif Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
			direction = "down"
		elif Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q):
			direction = "left"
	if direction.is_empty():
		direction = _gamepad_direction()
	if direction.is_empty():
		direction = touch_direction
	if direction.is_empty() or not _local_effect_active("confused"):
		return direction
	var opposites := {"up": "down", "right": "left", "down": "up", "left": "right"}
	return str(opposites.get(direction, direction))


func _gamepad_direction() -> String:
	for device in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):
			return "up"
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT):
			return "right"
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):
			return "down"
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT):
			return "left"

		var stick := Vector2(
			Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
		)
		if stick.length() < GAMEPAD_DEADZONE:
			continue
		if absf(stick.x) > absf(stick.y):
			return "right" if stick.x > 0.0 else "left"
		return "down" if stick.y > 0.0 else "up"
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
	elif race_phase == "waiting":
		top_margin = 190.0
	var available := Vector2(viewport_size.x - 48.0, viewport_size.y - top_margin - 58.0)
	var cell_size := floorf(minf(available.x / width, available.y / height))
	cell_size = maxf(cell_size, 8.0)
	var maze_size := Vector2(width * cell_size, height * cell_size)
	var origin := Vector2(
		(viewport_size.x - maze_size.x) * 0.5,
		top_margin + (available.y - maze_size.y) * 0.5
	)
	if wall_shake_enabled and wall_hit_timer > 0.0:
		var shake := wall_hit_timer / 0.16 * 2.8
		origin += Vector2(sin(animation_time * 91.0), cos(animation_time * 77.0)) * shake
	last_maze_origin = origin
	last_cell_size = cell_size

	var maze_backing := Color("0d1b2d")
	if wall_hit_timer > 0.0:
		maze_backing = maze_backing.lerp(Color("54203a"), wall_hit_timer / 0.16 * 0.35)
	draw_rect(Rect2(origin - Vector2(7, 7), maze_size + Vector2(14, 14)), maze_backing, true)
	_draw_goal(origin, cell_size)
	_draw_direction_hint(origin, cell_size)
	_draw_power_ups(origin, cell_size)
	_draw_trails(origin, cell_size)
	_draw_movement_ripples(origin, cell_size)
	_draw_pickup_particles(origin, cell_size)
	_draw_maze_walls(origin, cell_size, width, height)
	_draw_celebration(origin, cell_size)
	_draw_players(origin, cell_size)
	_draw_power_down_screen_fx(viewport_size)
	_draw_countdown_fx(viewport_size)


func _draw_power_down_screen_fx(viewport_size: Vector2) -> void:
	if _local_effect_active("slow"):
		_draw_slow_screen_fx(viewport_size, _power_down_fade("slow"))
	if _local_effect_active("confused"):
		_draw_confused_screen_fx(viewport_size, _power_down_fade("confused"))
	if _local_effect_active("frozen"):
		_draw_frozen_screen_fx(viewport_size, _power_down_fade("frozen"))
	if power_down_flash_timer > 0.0:
		var flash := clampf(power_down_flash_timer / 0.46, 0.0, 1.0)
		draw_rect(
			Rect2(Vector2.ZERO, viewport_size),
			Color(power_down_flash_color, flash * 0.11),
			true
		)
		draw_arc(
			viewport_size * 0.5,
			lerpf(28.0, minf(viewport_size.x, viewport_size.y) * 0.42, 1.0 - flash),
			0.0,
			TAU,
			64,
			Color(power_down_flash_color, flash * 0.58),
			lerpf(7.0, 2.0, 1.0 - flash),
			true
		)


func _power_down_fade(effect_name: String) -> float:
	return clampf(_local_effect_remaining(effect_name) * 2.5, 0.0, 1.0)


func _draw_edge_vignette(viewport_size: Vector2, color: Color, strength: float) -> void:
	var edge_size := clampf(minf(viewport_size.x, viewport_size.y) * 0.13, 52.0, 112.0)
	for layer in range(7):
		var progress := float(layer) / 6.0
		var depth := lerpf(edge_size, 5.0, progress)
		var alpha := strength * lerpf(0.015, 0.055, progress)
		var layer_color := Color(color, alpha)
		draw_rect(Rect2(0.0, 0.0, viewport_size.x, depth), layer_color, true)
		draw_rect(
			Rect2(0.0, viewport_size.y - depth, viewport_size.x, depth),
			layer_color,
			true
		)
		draw_rect(Rect2(0.0, 0.0, depth, viewport_size.y), layer_color, true)
		draw_rect(
			Rect2(viewport_size.x - depth, 0.0, depth, viewport_size.y),
			layer_color,
			true
		)


func _draw_slow_screen_fx(viewport_size: Vector2, fade: float) -> void:
	var color := Color("9b64e8")
	var pulse := 0.72 + (sin(animation_time * 2.0) + 1.0) * 0.14
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(color, 0.025 * fade), true)
	_draw_edge_vignette(viewport_size, color, pulse * fade)
	for side in range(2):
		var direction := 1.0 if side == 0 else -1.0
		var edge_x := 0.0 if side == 0 else viewport_size.x
		for streak in range(5):
			var y := fmod(animation_time * 21.0 + streak * viewport_size.y / 5.0, viewport_size.y)
			var length := 54.0 + streak * 11.0
			var wave := sin(animation_time * 1.7 + streak * 1.3) * 9.0
			draw_line(
				Vector2(edge_x, y),
				Vector2(edge_x + direction * length, y + wave),
				Color(color, (0.16 + streak * 0.018) * fade),
				3.0,
				true
			)


func _draw_confused_screen_fx(viewport_size: Vector2, fade: float) -> void:
	var cyan := Color("45d9ff")
	var magenta := Color("ff5ca8")
	var wobble := sin(animation_time * 6.0) * 6.0
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(magenta, 0.018 * fade), true)
	draw_rect(
		Rect2(Vector2(8.0 + wobble, 9.0), viewport_size - Vector2(18.0, 18.0)),
		Color(cyan, 0.42 * fade),
		false,
		2.0,
		true
	)
	draw_rect(
		Rect2(Vector2(10.0 - wobble, 11.0), viewport_size - Vector2(18.0, 18.0)),
		Color(magenta, 0.38 * fade),
		false,
		2.0,
		true
	)
	var corners := [
		Vector2.ZERO,
		Vector2(viewport_size.x, 0.0),
		viewport_size,
		Vector2(0.0, viewport_size.y),
	]
	for index in range(corners.size()):
		var start := index * PI * 0.5 + animation_time * 0.75
		draw_arc(
			corners[index],
			72.0 + sin(animation_time * 3.0 + index) * 8.0,
			start,
			start + PI * 0.72,
			20,
			Color(cyan if index % 2 == 0 else magenta, 0.48 * fade),
			4.0,
			true
		)


func _draw_frozen_screen_fx(viewport_size: Vector2, fade: float) -> void:
	var ice := Color("8fe7ff")
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(ice, 0.04 * fade), true)
	_draw_edge_vignette(viewport_size, ice, 1.15 * fade)
	var corner_data := [
		[Vector2.ZERO, Vector2(1.0, 1.0)],
		[Vector2(viewport_size.x, 0.0), Vector2(-1.0, 1.0)],
		[viewport_size, Vector2(-1.0, -1.0)],
		[Vector2(0.0, viewport_size.y), Vector2(1.0, -1.0)],
	]
	for index in range(corner_data.size()):
		var corner: Vector2 = corner_data[index][0]
		var direction: Vector2 = corner_data[index][1]
		var bend := Vector2(direction.x * (88.0 + index * 8.0), direction.y * 42.0)
		var tip := corner + bend
		draw_line(corner, tip, Color(ice, 0.58 * fade), 3.0, true)
		draw_line(
			tip,
			tip + Vector2(direction.x * 34.0, direction.y * 45.0),
			Color(ice, 0.38 * fade),
			2.0,
			true
		)
		draw_line(
			tip,
			tip + Vector2(direction.x * 48.0, -direction.y * 8.0),
			Color(ice, 0.32 * fade),
			2.0,
			true
		)
	for flake in range(16):
		var side := flake % 4
		var along := fmod(flake * 79.0 + animation_time * 13.0, 620.0) / 620.0
		var inset := 18.0 + float((flake * 17) % 34)
		var center := Vector2.ZERO
		if side == 0:
			center = Vector2(along * viewport_size.x, inset)
		elif side == 1:
			center = Vector2(viewport_size.x - inset, along * viewport_size.y)
		elif side == 2:
			center = Vector2((1.0 - along) * viewport_size.x, viewport_size.y - inset)
		else:
			center = Vector2(inset, (1.0 - along) * viewport_size.y)
		var radius := 2.0 + float(flake % 3)
		draw_line(
			center - Vector2(radius, 0.0),
			center + Vector2(radius, 0.0),
			Color(ice, 0.45 * fade),
			1.4,
			true
		)
		draw_line(
			center - Vector2(0.0, radius),
			center + Vector2(0.0, radius),
			Color(ice, 0.45 * fade),
			1.4,
			true
		)


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
	var panel_bottom := panel.position.y + panel.size.y if panel else viewport_size.y * 0.5
	var center := Vector2(
		viewport_size.x * 0.5,
		minf(viewport_size.y - 90.0, panel_bottom + 78.0)
	)
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


func _draw_power_ups(origin: Vector2, cell_size: float) -> void:
	for index in range(power_ups.size()):
		var power_up: Dictionary = power_ups[index]
		var center := origin + Vector2(
			(float(power_up.get("x", 0)) + 0.5) * cell_size,
			(float(power_up.get("y", 0)) + 0.5) * cell_size
		)
		center.y += sin(animation_time * 3.2 + index) * cell_size * 0.07
		if not bool(power_up.get("active", true)):
			var elapsed := Time.get_ticks_msec() - power_ups_snapshot_local_ms
			var remaining := maxf(0.0, float(power_up.get("respawnMs", 0)) - elapsed)
			var progress := clampf(1.0 - remaining / 8000.0, 0.0, 1.0)
			var warning_alpha := 0.18
			if remaining < 2000.0:
				warning_alpha = 0.35 + (sin(animation_time * 9.0) + 1.0) * 0.18
			draw_arc(
				center,
				cell_size * 0.24,
				-PI * 0.5,
				-PI * 0.5 + TAU * progress,
				28,
				Color(0.49, 0.87, 1.0, warning_alpha),
				clampf(cell_size * 0.055, 1.2, 2.5),
				true
			)
			continue
		var pulse := 1.0 + sin(animation_time * 5.0 + index) * 0.1
		var radius := clampf(cell_size * 0.25 * pulse, 3.5, 12.0)
		draw_circle(center, radius + 7.0, Color(0.45, 0.75, 1.0, 0.1))
		var points := PackedVector2Array()
		for corner in range(4):
			var angle := animation_time * 1.8 + corner * PI * 0.5
			points.append(center + Vector2.from_angle(angle) * radius)
		draw_colored_polygon(points, Color("7bdfff"))
		for segment in range(4):
			var segment_color := Color(CELEBRATION_COLORS[segment])
			draw_arc(
				center,
				radius * 0.72,
				animation_time * 2.2 + segment * PI * 0.5,
				animation_time * 2.2 + segment * PI * 0.5 + PI * 0.36,
				8,
				segment_color,
				clampf(cell_size * 0.055, 1.2, 2.4),
				true
			)
		draw_circle(center, radius * 0.22, Color.WHITE)


func _draw_direction_hint(origin: Vector2, cell_size: float) -> void:
	if Time.get_ticks_msec() >= direction_hint_until_ms:
		return
	var player := _get_local_player()
	if player.is_empty():
		return
	var id := str(player.get("id", ""))
	var position: Vector2 = visual_positions.get(
		id,
		Vector2(float(player.get("x", 0)), float(player.get("y", 0)))
	)
	var from := origin + (position + Vector2(0.5, 0.5)) * cell_size
	var goal: Dictionary = maze.get("exit", {})
	var to := origin + Vector2(
		(float(goal.get("x", 0)) + 0.5) * cell_size,
		(float(goal.get("y", 0)) + 0.5) * cell_size
	)
	for segment in range(14):
		if segment % 2 == 1:
			continue
		var start := from.lerp(to, float(segment) / 14.0)
		var end := from.lerp(to, float(segment + 1) / 14.0)
		draw_line(start, end, Color(1.0, 0.82, 0.36, 0.24), 2.0, true)


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


func _draw_movement_ripples(origin: Vector2, cell_size: float) -> void:
	for ripple in movement_ripples:
		var life_ratio := clampf(
			float(ripple.get("life", 0.0)) / float(ripple.get("max_life", 1.0)),
			0.0,
			1.0
		)
		var position: Vector2 = ripple.get("position", Vector2.ZERO)
		var center := origin + (position + Vector2(0.5, 0.5)) * cell_size
		var color: Color = ripple.get("color", Color.WHITE)
		color.a = life_ratio * 0.4
		var radius := cell_size * (0.12 + (1.0 - life_ratio) * 0.34)
		draw_arc(center, radius, 0.0, TAU, 28, color, 2.0, true)


func _draw_pickup_particles(origin: Vector2, cell_size: float) -> void:
	for particle in pickup_particles:
		var life_ratio := clampf(
			float(particle.get("life", 0.0)) / float(particle.get("max_life", 1.0)),
			0.0,
			1.0
		)
		var target_id := str(particle.get("target_id", ""))
		var target: Vector2 = visual_positions.get(target_id, particle.get("start", Vector2.ZERO))
		var start: Vector2 = particle.get("start", Vector2.ZERO)
		var progress := 1.0 - life_ratio
		var position := start.lerp(target + Vector2(0.5, 0.5), progress * progress)
		position += Vector2(0, sin(progress * PI) * float(particle.get("curve", 0.0)))
		var center := origin + position * cell_size
		var color: Color = particle.get("color", Color.WHITE)
		color.a = life_ratio
		draw_circle(center, clampf(cell_size * 0.06 * life_ratio, 1.2, 3.5), color)


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
		var effects: Dictionary = player.get("effects", {})
		var radius := clampf(cell_size * 0.27, 4.0, 14.0)
		var movement := target - visual_position
		var body_angle := 0.0
		var body_scale := Vector2.ONE
		if movement.length_squared() > 0.0005:
			body_angle = movement.angle()
			var stretch := clampf(movement.length() * 0.7, 0.0, 0.24)
			body_scale = Vector2(1.0 + stretch, 1.0 - stretch * 0.66)
		else:
			var breathing := sin(animation_time * 5.0 + float(id.hash() % 11)) * 0.025
			body_scale = Vector2(1.0 + breathing, 1.0 - breathing)
		if id == player_id and wall_hit_timer > 0.0:
			var hit_strength := clampf(wall_hit_timer / 0.18, 0.0, 1.0)
			body_scale *= Vector2(
				lerpf(1.0, 0.76, hit_strength),
				lerpf(1.0, 1.2, hit_strength)
			)
		if race_phase == "countdown" and Time.get_ticks_msec() < race_start_deadline_ms:
			var urgency := clampf(
				1.0 - float(race_start_deadline_ms - Time.get_ticks_msec()) / 3500.0,
				0.0,
				1.0
			)
			var phase := animation_time * lerpf(18.0, 42.0, urgency) + float(id.hash() % 17)
			center += Vector2(sin(phase), cos(phase * 1.37)) * urgency * 1.8
		var glow := color
		glow.a = 0.13 + (sin(animation_time * 5.0 + center.x) + 1.0) * 0.025
		draw_circle(center, radius + 8.0, glow)
		draw_set_transform(center, body_angle, body_scale)
		draw_circle(Vector2(0, 2), radius + 3.0, Color(0.01, 0.03, 0.06, 0.85))
		var avatar_url := str(player.get("avatarUrl", ""))
		var avatar_texture = avatar_textures.get(avatar_url)
		if avatar_texture is Texture2D:
			draw_circle(Vector2.ZERO, radius + 1.5, color)
			draw_texture_rect(
				avatar_texture,
				Rect2(Vector2(-radius, -radius), Vector2(radius * 2.0, radius * 2.0)),
				false
			)
		else:
			draw_circle(Vector2.ZERO, radius, color)
			draw_circle(
				Vector2(-radius * 0.28, -radius * 0.28),
				radius * 0.22,
				Color(1, 1, 1, 0.55)
			)
		if _effect_active(effects, "frozen"):
			draw_circle(Vector2.ZERO, radius * 0.82, Color(0.65, 0.94, 1.0, 0.55))
		draw_set_transform(Vector2.ZERO)
		if _effect_active(effects, "shield"):
			draw_arc(center, radius + 8.0, 0.0, TAU, 36, Color("ffd166"), 3.0, true)
		if _effect_active(effects, "speed"):
			draw_arc(
				center,
				radius + 9.0,
				animation_time * 5.0,
				animation_time * 5.0 + PI * 1.2,
				24,
				Color("45d9ff"),
				3.0,
				true
			)
		if _effect_active(effects, "slow") or _effect_active(effects, "confused"):
			draw_arc(
				center,
				radius + 9.0,
				-animation_time * 2.5,
				-animation_time * 2.5 + PI * 1.4,
				24,
				Color("b58cff"),
				3.0,
				true
			)
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


func _draw_countdown_fx(viewport_size: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if race_phase == "countdown" and now < race_start_deadline_ms:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.01, 0.02, 0.04, 0.34), true)
	var flash_remaining := go_flash_until_ms - now
	if race_phase == "countdown" and now >= race_start_deadline_ms:
		flash_remaining = maxi(flash_remaining, race_start_deadline_ms + 700 - now)
	if flash_remaining <= 0:
		return
	var progress := clampf(1.0 - flash_remaining / 700.0, 0.0, 1.0)
	draw_rect(
		Rect2(Vector2.ZERO, viewport_size),
		Color(1.0, 0.9, 0.55, (1.0 - progress) * 0.16),
		true
	)
	var center := viewport_size * 0.5
	draw_arc(
		center,
		lerpf(20.0, maxf(viewport_size.x, viewport_size.y) * 0.65, progress),
		0.0,
		TAU,
		72,
		Color(1.0, 0.86, 0.4, (1.0 - progress) * 0.75),
		lerpf(8.0, 2.0, progress),
		true
	)


func _on_create_pressed() -> void:
	var player_name := _required_player_name()
	if player_name.is_empty():
		return
	_play_tone(330.0, 0.08, 0.06)
	_connect_and_send({"type": "create", "name": player_name})


func _on_join_pressed() -> void:
	var player_name := _required_player_name()
	if player_name.is_empty():
		return
	var code := room_input.text.strip_edges().to_upper()
	if code.length() != 4:
		status_label.text = "Le code du salon doit contenir 4 caractères."
		return
	_play_tone(392.0, 0.08, 0.06)
	_connect_and_send({"type": "join", "room": code, "name": player_name})


func _player_name() -> String:
	return name_input.text.strip_edges()


func _required_player_name() -> String:
	var value := _player_name()
	if not value.is_empty():
		return value
	status_label.text = "Entrez votre pseudo pour continuer."
	name_input.placeholder_text = "Pseudo requis"
	name_input.add_theme_color_override("font_placeholder_color", Color("ff8fa3"))
	name_input.grab_focus()
	_play_tone(125.0, 0.09, 0.08, "noise")
	return ""


func _on_name_text_changed(value: String) -> void:
	if value.strip_edges().is_empty():
		return
	name_input.placeholder_text = "Votre pseudo"
	name_input.remove_theme_color_override("font_placeholder_color")
	if status_label.text == "Entrez votre pseudo pour continuer.":
		status_label.text = "Prêt pour une nouvelle course."


func _on_room_text_changed(value: String) -> void:
	var caret := room_input.caret_column
	room_input.text = value.to_upper()
	room_input.caret_column = caret


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(room_code)
	status_label.text = "Code %s copié." % room_code


func _on_start_race_pressed() -> void:
	_play_tone(220.0, 0.1, 0.07, "square")
	_send_json({"type": "start"})


func _on_maze_size_changed(value: float) -> void:
	maze_scale = clampi(roundi(value), 1, 10)
	maze_size_slider.set_value_no_signal(maze_scale)
	_update_maze_size_label()
	if race_phase == "waiting" and host_id == player_id:
		_send_json({"type": "maze_size", "scale": maze_scale})


func _update_maze_size_label() -> void:
	var factor := 0.75 + maze_scale * 0.25
	maze_size_label.text = "Taille %d/10  •  %d × %d" % [
		maze_scale, roundi(19 * factor), roundi(13 * factor)
	]


func _on_score_restart_pressed() -> void:
	_send_json({"type": "restart"})


func _on_viewport_resized() -> void:
	_layout_lobby_panel()
	queue_redraw()
