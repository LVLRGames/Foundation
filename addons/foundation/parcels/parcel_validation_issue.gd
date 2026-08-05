class_name FoundationParcelValidationIssue
extends RefCounted

## Stable severity-tagged Phase 4 diagnostic.

const SEVERITY_INFO: StringName = &"info"
const SEVERITY_WARNING: StringName = &"warning"
const SEVERITY_ERROR: StringName = &"error"

var kind: StringName
var severity: StringName
var parcel_id: StringName
var parent_block_id: StringName
var message := ""
var details: Dictionary = {}


func _init(
	p_kind: StringName = &"parcel_validation",
	p_severity: StringName = SEVERITY_WARNING,
	p_parcel_id: StringName = &"",
	p_parent_block_id: StringName = &"",
	p_message := "",
	p_details: Dictionary = {}
) -> void:
	kind = p_kind
	severity = p_severity
	parcel_id = p_parcel_id
	parent_block_id = p_parent_block_id
	message = p_message
	details = p_details.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"kind": String(kind),
		"severity": String(severity),
		"parcel_id": String(parcel_id),
		"parent_block_id": String(parent_block_id),
		"message": message,
		"details": details.duplicate(true),
	}


static func less(a: FoundationParcelValidationIssue, b: FoundationParcelValidationIssue) -> bool:
	return JSON.stringify(a.to_dict()) < JSON.stringify(b.to_dict())
