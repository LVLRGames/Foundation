class_name FoundationInteriorVerticalConnector
extends RefCounted

## Abstract adjacency between consecutive selected floors.

const FORMAT_VERSION := 1
const KIND_STAIR: StringName = &"stair"

var connector_id: StringName
var connector_kind: StringName = KIND_STAIR
var lower_floor_index := 0
var upper_floor_index := 1
var lower_room_id: StringName
var upper_room_id: StringName
var center := Vector2.ZERO
var footprint := PackedVector2Array()


func to_dict() -> Dictionary:
	var points: Array[Dictionary] = []
	for point in footprint:
		points.append({"x": point.x, "y": point.y})
	return {
		"format_version": FORMAT_VERSION,
		"connector_id": String(connector_id),
		"connector_kind": String(connector_kind),
		"lower_floor_index": lower_floor_index,
		"upper_floor_index": upper_floor_index,
		"lower_room_id": String(lower_room_id),
		"upper_room_id": String(upper_room_id),
		"center": {"x": center.x, "y": center.y},
		"footprint": points,
	}


static func from_dict(data: Dictionary) -> FoundationInteriorVerticalConnector:
	var connector := FoundationInteriorVerticalConnector.new()
	connector.connector_id = StringName(data.get("connector_id", ""))
	connector.connector_kind = StringName(data.get("connector_kind", String(KIND_STAIR)))
	connector.lower_floor_index = int(data.get("lower_floor_index", 0))
	connector.upper_floor_index = int(data.get("upper_floor_index", 1))
	connector.lower_room_id = StringName(data.get("lower_room_id", ""))
	connector.upper_room_id = StringName(data.get("upper_room_id", ""))
	var center_data: Dictionary = data.get("center", {})
	connector.center = Vector2(float(center_data.get("x", 0.0)), float(center_data.get("y", 0.0)))
	for point_data: Dictionary in data.get("footprint", []):
		connector.footprint.append(Vector2(float(point_data.get("x", 0.0)), float(point_data.get("y", 0.0))))
	return connector


static func less(a: FoundationInteriorVerticalConnector, b: FoundationInteriorVerticalConnector) -> bool:
	return String(a.connector_id) < String(b.connector_id)
