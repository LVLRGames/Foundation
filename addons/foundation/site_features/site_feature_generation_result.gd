class_name FoundationSiteFeatureGenerationResult
extends RefCounted

## Deterministic Phase 10 generation summary and diagnostics.

var success := false
var generated_parking_count := 0
var generated_public_feature_count := 0
var public_target_count := 0
var unserved_public_target_count := 0
var preserved_parking_count := 0
var preserved_public_feature_count := 0
var skipped_parcel_count := 0
var demand_spaces_total := 0
var supplied_spaces_total := 0
var unmet_demand_total := 0
var candidate_evaluations := 0
var generation_operation_count := 0
var diagnostics: Array[Dictionary] = []
var errors := PackedStringArray()


func add_diagnostic(kind: StringName, severity: StringName, details: Dictionary = {}) -> void:
	var diagnostic := details.duplicate(true)
	diagnostic["kind"] = String(kind)
	diagnostic["severity"] = String(severity)
	diagnostics.append(diagnostic)


func fail(message: String) -> FoundationSiteFeatureGenerationResult:
	errors.append(message)
	success = false
	return self


func to_dict() -> Dictionary:
	return {
		"success": success,
		"generated_parking_count": generated_parking_count,
		"generated_public_feature_count": generated_public_feature_count,
		"public_target_count": public_target_count,
		"unserved_public_target_count": unserved_public_target_count,
		"preserved_parking_count": preserved_parking_count,
		"preserved_public_feature_count": preserved_public_feature_count,
		"skipped_parcel_count": skipped_parcel_count,
		"demand_spaces_total": demand_spaces_total,
		"supplied_spaces_total": supplied_spaces_total,
		"unmet_demand_total": unmet_demand_total,
		"candidate_evaluations": candidate_evaluations,
		"generation_operation_count": generation_operation_count,
		"diagnostics": diagnostics.duplicate(true),
		"errors": Array(errors),
	}
