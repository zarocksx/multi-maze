extends Node

signal avatar_changed

var avatar_textures: Dictionary = {}


func ensure_loaded(player: Dictionary, request_url: String) -> void:
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
	var error := request.request(request_url)
	if error != OK:
		avatar_textures.erase(avatar_url)
		request.queue_free()


func get_texture(avatar_url: String):
	return avatar_textures.get(avatar_url)


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
			avatar_changed.emit()
		else:
			avatar_textures.erase(avatar_url)
	else:
		avatar_textures.erase(avatar_url)
	request.queue_free()
