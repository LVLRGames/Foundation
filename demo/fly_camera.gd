extends Camera3D

## Lightweight demo-only fly camera. Core Foundation data remains renderer-independent.

@export_range(1.0, 1000.0, 1.0) var move_speed := 90.0
@export_range(1.0, 10.0, 0.25) var boost_multiplier := 4.0
@export_range(0.0001, 0.02, 0.0001) var look_sensitivity := 0.0025
@export_range(0.1, 1.55, 0.01) var pitch_limit := 1.5
@export_range(1.0, 100.0, 1.0) var speed_step := 10.0
@export_range(1.0, 1000.0, 1.0) var minimum_speed := 10.0
@export_range(1.0, 2000.0, 1.0) var maximum_speed := 600.0

var _look_active := false


func _process(delta: float) -> void:
	if not current or _text_input_has_focus():
		return
	var input_axes := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var direction := movement_direction(input_axes)
	if direction == Vector3.ZERO:
		return
	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= boost_multiplier
	global_position += direction * speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			set_look_active(mouse_button.pressed)
			get_viewport().set_input_as_handled()
		elif _look_active and mouse_button.pressed:
			if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
				move_speed = clampf(move_speed + speed_step, minimum_speed, maximum_speed)
				get_viewport().set_input_as_handled()
			elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				move_speed = clampf(move_speed - speed_step, minimum_speed, maximum_speed)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _look_active:
		apply_look_delta((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			set_look_active(false)
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _look_active:
		set_look_active(false)


func movement_direction(input_axes: Vector3) -> Vector3:
	if input_axes == Vector3.ZERO:
		return Vector3.ZERO
	var camera_basis := global_transform.basis.orthonormalized()
	var direction := (
		camera_basis.x * input_axes.x
		+ Vector3.UP * input_axes.y
		+ camera_basis.z * input_axes.z
	)
	return direction.normalized()


func apply_look_delta(mouse_delta: Vector2) -> void:
	rotation.y -= mouse_delta.x * look_sensitivity
	rotation.x = clampf(rotation.x - mouse_delta.y * look_sensitivity, -pitch_limit, pitch_limit)
	rotation.z = 0.0


func set_look_active(enabled: bool) -> void:
	_look_active = enabled
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE


func is_look_active() -> bool:
	return _look_active


func _text_input_has_focus() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
