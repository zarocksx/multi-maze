extends Node2D
class_name WorldRenderer

var game_state: GameState
var avatar_loader: AvatarLoader
var lobby_panel: Control

var visual_positions: Dictionary = {}
var trail_marks: Array = []
var movement_ripples: Array = []
var pickup_particles: Array = []
var celebration_particles: Array = []

var animation_time := 0.0
var wall_hit_timer := 0.0
var power_down_flash_timer := 0.0
var power_down_flash_color := Color.TRANSPARENT
var wall_shake_enabled := true
var direction_hint_until_ms := 0
var last_maze_origin := Vector2.ZERO
var last_cell_size := 0.0
var hovered_player_id: String = ""


func configure(
	next_game_state: GameState,
	next_avatar_loader: AvatarLoader,
	next_lobby_panel: Control
) -> void:
	game_state = next_game_state
	avatar_loader = next_avatar_loader
	lobby_panel = next_lobby_panel


func bind_view_state(
	next_visual_positions: Dictionary,
	next_trail_marks: Array,
	next_movement_ripples: Array,
	next_pickup_particles: Array,
	next_celebration_particles: Array
) -> void:
	visual_positions = next_visual_positions
	trail_marks = next_trail_marks
	movement_ripples = next_movement_ripples
	pickup_particles = next_pickup_particles
	celebration_particles = next_celebration_particles


func set_timers(
	next_animation_time: float,
	next_wall_hit_timer: float,
	next_power_down_flash_timer: float,
	next_power_down_flash_color: Color,
	next_wall_shake_enabled: bool
) -> void:
	animation_time = next_animation_time
	wall_hit_timer = next_wall_hit_timer
	power_down_flash_timer = next_power_down_flash_timer
	power_down_flash_color = next_power_down_flash_color
	wall_shake_enabled = next_wall_shake_enabled


func show_direction_hint(until_ms: int) -> void:
	direction_hint_until_ms = until_ms


func reset_layout_cache() -> void:
	last_maze_origin = Vector2.ZERO
	last_cell_size = 0.0
	hovered_player_id = ""


func update_player_tooltip(player_tooltip: Label, mouse_position: Vector2) -> void:
	if not is_instance_valid(player_tooltip):
		return
	if game_state == null or game_state.maze.is_empty() or last_cell_size <= 0.0 or game_state.race_complete:
		player_tooltip.visible = false
		hovered_player_id = ""
		return

	var hovered_player: Dictionary = {}
	var closest_distance := INF
	for player in game_state.players:
		var id := str(player.get("id", ""))
		var target := GameState.grid_position(player)
		var visual_position: Vector2 = visual_positions.get(id, target)
		var center := last_maze_origin + (visual_position + Vector2(0.5, 0.5)) * last_cell_size
		var distance := mouse_position.distance_to(center)
		if distance <= last_cell_size * 0.38 + 6.0 and distance < closest_distance:
			hovered_player = player
			closest_distance = distance

	if hovered_player.is_empty():
		player_tooltip.visible = false
		hovered_player_id = ""
		return

	var id := str(hovered_player.get("id", ""))
	var target := GameState.grid_position(hovered_player)
	var visual_position: Vector2 = visual_positions.get(id, target)
	var center := last_maze_origin + (visual_position + Vector2(0.5, 0.5)) * last_cell_size
	if hovered_player_id != id:
		hovered_player_id = id
		var color := Color.from_string(
			str(hovered_player.get("color", "#ffffff")),
			Color.WHITE
		)
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		player_tooltip.add_theme_stylebox_override("normal", style)
		var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
		var text_color := Color("07101b") if luminance > 0.58 else Color.WHITE
		player_tooltip.add_theme_color_override("font_color", text_color)
		player_tooltip.text = str(hovered_player.get("name", "Joueur"))
		player_tooltip.reset_size()
		player_tooltip.size = player_tooltip.get_combined_minimum_size()

	var tooltip_position := center - Vector2(
		player_tooltip.size.x * 0.5,
		last_cell_size * 0.38 + player_tooltip.size.y + 10.0
	)
	var viewport_size := get_viewport_rect().size
	tooltip_position.x = clampf(tooltip_position.x, 6.0, viewport_size.x - player_tooltip.size.x - 6.0)
	tooltip_position.y = maxf(6.0, tooltip_position.y)
	player_tooltip.position = tooltip_position
	player_tooltip.visible = true


func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	_draw_background(viewport_size)
	if game_state == null or game_state.maze.is_empty():
		reset_layout_cache()
		_draw_idle_mark(viewport_size)
		return

	var maze := game_state.maze
	var width := int(maze.get("width", 1))
	var height := int(maze.get("height", 1))
	var top_margin := 72.0
	if game_state.room_code.is_empty():
		top_margin = maxf(174.0, lobby_panel.size.y + 28.0 if is_instance_valid(lobby_panel) else 174.0)
	elif game_state.race_phase == "waiting":
		top_margin = 190.0
	var available := Vector2(viewport_size.x - 48.0, viewport_size.y - top_margin - 58.0)
	var cell_size := floorf(minf(available.x / width, available.y / height))
	cell_size = maxf(cell_size, 8.0)
	var maze_size := Vector2(width * cell_size, height * cell_size)
	var origin := Vector2(
		(viewport_size.x - maze_size.x) * 0.5,
		top_margin + (available.y - maze_size.y) * 0.5
	)
	if wall_shake_enabled and wall_hit_timer > 0.0:
		var shake := wall_hit_timer / 0.2 * 4.0
		origin += Vector2(sin(animation_time * 91.0), cos(animation_time * 77.0)) * shake
	last_maze_origin = origin
	last_cell_size = cell_size

	var maze_backing := Color("0d1b2d")
	if wall_hit_timer > 0.0:
		maze_backing = maze_backing.lerp(Color("54203a"), wall_hit_timer / 0.16 * 0.35)
	draw_rect(Rect2(origin - Vector2(7, 7), maze_size + Vector2(14, 14)), maze_backing, true)
	_draw_goal(origin, cell_size)
	_draw_direction_hint(origin, cell_size)
	_draw_power_ups(origin, cell_size)
	_draw_trails(origin, cell_size)
	_draw_movement_ripples(origin, cell_size)
	_draw_pickup_particles(origin, cell_size)
	_draw_maze_walls(origin, cell_size, width, height)
	_draw_celebration(origin, cell_size)
	_draw_players(origin, cell_size)
	_draw_wall_hit_fx(origin, cell_size)
	_draw_power_down_screen_fx(viewport_size)
	_draw_countdown_fx(viewport_size)


func _draw_power_down_screen_fx(viewport_size: Vector2) -> void:
	if _local_effect_active("slow"):
		_draw_slow_screen_fx(viewport_size, _power_down_fade("slow"))
	if _local_effect_active("confused"):
		_draw_confused_screen_fx(viewport_size, _power_down_fade("confused"))
	if _local_effect_active("frozen"):
		_draw_frozen_screen_fx(viewport_size, _power_down_fade("frozen"))
	if power_down_flash_timer > 0.0:
		var flash := clampf(power_down_flash_timer / 0.46, 0.0, 1.0)
		draw_rect(
			Rect2(Vector2.ZERO, viewport_size),
			Color(power_down_flash_color, flash * 0.11),
			true
		)
		draw_arc(
			viewport_size * 0.5,
			lerpf(28.0, minf(viewport_size.x, viewport_size.y) * 0.42, 1.0 - flash),
			0.0,
			TAU,
			64,
			Color(power_down_flash_color, flash * 0.58),
			lerpf(7.0, 2.0, 1.0 - flash),
			true
		)


func _power_down_fade(effect_name: String) -> float:
	return clampf(_local_effect_remaining(effect_name) * 2.5, 0.0, 1.0)


func _draw_edge_vignette(viewport_size: Vector2, color: Color, strength: float) -> void:
	var edge_size := clampf(minf(viewport_size.x, viewport_size.y) * 0.13, 52.0, 112.0)
	for layer in range(7):
		var progress := float(layer) / 6.0
		var depth := lerpf(edge_size, 5.0, progress)
		var alpha := strength * lerpf(0.015, 0.055, progress)
		var layer_color := Color(color, alpha)
		draw_rect(Rect2(0.0, 0.0, viewport_size.x, depth), layer_color, true)
		draw_rect(
			Rect2(0.0, viewport_size.y - depth, viewport_size.x, depth),
			layer_color,
			true
		)
		draw_rect(Rect2(0.0, 0.0, depth, viewport_size.y), layer_color, true)
		draw_rect(
			Rect2(viewport_size.x - depth, 0.0, depth, viewport_size.y),
			layer_color,
			true
		)


func _draw_slow_screen_fx(viewport_size: Vector2, fade: float) -> void:
	var color := RaceVisuals.power_down_color("slow")
	var pulse := 0.72 + (sin(animation_time * 2.0) + 1.0) * 0.14
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(color, 0.025 * fade), true)
	_draw_edge_vignette(viewport_size, color, pulse * fade)
	for side in range(2):
		var direction := 1.0 if side == 0 else -1.0
		var edge_x := 0.0 if side == 0 else viewport_size.x
		for streak in range(5):
			var y := fmod(animation_time * 21.0 + streak * viewport_size.y / 5.0, viewport_size.y)
			var length := 54.0 + streak * 11.0
			var wave := sin(animation_time * 1.7 + streak * 1.3) * 9.0
			draw_line(
				Vector2(edge_x, y),
				Vector2(edge_x + direction * length, y + wave),
				Color(color, (0.16 + streak * 0.018) * fade),
				3.0,
				true
			)


func _draw_confused_screen_fx(viewport_size: Vector2, fade: float) -> void:
	var cyan := RaceVisuals.power_event_color("speed")
	var magenta := RaceVisuals.power_down_color("confused")
	var wobble := sin(animation_time * 6.0) * 6.0
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(magenta, 0.018 * fade), true)
	draw_rect(
		Rect2(Vector2(8.0 + wobble, 9.0), viewport_size - Vector2(18.0, 18.0)),
		Color(cyan, 0.42 * fade),
		false,
		2.0,
		true
	)
	draw_rect(
		Rect2(Vector2(10.0 - wobble, 11.0), viewport_size - Vector2(18.0, 18.0)),
		Color(magenta, 0.38 * fade),
		false,
		2.0,
		true
	)
	var corners := [
		Vector2.ZERO,
		Vector2(viewport_size.x, 0.0),
		viewport_size,
		Vector2(0.0, viewport_size.y),
	]
	for index in range(corners.size()):
		var start := index * PI * 0.5 + animation_time * 0.75
		draw_arc(
			corners[index],
			72.0 + sin(animation_time * 3.0 + index) * 8.0,
			start,
			start + PI * 0.72,
			20,
			Color(cyan if index % 2 == 0 else magenta, 0.48 * fade),
			4.0,
			true
		)


func _draw_frozen_screen_fx(viewport_size: Vector2, fade: float) -> void:
	var ice := RaceVisuals.power_down_color("frozen")
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(ice, 0.04 * fade), true)
	_draw_edge_vignette(viewport_size, ice, 1.15 * fade)
	var corner_data := [
		[Vector2.ZERO, Vector2(1.0, 1.0)],
		[Vector2(viewport_size.x, 0.0), Vector2(-1.0, 1.0)],
		[viewport_size, Vector2(-1.0, -1.0)],
		[Vector2(0.0, viewport_size.y), Vector2(1.0, -1.0)],
	]
	for index in range(corner_data.size()):
		var corner: Vector2 = corner_data[index][0]
		var direction: Vector2 = corner_data[index][1]
		var bend := Vector2(direction.x * (88.0 + index * 8.0), direction.y * 42.0)
		var tip := corner + bend
		draw_line(corner, tip, Color(ice, 0.58 * fade), 3.0, true)
		draw_line(
			tip,
			tip + Vector2(direction.x * 34.0, direction.y * 45.0),
			Color(ice, 0.38 * fade),
			2.0,
			true
		)
		draw_line(
			tip,
			tip + Vector2(direction.x * 48.0, -direction.y * 8.0),
			Color(ice, 0.32 * fade),
			2.0,
			true
		)
	for flake in range(16):
		var side := flake % 4
		var along := fmod(flake * 79.0 + animation_time * 13.0, 620.0) / 620.0
		var inset := 18.0 + float((flake * 17) % 34)
		var center := Vector2.ZERO
		if side == 0:
			center = Vector2(along * viewport_size.x, inset)
		elif side == 1:
			center = Vector2(viewport_size.x - inset, along * viewport_size.y)
		elif side == 2:
			center = Vector2((1.0 - along) * viewport_size.x, viewport_size.y - inset)
		else:
			center = Vector2(inset, (1.0 - along) * viewport_size.y)
		var radius := 2.0 + float(flake % 3)
		draw_line(
			center - Vector2(radius, 0.0),
			center + Vector2(radius, 0.0),
			Color(ice, 0.45 * fade),
			1.4,
			true
		)
		draw_line(
			center - Vector2(0.0, radius),
			center + Vector2(0.0, radius),
			Color(ice, 0.45 * fade),
			1.4,
			true
		)


func _draw_background(viewport_size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("07101b"))
	for index in range(28):
		var x := fmod(31.0 + index * 97.0, viewport_size.x)
		var y := fmod(
			47.0 + index * 61.0 + sin(animation_time * 0.35 + index) * 12.0,
			viewport_size.y
		)
		var alpha := 0.08 + (sin(animation_time * 0.8 + index * 1.7) + 1.0) * 0.035
		draw_circle(Vector2(x, y), 1.2 + index % 3 * 0.45, Color(0.4, 0.75, 0.95, alpha))


func _draw_idle_mark(viewport_size: Vector2) -> void:
	var panel_bottom := (
		lobby_panel.position.y + lobby_panel.size.y
		if is_instance_valid(lobby_panel)
		else viewport_size.y * 0.5
	)
	var center := Vector2(
		viewport_size.x * 0.5,
		minf(viewport_size.y - 90.0, panel_bottom + 78.0)
	)
	var pulse := 1.0 + sin(animation_time * 2.8) * 0.09
	draw_circle(center, 24.0 * pulse, Color(0.18, 0.75, 0.95, 0.08))
	draw_circle(center, 13.0 * pulse, Color("83e8ff"))
	draw_arc(
		center,
		34.0 * pulse,
		animation_time,
		animation_time + PI * 1.45,
		48,
		Color("3f6f91"),
		3.0,
		true
	)


func _draw_goal(origin: Vector2, cell_size: float) -> void:
	var goal: Dictionary = game_state.maze.get("exit", {})
	var center := origin + GameState.grid_center(goal) * cell_size
	var pulse := 1.0 + sin(animation_time * 4.2) * 0.1
	draw_circle(center, cell_size * 0.46 * pulse, Color(1.0, 0.75, 0.25, 0.09))
	draw_circle(center, cell_size * 0.31 * pulse, Color("ffd166"))
	draw_circle(center, cell_size * 0.15, Color("6b4e13"))
	draw_arc(
		center,
		cell_size * 0.39,
		-animation_time * 1.8,
		-animation_time * 1.8 + PI * 1.25,
		28,
		Color(1.0, 0.93, 0.62, 0.8),
		clampf(cell_size * 0.045, 1.2, 2.5),
		true
	)


func _draw_power_ups(origin: Vector2, cell_size: float) -> void:
	for index in range(game_state.power_ups.size()):
		var power_up: Dictionary = game_state.power_ups[index]
		var center := origin + GameState.grid_center(power_up) * cell_size
		center.y += sin(animation_time * 3.2 + index) * cell_size * 0.07
		if not bool(power_up.get("active", true)):
			var elapsed := Time.get_ticks_msec() - game_state.power_ups_snapshot_local_ms
			var remaining := maxf(0.0, float(power_up.get("respawnMs", 0)) - elapsed)
			var progress := clampf(1.0 - remaining / 8000.0, 0.0, 1.0)
			var warning_alpha := 0.18
			if remaining < 2000.0:
				warning_alpha = 0.35 + (sin(animation_time * 9.0) + 1.0) * 0.18
			draw_arc(
				center,
				cell_size * 0.24,
				-PI * 0.5,
				-PI * 0.5 + TAU * progress,
				28,
				Color(0.49, 0.87, 1.0, warning_alpha),
				clampf(cell_size * 0.055, 1.2, 2.5),
				true
			)
			continue
		var pulse := 1.0 + sin(animation_time * 5.0 + index) * 0.1
		var radius := clampf(cell_size * 0.25 * pulse, 3.5, 12.0)
		draw_circle(center, radius + 7.0, Color(0.45, 0.75, 1.0, 0.1))
		var points := PackedVector2Array()
		for corner in range(4):
			var angle := animation_time * 1.8 + corner * PI * 0.5
			points.append(center + Vector2.from_angle(angle) * radius)
		draw_colored_polygon(points, Color("7bdfff"))
		for segment in range(4):
			var segment_color := Color(RaceVisuals.CELEBRATION_COLORS[segment])
			draw_arc(
				center,
				radius * 0.72,
				animation_time * 2.2 + segment * PI * 0.5,
				animation_time * 2.2 + segment * PI * 0.5 + PI * 0.36,
				8,
				segment_color,
				clampf(cell_size * 0.055, 1.2, 2.4),
				true
			)
		draw_circle(center, radius * 0.22, Color.WHITE)


func _draw_direction_hint(origin: Vector2, cell_size: float) -> void:
	if Time.get_ticks_msec() >= direction_hint_until_ms:
		return
	var player := game_state.get_local_player()
	if player.is_empty():
		return
	var id := str(player.get("id", ""))
	var position: Vector2 = visual_positions.get(
		id,
		GameState.grid_position(player)
	)
	var from := origin + (position + Vector2(0.5, 0.5)) * cell_size
	var goal: Dictionary = game_state.maze.get("exit", {})
	var to := origin + GameState.grid_center(goal) * cell_size
	var hint_alpha := 0.24 + (sin(animation_time * 7.0) + 1.0) * 0.09
	draw_circle(from, cell_size * 0.42, Color(1.0, 0.82, 0.36, hint_alpha * 0.35))
	for segment in range(14):
		if (segment + int(animation_time * 9.0)) % 2 == 1:
			continue
		var start := from.lerp(to, float(segment) / 14.0)
		var end := from.lerp(to, float(segment + 1) / 14.0)
		draw_line(
			start,
			end,
			Color(1.0, 0.82, 0.36, hint_alpha),
			clampf(cell_size * 0.09, 2.0, 4.0),
			true
		)


func _draw_trails(origin: Vector2, cell_size: float) -> void:
	for mark in trail_marks:
		var position: Vector2 = mark.get("position", Vector2.ZERO)
		var life_ratio := clampf(
			float(mark.get("life", 0.0)) / float(mark.get("max_life", 1.0)),
			0.0,
			1.0
		)
		var color: Color = mark.get("color", Color.WHITE)
		color.a = life_ratio * 0.44
		var center := origin + (position + Vector2(0.5, 0.5)) * cell_size
		draw_circle(center, cell_size * float(mark.get("radius", 0.21)) * life_ratio, color)


func _draw_movement_ripples(origin: Vector2, cell_size: float) -> void:
	for ripple in movement_ripples:
		var life_ratio := clampf(
			float(ripple.get("life", 0.0)) / float(ripple.get("max_life", 1.0)),
			0.0,
			1.0
		)
		var position: Vector2 = ripple.get("position", Vector2.ZERO)
		var center := origin + (position + Vector2(0.5, 0.5)) * cell_size
		var color: Color = ripple.get("color", Color.WHITE)
		color.a = life_ratio * 0.58
		var radius := cell_size * (0.16 + (1.0 - life_ratio) * 0.46)
		draw_arc(center, radius, 0.0, TAU, 32, color, float(ripple.get("width", 2.4)), true)


func _draw_pickup_particles(origin: Vector2, cell_size: float) -> void:
	for particle in pickup_particles:
		var life_ratio := clampf(
			float(particle.get("life", 0.0)) / float(particle.get("max_life", 1.0)),
			0.0,
			1.0
		)
		var target_id := str(particle.get("target_id", ""))
		var target: Vector2 = visual_positions.get(target_id, particle.get("start", Vector2.ZERO))
		var start: Vector2 = particle.get("start", Vector2.ZERO)
		var progress := 1.0 - life_ratio
		var position := start.lerp(target + Vector2(0.5, 0.5), progress * progress)
		position += Vector2(0, sin(progress * PI) * float(particle.get("curve", 0.0)))
		var center := origin + position * cell_size
		var color: Color = particle.get("color", Color.WHITE)
		color.a = life_ratio
		draw_circle(center, clampf(cell_size * 0.085 * life_ratio, 1.6, 4.8), color)
		draw_circle(center, clampf(cell_size * 0.032 * life_ratio, 1.0, 2.2), Color.WHITE)


func _draw_celebration(origin: Vector2, cell_size: float) -> void:
	for particle in celebration_particles:
		var position: Vector2 = particle.get("position", Vector2.ZERO)
		var life_ratio := clampf(
			float(particle.get("life", 0.0)) / float(particle.get("max_life", 1.0)),
			0.0,
			1.0
		)
		var color: Color = particle.get("color", Color.WHITE)
		color.a = life_ratio
		var center := origin + position * cell_size
		var radius := clampf(cell_size * 0.105 * life_ratio, 1.8, 6.4)
		draw_circle(center, radius, color)


func _draw_maze_walls(origin: Vector2, cell_size: float, width: int, height: int) -> void:
	var cells: Array = game_state.maze.get("cells", [])
	var wall_color := Color("c6d5e8")
	var wall_width := clampf(cell_size * 0.085, 2.0, 5.0)
	for y in range(height):
		for x in range(width):
			var index := y * width + x
			if index >= cells.size():
				continue
			var walls := int(cells[index])
			var p := origin + Vector2(x * cell_size, y * cell_size)
			if walls & MazeWall.Flag.TOP:
				draw_line(p, p + Vector2(cell_size, 0), wall_color, wall_width, true)
			if walls & MazeWall.Flag.LEFT:
				draw_line(p, p + Vector2(0, cell_size), wall_color, wall_width, true)
			if y == height - 1 and walls & MazeWall.Flag.BOTTOM:
				draw_line(
					p + Vector2(0, cell_size),
					p + Vector2(cell_size, cell_size),
					wall_color,
					wall_width,
					true
				)
			if x == width - 1 and walls & MazeWall.Flag.RIGHT:
				draw_line(
					p + Vector2(cell_size, 0),
					p + Vector2(cell_size, cell_size),
					wall_color,
					wall_width,
					true
				)


func _draw_players(origin: Vector2, cell_size: float) -> void:
	for player in game_state.players:
		var id := str(player.get("id", ""))
		var target := GameState.grid_position(player)
		var visual_position: Vector2 = visual_positions.get(id, target)
		var center := origin + (visual_position + Vector2(0.5, 0.5)) * cell_size
		var color := Color.from_string(str(player.get("color", "#ffffff")), Color.WHITE)
		var effects: Dictionary = player.get("effects", {})
		var radius := clampf(cell_size * 0.27, 4.0, 14.0)
		var movement := target - visual_position
		var body_angle := 0.0
		var body_scale := Vector2.ONE
		if movement.length_squared() > 0.0005:
			body_angle = movement.angle()
			var stretch := clampf(movement.length() * 0.7, 0.0, 0.24)
			body_scale = Vector2(1.0 + stretch, 1.0 - stretch * 0.66)
		else:
			var breathing := sin(animation_time * 5.0 + float(id.hash() % 11)) * 0.025
			body_scale = Vector2(1.0 + breathing, 1.0 - breathing)
		if id == game_state.player_id and wall_hit_timer > 0.0:
			var hit_strength := clampf(wall_hit_timer / 0.18, 0.0, 1.0)
			body_scale *= Vector2(
				lerpf(1.0, 0.76, hit_strength),
				lerpf(1.0, 1.2, hit_strength)
			)
		if (
			game_state.race_phase == "countdown"
			and Time.get_ticks_msec() < game_state.race_start_deadline_ms
		):
			var urgency := clampf(
				1.0 - float(game_state.race_start_deadline_ms - Time.get_ticks_msec()) / 3500.0,
				0.0,
				1.0
			)
			var phase := animation_time * lerpf(18.0, 42.0, urgency) + float(id.hash() % 17)
			center += Vector2(sin(phase), cos(phase * 1.37)) * urgency * 1.8
		var glow := color
		glow.a = 0.13 + (sin(animation_time * 5.0 + center.x) + 1.0) * 0.025
		draw_circle(center, radius + 8.0, glow)
		draw_set_transform(center, body_angle, body_scale)
		draw_circle(Vector2(0, 2), radius + 3.0, Color(0.01, 0.03, 0.06, 0.85))
		var avatar_url := str(player.get("avatarUrl", ""))
		var avatar_texture = avatar_loader.get_texture(avatar_url) if avatar_loader != null else null
		if avatar_texture is Texture2D:
			draw_circle(Vector2.ZERO, radius + 1.5, color)
			draw_texture_rect(
				avatar_texture,
				Rect2(Vector2(-radius, -radius), Vector2(radius * 2.0, radius * 2.0)),
				false
			)
		else:
			draw_circle(Vector2.ZERO, radius, color)
			draw_circle(
				Vector2(-radius * 0.28, -radius * 0.28),
				radius * 0.22,
				Color(1, 1, 1, 0.55)
			)
		if _effect_active(effects, "frozen"):
			draw_circle(Vector2.ZERO, radius * 0.82, Color(0.65, 0.94, 1.0, 0.55))
		draw_set_transform(Vector2.ZERO)
		if _effect_active(effects, "shield"):
			draw_arc(center, radius + 8.0, 0.0, TAU, 36, RaceVisuals.power_event_color("shield"), 3.0, true)
		if _effect_active(effects, "speed"):
			draw_arc(
				center,
				radius + 9.0,
				animation_time * 5.0,
				animation_time * 5.0 + PI * 1.2,
				24,
				RaceVisuals.power_event_color("speed"),
				3.0,
				true
			)
		if _effect_active(effects, "slow") or _effect_active(effects, "confused"):
			draw_arc(
				center,
				radius + 9.0,
				-animation_time * 2.5,
				-animation_time * 2.5 + PI * 1.4,
				24,
				RaceVisuals.power_event_color("slow_all"),
				3.0,
				true
			)
		if id == game_state.player_id:
			draw_circle(center, radius + 12.0, Color(1.0, 1.0, 1.0, 0.07))
			draw_arc(
				center,
				radius + 6.0,
				animation_time * 2.2,
				animation_time * 2.2 + PI * 1.55,
				28,
				Color.WHITE,
				3.0,
				true
			)


func _draw_wall_hit_fx(origin: Vector2, cell_size: float) -> void:
	if wall_hit_timer <= 0.0:
		return
	var player := game_state.get_local_player()
	if player.is_empty():
		return
	var id := str(player.get("id", ""))
	var target := GameState.grid_position(player)
	var visual_position: Vector2 = visual_positions.get(id, target)
	var center := origin + (visual_position + Vector2(0.5, 0.5)) * cell_size
	var strength := clampf(wall_hit_timer / 0.2, 0.0, 1.0)
	var radius := clampf(cell_size * 0.46, 7.0, 18.0)
	var hot := Color(1.0, 0.32, 0.42, strength * 0.82)
	draw_arc(center, radius + (1.0 - strength) * 18.0, 0.0, TAU, 32, hot, 3.0, true)
	for ray in range(8):
		var angle := animation_time * 9.0 + ray * TAU / 8.0
		var direction := Vector2.from_angle(angle)
		draw_line(
			center + direction * radius * 0.6,
			center + direction * (radius + 16.0 * strength),
			Color(1.0, 0.72, 0.48, strength * 0.62),
			2.5,
			true
		)


func _draw_countdown_fx(viewport_size: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if game_state.race_phase == "countdown" and now < game_state.race_start_deadline_ms:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.01, 0.02, 0.04, 0.34), true)
	var flash_remaining := game_state.go_flash_until_ms - now
	if game_state.race_phase == "countdown" and now >= game_state.race_start_deadline_ms:
		flash_remaining = maxi(flash_remaining, game_state.race_start_deadline_ms + 700 - now)
	if flash_remaining <= 0:
		return
	var progress := clampf(1.0 - flash_remaining / 700.0, 0.0, 1.0)
	draw_rect(
		Rect2(Vector2.ZERO, viewport_size),
		Color(1.0, 0.9, 0.55, (1.0 - progress) * 0.16),
		true
	)
	var center := viewport_size * 0.5
	draw_arc(
		center,
		lerpf(20.0, maxf(viewport_size.x, viewport_size.y) * 0.65, progress),
		0.0,
		TAU,
		72,
		Color(1.0, 0.86, 0.4, (1.0 - progress) * 0.75),
		lerpf(8.0, 2.0, progress),
		true
	)


func _local_effect_active(effect_name: String) -> bool:
	if game_state == null:
		return false
	return game_state.local_effect_active(effect_name, Time.get_ticks_msec())


func _local_effect_remaining(effect_name: String) -> float:
	if game_state == null:
		return 0.0
	return game_state.local_effect_remaining(effect_name, Time.get_ticks_msec())


func _effect_active(effects: Dictionary, effect_name: String) -> bool:
	if game_state == null:
		return false
	return game_state.effect_active(effects, effect_name, Time.get_ticks_msec())
