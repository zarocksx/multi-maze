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
var rank_label: Label
var effect_hud_label: Label

var event_toast_timer := 0.0
var last_countdown_value := ""


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


func update_toast(delta: float) -> void:
	if event_toast_timer <= 0.0:
		return
	event_toast_timer = maxf(0.0, event_toast_timer - delta)
	event_toast.visible = event_toast_timer > 0.0


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
			tone_requested.emit(440.0, 0.22, 0.2, "square", 440.0)
			direction_hint_requested.emit(now + 3200)
		else:
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
	rank_label.visible = show_race_hud
	if show_race_hud:
		var ordered_players := players.duplicate()
		ordered_players.sort_custom(func(first, second): return _sort_live_race(first, second, goal))
		for index in range(ordered_players.size()):
			if str(ordered_players[index].get("id", "")) == player_id:
				rank_label.text = "%d%s / %d" % [
					index + 1,
					"er" if index == 0 else "e",
					ordered_players.size(),
				]
				break

	var effect_texts: Array[String] = []
	for effect in RaceVisuals.TIMED_EFFECTS:
		var remaining := float(effect_remaining.call(effect)) if effect_remaining.is_valid() else 0.0
		if remaining <= 0.0:
			continue
		effect_texts.append("%s  %.1fs" % [RaceVisuals.effect_label(effect), remaining])
	if effect_active.is_valid() and bool(effect_active.call("shield")):
		effect_texts.append(RaceVisuals.effect_label("shield"))
	effect_hud_label.visible = not effect_texts.is_empty()
	effect_hud_label.text = "  •  ".join(effect_texts)


func show_power_event(event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	var color := RaceVisuals.power_event_color(kind)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.92)
	style.set_corner_radius_all(9)
	style.content_margin_left = 14
	style.content_margin_right = 14
	event_toast.add_theme_stylebox_override("normal", style)
	event_toast.add_theme_color_override("font_color", RaceVisuals.text_color_for_background(color))
	event_toast.text = str(event.get("message", "Objet mystère activé !"))
	event_toast_timer = 3.0
	event_toast.visible = true

	var tone := RaceVisuals.power_event_tone(kind)
	tone_requested.emit(
		float(tone["frequency"]),
		float(tone["duration"]),
		float(tone["volume"]),
		str(tone["waveform"]),
		float(tone["slide"])
	)


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
