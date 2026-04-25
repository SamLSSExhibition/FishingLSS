extends Node2D

enum RodState {
	IDLE,
	CHARGING,
	CASTING,
	AT_DEPTH,
	REELING_UP,
	AT_TOP,
	REELING_TO_BOAT,
}

const START_X := 640.0
const TOP_Y := 120.0
const BOTTOM_Y := 1400.0
const CHARGE_SPEED := 1.15
const CAST_GRAVITY := 980.0
const MIN_CAST_X_SPEED := 300.0
const MAX_CAST_X_SPEED := 980.0
const MIN_CAST_UP_SPEED := 260.0
const MAX_CAST_UP_SPEED := 620.0
const REEL_SPEED := 520.0
const REEL_STEER_SPEED := 360.0
const CAMERA_SMOOTH := 4.8
const CAMERA_RETURN_SMOOTH := 1.9
const FISH_COUNT := 88
const FISH_MIN_SPEED := 55.0
const FISH_MAX_SPEED := 280.0
const FISH_SWIM_RANGE := 2000.0
const LONG_SWIM_RANGE := 2600.0
const FISH_COLLECT_RADIUS := 34.0
const FISH_RESPAWN_MIN := 1.2
const FISH_RESPAWN_MAX := 2.8
const FISH_MIN_DEPTH_OFFSET := 90.0
const FISH_MAX_DEPTH_OFFSET := 1200.0
const BOAT_SCALE_FACTOR := 0.25
const FISH_MIN_SCALE_FACTOR := 0.25
const FISH_MAX_SCALE_FACTOR := 1.0
const BOAT_CAMERA_ZOOM := Vector2(0.78, 0.78)
const PLAY_CAMERA_ZOOM := Vector2(1.0, 1.0)

@onready var backdrop: Node2D = $Backdrop
@onready var fish_layer: Node2D = $FishLayer
@onready var boat_sprite: Sprite2D = $BoatSprite
@onready var rod: Node2D = $Rod
@onready var rod_sprite: Sprite2D = $Rod/RodSprite
@onready var lure_sprite: Sprite2D = $Rod/LureSprite
@onready var cast_line: Line2D = $CastLine
@onready var camera_2d: Camera2D = $Camera2D
@onready var meter_frame: ColorRect = $UI/MeterFrame
@onready var meter_fill: ColorRect = $UI/MeterFrame/MeterFill
@onready var state_label: Label = $UI/StateLabel
@onready var catch_label: Label = $UI/CatchLabel
@onready var money_label: Label = $UI/MoneyLabel
@onready var menu_layer: Control = $UI/MenuLayer
@onready var menu_title_label: Label = $UI/MenuLayer/MenuTitleLabel
@onready var menu_start_label: Label = $UI/MenuLayer/MenuStartLabel
@onready var menu_reason_label: Label = $UI/MenuLayer/MenuReasonLabel
@onready var menu_controls_label: Label = $UI/MenuLayer/MenuControlsLabel
@onready var action_prompt_label: Label = $UI/ActionPromptLabel
@onready var action_reason_label: Label = $UI/ActionReasonLabel
@onready var arrow_hint_label: Label = $UI/ArrowHintLabel
@onready var mobile_layer: Control = $UI/MobileLayer
@onready var mobile_hint_label: Label = $UI/MobileLayer/MobileHintLabel
@onready var mobile_left_button: Button = $UI/MobileLayer/MobileLeftButton
@onready var mobile_charge_button: Button = $UI/MobileLayer/MobileChargeButton
@onready var mobile_right_button: Button = $UI/MobileLayer/MobileRightButton

var state: RodState = RodState.IDLE
var charge_value := 0.0
var charge_direction := 1.0
var cast_velocity := Vector2.ZERO
var boat_surface_y := 84.0
var rod_spawn_x := START_X
var sky_sprite: Sprite2D
var water_sprite: Sprite2D
var sky_height := 2600.0
var water_height := 2600.0
var fish_data: Array[Dictionary] = []
var fish_caught := 0
var total_money := 0
var game_started := false
var prompt_tween: Tween
var fish_texture_map: Dictionary = {}
var boat_texture: Texture2D
var rod_home_position := Vector2.ZERO
var mobile_charge_touch_id := -1
var mobile_left_touch_id := -1
var mobile_right_touch_id := -1
var mobile_steer_direction := 0.0


func _ready() -> void:
	randomize()
	_load_game_assets()
	_create_placeholder_world()
	_update_rod_home_position()
	rod_spawn_x = boat_sprite.position.x
	rod.position = rod_home_position
	camera_2d.position = Vector2(rod_spawn_x, 360.0)
	boat_surface_y = boat_sprite.global_position.y
	_spawn_fish_school()
	_update_catch_label()
	_update_money_label()
	_set_game_started(false)
	menu_start_label.add_theme_font_size_override("font_size", 48)
	action_prompt_label.add_theme_font_size_override("font_size", 60)
	action_reason_label.add_theme_font_size_override("font_size", 28)
	arrow_hint_label.add_theme_font_size_override("font_size", 24)
	menu_title_label.add_theme_font_size_override("font_size", 42)
	menu_reason_label.add_theme_font_size_override("font_size", 28)
	menu_controls_label.add_theme_font_size_override("font_size", 24)
	_set_mobile_controls_visible(DisplayServer.is_touchscreen_available())
	_update_backdrop_positions()
	_update_meter()
	_update_status_text()
	_update_line()


func _process(delta: float) -> void:
	rod_spawn_x = boat_sprite.position.x
	_update_rod_home_position()
	_update_control_prompts()
	_update_menu_prompt_animation()
	_update_overlay_layout()

	match state:
		RodState.CHARGING:
			charge_value += charge_direction * CHARGE_SPEED * delta
			if charge_value >= 1.0:
				charge_value = 1.0
				charge_direction = -1.0
			elif charge_value <= 0.0:
				charge_value = 0.0
				charge_direction = 1.0
		RodState.CASTING:
			cast_velocity.y += CAST_GRAVITY * delta
			rod.position += cast_velocity * delta
			if rod.position.y >= BOTTOM_Y:
				rod.position.y = BOTTOM_Y
				cast_velocity = Vector2.ZERO
				state = RodState.AT_DEPTH
				_update_status_text()
				_update_control_prompts()
		RodState.REELING_UP:
			var horizontal_input := clampf(Input.get_axis("ui_left", "ui_right") + mobile_steer_direction, -1.0, 1.0)
			rod.position.x += horizontal_input * REEL_STEER_SPEED * delta
			rod.position.y = move_toward(rod.position.y, TOP_Y, REEL_SPEED * delta)
			if is_equal_approx(rod.position.y, TOP_Y):
				rod.position.y = TOP_Y
				state = RodState.AT_TOP
				_update_status_text()
				_update_control_prompts()
		RodState.REELING_TO_BOAT:
			rod.position = rod.position.move_toward(rod_home_position, REEL_SPEED * delta)
			if rod.position.distance_to(rod_home_position) <= 1.0:
				state = RodState.IDLE
				rod.position = rod_home_position
				charge_value = 0.0
				charge_direction = 1.0
				_update_status_text()
				_update_control_prompts()

	if state == RodState.IDLE:
		rod.position = rod.position.move_toward(rod_home_position, 420.0 * delta)

	var camera_target_x := rod_spawn_x
	var camera_target_y := 360.0
	if state != RodState.IDLE and state != RodState.CHARGING:
		camera_target_x = rod.position.x
		camera_target_y = rod.position.y + 220.0
		if state == RodState.CASTING or state == RodState.AT_DEPTH:
			var depth_t := clampf((rod.position.y - TOP_Y) / (BOTTOM_Y - TOP_Y), 0.0, 1.0)
			var camera_offset_y := lerpf(220.0, -120.0, depth_t)
			camera_target_y = rod.position.y + camera_offset_y
		elif state == RodState.REELING_UP or state == RodState.AT_TOP:
			camera_target_y = rod.position.y - 120.0
		elif state == RodState.REELING_TO_BOAT:
			camera_target_x = rod_spawn_x
			camera_target_y = 360.0

	var camera_smooth := CAMERA_SMOOTH
	if state == RodState.REELING_TO_BOAT:
		camera_smooth = CAMERA_RETURN_SMOOTH
	var camera_zoom_target := PLAY_CAMERA_ZOOM
	if state == RodState.IDLE or state == RodState.CHARGING or state == RodState.REELING_TO_BOAT:
		camera_zoom_target = BOAT_CAMERA_ZOOM

	camera_2d.position.x = lerpf(camera_2d.position.x, camera_target_x, camera_smooth * delta)
	camera_2d.position.y = lerpf(camera_2d.position.y, camera_target_y, camera_smooth * delta)
	camera_2d.zoom = camera_2d.zoom.lerp(camera_zoom_target, camera_smooth * delta)
	_update_fish(delta)
	if state == RodState.REELING_UP or state == RodState.REELING_TO_BOAT:
		_check_fish_collection()
	_update_backdrop_positions()
	_update_overlay_layout()

	_update_meter()
	_update_line()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_SPACE:
		if event.pressed and not event.echo:
			if not game_started:
				_set_game_started(true)
			elif state == RodState.IDLE:
				_begin_charge()
			elif state == RodState.AT_DEPTH:
				_begin_reel_up()
			elif state == RodState.AT_TOP:
				_begin_reel_to_boat()
		elif not event.pressed and state == RodState.CHARGING:
			_release_cast()

	if event is InputEventScreenTouch:
		if event.pressed:
			if not game_started:
				_set_game_started(true)
				return
			if state == RodState.IDLE and _touch_in_button(event.position, mobile_charge_button):
				mobile_charge_touch_id = event.index
				_begin_charge()
				return
			if state == RodState.REELING_UP and _touch_in_button(event.position, mobile_left_button):
				mobile_left_touch_id = event.index
				_update_mobile_steer_direction()
				return
			if state == RodState.REELING_UP and _touch_in_button(event.position, mobile_right_button):
				mobile_right_touch_id = event.index
				_update_mobile_steer_direction()
				return
			if state == RodState.AT_DEPTH:
				_begin_reel_up()
				return
			if state == RodState.AT_TOP:
				_begin_reel_to_boat()
				return
		else:
			if event.index == mobile_charge_touch_id:
				mobile_charge_touch_id = -1
				if state == RodState.CHARGING:
					_release_cast()
			if event.index == mobile_left_touch_id:
				mobile_left_touch_id = -1
				_update_mobile_steer_direction()
			if event.index == mobile_right_touch_id:
				mobile_right_touch_id = -1
				_update_mobile_steer_direction()


func _update_meter() -> void:
	var frame_size := meter_frame.size
	var fill_height := maxf(frame_size.y - 6.0, 1.0)
	meter_fill.offset_right = 3.0 + (frame_size.x - 6.0) * charge_value
	meter_fill.offset_bottom = 3.0 + fill_height


func _update_line() -> void:
	cast_line.points = PackedVector2Array([
		rod_home_position,
		rod.position + Vector2(0.0, 44.0),
	])


func _update_status_text() -> void:
	match state:
		RodState.IDLE:
			state_label.text = "State: Idle (hold SPACE to start charging)"
		RodState.CHARGING:
			state_label.text = "State: Charging cast power"
		RodState.CASTING:
			state_label.text = "State: Casting in an arc"
		RodState.AT_DEPTH:
			state_label.text = "State: Lure at bottom (press SPACE to reel up)"
		RodState.REELING_UP:
			state_label.text = "State: Reeling up (use LEFT/RIGHT arrows)"
		RodState.AT_TOP:
			state_label.text = "State: At top (press SPACE to reel to boat)"
		RodState.REELING_TO_BOAT:
			state_label.text = "State: Reeling back to boat"


func _set_game_started(started: bool) -> void:
	game_started = started
	menu_layer.visible = not started
	menu_layer.mouse_filter = Control.MOUSE_FILTER_STOP if not started else Control.MOUSE_FILTER_IGNORE
	_update_control_prompts()
	_update_menu_prompt_animation()


func _update_control_prompts() -> void:
	if not game_started:
		action_prompt_label.text = "SPACE"
		action_reason_label.text = "Hold to charge. Release to cast."
		arrow_hint_label.text = ""
		_update_mobile_controls_ui()
		return

	match state:
		RodState.IDLE:
			action_prompt_label.text = "SPACE"
			action_reason_label.text = "Hold to charge your cast power."
			arrow_hint_label.text = ""
		RodState.CHARGING:
			action_prompt_label.text = "SPACE"
			action_reason_label.text = "Release to cast farther."
			arrow_hint_label.text = ""
		RodState.AT_DEPTH:
			action_prompt_label.text = "SPACE"
			action_reason_label.text = "Press to reel the lure straight up."
			arrow_hint_label.text = ""
		RodState.REELING_UP:
			action_prompt_label.text = "SPACE"
			action_reason_label.text = "Keep reeling up to reach the top."
			arrow_hint_label.text = "←   →  Move"
		RodState.AT_TOP:
			action_prompt_label.text = "SPACE"
			action_reason_label.text = "Press to reel back to the boat."
			arrow_hint_label.text = ""
		RodState.REELING_TO_BOAT:
			action_prompt_label.text = "SPACE"
			action_reason_label.text = "The camera returns to the boat."
			arrow_hint_label.text = ""
		_:
			action_prompt_label.text = ""
			action_reason_label.text = ""
			arrow_hint_label.text = ""

	_update_mobile_controls_ui()


func _update_menu_prompt_animation() -> void:
	if prompt_tween != null:
		prompt_tween.kill()
		prompt_tween = null
	if game_started:
		return
	prompt_tween = create_tween()
	prompt_tween.set_loops()
	prompt_tween.tween_property(menu_start_label, "scale", Vector2(1.08, 1.08), 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	prompt_tween.tween_property(menu_start_label, "scale", Vector2(1.0, 1.0), 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _begin_charge() -> void:
	if state != RodState.IDLE:
		return
	state = RodState.CHARGING
	charge_value = 0.0
	charge_direction = 1.0
	_update_status_text()
	_update_control_prompts()


func _release_cast() -> void:
	var cast_strength := maxf(charge_value, 0.08)
	cast_velocity.x = lerpf(MIN_CAST_X_SPEED, MAX_CAST_X_SPEED, cast_strength)
	cast_velocity.y = -lerpf(MIN_CAST_UP_SPEED, MAX_CAST_UP_SPEED, cast_strength)
	state = RodState.CASTING
	_update_status_text()
	_update_control_prompts()


func _begin_reel_up() -> void:
	state = RodState.REELING_UP
	mobile_steer_direction = 0.0
	_update_status_text()
	_update_control_prompts()


func _begin_reel_to_boat() -> void:
	state = RodState.REELING_TO_BOAT
	_update_status_text()
	_update_control_prompts()


func _touch_in_button(position: Vector2, button: Button) -> bool:
	return button.visible and button.get_global_rect().has_point(position)


func _update_mobile_steer_direction() -> void:
	mobile_steer_direction = 0.0
	if mobile_left_touch_id != -1:
		mobile_steer_direction -= 1.0
	if mobile_right_touch_id != -1:
		mobile_steer_direction += 1.0


func _update_mobile_controls_ui() -> void:
	if not mobile_layer.visible:
		return

	mobile_hint_label.text = "HOLD TO CHARGE | TAP SCREEN TO REEL | HOLD ARROWS WHILE REELING"
	mobile_charge_button.visible = game_started and state == RodState.IDLE
	mobile_left_button.visible = game_started and state == RodState.REELING_UP
	mobile_right_button.visible = game_started and state == RodState.REELING_UP


func _set_mobile_controls_visible(visible: bool) -> void:
	mobile_layer.visible = visible
	if visible:
		_update_mobile_controls_ui()


func _spawn_fish_school() -> void:
	fish_data.clear()
	for i in range(FISH_COUNT):
		var fish_profile := _build_fish_profile()
		var fish := Sprite2D.new()
		fish.texture = fish_profile["texture"]
		if fish.texture == null:
			fish.texture = _make_color_texture(Vector2i(30, 14), fish_profile["color"])
		fish.global_position = Vector2(
			_random_fish_x(rod_spawn_x, fish_profile["spawn_min_range"], fish_profile["spawn_max_range"]),
			_random_fish_y()
		)
		fish_layer.add_child(fish)

		var direction := 1.0
		if randf() < 0.5:
			direction = -1.0
		fish.scale = Vector2(fish_profile["base_scale"] * -direction, fish_profile["base_scale"])

		fish_data.append({
			"sprite": fish,
			"speed": randf_range(FISH_MIN_SPEED, FISH_MAX_SPEED),
			"direction": direction,
			"base_scale": fish_profile["base_scale"],
			"texture": fish_profile["texture"],
			"color_key": fish_profile["color_key"],
			"color": fish_profile["color"],
			"value": fish_profile["value"],
			"spawn_min_range": fish_profile["spawn_min_range"],
			"spawn_max_range": fish_profile["spawn_max_range"],
			"swim_range": fish_profile["swim_range"],
			"caught": false,
			"respawn_timer": 0.0,
		})


func _update_fish(delta: float) -> void:
	var camera_x := camera_2d.get_screen_center_position().x
	for i in range(fish_data.size()):
		var fish := fish_data[i]
		var sprite: Sprite2D = fish["sprite"]

		if fish["caught"]:
			fish["respawn_timer"] -= delta
			if fish["respawn_timer"] <= 0.0:
				fish["caught"] = false
				sprite.visible = true
				var fish_profile := _build_fish_profile()
				fish["speed"] = randf_range(FISH_MIN_SPEED, FISH_MAX_SPEED)
				fish["base_scale"] = fish_profile["base_scale"]
				fish["texture"] = fish_profile["texture"]
				fish["color_key"] = fish_profile["color_key"]
				fish["color"] = fish_profile["color"]
				fish["value"] = fish_profile["value"]
				fish["spawn_min_range"] = fish_profile["spawn_min_range"]
				fish["spawn_max_range"] = fish_profile["spawn_max_range"]
				fish["swim_range"] = fish_profile["swim_range"]
				sprite.texture = fish["texture"]
				if sprite.texture == null:
					sprite.texture = _make_color_texture(Vector2i(30, 14), fish["color"])
				fish["direction"] = -1.0 if randf() < 0.5 else 1.0
				sprite.scale = Vector2(fish["base_scale"] * -fish["direction"], fish["base_scale"])
				sprite.global_position = Vector2(
					_random_fish_x(camera_x, fish["spawn_min_range"], fish["spawn_max_range"]),
					_random_fish_y()
				)
			fish_data[i] = fish
			continue

		sprite.global_position.x += fish["speed"] * fish["direction"] * delta
		if sprite.global_position.x > camera_x + fish["swim_range"]:
			sprite.global_position.x = camera_x - fish["swim_range"]
			sprite.global_position.y = _random_fish_y()
		elif sprite.global_position.x < camera_x - fish["swim_range"]:
			sprite.global_position.x = camera_x + fish["swim_range"]
			sprite.global_position.y = _random_fish_y()

		fish_data[i] = fish


func _check_fish_collection() -> void:
	var lure_world := lure_sprite.global_position
	for i in range(fish_data.size()):
		var fish := fish_data[i]
		if fish["caught"]:
			continue

		var sprite: Sprite2D = fish["sprite"]
		if lure_world.distance_to(sprite.global_position) <= FISH_COLLECT_RADIUS:
			fish["caught"] = true
			fish["respawn_timer"] = randf_range(FISH_RESPAWN_MIN, FISH_RESPAWN_MAX)
			_spawn_catch_particles(sprite.global_position, fish["color"])
			_spawn_money_bounce(fish["value"])
			sprite.visible = false
			fish_caught += 1
			total_money += fish["value"]
			_update_catch_label()
			_update_money_label()
			fish_data[i] = fish


func _update_catch_label() -> void:
	catch_label.text = "Fish Caught: %d" % fish_caught


func _update_money_label() -> void:
	money_label.text = "Money: $%d" % total_money


func _update_rod_home_position() -> void:
	if boat_texture == null:
		rod_home_position = Vector2(rod_spawn_x, TOP_Y)
		return

	var boat_size := Vector2(boat_texture.get_size()) * boat_sprite.scale
	rod_home_position = boat_sprite.global_position + Vector2(-boat_size.x * 0.44, -boat_size.y * 0.18)
	rod_spawn_x = rod_home_position.x


func _spawn_money_bounce(amount: int) -> void:
	var money_popup := Label.new()
	money_popup.text = "+$%d" % amount
	money_popup.add_theme_font_size_override("font_size", 26)
	var rod_screen := _get_rod_screen_position()
	money_popup.position = rod_screen + Vector2(-18.0, -48.0)
	money_popup.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2, 1.0))
	money_popup.scale = Vector2(1.0, 1.0)
	$UI.add_child(money_popup)

	var tween := create_tween()
	tween.tween_property(money_popup, "position", money_popup.position + Vector2(0.0, -96.0), 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(money_popup, "scale", Vector2(1.45, 1.45), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(money_popup, "scale", Vector2(1.0, 1.0), 0.18)
	tween.tween_property(money_popup, "modulate:a", 0.0, 0.24)
	tween.finished.connect(money_popup.queue_free)


func _get_rod_screen_position() -> Vector2:
	return get_viewport().get_canvas_transform() * rod.global_position


func _update_overlay_layout() -> void:
	if not game_started:
		menu_title_label.size = menu_title_label.get_combined_minimum_size()
		menu_start_label.size = menu_start_label.get_combined_minimum_size()
		menu_reason_label.size = menu_reason_label.get_combined_minimum_size()
		menu_controls_label.size = menu_controls_label.get_combined_minimum_size()
		var viewport_size := get_viewport().get_visible_rect().size
		var menu_left := viewport_size.x * 0.12
		var menu_top := viewport_size.y * 0.18

		menu_title_label.position = Vector2(menu_left, menu_top)
		menu_start_label.position = Vector2(menu_left, menu_top + 120.0)
		menu_reason_label.position = Vector2(menu_left, menu_top + 220.0)
		menu_controls_label.position = Vector2(menu_left, menu_top + 340.0)

	action_prompt_label.size = action_prompt_label.get_combined_minimum_size()
	action_reason_label.size = action_reason_label.get_combined_minimum_size()
	arrow_hint_label.size = arrow_hint_label.get_combined_minimum_size()
	var rod_screen := _get_rod_screen_position()

	action_prompt_label.position = rod_screen + Vector2(-action_prompt_label.size.x * 0.5, -210.0)
	action_reason_label.position = rod_screen + Vector2(-action_reason_label.size.x * 0.5, -120.0)
	arrow_hint_label.position = rod_screen + Vector2(-arrow_hint_label.size.x * 0.5, -40.0)


func _build_fish_profile() -> Dictionary:
	var variants: PackedStringArray = PackedStringArray(["A", "B", "C"])
	var colors: PackedStringArray = PackedStringArray(["blue", "green", "orange"])
	var variant: String = variants[randi() % variants.size()]
	var color_key: String = colors[randi() % colors.size()]
	var texture_key := "%s_%s" % [variant, color_key]
	var color := _color_for_key(color_key)
	var value := _value_for_color(color_key)
	var range := _range_for_color(color_key)

	return {
		"texture": fish_texture_map.get(texture_key),
		"color_key": color_key,
		"color": color,
		"value": value,
		"base_scale": 0.22 * randf_range(FISH_MIN_SCALE_FACTOR, FISH_MAX_SCALE_FACTOR),
		"spawn_min_range": range["spawn_min_range"],
		"spawn_max_range": range["spawn_max_range"],
		"swim_range": range["swim_range"],
	}


func _value_for_color(color_key: String) -> int:
	match color_key:
		"blue":
			return 1
		"green":
			return 2
		"orange":
			return 3
		_:
			return 1


func _color_for_key(color_key: String) -> Color:
	match color_key:
		"blue":
			return Color(0.24, 0.76, 1.0, 1.0)
		"green":
			return Color(0.2, 0.9, 0.45, 1.0)
		"orange":
			return Color(0.98, 0.58, 0.18, 1.0)
		_:
			return Color(0.95, 0.62, 0.24, 1.0)


func _range_for_color(color_key: String) -> Dictionary:
	match color_key:
		"blue":
			return {
				"spawn_min_range": 120.0,
				"spawn_max_range": FISH_SWIM_RANGE * 0.7,
				"swim_range": FISH_SWIM_RANGE,
			}
		"green":
			return {
				"spawn_min_range": 520.0,
				"spawn_max_range": FISH_SWIM_RANGE,
				"swim_range": FISH_SWIM_RANGE,
			}
		"orange":
			return {
				"spawn_min_range": 960.0,
				"spawn_max_range": LONG_SWIM_RANGE,
				"swim_range": LONG_SWIM_RANGE,
			}
		_:
			return {
				"spawn_min_range": 120.0,
				"spawn_max_range": FISH_SWIM_RANGE,
				"swim_range": FISH_SWIM_RANGE,
			}


func _load_game_assets() -> void:
	boat_texture = load("res://Assets/Ship PNG.png")
	fish_texture_map = {
		"A_blue": load("res://Assets/Fish A blue PNG.png"),
		"A_green": load("res://Assets/Fish A green PNG.png"),
		"A_orange": load("res://Assets/Fish A orange PNG.png"),
		"B_blue": load("res://Assets/Fish B blue PNG.png"),
		"B_green": load("res://Assets/Fish B green PNG.png"),
		"B_orange": load("res://Assets/Fish B orange PNG.png"),
		"C_blue": load("res://Assets/Fish C blue PNG.png"),
		"C_green": load("res://Assets/Fish C green PNG.png"),
		"C_orange": load("res://Assets/Fish C orange PNG.png"),
	}


func _random_fish_x(center_x: float, min_range: float, max_range: float) -> float:
	var direction := -1.0 if randf() < 0.5 else 1.0
	return center_x + direction * randf_range(min_range, max_range)


func _spawn_catch_particles(at_position: Vector2, particle_color: Color) -> void:
	for i in range(14):
		var bit := Sprite2D.new()
		var c := particle_color
		c.r = minf(c.r + 0.2, 1.0)
		c.g = minf(c.g + 0.2, 1.0)
		c.b = minf(c.b + 0.2, 1.0)
		bit.texture = _make_color_texture(Vector2i(4, 4), c)
		bit.global_position = at_position
		fish_layer.add_child(bit)

		var angle := randf_range(0.0, TAU)
		var distance := randf_range(18.0, 54.0)
		var target_position := at_position + Vector2(cos(angle), sin(angle)) * distance

		var tween := create_tween()
		tween.tween_property(bit, "global_position", target_position, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(bit, "modulate:a", 0.0, 0.42)
		tween.finished.connect(bit.queue_free)


func _random_fish_y() -> float:
	return boat_surface_y + randf_range(FISH_MIN_DEPTH_OFFSET, FISH_MAX_DEPTH_OFFSET)


func _create_placeholder_world() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var backdrop_width := int(maxf(viewport_size.x + 900.0, 2400.0))
	var backdrop_height := int(maxf(viewport_size.y + 1400.0, 2600.0))
	sky_height = float(backdrop_height)
	water_height = float(backdrop_height)

	sky_sprite = Sprite2D.new()
	sky_sprite.texture = _make_color_texture(Vector2i(backdrop_width, backdrop_height), Color(0.58, 0.8, 0.96, 1.0))
	backdrop.add_child(sky_sprite)

	water_sprite = Sprite2D.new()
	water_sprite.texture = _make_color_texture(Vector2i(backdrop_width, backdrop_height), Color(0.12, 0.38, 0.72, 0.96))
	backdrop.add_child(water_sprite)

	if boat_texture != null:
		boat_sprite.texture = boat_texture
	else:
		boat_sprite.texture = _make_color_texture(Vector2i(190, 46), Color(0.8, 0.44, 0.2, 1.0))
	boat_sprite.scale = Vector2.ONE * BOAT_SCALE_FACTOR
	rod_sprite.texture = _make_color_texture(Vector2i(8, 62), Color(0.24, 0.14, 0.08, 1.0))
	lure_sprite.texture = _make_color_texture(Vector2i(24, 24), Color(1.0, 0.3, 0.2, 1.0))


func _update_backdrop_positions() -> void:
	if sky_sprite == null or water_sprite == null:
		return
	var camera_center := camera_2d.get_screen_center_position()
	sky_sprite.global_position = Vector2(camera_center.x, boat_surface_y - sky_height * 0.5)
	water_sprite.global_position = Vector2(camera_center.x, boat_surface_y + water_height * 0.5)


func _make_color_texture(size: Vector2i, color: Color) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
