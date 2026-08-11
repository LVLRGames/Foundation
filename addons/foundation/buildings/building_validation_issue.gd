class_name FoundationBuildingValidationIssue
extends RefCounted

## Stable severity-tagged Phase 5 diagnostic.

const SEVERITY_INFO: StringName = &"info"
const SEVERITY_WARNING: StringName = &"warning"
const SEVERITY_ERROR: StringName = &"error"

var kind: StringName
var severity: StringName
var building_id: StringName
var parent_parcel_id: StringName
var message := ""
var details: Dictionary = {}


func _init(
	p_kind: StringName = &"building_validation",
	p_severity: StringName = SEVERITY_WARNING,
	p_building_id: StringName = &"",
	p_parent_parcel_id: StringName = &"",
	p_message := "",
	p_details: Dictionary = {}
) -> void:
	kind = p_kind
	severity = p_severity
	building_id = p_building_id
	parent_parcel_id = p_parent_parcel_id
	message = p_message
	details = p_details.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"kind": String(kind),
		"severity": String(severity),
		"building_id": String(building_id),
		"parent_parcel_id": String(parent_parcel_id),
		"message": message,
		"details": details.duplicate(true),
	}


static func less(a: FoundationBuildingValidationIssue, b: FoundationBuildingValidationIssue) -> bool:
	return JSON.stringify(a.to_dict()) < JSON.stringify(b.to_dict())
