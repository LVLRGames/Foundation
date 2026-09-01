class_name FoundationInteriorRoom
extends RefCounted

## Canonical Node-free room value nested beneath an interior floor.

const FORMAT_VERSION := 1
const KIND_STANDARD: StringName = &"standard"
const KIND_CIRCULATION: StringName = &"circulation"
const KIND_SERVICE: StringName = &"service"

var room_id: StringName
var floor_index := 0
var room_kind: StringName = KIND_STANDARD
var boundary := PackedVector2Array()
var area := 0.0
var centroid := Vector2.ZERO
var label_point := Vector2.ZERO


func _init(
	p_room_id: StringName = &"",
	p_floor_index := 0,
	p_boundary := PackedVector2Array(),
	p_room_kind: StringName = KIND_STANDARD
) -> void:
	room_id = p_room_id
	floor_index = p_floor_index
	boundary = p_boundary.duplicate()
	room_kind = p_room_kind
	refresh_metrics()


func refresh_metrics() -> void:
	area = absf(FoundationBlockRecord._signed_area(boundary))
	centroid = FoundationBlockRecord._polygon_centroid(boundary)
	label_point = FoundationBlockRecord._stable_interior_point(boundary, centroid)


func to_dict() -> Dictionary:
	var points: Array[Dictionary] = []
	for point in boundary:
		points.append({"x": point.x, "y": point.y})
	return {
		"format_version": FORMAT_VERSION,
		"room_id": String(room_id),
		"floor_index": floor_index,
		"room_kind": String(room_kind),
		"boundary": points,
		"area": area,
		"centroid": {"x": centroid.x, "y": centroid.y},
		"label_point": {"x": label_point.x, "y": label_point.y},
	}


static func from_dict(data: Dictionary) -> FoundationInteriorRoom:
	var points := PackedVector2Array()
	for point_data: Dictionary in data.get("boundary", []):
		points.append(Vector2(float(point_data.get("x", 0.0)), float(point_data.get("y", 0.0))))
	var room := FoundationInteriorRoom.new(
		StringName(data.get("room_id", "")), int(data.get("floor_index", 0)), points,
		StringName(data.get("room_kind", String(KIND_STANDARD)))
	)
	room.area = float(data.get("area", room.area))
	var centroid_data: Dictionary = data.get("centroid", {})
	room.centroid = Vector2(float(centroid_data.get("x", room.centroid.x)), float(centroid_data.get("y", room.centroid.y)))
	var label_data: Dictionary = data.get("label_point", {})
	room.label_point = Vector2(float(label_data.get("x", room.label_point.x)), float(label_data.get("y", room.label_point.y)))
	return room


static func less(a: FoundationInteriorRoom, b: FoundationInteriorRoom) -> bool:
	return String(a.room_id) < String(b.room_id)
