class_name FoundationTerrainGradingValidationIssue
extends RefCounted

## Read-only Phase 9 plan/terrain validation diagnostic.

const FORMAT_VERSION := 1
const SEVERITY_WARNING: StringName = &"warning"
const SEVERITY_ERROR: StringName = &"error"

var kind: StringName
var severity: StringName = SEVERITY_ERROR
var message := ""
var operation_id: StringName
var source_record_id: StringName
var grid_vertex := Vector2i(-1, -1)


func _init(
	p_kind: StringName = &"",
	p_severity: StringName = SEVERITY_ERROR,
	p_message := "",
	p_operation_id: StringName = &"",
	p_source_record_id: StringName = &"",
	p_grid_vertex := Vector2i(-1, -1)
) -> void:
	kind = p_kind
	severity = p_severity
	message = p_message
	operation_id = p_operation_id
	source_record_id = p_source_record_id
	grid_vertex = p_grid_vertex


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"kind": String(kind),
		"severity": String(severity),
		"message": message,
		"operation_id": String(operation_id),
		"source_record_id": String(source_record_id),
		"grid_vertex": {"x": grid_vertex.x, "y": grid_vertex.y},
	}


static func from_dict(data: Dictionary) -> FoundationTerrainGradingValidationIssue:
	var vertex_data: Dictionary = data.get("grid_vertex", {})
	return FoundationTerrainGradingValidationIssue.new(
		StringName(data.get("kind", "")),
		StringName(data.get("severity", String(SEVERITY_ERROR))),
		String(data.get("message", "")),
		StringName(data.get("operation_id", "")),
		StringName(data.get("source_record_id", "")),
		Vector2i(int(vertex_data.get("x", -1)), int(vertex_data.get("y", -1)))
	)
