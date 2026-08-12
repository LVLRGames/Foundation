class_name FoundationParkingSpace
extends RefCounted

## Compact deterministic parking-space value. It owns no scene objects.

const FORMAT_VERSION := 1
const KIND_STANDARD: StringName = &"standard"
const KIND_ACCESSIBLE: StringName = &"accessible"
const KIND_BICYCLE: StringName = &"bicycle"
const KIND_LOADING: StringName = &"loading"

var space_id: StringName
var row_index := 0
var column_index := 0
var position := Vector2.ZERO
var orientation_degrees := 0.0
var width := 2.6
var length := 5.2
var space_kind: StringName = KIND_STANDARD
var accessible := false


func _init(
	p_space_id: StringName = &"",
	p_row_index := 0,
	p_column_index := 0,
	p_position := Vector2.ZERO
) -> void:
	space_id = p_space_id
	row_index = p_row_index
	column_index = p_column_index
	position = p_position


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"space_id": String(space_id),
		"row_index": row_index,
		"column_index": column_index,
		"position": {"x": position.x, "y": position.y},
		"orientation_degrees": orientation_degrees,
		"width": width,
		"length": length,
		"space_kind": String(space_kind),
		"accessible": accessible,
	}


static func from_dict(data: Dictionary) -> FoundationParkingSpace:
	var point: Dictionary = data.get("position", {})
	var space := FoundationParkingSpace.new(
		StringName(data.get("space_id", "")),
		int(data.get("row_index", 0)),
		int(data.get("column_index", 0)),
		Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0)))
	)
	space.orientation_degrees = float(data.get("orientation_degrees", 0.0))
	space.width = float(data.get("width", 2.6))
	space.length = float(data.get("length", 5.2))
	space.space_kind = StringName(data.get("space_kind", String(KIND_STANDARD)))
	space.accessible = bool(data.get("accessible", false))
	return space


static func less(a: FoundationParkingSpace, b: FoundationParkingSpace) -> bool:
	if a.row_index != b.row_index:
		return a.row_index < b.row_index
	if a.column_index != b.column_index:
		return a.column_index < b.column_index
	return String(a.space_id) < String(b.space_id)
