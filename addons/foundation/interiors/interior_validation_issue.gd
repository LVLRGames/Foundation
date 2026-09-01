class_name FoundationInteriorValidationIssue
extends RefCounted

## Stable severity-tagged Phase 12 diagnostic.

const SEVERITY_INFO: StringName = &"info"
const SEVERITY_WARNING: StringName = &"warning"
const SEVERITY_ERROR: StringName = &"error"

var kind: StringName
var severity: StringName
var interior_id: StringName
var parent_building_id: StringName
var message := ""
var details: Dictionary = {}


func _init(
	p_kind: StringName = &"interior_validation",
	p_severity: StringName = SEVERITY_WARNING,
	p_interior_id: StringName = &"",
	p_parent_building_id: StringName = &"",
	p_message := "",
	p_details: Dictionary = {}
) -> void:
	kind = p_kind
	severity = p_severity
	interior_id = p_interior_id
	parent_building_id = p_parent_building_id
	message = p_message
	details = p_details.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"kind": String(kind), "severity": String(severity),
		"interior_id": String(interior_id), "parent_building_id": String(parent_building_id),
		"message": message, "details": details.duplicate(true),
	}


static func less(a: FoundationInteriorValidationIssue, b: FoundationInteriorValidationIssue) -> bool:
	return JSON.stringify(a.to_dict()) < JSON.stringify(b.to_dict())
