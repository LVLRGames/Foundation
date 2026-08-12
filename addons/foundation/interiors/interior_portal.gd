class_name FoundationInteriorPortal
extends RefCounted

## Abstract passable relationship. It is topology data, not a runtime door or navigation edge.

const FORMAT_VERSION := 1
const KIND_INTERIOR: StringName = &"interior_door"
const KIND_EXTERIOR: StringName = &"exterior_entrance"

var portal_id: StringName
var portal_kind: StringName = KIND_INTERIOR
var floor_index := 0
var room_a_id: StringName
var room_b_id: StringName
var start := Vector2.ZERO
var end := Vector2.ZERO
var width := 0.0
var source_facade_id: StringName
var source_module_id: StringName
var provenance: StringName


func _init(
	p_portal_id: StringName = &"",
	p_floor_index := 0,
	p_room_a_id: StringName = &"",
	p_room_b_id: StringName = &"",
	p_start := Vector2.ZERO,
	p_end := Vector2.ZERO,
	p_kind: StringName = KIND_INTERIOR
) -> void:
	portal_id = p_portal_id
	floor_index = p_floor_index
	room_a_id = p_room_a_id
	room_b_id = p_room_b_id
	start = p_start
	end = p_end
	portal_kind = p_kind
	width = start.distance_to(end)


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"portal_id": String(portal_id),
		"portal_kind": String(portal_kind),
		"floor_index": floor_index,
		"room_a_id": String(room_a_id),
		"room_b_id": String(room_b_id),
		"start": {"x": start.x, "y": start.y},
		"end": {"x": end.x, "y": end.y},
		"width": width,
		"source_facade_id": String(source_facade_id),
		"source_module_id": String(source_module_id),
		"provenance": String(provenance),
	}


static func from_dict(data: Dictionary) -> FoundationInteriorPortal:
	var start_data: Dictionary = data.get("start", {})
	var end_data: Dictionary = data.get("end", {})
	var portal := FoundationInteriorPortal.new(
		StringName(data.get("portal_id", "")), int(data.get("floor_index", 0)),
		StringName(data.get("room_a_id", "")), StringName(data.get("room_b_id", "")),
		Vector2(float(start_data.get("x", 0.0)), float(start_data.get("y", 0.0))),
		Vector2(float(end_data.get("x", 0.0)), float(end_data.get("y", 0.0))),
		StringName(data.get("portal_kind", String(KIND_INTERIOR)))
	)
	portal.width = float(data.get("width", portal.width))
	portal.source_facade_id = StringName(data.get("source_facade_id", ""))
	portal.source_module_id = StringName(data.get("source_module_id", ""))
	portal.provenance = StringName(data.get("provenance", ""))
	return portal


static func less(a: FoundationInteriorPortal, b: FoundationInteriorPortal) -> bool:
	return String(a.portal_id) < String(b.portal_id)
