class_name FoundationParkingAccessPath
extends RefCounted

## Compact abstract access/aisle path. It is not a navigation or traffic graph.

const FORMAT_VERSION := 1
const KIND_ACCESS: StringName = &"access"
const KIND_AISLE: StringName = &"aisle"

var path_id: StringName
var path_kind: StringName = KIND_AISLE
var points := PackedVector2Array()
var width := 6.0


func _init(
	p_path_id: StringName = &"",
	p_path_kind: StringName = KIND_AISLE,
	p_points := PackedVector2Array()
) -> void:
	path_id = p_path_id
	path_kind = p_path_kind
	points = p_points.duplicate()


func to_dict() -> Dictionary:
	var serialized_points: Array[Dictionary] = []
	for point in points:
		serialized_points.append({"x": point.x, "y": point.y})
	return {
		"format_version": FORMAT_VERSION,
		"path_id": String(path_id),
		"path_kind": String(path_kind),
		"points": serialized_points,
		"width": width,
	}


static func from_dict(data: Dictionary) -> FoundationParkingAccessPath:
	var restored_points := PackedVector2Array()
	for point_data: Dictionary in data.get("points", []):
		restored_points.append(Vector2(float(point_data.get("x", 0.0)), float(point_data.get("y", 0.0))))
	var path := FoundationParkingAccessPath.new(
		StringName(data.get("path_id", "")),
		StringName(data.get("path_kind", String(KIND_AISLE))),
		restored_points
	)
	path.width = float(data.get("width", 6.0))
	return path


static func less(a: FoundationParkingAccessPath, b: FoundationParkingAccessPath) -> bool:
	return String(a.path_id) < String(b.path_id)
