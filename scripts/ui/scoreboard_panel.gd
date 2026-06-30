extends Node
class_name ScoreboardPanel

signal restart_requested

var panel: PanelContainer
var restart_button: Button

var score_margin: MarginContainer
var score_content: VBoxContainer
var score_header: HBoxContainer
var score_scroll: ScrollContainer
var score_rows: VBoxContainer
var podium_title: Label
var podium_rows: VBoxContainer
var score_title: Label
var score_subtitle: Label
var restart_hint_label: Label
var avatar_loader: Node
var ensure_avatar_loaded_callback: Callable
var animated_round := 0
var compact_layout := false


func build(root: Control, next_avatar_loader: Node, next_ensure_avatar_loaded: Callable) -> void:
	avatar_loader = next_avatar_loader
	ensure_avatar_loaded_callback = next_ensure_avatar_loaded

	panel = PanelContainer.new()
	panel.visible = false
	panel.z_index = 10
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var score_style := StyleBoxFlat.new()
	score_style.bg_color = Color(0.05, 0.09, 0.15, 0.96)
	score_style.border_color = Color("ffd166")
	score_style.set_border_width_all(2)
	score_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", score_style)
	root.add_child(panel)

	score_margin = MarginContainer.new()
	panel.add_child(score_margin)

	score_content = VBoxContainer.new()
	score_content.add_theme_constant_override("separation", 12)
	score_margin.add_child(score_content)

	score_title = Label.new()
	score_title.text = "MANCHE TERMINEE !"
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

	score_header = HBoxContainer.new()
	score_header.add_theme_constant_override("separation", 8)
	score_content.add_child(score_header)

	score_scroll = ScrollContainer.new()
	score_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	score_content.add_child(score_scroll)

	score_rows = VBoxContainer.new()
	score_rows.add_theme_constant_override("separation", 6)
	score_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_scroll.add_child(score_rows)
	score_content.add_child(HSeparator.new())

	podium_title = Label.new()
	podium_title.text = "PODIUM GENERAL"
	podium_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	podium_title.add_theme_font_size_override("font_size", 19)
	podium_title.add_theme_color_override("font_color", Color("83e8ff"))
	score_content.add_child(podium_title)

	podium_rows = VBoxContainer.new()
	podium_rows.add_theme_constant_override("separation", 5)
	score_content.add_child(podium_rows)

	restart_button = Button.new()
	restart_button.text = "Relancer maintenant"
	restart_button.visible = false
	restart_button.custom_minimum_size = Vector2(0, 52)
	restart_button.pressed.connect(func(): restart_requested.emit())
	_apply_restart_button_style(restart_button)
	score_content.add_child(restart_button)

	restart_hint_label = Label.new()
	restart_hint_label.text = "En attente de l'hote"
	restart_hint_label.visible = false
	restart_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_hint_label.add_theme_color_override("font_color", Color("9fb3c8"))
	score_content.add_child(restart_hint_label)

	layout(root.get_viewport_rect().size)


func layout(viewport_size: Vector2) -> void:
	if not is_instance_valid(panel):
		return
	compact_layout = viewport_size.y < 520.0 or viewport_size.x < 760.0
	var panel_width := minf(620.0, viewport_size.x - 24.0)
	var panel_height := minf(540.0, viewport_size.y - 24.0)
	panel_height = maxf(panel_height, 320.0)
	panel.offset_left = -panel_width * 0.5
	panel.offset_top = -panel_height * 0.5
	panel.offset_right = panel_width * 0.5
	panel.offset_bottom = panel_height * 0.5

	var margin := 16 if compact_layout else 24
	score_margin.add_theme_constant_override("margin_left", margin)
	score_margin.add_theme_constant_override("margin_top", 14 if compact_layout else 20)
	score_margin.add_theme_constant_override("margin_right", margin)
	score_margin.add_theme_constant_override("margin_bottom", 14 if compact_layout else 20)
	score_content.add_theme_constant_override("separation", 7 if compact_layout else 12)
	score_rows.add_theme_constant_override("separation", 4 if compact_layout else 6)
	podium_rows.add_theme_constant_override("separation", 3 if compact_layout else 5)
	score_scroll.custom_minimum_size.y = 86.0 if compact_layout else 150.0
	score_title.add_theme_font_size_override("font_size", 21 if compact_layout else 25)
	podium_title.add_theme_font_size_override("font_size", 16 if compact_layout else 19)
	restart_button.custom_minimum_size.y = 46 if compact_layout else 52
	_refresh_header()


func refresh(
	players: Array,
	podium: Array,
	race_complete: bool,
	current_round: int,
	is_host: bool
) -> void:
	panel.visible = race_complete
	restart_button.visible = race_complete and is_host
	restart_hint_label.visible = race_complete and not is_host
	if not race_complete:
		return

	layout(panel.get_viewport_rect().size)
	var animate_rows := animated_round != current_round
	if animate_rows:
		animated_round = current_round
		_animate_panel()
	score_title.text = "MANCHE %d TERMINEE !" % current_round
	score_subtitle.text = "Encore une ?"

	_clear_rows(score_rows)
	var ranked_players := players.duplicate()
	ranked_players.sort_custom(_sort_players_by_rank)
	var rank_width := 30.0 if compact_layout else 40.0
	var name_width := 168.0 if compact_layout else 270.0
	var time_width := 96.0 if compact_layout else 130.0
	for index in range(ranked_players.size()):
		var player: Dictionary = ranked_players[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6 if compact_layout else 8)
		score_rows.add_child(row)
		var color := Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE)
		_add_score_label(row, "%d." % int(player.get("rank", 0)), rank_width, HORIZONTAL_ALIGNMENT_LEFT, color)
		_add_score_avatar(row, player, color)
		_add_score_label(row, str(player.get("name", "Joueur")), name_width, HORIZONTAL_ALIGNMENT_LEFT, color)
		_add_score_label(
			row,
			_format_time(int(player.get("timeMs", 0))),
			time_width,
			HORIZONTAL_ALIGNMENT_RIGHT,
			Color("e8f1ff")
		)
		if animate_rows:
			_animate_score_row(row, index * 0.07)

	_clear_rows(podium_rows)
	podium_title.visible = not podium.is_empty()
	podium_rows.visible = not podium.is_empty()
	var podium_name_width := 142.0 if compact_layout else 235.0
	var podium_score_width := 116.0 if compact_layout else 155.0
	for index in range(podium.size()):
		var standing: Dictionary = podium[index]
		var podium_row := HBoxContainer.new()
		podium_row.add_theme_constant_override("separation", 6 if compact_layout else 8)
		podium_rows.add_child(podium_row)
		var color := Color.from_string(str(standing.get("color", "#ffffff")), Color.WHITE)
		if ensure_avatar_loaded_callback.is_valid():
			ensure_avatar_loaded_callback.call(standing)
		_add_score_label(
			podium_row,
			"%d" % (index + 1),
			rank_width,
			HORIZONTAL_ALIGNMENT_LEFT,
			Color("ffd166") if index == 0 else Color("c6d5e8")
		)
		_add_score_avatar(podium_row, standing, color)
		_add_score_label(
			podium_row,
			str(standing.get("name", "Joueur")),
			podium_name_width,
			HORIZONTAL_ALIGNMENT_LEFT,
			color
		)
		_add_score_label(
			podium_row,
			"%d pts / %d vict." % [
				int(standing.get("points", 0)),
				int(standing.get("wins", 0)),
			],
			podium_score_width,
			HORIZONTAL_ALIGNMENT_RIGHT,
			Color("9fb3c8")
		)
		if animate_rows:
			_animate_score_row(podium_row, 0.18 + index * 0.1)


func _refresh_header() -> void:
	if not is_instance_valid(score_header):
		return
	_clear_rows(score_header)
	_add_score_label(score_header, "#", 30.0 if compact_layout else 40.0, HORIZONTAL_ALIGNMENT_LEFT, Color("9aa9c2"))
	var avatar_header_spacer := Control.new()
	avatar_header_spacer.custom_minimum_size.x = 30.0 if compact_layout else 36.0
	score_header.add_child(avatar_header_spacer)
	_add_score_label(score_header, "Joueur", 168.0 if compact_layout else 270.0, HORIZONTAL_ALIGNMENT_LEFT, Color("9aa9c2"))
	_add_score_label(score_header, "Temps", 96.0 if compact_layout else 130.0, HORIZONTAL_ALIGNMENT_RIGHT, Color("9aa9c2"))


func _clear_rows(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _animate_panel() -> void:
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	panel.scale = Vector2(0.94, 0.94)
	panel.pivot_offset = panel.size * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)


func _animate_score_row(row: Control, delay: float) -> void:
	row.modulate = Color(1.0, 1.0, 1.0, 0.0)
	row.scale = Vector2(0.92, 0.92)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(row, "modulate:a", 1.0, 0.24).set_delay(delay)
	tween.tween_property(row, "scale", Vector2.ONE, 0.3).set_delay(delay).set_trans(
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
	label.add_theme_font_size_override("font_size", 14 if compact_layout else 16)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _add_score_avatar(parent: Container, player: Dictionary, color: Color) -> void:
	var avatar_size := 28.0 if compact_layout else 32.0
	var avatar_slot := Control.new()
	avatar_slot.custom_minimum_size = Vector2(avatar_size + 4.0, avatar_size + 2.0)
	avatar_slot.tooltip_text = "Avatar de %s" % str(player.get("name", "Joueur"))
	parent.add_child(avatar_slot)

	var frame := Panel.new()
	frame.position = Vector2.ZERO
	frame.size = Vector2(avatar_size, avatar_size)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = color.darkened(0.52)
	frame_style.border_color = color
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(int(avatar_size * 0.5))
	frame.add_theme_stylebox_override("panel", frame_style)
	avatar_slot.add_child(frame)

	var avatar_url := str(player.get("avatarUrl", ""))
	var avatar_texture = avatar_loader.get_texture(avatar_url) if avatar_loader else null
	if avatar_texture is Texture2D:
		var portrait := TextureRect.new()
		portrait.texture = avatar_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.position = Vector2(4, 4)
		portrait.size = Vector2(avatar_size - 8.0, avatar_size - 8.0)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar_slot.add_child(portrait)
		return

	var fallback := Label.new()
	fallback.text = _player_initial(player)
	fallback.position = Vector2.ZERO
	fallback.size = Vector2(avatar_size, avatar_size)
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_font_size_override("font_size", int(avatar_size * 0.42))
	fallback.add_theme_color_override("font_color", _readable_text_color(color))
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_slot.add_child(fallback)


func _player_initial(player: Dictionary) -> String:
	var player_name := str(player.get("name", "Joueur")).strip_edges().to_upper()
	for index in range(player_name.length()):
		var code := player_name.unicode_at(index)
		if (code >= 48 and code <= 57) or (code >= 65 and code <= 90):
			return player_name.substr(index, 1)
	return "?"


func _readable_text_color(background: Color) -> Color:
	var luminance := background.r * 0.299 + background.g * 0.587 + background.b * 0.114
	return Color("07101b") if luminance > 0.58 else Color.WHITE

func _apply_restart_button_style(button: Button) -> void:
	var colors := {
		"normal": Color("1d6b48"),
		"hover": Color("2fa56d"),
		"pressed": Color("154c35"),
	}
	for state in colors:
		var style := StyleBoxFlat.new()
		style.bg_color = colors[state]
		style.set_corner_radius_all(8)
		style.content_margin_left = 14
		style.content_margin_right = 14
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("e8fff3"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)


func _sort_players_by_rank(first: Dictionary, second: Dictionary) -> bool:
	return int(first.get("rank", 999)) < int(second.get("rank", 999))


func _format_time(time_ms: int) -> String:
	var minutes := int(time_ms / 60000)
	var seconds := int(time_ms / 1000) % 60
	var milliseconds := time_ms % 1000
	return "%02d:%02d.%03d" % [minutes, seconds, milliseconds]
