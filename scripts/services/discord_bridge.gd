extends Node

signal debug_logged(message: String, level: String)

var auth_request: HTTPRequest
var auth_request_action := ""
var user: Dictionary = {}
var session_token := ""
var activity_mode := false
var activity_ready := false
var activity_scope_ready := false
var login_pending := false
var bridge_error := ""
var bridge_poll_timer := 0.0
var presence_start_unix := 0
var presence_dirty := true
var presence_refresh_timer := 0.0
var presence_last_signature := ""
var debug_log_last_id := 0
var debug_empty_logged := false
var debug_last_error := ""
var debug_last_user_signature := ""

var discord_button: Button
var discord_status_label: Label
var name_input: LineEdit
var status_label: Label


func setup() -> void:
	if auth_request:
		return
	auth_request = HTTPRequest.new()
	auth_request.timeout = 8.0
	auth_request.request_completed.connect(_on_auth_request_completed)
	add_child(auth_request)


func configure_ui(
	next_discord_button: Button,
	next_discord_status_label: Label,
	next_name_input: LineEdit,
	next_status_label: Label
) -> void:
	discord_button = next_discord_button
	discord_status_label = next_discord_status_label
	name_input = next_name_input
	status_label = next_status_label


func default_server_url(fallback_url: String) -> String:
	if OS.has_feature("web"):
		var javascript := (
			"(function(){"
			+ "if (window.mazeDiscord && window.mazeDiscord.getWebSocketUrl) {"
			+ " return window.mazeDiscord.getWebSocketUrl();"
			+ "}"
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
	return fallback_url


func http_url(endpoint: String, local_server_url: String = "") -> String:
	if endpoint.begins_with("http://") or endpoint.begins_with("https://"):
		return endpoint
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval(
			"window.mazeDiscord && window.mazeDiscord.getServerBaseUrl"
			+ " ? window.mazeDiscord.getServerBaseUrl() : window.location.origin"
		)
		if origin is String and not origin.is_empty():
			return str(origin).rstrip("/") + endpoint
	var base := local_server_url.strip_edges()
	if base.is_empty():
		base = "ws://127.0.0.1:8080/ws"
	if base.begins_with("wss://"):
		base = "https://" + base.substr(6)
	elif base.begins_with("ws://"):
		base = "http://" + base.substr(5)
	if base.ends_with("/ws"):
		base = base.left(base.length() - 3)
	while base.ends_with("/"):
		base = base.left(base.length() - 1)
	return base + endpoint


func should_use_activity_flow() -> bool:
	if not OS.has_feature("web"):
		return false
	if activity_mode:
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


func check_session() -> void:
	if not OS.has_feature("web"):
		_set_discord_button("Discord : version Web", true)
		_set_discord_status("Connexion disponible dans l'export Web", Color("9aa9c2"))
		_log("Discord : export Web requis", "info")
		return
	JavaScriptBridge.eval("window.mazeDiscord && window.mazeDiscord.init && window.mazeDiscord.init()")
	_sync_bridge_state(true)
	if should_use_activity_flow():
		_log("Flux Discord Activity actif", "discord")
		return
	_request_session_check()


func handle_button_pressed() -> void:
	if should_use_activity_flow():
		_set_discord_button(null, true)
		_set_discord_status("Autorisation Discord...", Color("9aa9c2"))
		login_pending = true
		_log("Demande d'autorisation Rich Presence", "discord")
		JavaScriptBridge.eval(
			"window.mazeDiscord && window.mazeDiscord.beginLogin && window.mazeDiscord.beginLogin()"
		)
		return
	if not user.is_empty():
		auth_request_action = "logout"
		_set_discord_button(null, true)
		var error := auth_request.request(
			http_url("/api/auth/logout"),
			_auth_headers(),
			HTTPClient.METHOD_POST
		)
		if error != OK:
			_set_discord_button(null, false)
			_set_discord_status("Déconnexion impossible.", Color("9aa9c2"))
		return
	_set_discord_button(null, true)
	_set_discord_status("Ouverture de Discord...", Color("9aa9c2"))
	_log("Redirection OAuth Discord", "discord")
	JavaScriptBridge.eval("window.location.assign('/auth/discord')")


func update_bridge(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	bridge_poll_timer -= delta
	if bridge_poll_timer > 0.0:
		return
	bridge_poll_timer = 0.5
	_sync_bridge_state()
	if should_use_activity_flow() and not activity_ready:
		JavaScriptBridge.eval("window.mazeDiscord && window.mazeDiscord.init && window.mazeDiscord.init()")


func update_presence(delta: float, context: Dictionary) -> void:
	if not OS.has_feature("web") or not activity_mode or not activity_ready:
		return
	presence_refresh_timer -= delta
	if presence_refresh_timer > 0.0:
		return
	if presence_start_unix <= 0:
		presence_start_unix = int(Time.get_unix_time_from_system())
	var was_dirty := presence_dirty
	var payload := _presence_payload(context)
	var signature := JSON.stringify(payload)
	if was_dirty or signature != presence_last_signature or presence_refresh_timer <= 0.0:
		presence_last_signature = signature
		_send_presence(payload)
	presence_dirty = false
	presence_refresh_timer = 4.0 if was_dirty else 30.0


func mark_presence_dirty() -> void:
	presence_dirty = true
	presence_refresh_timer = 0.0


func add_activity_user(message: Dictionary) -> void:
	if not should_use_activity_flow() or user.is_empty():
		return
	var profile := {}
	for key in ["id", "username", "displayName", "global_name", "discriminator", "avatar", "defaultAvatar"]:
		if user.has(key):
			profile[key] = user[key]
	if not profile.is_empty():
		message["discordActivityUser"] = profile
		_log("Profil Activity joint au message %s" % str(message.get("type", "?")), "discord")


func get_session_token() -> String:
	return session_token


func _request_session_check() -> void:
	auth_request_action = "check"
	var url := http_url("/api/auth/me")
	_log("HTTP GET %s" % _safe_url(url), "net")
	var error := auth_request.request(url, _auth_headers())
	if error != OK:
		_log("HTTP auth impossible : %s" % error_string(error), "error")
		_show_unavailable()


func _auth_headers() -> PackedStringArray:
	var headers := PackedStringArray()
	if not session_token.is_empty():
		headers.append("Authorization: Bearer %s" % session_token)
	return headers


func _bridge_state() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var raw = JavaScriptBridge.eval(
		"window.mazeDiscord && window.mazeDiscord.getStateJson ? window.mazeDiscord.getStateJson() : ''"
	)
	if not raw is String or str(raw).is_empty():
		return {}
	var json := JSON.new()
	if json.parse(str(raw)) != OK or not json.data is Dictionary:
		return {}
	return json.data


func _sync_bridge_state(force_refresh: bool = false) -> void:
	var state := _bridge_state()
	if state.is_empty():
		if not debug_empty_logged:
			debug_empty_logged = true
			_log("Bridge Discord JS indisponible pour l'instant", "warn")
		return
	debug_empty_logged = false
	_sync_debug_logs(state.get("logs", []))
	var was_activity_mode := activity_mode
	var was_activity_ready := activity_ready
	var was_activity_scope_ready := activity_scope_ready
	activity_mode = bool(state.get("isActivity", false))
	activity_ready = bool(state.get("sdkReady", false))
	activity_scope_ready = bool(state.get("activityScopeReady", false))
	login_pending = bool(state.get("loginInFlight", false))
	bridge_error = str(state.get("error", ""))
	if activity_mode != was_activity_mode or activity_ready != was_activity_ready:
		mark_presence_dirty()
	if activity_mode != was_activity_mode:
		_log("Mode Discord Activity détecté" if activity_mode else "Mode web classique détecté", "discord")
	if activity_ready != was_activity_ready:
		_log("SDK Discord prêt" if activity_ready else "SDK Discord en attente", "discord")
	if activity_scope_ready and not was_activity_scope_ready:
		_log("Rich Presence autorisée", "ok")
	if not bridge_error.is_empty() and bridge_error != debug_last_error:
		_log("Discord : %s" % bridge_error, "error")
	debug_last_error = bridge_error
	var next_session_token := str(state.get("sessionToken", ""))
	var session_changed := next_session_token != session_token
	session_token = next_session_token
	if activity_mode:
		var bridge_user = state.get("user", {})
		if bridge_user is Dictionary and not bridge_user.is_empty():
			user = bridge_user
			var user_signature := "%s:%s" % [
				str(user.get("id", "")),
				str(user.get("displayName", user.get("username", ""))),
			]
			if user_signature != debug_last_user_signature:
				debug_last_user_signature = user_signature
				_log("Profil Activity : %s" % str(user.get("displayName", "Joueur Discord")), "discord")
		else:
			user = {}
			debug_last_user_signature = ""
		_refresh_controls(bool(state.get("enabled", false)))
		if session_changed or force_refresh:
			mark_presence_dirty()


func _sync_debug_logs(raw_logs) -> void:
	if not raw_logs is Array:
		return
	for entry in raw_logs:
		if not entry is Dictionary:
			continue
		var entry_id := int(entry.get("id", 0))
		if entry_id > 0 and entry_id <= debug_log_last_id:
			continue
		debug_log_last_id = maxi(debug_log_last_id, entry_id)
		var message := str(entry.get("message", ""))
		if message.is_empty():
			continue
		_log("JS " + message, str(entry.get("level", "info")))


func _presence_payload(context: Dictionary) -> Dictionary:
	var details := "Dans le lobby"
	var state := "Prêt pour une nouvelle course"
	var small_text := "Lobby"
	var room_code := str(context.get("room_code", ""))
	var player_count := int(context.get("player_count", 0))
	var current_round := int(context.get("current_round", 1))
	var max_players := int(context.get("max_players", 8))

	if not room_code.is_empty():
		state = "Manche %d - %d/%d joueur(s)" % [current_round, player_count, max_players]
		if bool(context.get("race_complete", false)):
			details = "Course terminée"
			small_text = "Classement"
			var rank := int(context.get("local_rank", 0))
			if rank > 0:
				state = "%s sur %d - manche %d" % [
					_rank_text(rank),
					maxi(1, player_count),
					current_round,
				]
		elif str(context.get("race_phase", "waiting")) == "waiting":
			details = "Prépare une course"
			small_text = "Salon en attente"
		elif str(context.get("race_phase", "waiting")) == "countdown":
			details = "Départ imminent"
			small_text = "Compte à rebours"
		elif bool(context.get("local_finished", false)):
			details = "A trouvé la sortie"
			state = "Attend les autres - manche %d" % current_round
			small_text = "Arrivé"
		else:
			details = "Dans le labyrinthe"
			small_text = "Course en cours"

	var payload := {
		"details": details,
		"state": state,
		"started_at": presence_start_unix,
		"large_text": "A Maze Inc.",
		"small_text": small_text,
	}
	if not room_code.is_empty() and player_count > 0:
		payload["party_size"] = player_count
		payload["party_max"] = max_players
	return payload


func _send_presence(payload: Dictionary) -> void:
	var payload_json := JSON.stringify(payload)
	var script := (
		"window.mazeDiscord"
		+ "&& window.mazeDiscord.setActivityFromGodot"
		+ "&& window.mazeDiscord.setActivityFromGodot(%s)"
	) % payload_json
	JavaScriptBridge.eval(script)


func _on_auth_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_log(
		"HTTP auth result=%d code=%d bytes=%d" % [result, response_code, body.size()],
		"net" if response_code == 200 else "warn"
	)
	var raw_body := body.get_string_from_utf8().strip_edges()
	if not raw_body.begins_with("{"):
		_log("HTTP auth non JSON : %s" % _shorten(raw_body.left(80)), "error")
		_show_unavailable()
		return
	var json := JSON.new()
	if json.parse(raw_body) != OK:
		_log("HTTP auth JSON invalide : %s" % _shorten(raw_body.left(80)), "error")
		_show_unavailable()
		return
	var payload = json.data
	if response_code != 200 or not payload is Dictionary:
		_log("HTTP auth refusé : code %d" % response_code, "warn")
		_show_unavailable()
		return
	var enabled := bool(payload.get("enabled", false))
	if bool(payload.get("authenticated", false)):
		var next_user = payload.get("user", {})
		user = next_user if next_user is Dictionary else {}
		login_pending = false
	else:
		user = {}
		if auth_request_action == "logout":
			session_token = ""
	_log(
		"HTTP auth : %s" % ("connecté" if bool(payload.get("authenticated", false)) else "non connecté"),
		"ok" if bool(payload.get("authenticated", false)) else "info"
	)
	_refresh_controls(enabled)
	mark_presence_dirty()
	if auth_request_action == "logout" and is_instance_valid(status_label):
		status_label.text = "Compte Discord déconnecté."
	auth_request_action = ""


func _refresh_controls(enabled: bool) -> void:
	if not _has_ui():
		return
	if should_use_activity_flow():
		if not user.is_empty():
			var activity_display_name := str(user.get("displayName", "Joueur Discord"))
			name_input.text = activity_display_name.left(16)
			name_input.editable = false
			name_input.tooltip_text = "Le profil Discord de l'Activity est utilisé automatiquement."
			_set_discord_status("Activity : %s" % activity_display_name, Color("79e36a"))
			if login_pending:
				_set_discord_button("Connexion Discord...", true)
			elif activity_scope_ready:
				_set_discord_button("Rich Presence active", true)
			elif activity_ready:
				_set_discord_button("Activer Rich Presence", false)
			else:
				_set_discord_button("Discord Activity", true)
			return
		name_input.editable = true
		name_input.tooltip_text = ""
		if not enabled:
			_set_discord_button("Discord non configuré", true)
			_set_discord_status("Configuration serveur requise", Color("9aa9c2"))
		elif not activity_ready:
			_set_discord_button("Discord Activity", true)
			_set_discord_status("Récupération du profil Discord...", Color("9aa9c2"))
		else:
			_set_discord_button("Activer Rich Presence", false)
			_set_discord_status("Profil Activity en attente", Color("9aa9c2"))
		return

	if not user.is_empty():
		var display_name := str(user.get("displayName", "Joueur Discord"))
		_set_discord_button("Se déconnecter", false)
		_set_discord_status("Connecté : %s" % display_name, Color("79e36a"))
		name_input.text = display_name.left(16)
		name_input.editable = false
		name_input.tooltip_text = "Le pseudo Discord est utilisé pendant la connexion."
		return
	name_input.editable = true
	name_input.tooltip_text = ""
	if enabled:
		_set_discord_button("Se connecter avec Discord", false)
		_set_discord_status("Utiliser votre photo de profil", Color("9aa9c2"))
	else:
		_set_discord_button("Discord non configuré", true)
		_set_discord_status("Configuration serveur requise", Color("9aa9c2"))


func _show_unavailable() -> void:
	user = {}
	login_pending = false
	_set_discord_button("Discord indisponible", true)
	_set_discord_status("Le serveur d'authentification ne répond pas", Color("ff8fa3"))
	_log("Discord indisponible côté menu", "error")


func _set_discord_button(text, disabled: bool) -> void:
	if not is_instance_valid(discord_button):
		return
	if text != null:
		discord_button.text = str(text)
	discord_button.disabled = disabled


func _set_discord_status(text: String, color: Color) -> void:
	if not is_instance_valid(discord_status_label):
		return
	discord_status_label.text = text
	discord_status_label.add_theme_color_override("font_color", color)


func _has_ui() -> bool:
	return (
		is_instance_valid(discord_button)
		and is_instance_valid(discord_status_label)
		and is_instance_valid(name_input)
	)


func _rank_text(rank: int) -> String:
	if rank == 1:
		return "1er"
	return "%de" % rank


func _log(message: String, level: String = "info") -> void:
	debug_logged.emit(message, level)


func _shorten(message: String) -> String:
	var compact := message.replace("\r", " ").replace("\n", " ").strip_edges()
	while compact.contains("  "):
		compact = compact.replace("  ", " ")
	if compact.length() > 112:
		return compact.left(111) + "..."
	return compact


func _safe_url(url: String) -> String:
	var safe := url
	var session_index := safe.find("session=")
	if session_index >= 0:
		var session_end := safe.find("&", session_index)
		if session_end >= 0:
			safe = safe.left(session_index) + "session=..." + safe.substr(session_end)
		else:
			safe = safe.left(session_index) + "session=..."
	return _shorten(safe)
