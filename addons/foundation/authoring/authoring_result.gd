class_name FoundationAuthoringResult
extends RefCounted

## Atomic Phase 11 operation/reapply summary.

var success := false
var action: StringName
var target_record_id: StringName
var override_record_id: StringName
var message := ""
var conflict_state: StringName = FoundationOverrideRecord.CONFLICT_NONE
var changed_fields := PackedStringArray()
var affected_layers: Array[StringName] = []
var applied_count := 0
var already_applied_count := 0
var conflicted_count := 0
var diagnostics: Array[Dictionary] = []


func fail(p_message: String, p_conflict: StringName = FoundationOverrideRecord.CONFLICT_NONE) -> FoundationAuthoringResult:
	message = p_message
	conflict_state = p_conflict
	success = false
	return self


func to_dict() -> Dictionary:
	var layers: Array[String] = []
	for layer in affected_layers:
		layers.append(String(layer))
	return {
		"success": success,
		"action": String(action),
		"target_record_id": String(target_record_id),
		"override_record_id": String(override_record_id),
		"message": message,
		"conflict_state": String(conflict_state),
		"changed_fields": Array(changed_fields),
		"affected_layers": layers,
		"applied_count": applied_count,
		"already_applied_count": already_applied_count,
		"conflicted_count": conflicted_count,
		"diagnostics": diagnostics.duplicate(true),
	}
