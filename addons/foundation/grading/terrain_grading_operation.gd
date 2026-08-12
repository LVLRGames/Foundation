class_name FoundationTerrainGradingOperation
extends RefCounted

## Stable, serializable grading intent. Bridge-span operations intentionally own no edits.

const FORMAT_VERSION := 1
const KIND_ROAD_CORRIDOR: StringName = &"road_corridor"
const KIND_BUILDING_PAD: StringName = &"building_pad"
const KIND_BRIDGE_SPAN: StringName = &"bridge_span"
const KIND_BRIDGE_APPROACH: StringName = &"bridge_approach"

var stable_id: StringName
var operation_kind: StringName
var source_record_id: StringName
var source_record_hash := ""
var priority := 0
var world_bounds := Rect2()
var target_elevation_min := 0.0
var target_elevation_max := 0.0
var edit_keys := PackedStringArray()
var metadata: Dictionary = {}


func _init(
	p_stable_id: StringName = &"",
	p_operation_kind: StringName = &"",
	p_source_record_id: StringName = &"",
	p_priority := 0
) -> void:
	stable_id = p_stable_id
	operation_kind = p_operation_kind
	source_record_id = p_source_record_id
	priority = p_priority


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"stable_id": String(stable_id),
		"operation_kind": String(operation_kind),
		"source_record_id": String(source_record_id),
		"source_record_hash": source_record_hash,
		"priority": priority,
		"world_bounds": {
			"x": world_bounds.position.x,
			"y": world_bounds.position.y,
			"width": world_bounds.size.x,
			"height": world_bounds.size.y,
		},
		"target_elevation_min": target_elevation_min,
		"target_elevation_max": target_elevation_max,
		"edit_keys": Array(edit_keys),
		"metadata": metadata.duplicate(true),
	}


static func from_dict(data: Dictionary) -> FoundationTerrainGradingOperation:
	var operation := FoundationTerrainGradingOperation.new(
		StringName(data.get("stable_id", "")),
		StringName(data.get("operation_kind", "")),
		StringName(data.get("source_record_id", "")),
		int(data.get("priority", 0))
	)
	var bounds_data: Dictionary = data.get("world_bounds", {})
	operation.world_bounds = Rect2(
		float(bounds_data.get("x", 0.0)),
		float(bounds_data.get("y", 0.0)),
		float(bounds_data.get("width", 0.0)),
		float(bounds_data.get("height", 0.0))
	)
	operation.source_record_hash = String(data.get("source_record_hash", ""))
	operation.target_elevation_min = float(data.get("target_elevation_min", 0.0))
	operation.target_elevation_max = float(data.get("target_elevation_max", 0.0))
	operation.edit_keys = PackedStringArray(data.get("edit_keys", []))
	operation.metadata = data.get("metadata", {}).duplicate(true)
	return operation
