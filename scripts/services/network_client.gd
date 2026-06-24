extends Node
class_name NetworkClient

signal connecting(url: String)
signal connection_failed(error_text: String)
signal opened
signal closed(while_in_room: bool)
signal sent(message_type: String)
signal packet_warning(message: String)
signal message_received(message: Dictionary)

const CONNECT_TIMEOUT_MS := 4500

var socket := WebSocketPeer.new()
var pending_message: Dictionary = {}
var last_socket_state := WebSocketPeer.STATE_CLOSED
var candidate_urls: Array = []
var candidate_index := 0
var active_url := ""
var active_session_token := ""
var connect_started_ms := 0


func poll(while_in_room: bool) -> void:
	var state := socket.get_ready_state()
	if state != WebSocketPeer.STATE_CLOSED:
		socket.poll()
		state = socket.get_ready_state()

	if (
		state == WebSocketPeer.STATE_CONNECTING
		and connect_started_ms > 0
		and Time.get_ticks_msec() - connect_started_ms > CONNECT_TIMEOUT_MS
	):
		if _try_next_candidate("WS timeout"):
			return
		pending_message = {}
		connect_started_ms = 0
		connection_failed.emit("timeout WebSocket")
		return

	if state != last_socket_state:
		last_socket_state = state
		if state == WebSocketPeer.STATE_OPEN:
			connect_started_ms = 0
			opened.emit()
			if not pending_message.is_empty():
				send_json(pending_message)
				pending_message = {}
		elif state == WebSocketPeer.STATE_CLOSED:
			if connect_started_ms > 0 and not pending_message.is_empty():
				if _try_next_candidate("WS fermé avant ouverture"):
					return
				pending_message = {}
				connect_started_ms = 0
				connection_failed.emit("connexion WebSocket fermée avant ouverture")
				return
			closed.emit(while_in_room)

	while (
		socket.get_ready_state() == WebSocketPeer.STATE_OPEN
		and socket.get_available_packet_count() > 0
	):
		var packet := socket.get_packet().get_string_from_utf8()
		var packet_text := packet.strip_edges()
		if not packet_text.begins_with("{"):
			packet_warning.emit("WS paquet non JSON : %s" % packet_text.left(80))
			continue
		var json := JSON.new()
		if json.parse(packet_text) != OK:
			packet_warning.emit("WS JSON invalide : %s" % packet_text.left(80))
			continue
		var message = json.data
		if message is Dictionary:
			message_received.emit(message)


func connect_and_send(message: Dictionary, url: String, session_token: String = "") -> void:
	connect_and_send_with_candidates(message, [url], session_token)


func connect_and_send_with_candidates(message: Dictionary, urls: Array, session_token: String = "") -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		send_json(message)
		return
	if socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		pending_message = message
		return

	pending_message = message
	active_session_token = session_token
	candidate_urls = _unique_urls(urls)
	candidate_index = 0
	if candidate_urls.is_empty():
		pending_message = {}
		connection_failed.emit("aucune URL WebSocket")
		return
	if not _connect_current_candidate():
		pending_message = {}
		connection_failed.emit("aucun candidat WebSocket joignable")


func _connect_current_candidate() -> bool:
	while candidate_index < candidate_urls.size():
		var next_url := str(candidate_urls[candidate_index]).strip_edges()
		candidate_index += 1
		if next_url.is_empty():
			continue
		active_url = _with_session_token(next_url)
		socket = WebSocketPeer.new()
		last_socket_state = WebSocketPeer.STATE_CLOSED
		connect_started_ms = Time.get_ticks_msec()
		var error := socket.connect_to_url(active_url)
		if error == OK:
			connecting.emit(active_url)
			return true
		packet_warning.emit("WS candidat refusé : %s" % error_string(error))
	connect_started_ms = 0
	active_url = ""
	return false


func _try_next_candidate(reason: String) -> bool:
	packet_warning.emit("%s : %s" % [reason, active_url])
	socket = WebSocketPeer.new()
	last_socket_state = WebSocketPeer.STATE_CLOSED
	return _connect_current_candidate()


func _unique_urls(urls: Array) -> Array:
	var output := []
	for raw_url in urls:
		var value := str(raw_url).strip_edges()
		if value.is_empty() or output.has(value):
			continue
		output.append(value)
	return output


func _with_session_token(url: String) -> String:
	var next_url := url.strip_edges()
	if OS.has_feature("web") and not active_session_token.is_empty():
		next_url += "%ssession=%s" % ["&" if next_url.contains("?") else "?", active_session_token]
	return next_url


func send_json(message: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	sent.emit(str(message.get("type", "?")))
	socket.send_text(JSON.stringify(message))
