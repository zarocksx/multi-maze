extends Node

const MAX_LINES := 8
const MAX_CHARS := 112

var panel: PanelContainer
var label: Label
var lines: Array = []
var last_visible := false


func build(root: Control) -> void:
	panel = PanelContainer.new()
	panel.name = "MenuDebugLogs"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 18
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	var debug_style := StyleBoxFlat.new()
	debug_style.bg_color = Color(0.025, 0.055, 0.09, 0.74)
	debug_style.border_color = Color(0.32, 0.79, 0.95, 0.24)
	debug_style.set_border_width_all(1)
	debug_style.set_corner_radius_all(9)
	debug_style.content_margin_left = 10
	debug_style.content_margin_right = 10
	debug_style.content_margin_top = 8
	debug_style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", debug_style)
	root.add_child(panel)

	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("b9d5ec"))
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(label)
	layout(root.get_viewport_rect().size)
	refresh()


func layout(viewport_size: Vector2) -> void:
	if not is_instance_valid(panel):
		return
	var width := minf(460.0, maxf(292.0, viewport_size.x - 32.0))
	var height := 142.0 if viewport_size.y >= 480.0 else 108.0
	panel.offset_left = 16
	panel.offset_right = 16 + width
	panel.offset_bottom = -64
	panel.offset_top = panel.offset_bottom - height


func log(message: String, level: String = "info") -> void:
	var now := Time.get_time_dict_from_system()
	var stamp := "%02d:%02d:%02d" % [
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
		int(now.get("second", 0)),
	]
	var tag := _level_tag(level)
	lines.append("%s %-4s %s" % [stamp, tag, shorten(message)])
	while lines.size() > MAX_LINES:
		lines.pop_front()
	refresh()


func shorten(message: String) -> String:
	var compact := message.replace("\r", " ").replace("\n", " ").strip_edges()
	while compact.contains("  "):
		compact = compact.replace("  ", " ")
	if compact.length() > MAX_CHARS:
		return compact.left(MAX_CHARS - 1) + "…"
	return compact


func safe_url(url: String) -> String:
	var safe := url
	var session_index := safe.find("session=")
	if session_index >= 0:
		var session_end := safe.find("&", session_index)
		if session_end >= 0:
			safe = safe.left(session_index) + "session=…" + safe.substr(session_end)
		else:
			safe = safe.left(session_index) + "session=…"
	return shorten(safe)


func refresh() -> void:
	if not is_instance_valid(label):
		return
	var text := ""
	for line in lines:
		if not text.is_empty():
			text += "\n"
		text += str(line)
	label.text = text if not text.is_empty() else "diag: en attente des événements…"


func set_context_visible(next_visible: bool) -> void:
	if not is_instance_valid(panel):
		return
	panel.visible = next_visible
	if next_visible == last_visible:
		return
	last_visible = next_visible
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"window.mazeDiscord && window.mazeDiscord.setDebugOverlayVisible"
			+ " && window.mazeDiscord.setDebugOverlayVisible(%s)" % ("true" if next_visible else "false")
		)


func _level_tag(level: String) -> String:
	match level.to_lower():
		"ok":
			return "OK"
		"net":
			return "NET"
		"discord":
			return "DISC"
		"warn":
			return "WARN"
		"error":
			return "ERR"
		_:
			return "INFO"
