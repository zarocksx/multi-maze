extends Node2D

const LOCAL_SERVER_URL: String = "ws://127.0.0.1:8080/ws"
const GAMEPAD_DEADZONE: float = 0.42
const MAX_PLAYERS: int = 20
const DEFAULT_POWER_UP_COUNT: int = GameState.DEFAULT_POWER_UP_COUNT
const MAX_POWER_UP_COUNT: int = GameState.MAX_POWER_UP_COUNT

@onready var settings_store: SettingStore = $SettingsStore
@onready var audio_director: AudioDirector = $AudioDirector
@onready var network_client: NetworkClient = $NetworkClient
@onready var avatar_loader: AvatarLoader = $AvatarLoader
@onready var debug_overlay: DebugOverlay = $DebugOverlay
@onready var discord_bridge: DiscordBridge = $DiscordBridge
@onready var game_state: GameState = $GameState
@onready var world_renderer: WorldRenderer = $WorldRenderer
@onready var scoreboard_panel: ScoreboardPanel = $ScoreboardPanel
@onready var race_hud: RaceHud = $RaceHud

var player_id: String:
	get:
		return game_state.player_id
	set(value):
		game_state.player_id = value
var host_id: String:
	get:
		return game_state.host_id
	set(value):
		game_state.host_id = value
var room_code: String:
	get:
		return game_state.room_code
	set(value):
		game_state.room_code = value
var maze: Dictionary:
	get:
		return game_state.maze
	set(value):
		game_state.maze = value
var players: Array:
	get:
		return game_state.players
	set(value):
		game_state.players = value
var winner_id: String:
	get:
		return game_state.winner_id
	set(value):
		game_state.winner_id = value
var race_complete: bool:
	get:
		return game_state.race_complete
	set(value):
		game_state.race_complete = value
var race_phase: String:
	get:
		return game_state.race_phase
	set(value):
		game_state.race_phase = value
var race_start_deadline_ms: int:
	get:
		return game_state.race_start_deadline_ms
	set(value):
		game_state.race_start_deadline_ms = value
var go_flash_until_ms: int:
	get:
		return game_state.go_flash_until_ms
	set(value):
		game_state.go_flash_until_ms = value
var power_ups: Array:
	get:
		return game_state.power_ups
	set(value):
		game_state.power_ups = value
var power_up_count: int:
	get:
		return game_state.power_up_count
	set(value):
		game_state.power_up_count = value
var podium: Array:
	get:
		return game_state.podium
	set(value):
		game_state.podium = value
var maze_scale: int:
	get:
		return game_state.maze_scale
	set(value):
		game_state.maze_scale = value
var current_round: int:
	get:
		return game_state.current_round
	set(value):
		game_state.current_round = value

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
var host_controls_panel: PanelContainer
var host_controls_content: VBoxContainer
var start_race_button: Button
var waiting_label: Label
var maze_size_controls: VBoxContainer
var maze_size_label: Label
var maze_size_slider: HSlider
var power_up_count_label: Label
var power_up_count_slider: HSlider
var score_restart_button: Button
var wall_shake_toggle: CheckButton
var help_label: Label
var player_tooltip: Label
var held_direction: String = ""
var move_repeat_timer := 0.0
var animation_time := 0.0
var wall_hit_timer := 0.0
var visual_positions: Dictionary = {}
var trail_marks: Array = []
var movement_ripples: Array = []
var pickup_particles: Array = []
var celebration_particles: Array = []
var random := RandomNumberGenerator.new()
var finish_slow_timer := 0.0
var power_down_flash_timer := 0.0
var power_down_flash_color := Color.TRANSPARENT
var active_power_downs: Dictionary = {}
var wall_shake_enabled := true
var touchscreen_available := false
var touch_controls: PanelContainer
var touch_pad_surface: Control
var touch_direction_buttons: Dictionary = {}
var touch_direction: String = ""
var gamepad_focus_locked := false


func _ready() -> void:
	random.randomize()
	_setup_services()
	_load_settings()
	touchscreen_available = _detect_touchscreen()
	_build_interface()
	discord_bridge.configure_ui(discord_button, discord_status_label, name_input, status_label)
	server_input.text = _default_server_url()
	_debug_log("Menu principal prêt", "ok")
	_debug_log("WS par défaut : %s" % _debug_safe_url(server_input.text), "net")
	_check_discord_session()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_queue_world_redraw()


func _setup_services() -> void:
	audio_director.setup()
	discord_bridge.setup()
	discord_bridge.debug_logged.connect(_on_discord_debug_logged)
	network_client.connecting.connect(_on_network_connecting)
	network_client.connection_failed.connect(_on_network_connection_failed)
	network_client.opened.connect(_on_network_opened)
	network_client.closed.connect(_on_network_closed)
	network_client.sent.connect(_on_network_sent)
	network_client.packet_warning.connect(_on_network_packet_warning)
	network_client.message_received.connect(_on_network_message_received)
	avatar_loader.avatar_changed.connect(_on_avatar_changed)


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

	host_controls_panel = PanelContainer.new()
	host_controls_panel.visible = false
	host_controls_panel.z_index = 12
	host_controls_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	var host_panel_style := StyleBoxFlat.new()
	host_panel_style.bg_color = Color(0.035, 0.075, 0.12, 0.9)
	host_panel_style.border_color = Color(0.54, 0.86, 1.0, 0.34)
	host_panel_style.set_border_width_all(1)
	host_panel_style.set_corner_radius_all(12)
	host_panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	host_panel_style.shadow_size = 16
	host_controls_panel.add_theme_stylebox_override("panel", host_panel_style)
	root.add_child(host_controls_panel)

	var host_margin := MarginContainer.new()
	host_margin.add_theme_constant_override("margin_left", 12)
	host_margin.add_theme_constant_override("margin_top", 10)
	host_margin.add_theme_constant_override("margin_right", 12)
	host_margin.add_theme_constant_override("margin_bottom", 10)
	host_controls_panel.add_child(host_margin)

	host_controls_content = VBoxContainer.new()
	host_controls_content.add_theme_constant_override("separation", 7)
	host_margin.add_child(host_controls_content)

	copy_button = Button.new()
	copy_button.text = "Copier le code"
	copy_button.visible = false
	copy_button.custom_minimum_size = Vector2(248, 40)
	copy_button.pressed.connect(_on_copy_pressed)
	_apply_button_style(copy_button, Color("101a28"), Color("17283b"), Color("dcecff"))
	host_controls_content.add_child(copy_button)

	start_race_button = Button.new()
	start_race_button.text = "Lancer le départ"
	start_race_button.visible = false
	start_race_button.custom_minimum_size = Vector2(248, 44)
	start_race_button.pressed.connect(_on_start_race_pressed)
	host_controls_content.add_child(start_race_button)
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
	waiting_label.custom_minimum_size = Vector2(248, 34)
	host_controls_content.add_child(waiting_label)

	maze_size_controls = VBoxContainer.new()
	maze_size_controls.visible = false
	maze_size_controls.add_theme_constant_override("separation", 5)
	host_controls_content.add_child(maze_size_controls)

	var settings_title := Label.new()
	settings_title.text = "Paramètres de course"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_font_size_override("font_size", 14)
	settings_title.add_theme_color_override("font_color", Color("84e6ff"))
	maze_size_controls.add_child(settings_title)

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
	maze_size_slider.custom_minimum_size = Vector2(248, 24)
	maze_size_slider.value_changed.connect(_on_maze_size_changed)
	maze_size_controls.add_child(maze_size_slider)

	power_up_count_label = Label.new()
	power_up_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_up_count_label.add_theme_color_override("font_color", Color("b9d5ec"))
	maze_size_controls.add_child(power_up_count_label)

	power_up_count_slider = HSlider.new()
	power_up_count_slider.min_value = 0
	power_up_count_slider.max_value = MAX_POWER_UP_COUNT
	power_up_count_slider.step = 1
	power_up_count_slider.value = DEFAULT_POWER_UP_COUNT
	power_up_count_slider.tick_count = 7
	power_up_count_slider.ticks_on_borders = true
	power_up_count_slider.custom_minimum_size = Vector2(248, 24)
	power_up_count_slider.value_changed.connect(_on_power_up_count_changed)
	maze_size_controls.add_child(power_up_count_slider)
	_update_maze_size_label()
	_update_power_up_count_label()
	_layout_host_controls()

	race_hud.build(root)
	race_hud.tone_requested.connect(_on_race_hud_tone_requested)
	race_hud.direction_hint_requested.connect(_on_direction_hint_requested)

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

	help_label = Label.new()
	help_label.text = "Clavier • Manette • Tactile    |    Atteignez la sortie dorée"
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_left = 18
	help_label.offset_right = -18
	help_label.offset_top = -38
	help_label.offset_bottom = -12
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.add_theme_color_override("font_color", Color("9aa9c2"))
	help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help_label)

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

	_build_menu_debug_panel(root)

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
	touch_pad_surface = Control.new()
	touch_pad_surface.custom_minimum_size = Vector2(196, 196)
	touch_pad_surface.mouse_filter = Control.MOUSE_FILTER_PASS
	touch_controls.add_child(touch_pad_surface)
	_add_touch_direction_button(touch_pad_surface, "↑", "up", Vector2(68, 6))
	_add_touch_direction_button(touch_pad_surface, "←", "left", Vector2(6, 68))
	_add_touch_direction_button(touch_pad_surface, "→", "right", Vector2(130, 68))
	_add_touch_direction_button(touch_pad_surface, "↓", "down", Vector2(68, 130))
	_layout_touch_controls()

	player_tooltip = Label.new()
	player_tooltip.visible = false
	player_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_tooltip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_tooltip.z_index = 5
	root.add_child(player_tooltip)

	scoreboard_panel.build(root, avatar_loader, Callable(self, "_ensure_avatar_loaded"))
	scoreboard_panel.restart_requested.connect(_on_score_restart_pressed)
	score_restart_button = scoreboard_panel.restart_button
	_configure_world_renderer()
	_configure_focus_navigation()


func _configure_world_renderer() -> void:
	world_renderer.configure(game_state, avatar_loader, panel)
	world_renderer.bind_view_state(
		visual_positions,
		trail_marks,
		movement_ripples,
		pickup_particles,
		celebration_particles
	)
	_sync_world_renderer()


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


func _layout_host_controls() -> void:
	if not is_instance_valid(host_controls_panel):
		return
	var viewport_size := get_viewport_rect().size
	var landscape := viewport_size.x >= viewport_size.y
	var compact := landscape and viewport_size.y < 520.0
	var right_margin := 12.0 if compact else 16.0
	var top_margin := 8.0 if compact else 14.0
	var panel_width := clampf(
		viewport_size.x * (0.32 if compact else 0.2),
		248.0,
		312.0
	)
	var is_host_waiting := (
		not room_code.is_empty()
		and race_phase == "waiting"
		and host_id == player_id
	)
	var panel_height := 108.0
	if is_host_waiting:
		panel_height = 236.0 if compact else 248.0

	host_controls_panel.offset_left = -panel_width - right_margin
	host_controls_panel.offset_top = top_margin
	host_controls_panel.offset_right = -right_margin
	host_controls_panel.offset_bottom = top_margin + panel_height

	var control_width := maxf(196.0, panel_width - 24.0)
	if is_instance_valid(host_controls_content):
		host_controls_content.add_theme_constant_override("separation", 5 if compact else 7)
	if is_instance_valid(maze_size_controls):
		maze_size_controls.add_theme_constant_override("separation", 4 if compact else 5)
	if is_instance_valid(copy_button):
		copy_button.custom_minimum_size = Vector2(control_width, 38.0 if compact else 40.0)
	if is_instance_valid(start_race_button):
		start_race_button.custom_minimum_size = Vector2(control_width, 42.0 if compact else 44.0)
	if is_instance_valid(waiting_label):
		waiting_label.custom_minimum_size = Vector2(control_width, 34.0)
	if is_instance_valid(maze_size_slider):
		maze_size_slider.custom_minimum_size = Vector2(control_width, 22.0 if compact else 24.0)
	if is_instance_valid(power_up_count_slider):
		power_up_count_slider.custom_minimum_size = Vector2(control_width, 22.0 if compact else 24.0)


func _build_menu_debug_panel(root: Control) -> void:
	debug_overlay.build(root)


func _layout_menu_debug_panel() -> void:
	debug_overlay.layout(get_viewport_rect().size)


func _debug_log(message: String, level: String = "info") -> void:
	debug_overlay.log(message, level)


func _on_discord_debug_logged(message: String, level: String) -> void:
	_debug_log(message, level)


func _debug_shorten(message: String) -> String:
	return debug_overlay.shorten(message)


func _debug_safe_url(url: String) -> String:
	return debug_overlay.safe_url(url)


func _refresh_menu_debug_log() -> void:
	debug_overlay.refresh()
	_update_menu_debug_visibility()


func _update_menu_debug_visibility() -> void:
	var next_visible := is_instance_valid(panel) and panel.visible and room_code.is_empty()
	debug_overlay.set_context_visible(next_visible)


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
	touch_direction_buttons[direction] = button


func _layout_touch_controls() -> void:
	if not is_instance_valid(touch_controls) or not is_instance_valid(touch_pad_surface):
		return
	var viewport_size := get_viewport_rect().size
	var landscape := viewport_size.x >= viewport_size.y
	var side_margin := 12.0 if landscape else 16.0
	var bottom_margin := 12.0 if landscape else 16.0
	var pad_size := clampf(
		minf(viewport_size.y * (0.54 if landscape else 0.32), viewport_size.x * 0.25),
		190.0 if landscape else 176.0,
		228.0 if landscape else 204.0
	)
	var button_size := clampf(pad_size * 0.34, 64.0, 78.0)
	var inner_margin := pad_size * 0.055
	var center_pos := (pad_size - button_size) * 0.5
	var far_pos := pad_size - button_size - inner_margin

	touch_controls.offset_left = side_margin
	touch_controls.offset_top = -pad_size - bottom_margin
	touch_controls.offset_right = side_margin + pad_size
	touch_controls.offset_bottom = -bottom_margin
	touch_pad_surface.custom_minimum_size = Vector2(pad_size, pad_size)
	touch_pad_surface.size = Vector2(pad_size, pad_size)

	var positions := {
		"up": Vector2(center_pos, inner_margin),
		"left": Vector2(inner_margin, center_pos),
		"right": Vector2(far_pos, center_pos),
		"down": Vector2(center_pos, far_pos),
	}
	for direction in touch_direction_buttons.keys():
		var button := touch_direction_buttons[direction] as Button
		button.position = positions.get(direction, Vector2.ZERO)
		button.size = Vector2(button_size, button_size)
		button.custom_minimum_size = Vector2(button_size, button_size)
		button.pivot_offset = button.size * 0.5
		button.add_theme_font_size_override("font_size", int(clampf(button_size * 0.48, 30.0, 38.0)))


func _apply_touch_button_style(button: Button) -> void:
	var colors := {
		"normal": Color(0.05, 0.13, 0.2, 0.84),
		"hover": Color(0.08, 0.26, 0.36, 0.94),
		"pressed": Color(0.47, 0.9, 1.0, 0.98),
	}
	for state in colors:
		var style := StyleBoxFlat.new()
		style.bg_color = colors[state]
		style.border_color = Color(0.66, 0.95, 1.0, 0.72)
		style.set_border_width_all(3 if state == "pressed" else 2)
		style.set_corner_radius_all(20)
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
	maze_size_slider.focus_neighbor_bottom = maze_size_slider.get_path_to(power_up_count_slider)
	power_up_count_slider.focus_neighbor_top = power_up_count_slider.get_path_to(maze_size_slider)


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
	audio_director.setup()


func _play_tone(
	frequency: float,
	duration: float,
	volume: float = 0.16,
	waveform: String = "sine",
	slide: float = 0.0
) -> void:
	audio_director.play_tone(frequency, duration, volume, waveform, slide)


func _on_race_hud_tone_requested(
	frequency: float,
	duration: float,
	volume: float,
	waveform: String,
	slide: float
) -> void:
	_play_tone(frequency, duration, volume, waveform, slide)


func _on_direction_hint_requested(until_ms: int) -> void:
	world_renderer.show_direction_hint(until_ms)


func _default_server_url() -> String:
	return discord_bridge.default_server_url(LOCAL_SERVER_URL)


func _http_url(endpoint: String) -> String:
	var local_server_url := server_input.text.strip_edges() if server_input else LOCAL_SERVER_URL
	return discord_bridge.http_url(endpoint, local_server_url)


func _should_use_discord_activity_flow() -> bool:
	return discord_bridge.should_use_activity_flow()


func _update_discord_bridge(delta: float) -> void:
	discord_bridge.update_bridge(delta)


func _mark_discord_presence_dirty() -> void:
	discord_bridge.mark_presence_dirty()


func _update_discord_presence(delta: float) -> void:
	discord_bridge.update_presence(delta, _discord_game_context())


func _discord_game_context() -> Dictionary:
	return game_state.discord_context(MAX_PLAYERS)


func _check_discord_session() -> void:
	discord_bridge.check_session()


func _on_discord_pressed() -> void:
	discord_bridge.handle_button_pressed()


func _ensure_avatar_loaded(player: Dictionary) -> void:
	var avatar_url := str(player.get("avatarUrl", ""))
	if avatar_url.is_empty():
		return
	avatar_loader.ensure_loaded(player, _http_url(avatar_url))


func _on_avatar_changed() -> void:
	if race_complete:
		_refresh_scoreboard()
	_queue_world_redraw()


func _load_settings() -> void:
	wall_shake_enabled = settings_store.load_wall_shake_enabled(wall_shake_enabled)


func _on_wall_shake_toggled(enabled: bool) -> void:
	wall_shake_enabled = enabled
	settings_store.save_wall_shake_enabled(wall_shake_enabled)


func _process(delta: float) -> void:
	_update_discord_bridge(delta)
	_update_discord_presence(delta)
	_update_network()
	_update_movement(delta)
	_update_effects(delta)
	_update_countdown_ui()
	_update_music(delta)
	_update_race_hud()
	_update_player_tooltip()
	_sync_gamepad_focus_lock()
	_update_menu_debug_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		if not event.pressed:
			return
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) < GAMEPAD_DEADZONE:
			return
	else:
		return

	if _should_lock_gamepad_focus():
		_release_gamepad_focus()
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


func _should_lock_gamepad_focus() -> bool:
	return (
		not room_code.is_empty()
		and not race_complete
		and (race_phase == "countdown" or race_phase == "running")
	)


func _sync_gamepad_focus_lock() -> void:
	var should_lock := _should_lock_gamepad_focus()
	if should_lock != gamepad_focus_locked:
		gamepad_focus_locked = should_lock
		var next_focus_mode := Control.FOCUS_NONE if should_lock else Control.FOCUS_ALL
		_set_focus_mode_if_valid(discord_button, next_focus_mode)
		_set_focus_mode_if_valid(name_input, next_focus_mode)
		_set_focus_mode_if_valid(create_button, next_focus_mode)
		_set_focus_mode_if_valid(room_input, next_focus_mode)
		_set_focus_mode_if_valid(join_button, next_focus_mode)
		_set_focus_mode_if_valid(copy_button, next_focus_mode)
		_set_focus_mode_if_valid(start_race_button, next_focus_mode)
		_set_focus_mode_if_valid(maze_size_slider, next_focus_mode)
		_set_focus_mode_if_valid(power_up_count_slider, next_focus_mode)
		_set_focus_mode_if_valid(score_restart_button, next_focus_mode)
		_set_focus_mode_if_valid(wall_shake_toggle, next_focus_mode)
	if should_lock:
		_release_gamepad_focus()


func _set_focus_mode_if_valid(control: Control, focus_mode: int) -> void:
	if is_instance_valid(control):
		control.focus_mode = focus_mode


func _release_gamepad_focus() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is Control:
		focus_owner.release_focus()


func _update_network() -> void:
	network_client.poll(not room_code.is_empty())



func _connect_and_send(message: Dictionary) -> void:
	var url := _default_server_url() if _should_use_discord_activity_flow() else server_input.text.strip_edges()
	if url.is_empty():
		url = _default_server_url()
	var urls := discord_bridge.websocket_candidate_urls(url) if _should_use_discord_activity_flow() else [url]
	network_client.connect_and_send_with_candidates(message, urls, discord_bridge.get_session_token())


func _send_json(message: Dictionary) -> void:
	network_client.send_json(message)


func _on_network_connecting(url: String) -> void:
	status_label.text = "Connexion à %s…" % url
	_debug_log("WS connect %s" % _debug_safe_url(url), "net")


func _on_network_connection_failed(error_text: String) -> void:
	status_label.text = "Impossible de démarrer la connexion (%s)." % error_text
	_debug_log("WS connect impossible : %s" % error_text, "error")


func _on_network_opened() -> void:
	status_label.text = "Connecté au serveur…"
	_debug_log("WS ouvert", "ok")


func _on_network_closed(while_in_room: bool) -> void:
	if not while_in_room:
		return
	status_label.text = "Connexion perdue. Vérifiez le serveur."
	_debug_log("WS fermé pendant un salon", "error")
	game_state.reset_room()
	visual_positions.clear()
	trail_marks.clear()
	celebration_particles.clear()
	_refresh_room_controls()
	_refresh_scoreboard()
	_mark_discord_presence_dirty()
	_queue_world_redraw()


func _on_network_sent(message_type: String) -> void:
	_debug_log("WS send %s" % message_type, "net")


func _on_network_packet_warning(message: String) -> void:
	_debug_log(_debug_shorten(message), "warn")


func _on_network_message_received(message: Dictionary) -> void:
	_handle_message(message)


func _handle_message(message: Dictionary) -> void:
	_debug_log("WS recv %s" % str(message.get("type", "?")), "net")
	match str(message.get("type", "")):
		"hello":
			game_state.apply_hello(message)
		"room":
			game_state.apply_room_snapshot(message)
			_set_players(message.get("players", []))
			_set_winner(str(message.get("winner", "")))
			_apply_race_metadata(message)
			status_label.text = "%d joueur(s) dans le salon." % players.size()
			_refresh_room_controls()
			_refresh_scoreboard()
			_mark_discord_presence_dirty()
			_queue_world_redraw()
		"state":
			game_state.apply_state_snapshot(message)
			_set_players(message.get("players", []))
			_set_winner(str(message.get("winner", "")))
			_apply_race_metadata(message)
			if not winner_id.is_empty():
				status_label.text = _winner_text()
			else:
				status_label.text = "%d joueur(s) • trouvez la sortie !" % players.size()
			_refresh_room_controls()
			_refresh_scoreboard()
			_mark_discord_presence_dirty()
			_queue_world_redraw()
		"error":
			status_label.text = str(message.get("message", "Erreur du serveur."))


func _apply_race_metadata(message: Dictionary) -> void:
	game_state.apply_race_metadata(message, Time.get_ticks_msec())
	maze_size_slider.set_value_no_signal(maze_scale)
	_update_maze_size_label()
	power_up_count_slider.set_value_no_signal(power_up_count)
	_update_power_up_count_label()
	_handle_power_event(message.get("event", {}))


func _refresh_room_controls() -> void:
	var is_in_room := not room_code.is_empty()
	var is_waiting_room := is_in_room and race_phase == "waiting"
	var is_host_waiting := is_waiting_room and host_id == player_id
	panel.visible = not is_in_room
	host_controls_panel.visible = is_waiting_room
	copy_button.visible = is_waiting_room
	start_race_button.visible = is_host_waiting
	maze_size_controls.visible = is_host_waiting
	waiting_label.visible = is_waiting_room and host_id != player_id
	_layout_host_controls()
	_update_menu_debug_visibility()
	_refresh_touch_controls()
	_sync_gamepad_focus_lock()
	if is_in_room:
		if winner_id.is_empty():
			copy_button.text = "Copier le code  •  %s" % room_code
		else:
			copy_button.text = "%s  •  Copier %s" % [_winner_text(), room_code]
	_queue_world_redraw()


func _refresh_touch_controls() -> void:
	if not touch_controls:
		return
	_layout_touch_controls()
	var active_phase := race_phase == "countdown" or race_phase == "running"
	var show_controls := (
		touchscreen_available
		and not room_code.is_empty()
		and active_phase
		and not race_complete
		and not _local_player_finished()
	)
	touch_controls.visible = show_controls
	wall_shake_toggle.visible = room_code.is_empty()
	if is_instance_valid(help_label):
		help_label.visible = room_code.is_empty()
	if not show_controls:
		touch_direction = ""


func _on_touch_direction_pressed(direction: String) -> void:
	touch_direction = direction
	held_direction = ""
	move_repeat_timer = 0.0
	_vibrate(18)
	_play_tone(310.0, 0.035, 0.035, "square")
	_pulse_touch_button(direction)


func _on_touch_direction_released(direction: String) -> void:
	if touch_direction == direction:
		touch_direction = ""


func _pulse_touch_button(direction: String) -> void:
	var button := touch_direction_buttons.get(direction) as Button
	if not is_instance_valid(button):
		return
	button.pivot_offset = button.size * 0.5
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * 1.08, 0.045)
	tween.tween_property(button, "scale", Vector2.ONE, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _vibrate(duration_ms: int) -> void:
	if touchscreen_available or OS.has_feature("web"):
		Input.vibrate_handheld(duration_ms)


func _refresh_scoreboard() -> void:
	if race_complete:
		player_tooltip.visible = false
	scoreboard_panel.refresh(players, podium, race_complete, current_round, host_id == player_id)


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
		previous_targets[previous_id] = GameState.grid_position(player)
		previous_finished[previous_id] = bool(player.get("finished", false))

	game_state.set_players(next_players)
	var present_players: Dictionary = {}
	var newly_finished_players: Array = []
	for player in players:
		var id := str(player.get("id", ""))
		_ensure_avatar_loaded(player)
		var target := GameState.grid_position(player)
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
			_vibrate(75)


func _set_winner(next_winner: String) -> void:
	game_state.set_winner(next_winner)
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
		move_repeat_timer = 0.11
		_try_send_move(direction)
	else:
		move_repeat_timer -= delta
		if move_repeat_timer <= 0.0:
			move_repeat_timer = 0.068
			if _local_effect_active("speed"):
				move_repeat_timer = 0.034
			elif _local_effect_active("slow"):
				move_repeat_timer = 0.12
			_try_send_move(direction)


func _race_can_move() -> bool:
	return game_state.race_can_move(Time.get_ticks_msec())


func _local_player_finished() -> bool:
	return game_state.local_player_finished()


func _local_effect_active(effect_name: String) -> bool:
	return game_state.local_effect_active(effect_name, Time.get_ticks_msec())


func _get_local_player() -> Dictionary:
	return game_state.get_local_player()


func _local_effect_remaining(effect_name: String) -> float:
	return game_state.local_effect_remaining(effect_name, Time.get_ticks_msec())


func _try_send_move(direction: String) -> void:
	if _can_local_player_move(direction):
		_send_json({"type": "move", "direction": direction})
	elif wall_hit_timer <= 0.0:
		wall_hit_timer = 0.2
		_vibrate(30)
		if wall_shake_enabled:
			_play_tone(95.0, 0.09, 0.11, "noise")


func _can_local_player_move(direction: String) -> bool:
	return game_state.can_local_player_move(direction)


func _spawn_trail(from: Vector2, to: Vector2, color: Color, boosted: bool = false) -> void:
	var mark_count := 13 if boosted else 8
	for step in range(mark_count):
		trail_marks.append(
			{
				"position": from.lerp(to, float(step) / mark_count),
				"color": color,
				"life": (0.5 if boosted else 0.32) + step * 0.028,
				"max_life": 0.68 if boosted else 0.46,
				"radius": 0.26 if boosted else 0.21,
			}
		)
	movement_ripples.append(
		{"position": to, "color": color, "life": 0.52, "max_life": 0.52, "width": 3.0}
	)
	if boosted:
		movement_ripples.append(
			{"position": to, "color": color, "life": 0.68, "max_life": 0.68, "width": 4.0}
		)
	_trim_particles(trail_marks, 180)
	_trim_particles(movement_ripples, 72)


func _start_celebration(dominant_color: Color = Color.TRANSPARENT) -> void:
	celebration_particles.clear()
	var goal: Dictionary = maze.get("exit", {})
	var origin := GameState.grid_center(goal)
	for index in range(84):
		var angle := random.randf_range(0.0, TAU)
		var speed := random.randf_range(1.8, 6.2)
		var particle_color := Color(
			RaceVisuals.CELEBRATION_COLORS[index % RaceVisuals.CELEBRATION_COLORS.size()]
		)
		if dominant_color.a > 0.0 and index < 48:
			particle_color = dominant_color
		celebration_particles.append(
			{
				"position": origin,
				"velocity": Vector2.from_angle(angle) * speed,
				"color": particle_color,
				"life": random.randf_range(0.85, 1.55),
				"max_life": 1.55,
			}
		)
	_trim_particles(celebration_particles, 140)


func _update_effects(delta: float) -> void:
	finish_slow_timer = maxf(0.0, finish_slow_timer - delta)
	power_down_flash_timer = maxf(0.0, power_down_flash_timer - delta)
	for effect in ["slow", "confused", "frozen"]:
		var is_active := _local_effect_active(effect)
		if is_active and not bool(active_power_downs.get(effect, false)):
			power_down_flash_timer = 0.46
			power_down_flash_color = RaceVisuals.power_down_color(effect)
		active_power_downs[effect] = is_active
	var visual_delta := delta * (0.28 if finish_slow_timer > 0.0 else 1.0)
	animation_time += visual_delta
	wall_hit_timer = maxf(0.0, wall_hit_timer - delta)
	race_hud.update_toast(delta)

	var targets: Dictionary = {}
	for player in players:
		targets[str(player.get("id", ""))] = GameState.grid_position(player)
	var smoothing := 1.0 - exp(-visual_delta * 18.0)
	for id in visual_positions.keys():
		if targets.has(id):
			visual_positions[id] = visual_positions[id].lerp(targets[id], smoothing)

	_decay_life_particles(trail_marks, visual_delta)
	_decay_life_particles(movement_ripples, visual_delta)
	_decay_life_particles(pickup_particles, visual_delta)

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

	_queue_world_redraw()


func _decay_life_particles(particles: Array, visual_delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[index]
		particle["life"] = float(particle.get("life", 0.0)) - visual_delta
		if float(particle["life"]) <= 0.0:
			particles.remove_at(index)
		else:
			particles[index] = particle


func _trim_particles(particles: Array, max_count: int) -> void:
	while particles.size() > max_count:
		particles.remove_at(0)


func _update_countdown_ui() -> void:
	race_hud.update_countdown(race_phase, race_start_deadline_ms, go_flash_until_ms)


func _update_music(delta: float) -> void:
	audio_director.update_music(
		delta,
		_race_can_move(),
		_local_player_finished(),
		_get_local_player(),
		maze
	)


func _update_race_hud() -> void:
	race_hud.update_race_hud(
		room_code,
		race_complete,
		race_phase,
		players,
		player_id,
		maze.get("exit", {}),
		Callable(self, "_local_effect_remaining"),
		Callable(self, "_local_effect_active")
	)


func _handle_power_event(event) -> void:
	if not game_state.accept_power_event(event):
		return
	var kind := str(event.get("kind", ""))
	race_hud.show_power_event(event)
	_spawn_pickup_particles(event, RaceVisuals.power_event_color(kind))
	if str(event.get("actorId", "")) == player_id:
		_vibrate(45)


func _spawn_pickup_particles(event: Dictionary, color: Color) -> void:
	var start := GameState.grid_center(event)
	for index in range(22):
		pickup_particles.append(
			{
				"start": start + Vector2.from_angle(index * TAU / 22.0) * random.randf_range(0.2, 0.42),
				"target_id": str(event.get("actorId", "")),
				"color": color,
				"life": random.randf_range(0.62, 0.86),
				"max_life": 0.86,
				"curve": random.randf_range(-0.44, 0.44),
			}
		)
	_trim_particles(pickup_particles, 120)


func _update_player_tooltip() -> void:
	world_renderer.update_player_tooltip(player_tooltip, get_viewport().get_mouse_position())


func _sync_world_renderer() -> void:
	if not is_instance_valid(world_renderer):
		return
	world_renderer.set_timers(
		animation_time,
		wall_hit_timer,
		power_down_flash_timer,
		power_down_flash_color,
		wall_shake_enabled
	)


func _queue_world_redraw() -> void:
	_sync_world_renderer()
	if is_instance_valid(world_renderer):
		world_renderer.queue_redraw()


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


func _on_create_pressed() -> void:
	var player_name := _required_player_name()
	if player_name.is_empty():
		return
	_play_tone(330.0, 0.08, 0.06)
	var message := {"type": "create", "name": player_name}
	_add_discord_activity_user(message)
	_connect_and_send(message)


func _on_join_pressed() -> void:
	var player_name := _required_player_name()
	if player_name.is_empty():
		return
	var code := room_input.text.strip_edges().to_upper()
	if code.length() != 4:
		status_label.text = "Le code du salon doit contenir 4 caractères."
		return
	_play_tone(392.0, 0.08, 0.06)
	var message := {"type": "join", "room": code, "name": player_name}
	_add_discord_activity_user(message)
	_connect_and_send(message)


func _add_discord_activity_user(message: Dictionary) -> void:
	discord_bridge.add_activity_user(message)


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


func _on_power_up_count_changed(value: float) -> void:
	power_up_count = clampi(roundi(value), 0, MAX_POWER_UP_COUNT)
	power_up_count_slider.set_value_no_signal(power_up_count)
	_update_power_up_count_label()
	if race_phase == "waiting" and host_id == player_id:
		_send_json({"type": "power_up_count", "count": power_up_count})


func _update_maze_size_label() -> void:
	var factor := 0.75 + maze_scale * 0.25
	maze_size_label.text = "Taille %d/10  •  %d × %d" % [
		maze_scale, roundi(19 * factor), roundi(13 * factor)
	]


func _update_power_up_count_label() -> void:
	power_up_count_label.text = "Objets %d/%d  -  %d actif(s)" % [
		power_up_count, MAX_POWER_UP_COUNT, power_ups.size()
	]


func _on_score_restart_pressed() -> void:
	_play_tone(330.0, 0.09, 0.08, "square", 180.0)
	_vibrate(35)
	_send_json({"type": "restart"})


func _on_viewport_resized() -> void:
	_layout_lobby_panel()
	_layout_host_controls()
	_layout_menu_debug_panel()
	_layout_touch_controls()
	if is_instance_valid(race_hud):
		race_hud.layout(get_viewport_rect().size)
	if is_instance_valid(scoreboard_panel):
		scoreboard_panel.layout(get_viewport_rect().size)
	_queue_world_redraw()
