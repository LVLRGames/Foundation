class_name FoundationFacadeValidationIssue
extends RefCounted

## Stable severity-tagged Phase 7 diagnostic.

const SEVERITY_INFO: StringName = &"info"
const SEVERITY_WARNING: StringName = &"warning"
const SEVERITY_ERROR: StringName = &"error"

var kind: StringName
var severity: StringName
var facade_id: StringName
var parent_building_id: StringName
var message := ""
var details: Dictionary = {}


func _init(
	p_kind: StringName = &"facade_validation",
	p_severity: StringName = SEVERITY_WARNING,
	p_facade_id: StringName = &"",
	p_parent_building_id: StringName = &"",
	p_message := "",
	p_details: Dictionary = {}
) -> void:
	kind = p_kind
	severity = p_severity
	facade_id = p_facade_id
	parent_building_id = p_parent_building_id
	message = p_message
	details = p_details.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"kind": String(kind),
		"severity": String(severity),
		"facade_id": String(facade_id),
		"parent_building_id": String(parent_building_id),
		"message": message,
		"details": details.duplicate(true),
	}


static func less(a: FoundationFacadeValidationIssue, b: FoundationFacadeValidationIssue) -> bool:
	return JSON.stringify(a.to_dict()) < JSON.stringify(b.to_dict())
