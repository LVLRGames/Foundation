class_name FoundationBuildingGenerationResult
extends RefCounted

## Deterministic Phase 5 generation summary and diagnostics.

var success := false
var generated_building_count := 0
var preserved_building_count := 0
var skipped_parcel_count := 0
var generation_operation_count := 0
var footprint_area_total := 0.0
var gross_floor_area_total := 0.0
var diagnostics: Array[Dictionary] = []
var errors := PackedStringArray()


func add_diagnostic(kind: StringName, severity: StringName, details: Dictionary = {}) -> void:
	var diagnostic := details.duplicate(true)
	diagnostic["kind"] = String(kind)
	diagnostic["severity"] = String(severity)
	diagnostics.append(diagnostic)


func fail(message: String) -> FoundationBuildingGenerationResult:
	errors.append(message)
	success = false
	return self


func to_dict() -> Dictionary:
	return {
		"success": success,
		"generated_building_count": generated_building_count,
		"preserved_building_count": preserved_building_count,
		"skipped_parcel_count": skipped_parcel_count,
		"generation_operation_count": generation_operation_count,
		"footprint_area_total": footprint_area_total,
		"gross_floor_area_total": gross_floor_area_total,
		"diagnostics": diagnostics.duplicate(true),
		"errors": Array(errors),
	}
