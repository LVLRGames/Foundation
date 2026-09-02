class_name FoundationRoadLane
extends RefCounted

## Stable renderer-independent lane metadata nested in a road cross section.

const FORMAT_VERSION := 1
const DIRECTION_FORWARD: StringName = &"forward"
const DIRECTION_REVERSE: StringName = &"reverse"
const ROLE_TRAVEL: StringName = &"travel"

var lane_id: StringName
var lane_index := 0
var direction: StringName = DIRECTION_FORWARD
var lane_role: StringName = ROLE_TRAVEL
var width := 3.2
var speed_limit_kph := 40.0
var abstract_capacity_per_hour := 900
var centerline := PackedVector3Array()
var allowed_movement_modes := PackedStringArray(["motor_vehicle"])
var turn_permissions := PackedStringArray(["left", "through", "right"])


func _init(
	p_lane_id: StringName = &"",
	p_lane_index := 0,
	p_direction: StringName = DIRECTION_FORWARD
) -> void:
	lane_id = p_lane_id
	lane_index = p_lane_index
	direction = p_direction


func to_dict() -> Dictionary:
	var points: Array[Dictionary] = []
	for point in centerline:
		points.append({"x": point.x, "y": point.y, "z": point.z})
	return {
		"format_version": FORMAT_VERSION,
		"lane_id": String(lane_id),
		"lane_index": lane_index,
		"direction": String(direction),
		"lane_role": String(lane_role),
		"width": width,
		"speed_limit_kph": speed_limit_kph,
		"abstract_capacity_per_hour": abstract_capacity_per_hour,
		"centerline": points,
		"allowed_movement_modes": Array(allowed_movement_modes),
		"turn_permissions": Array(turn_permissions),
	}


static func from_dict(data: Dictionary) -> FoundationRoadLane:
	var lane := FoundationRoadLane.new(
		StringName(data.get("lane_id", "")),
		int(data.get("lane_index", 0)),
		StringName(data.get("direction", String(DIRECTION_FORWARD)))
	)
	lane.lane_role = StringName(data.get("lane_role", String(ROLE_TRAVEL)))
	lane.width = float(data.get("width", 3.2))
	lane.speed_limit_kph = float(data.get("speed_limit_kph", 40.0))
	lane.abstract_capacity_per_hour = int(data.get("abstract_capacity_per_hour", 900))
	for point_data: Dictionary in data.get("centerline", []):
		lane.centerline.append(Vector3(
			float(point_data.get("x", 0.0)),
			float(point_data.get("y", 0.0)),
			float(point_data.get("z", 0.0))
		))
	lane.allowed_movement_modes = PackedStringArray(data.get("allowed_movement_modes", ["motor_vehicle"]))
	lane.turn_permissions = PackedStringArray(data.get("turn_permissions", ["left", "through", "right"]))
	return lane


static func less(a: FoundationRoadLane, b: FoundationRoadLane) -> bool:
	if a.direction != b.direction:
		return String(a.direction) < String(b.direction)
	if a.lane_index != b.lane_index:
		return a.lane_index < b.lane_index
	return String(a.lane_id) < String(b.lane_id)
