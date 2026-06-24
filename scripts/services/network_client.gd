extends Node

signal connecting(url: String)
signal connection_failed(error_text: String)
signal opened
signal closed(while_in_room: bool)
signal sent(message_type: String)
signal packet_warning(message: String)
signal message_received(message: Dictionary)

var socket := WebSocketPeer.new()
var pending_message: Dictionary = {}
var last_socket_state := WebSocketPeer.STATE_CLOSED


func poll(while_in_room: bool) -> void:
	var state := socket.get_ready_state()
	if state != WebSocketPeer.STATE_CLOSED:
		socket.poll()
		state = socket.get_ready_state()

	if state != last_socket_state:
		last_socket_state = state
		if state == WebSocketPeer.STATE_OPEN:
			opened.emit()
			if not pending_message.is_empty():
				send_json(pending_message)
				pending_message = {}
		elif state == WebSocketPeer.STATE_CLOSED:
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
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		send_json(message)
		return
	if socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		pending_message = message
		return

	socket = WebSocketPeer.new()
	last_socket_state = WebSocketPeer.STATE_CLOSED
	pending_message = message
	var next_url := url.strip_edges()
	if OS.has_feature("web") and not session_token.is_empty():
		next_url += "%ssession=%s" % ["&" if next_url.contains("?") else "?", session_token]
	var error := socket.connect_to_url(next_url)
	if error != OK:
		pending_message = {}
		connection_failed.emit(error_string(error))
	else:
		connecting.emit(next_url)


func send_json(message: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	sent.emit(str(message.get("type", "?")))
	socket.send_text(JSON.stringify(message))
