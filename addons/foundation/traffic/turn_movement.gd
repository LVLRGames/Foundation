class_name FoundationTurnMovement
extends RefCounted

## Abstract intersection movement. It is not a driveable path or navigation edge.

const FORMAT_VERSION := 1
const TURN_LEFT: StringName = &"left"
const TURN_THROUGH: StringName = &"through"
const TURN_RIGHT: StringName = &"right"

var movement_id: StringName
var from_approach_id: StringName
var to_approach_id: StringName
var from_lane_id: StringName
var to_lane_id: StringName
var turn_type: StringName = TURN_THROUGH
var permitted := true
var priority_rank := 0
var conflict_group_id: StringName
var path_hint := PackedVector3Array()


func to_dict() -> Dictionary:
	var points: Array[Dictionary] = []
	for point in path_hint:
		points.append({"x": point.x, "y": point.y, "z": point.z})
	return {
		"format_version": FORMAT_VERSION,
		"movement_id": String(movement_id),
		"from_approach_id": String(from_approach_id),
		"to_approach_id": String(to_approach_id),
		"from_lane_id": String(from_lane_id),
		"to_lane_id": String(to_lane_id),
		"turn_type": String(turn_type),
		"permitted": permitted,
		"priority_rank": priority_rank,
		"conflict_group_id": String(conflict_group_id),
		"path_hint": points,
	}


static func from_dict(data: Dictionary) -> FoundationTurnMovement:
	var movement := FoundationTurnMovement.new()
	movement.movement_id = StringName(data.get("movement_id", ""))
	movement.from_approach_id = StringName(data.get("from_approach_id", ""))
	movement.to_approach_id = StringName(data.get("to_approach_id", ""))
	movement.from_lane_id = StringName(data.get("from_lane_id", ""))
	movement.to_lane_id = StringName(data.get("to_lane_id", ""))
	movement.turn_type = StringName(data.get("turn_type", String(TURN_THROUGH)))
	movement.permitted = bool(data.get("permitted", true))
	movement.priority_rank = int(data.get("priority_rank", 0))
	movement.conflict_group_id = StringName(data.get("conflict_group_id", ""))
	for point_data: Dictionary in data.get("path_hint", []):
		movement.path_hint.append(Vector3(
			float(point_data.get("x", 0.0)),
			float(point_data.get("y", 0.0)),
			float(point_data.get("z", 0.0))
		))
	return movement


static func less(a: FoundationTurnMovement, b: FoundationTurnMovement) -> bool:
	return String(a.movement_id) < String(b.movement_id)
