extends Node
class_name ScoreboardPanel

signal restart_requested

var panel: PanelContainer
var restart_button: Button

var score_rows: VBoxContainer
var podium_rows: VBoxContainer
var score_subtitle: Label
var avatar_loader: Node
var ensure_avatar_loaded_callback: Callable
var animated_round := 0


func build(root: Control, next_avatar_loader: Node, next_ensure_avatar_loaded: Callable) -> void:
	avatar_loader = next_avatar_loader
	ensure_avatar_loaded_callback = next_ensure_avatar_loaded

	panel = PanelContainer.new()
	panel.visible = false
	panel.z_index = 10
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -290
	panel.offset_top = -270
	panel.offset_right = 290
	panel.offset_bottom = 270
	var score_style := StyleBoxFlat.new()
	score_style.bg_color = Color("101c2d")
	score_style.border_color = Color("ffd166")
	score_style.set_border_width_all(2)
	score_style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", score_style)
	root.add_child(panel)

	var score_margin := MarginContainer.new()
	score_margin.add_theme_constant_override("margin_left", 24)
	score_margin.add_theme_constant_override("margin_top", 20)
	score_margin.add_theme_constant_override("margin_right", 24)
	score_margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(score_margin)

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

	restart_button = Button.new()
	restart_button.text = "Préparer un nouveau labyrinthe"
	restart_button.visible = false
	restart_button.pressed.connect(func(): restart_requested.emit())
	score_content.add_child(restart_button)


func refresh(
	players: Array,
	podium: Array,
	race_complete: bool,
	current_round: int,
	is_host: bool
) -> void:
	panel.visible = race_complete
	restart_button.visible = race_complete and is_host
	if not race_complete:
		return

	var animate_rows := animated_round != current_round
	if animate_rows:
		animated_round = current_round
	score_subtitle.text = "Classement de la manche %d" % current_round

	_clear_rows(score_rows)
	var ranked_players := players.duplicate()
	ranked_players.sort_custom(_sort_players_by_rank)
	for index in range(ranked_players.size()):
		var player: Dictionary = ranked_players[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		score_rows.add_child(row)
		var color := Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE)
		_add_score_label(row, "%d." % int(player.get("rank", 0)), 40, HORIZONTAL_ALIGNMENT_LEFT, color)
		_add_score_avatar(row, player, color)
		_add_score_label(row, str(player.get("name", "Joueur")), 270, HORIZONTAL_ALIGNMENT_LEFT, color)
		_add_score_label(
			row,
			_format_time(int(player.get("timeMs", 0))),
			130,
			HORIZONTAL_ALIGNMENT_RIGHT,
			Color("e8f1ff")
		)
		if animate_rows:
			_animate_score_row(row, index * 0.09)

	_clear_rows(podium_rows)
	for index in range(podium.size()):
		var standing: Dictionary = podium[index]
		var podium_row := HBoxContainer.new()
		podium_row.add_theme_constant_override("separation", 8)
		podium_rows.add_child(podium_row)
		var color := Color.from_string(str(standing.get("color", "#ffffff")), Color.WHITE)
		if ensure_avatar_loaded_callback.is_valid():
			ensure_avatar_loaded_callback.call(standing)
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


func _clear_rows(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


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
	var avatar_texture = avatar_loader.get_texture(avatar_url) if avatar_loader else null
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
