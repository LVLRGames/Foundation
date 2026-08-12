class_name FoundationSiteFeatureValidationIssue
extends RefCounted

## Stable severity-tagged Phase 10 diagnostic.

const SEVERITY_INFO: StringName = &"info"
const SEVERITY_WARNING: StringName = &"warning"
const SEVERITY_ERROR: StringName = &"error"

var kind: StringName
var severity: StringName
var record_id: StringName
var parent_id: StringName
var message := ""
var details: Dictionary = {}


func _init(
	p_kind: StringName = &"site_feature_validation",
	p_severity: StringName = SEVERITY_WARNING,
	p_record_id: StringName = &"",
	p_parent_id: StringName = &"",
	p_message := "",
	p_details: Dictionary = {}
) -> void:
	kind = p_kind
	severity = p_severity
	record_id = p_record_id
	parent_id = p_parent_id
	message = p_message
	details = p_details.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"kind": String(kind), "severity": String(severity),
		"record_id": String(record_id), "parent_id": String(parent_id),
		"message": message, "details": details.duplicate(true),
	}


static func less(a: FoundationSiteFeatureValidationIssue, b: FoundationSiteFeatureValidationIssue) -> bool:
	return JSON.stringify(a.to_dict()) < JSON.stringify(b.to_dict())
