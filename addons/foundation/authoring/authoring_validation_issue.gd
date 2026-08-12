class_name FoundationAuthoringValidationIssue
extends RefCounted

## Stable read-only Phase 11 diagnostic.

const SEVERITY_INFO: StringName = &"info"
const SEVERITY_WARNING: StringName = &"warning"
const SEVERITY_ERROR: StringName = &"error"

var kind: StringName
var severity: StringName
var override_id: StringName
var target_id: StringName
var message := ""
var details: Dictionary = {}


func _init(
	p_kind: StringName = &"authoring_validation",
	p_severity: StringName = SEVERITY_WARNING,
	p_override_id: StringName = &"",
	p_target_id: StringName = &"",
	p_message := "",
	p_details: Dictionary = {}
) -> void:
	kind = p_kind
	severity = p_severity
	override_id = p_override_id
	target_id = p_target_id
	message = p_message
	details = p_details.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"kind": String(kind), "severity": String(severity),
		"override_id": String(override_id), "target_id": String(target_id),
		"message": message, "details": details.duplicate(true),
	}


static func less(a: FoundationAuthoringValidationIssue, b: FoundationAuthoringValidationIssue) -> bool:
	return FoundationSpatialRecordCodec.canonical_json(a.to_dict()) < FoundationSpatialRecordCodec.canonical_json(b.to_dict())
