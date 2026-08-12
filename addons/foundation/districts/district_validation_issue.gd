class_name FoundationDistrictValidationIssue
extends RefCounted

## Stable severity-tagged Phase 8 diagnostic.

const SEVERITY_INFO: StringName = &"info"
const SEVERITY_WARNING: StringName = &"warning"
const SEVERITY_ERROR: StringName = &"error"

var kind: StringName
var severity: StringName
var district_id: StringName
var block_id: StringName
var message := ""
var details: Dictionary = {}


func _init(
	p_kind: StringName = &"district_validation",
	p_severity: StringName = SEVERITY_WARNING,
	p_district_id: StringName = &"",
	p_block_id: StringName = &"",
	p_message := "",
	p_details: Dictionary = {}
) -> void:
	kind = p_kind
	severity = p_severity
	district_id = p_district_id
	block_id = p_block_id
	message = p_message
	details = p_details.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"kind": String(kind),
		"severity": String(severity),
		"district_id": String(district_id),
		"block_id": String(block_id),
		"message": message,
		"details": details.duplicate(true),
	}


static func less(a: FoundationDistrictValidationIssue, b: FoundationDistrictValidationIssue) -> bool:
	return JSON.stringify(a.to_dict()) < JSON.stringify(b.to_dict())
