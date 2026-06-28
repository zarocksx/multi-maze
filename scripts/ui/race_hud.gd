extends Node
class_name RaceHud

signal tone_requested(
	frequency: float,
	duration: float,
	volume: float,
	waveform: String,
	slide: float
)
signal direction_hint_requested(until_ms: int)

var countdown_label: Label
var event_toast: Label
var hud_row: HBoxContainer
var rank_label: Label
var progress_label: Label
var effect_hud_label: Label

var event_toast_timer := 0.0
var last_countdown_value := ""
var last_rank_text := ""
var last_effect_signature := ""


func build(root: Control) -> void:
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
	event_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	event_toast.add_theme_font_size_override("font_size", 19)
	event_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	event_toast.offset_left = -270
	event_toast.offset_top = 18
	event_toast.offset_right = 270
	event_toast.offset_bottom = 58
	event_toast.z_index = 15
	root.add_child(event_toast)

	hud_row = HBoxContainer.new()
	hud_row.visible = false
	hud_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_row.add_theme_constant_override("separation", 8)
	hud_row.z_index = 12
	root.add_child(hud_row)

	rank_label = Label.new()
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_chip_style(rank_label, Color(0.16, 0.12, 0.04, 0.9), Color("ffd166"), Color("ffd166"))
	hud_row.add_child(rank_label)

	progress_label = Label.new()
	progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_chip_style(progress_label, Color(0.04, 0.12, 0.15, 0.9), Color("83e8ff"), Color("dffbff"))
	hud_row.add_child(progress_label)

	effect_hud_label = Label.new()
	effect_hud_label.visible = false
	effect_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_hud_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_chip_style(effect_hud_label, Color(0.12, 0.06, 0.17, 0.92), Color("b58cff"), Color("f3eaff"))
	hud_row.add_child(effect_hud_label)

	layout(root.get_viewport_rect().size)


func layout(viewport_size: Vector2) -> void:
	var compact := viewport_size.y < 520.0 or viewport_size.x < 760.0
	var side_margin := 12.0 if compact else 16.0
	var top_margin := 10.0 if compact else 14.0
	if is_instance_valid(hud_row):
		hud_row.position = Vector2(side_margin, top_margin)
		hud_row.size = Vector2(maxf(300.0, viewport_size.x - side_margin * 2.0), 44.0)
		rank_label.custom_minimum_size = Vector2(78.0 if compact else 96.0, 34.0 if compact else 38.0)
		progress_label.custom_minimum_size = Vector2(112.0 if compact else 142.0, 34.0 if compact else 38.0)
		effect_hud_label.custom_minimum_size = Vector2(0.0, 34.0 if compact else 38.0)
		rank_label.add_theme_font_size_override("font_size", 16 if compact else 18)
		progress_label.add_theme_font_size_override("font_size", 15 if compact else 16)
		effect_hud_label.add_theme_font_size_override("font_size", 14 if compact else 16)
	if is_instance_valid(event_toast):
		var toast_width := minf(560.0, viewport_size.x - side_margin * 2.0)
		event_toast.offset_left = -toast_width * 0.5
		event_toast.offset_top = 10.0 if compact else 18.0
		event_toast.offset_right = toast_width * 0.5
		event_toast.offset_bottom = event_toast.offset_top + (42.0 if compact else 48.0)
		event_toast.add_theme_font_size_override("font_size", 17 if compact else 19)
	if is_instance_valid(countdown_label):
		var countdown_size := int(clampf(minf(viewport_size.x, viewport_size.y) * 0.22, 72.0, 112.0))
		countdown_label.add_theme_font_size_override("font_size", countdown_size)


func update_toast(delta: float) -> void:
	if event_toast_timer <= 0.0:
		return
	event_toast_timer = maxf(0.0, event_toast_timer - delta)
	event_toast.visible = event_toast_timer > 0.0
	if event_toast.visible:
		event_toast.modulate.a = clampf(event_toast_timer * 2.4, 0.0, 1.0)


func update_countdown(race_phase: String, race_start_deadline_ms: int, go_flash_until_ms: int) -> void:
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
			_pulse_label(countdown_label, 1.12)
			tone_requested.emit(440.0, 0.22, 0.2, "square", 440.0)
			direction_hint_requested.emit(now + 3200)
		else:
			_pulse_label(countdown_label, 1.08)
			tone_requested.emit(280.0, 0.11, 0.13, "square", 0.0)
	elif not countdown_label.visible:
		last_countdown_value = ""


func update_race_hud(
	room_code: String,
	race_complete: bool,
	race_phase: String,
	players: Array,
	player_id: String,
	goal: Dictionary,
	effect_remaining: Callable,
	effect_active: Callable
) -> void:
	var show_race_hud := not room_code.is_empty() and not race_complete and race_phase != "waiting"
	hud_row.visible = show_race_hud
	rank_label.visible = show_race_hud
	progress_label.visible = show_race_hud
	if show_race_hud:
		var ordered_players := players.duplicate()
		ordered_players.sort_custom(func(first, second): return _sort_live_race(first, second, goal))
		for index in range(ordered_players.size()):
			if str(ordered_players[index].get("id", "")) == player_id:
				rank_label.text = "RANG %d%s/%d" % [
					index + 1,
					"er" if index == 0 else "e",
					ordered_players.size(),
				]
				break
		if rank_label.text != last_rank_text:
			last_rank_text = rank_label.text
			_pulse_label(rank_label, 1.12)
		progress_label.text = _progress_text(players, player_id, goal)
	else:
		last_rank_text = ""

	var effect_texts: Array[String] = []
	var effect_names: Array[String] = []
	for effect in RaceVisuals.TIMED_EFFECTS:
		var remaining := float(effect_remaining.call(effect)) if effect_remaining.is_valid() else 0.0
		if remaining <= 0.0:
			continue
		effect_texts.append("%s %.1fs" % [RaceVisuals.effect_label(effect), remaining])
		effect_names.append(effect)
	if effect_active.is_valid() and bool(effect_active.call("shield")):
		effect_texts.append(RaceVisuals.effect_label("shield"))
		effect_names.append("shield")
	effect_hud_label.visible = show_race_hud and not effect_texts.is_empty()
	effect_hud_label.text = " / ".join(effect_texts)
	var effect_signature := "|".join(effect_names)
	if effect_signature != last_effect_signature:
		last_effect_signature = effect_signature
		if effect_hud_label.visible:
			_pulse_label(effect_hud_label, 1.1)


func show_power_event(event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	var color := RaceVisuals.power_event_color(kind)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.94)
	style.border_color = Color(1.0, 1.0, 1.0, 0.32)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	event_toast.add_theme_stylebox_override("normal", style)
	event_toast.add_theme_color_override("font_color", RaceVisuals.text_color_for_background(color))
	event_toast.text = str(event.get("message", "Objet mystere active !"))
	event_toast_timer = 3.0
	event_toast.visible = true
	event_toast.modulate.a = 1.0
	_pulse_label(event_toast, 1.08)

	var tone := RaceVisuals.power_event_tone(kind)
	tone_requested.emit(
		float(tone["frequency"]),
		float(tone["duration"]),
		float(tone["volume"]),
		str(tone["waveform"]),
		float(tone["slide"])
	)


func _apply_chip_style(label: Label, bg_color: Color, border_color: Color, font_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	var next_border_color := border_color
	next_border_color.a = 0.7
	style.border_color = next_border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	label.add_theme_stylebox_override("normal", style)
	label.add_theme_color_override("font_color", font_color)


func _progress_text(players: Array, player_id: String, goal: Dictionary) -> String:
	var local_player: Dictionary = {}
	for player in players:
		if str(player.get("id", "")) == player_id:
			local_player = player
			break
	if local_player.is_empty():
		return "SORTIE --%"
	var maximum_distance := maxf(1.0, float(goal.get("x", 0)) + float(goal.get("y", 0)))
	var distance := absf(float(goal.get("x", 0)) - float(local_player.get("x", 0)))
	distance += absf(float(goal.get("y", 0)) - float(local_player.get("y", 0)))
	var progress := clampf(1.0 - distance / maximum_distance, 0.0, 1.0)
	return "SORTIE %d%%" % roundi(progress * 100.0)


func _pulse_label(label: Control, peak: float) -> void:
	if not is_instance_valid(label):
		return
	label.pivot_offset = label.size * 0.5
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE * peak, 0.08).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, 0.16).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)


func _sort_live_race(first: Dictionary, second: Dictionary, goal: Dictionary) -> bool:
	var first_finished := bool(first.get("finished", false))
	var second_finished := bool(second.get("finished", false))
	if first_finished != second_finished:
		return first_finished
	if first_finished:
		return int(first.get("rank", 999)) < int(second.get("rank", 999))
	var first_distance := absf(float(goal.get("x", 0)) - float(first.get("x", 0)))
	first_distance += absf(float(goal.get("y", 0)) - float(first.get("y", 0)))
	var second_distance := absf(float(goal.get("x", 0)) - float(second.get("x", 0)))
	second_distance += absf(float(goal.get("y", 0)) - float(second.get("y", 0)))
	return first_distance < second_distance
