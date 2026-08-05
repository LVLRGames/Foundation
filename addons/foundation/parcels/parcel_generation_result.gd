class_name FoundationParcelGenerationResult
extends RefCounted

## Deterministic Phase 4 generation summary and diagnostics.

var success := false
var generated_parcel_count := 0
var preserved_parcel_count := 0
var standard_parcel_count := 0
var corner_parcel_count := 0
var remainder_parcel_count := 0
var skipped_block_count := 0
var subdivision_operation_count := 0
var parent_area_total := 0.0
var parcel_area_total := 0.0
var coverage_error_total := 0.0
var diagnostics: Array[Dictionary] = []
var errors := PackedStringArray()


func add_diagnostic(kind: StringName, severity: StringName, details: Dictionary = {}) -> void:
	var diagnostic := details.duplicate(true)
	diagnostic["kind"] = String(kind)
	diagnostic["severity"] = String(severity)
	diagnostics.append(diagnostic)


func fail(message: String) -> FoundationParcelGenerationResult:
	errors.append(message)
	success = false
	return self


func to_dict() -> Dictionary:
	return {
		"success": success,
		"generated_parcel_count": generated_parcel_count,
		"preserved_parcel_count": preserved_parcel_count,
		"standard_parcel_count": standard_parcel_count,
		"corner_parcel_count": corner_parcel_count,
		"remainder_parcel_count": remainder_parcel_count,
		"skipped_block_count": skipped_block_count,
		"subdivision_operation_count": subdivision_operation_count,
		"parent_area_total": parent_area_total,
		"parcel_area_total": parcel_area_total,
		"coverage_error_total": coverage_error_total,
		"diagnostics": diagnostics.duplicate(true),
		"errors": Array(errors),
	}
