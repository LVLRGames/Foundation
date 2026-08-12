class_name FoundationInteriorGenerationResult
extends RefCounted

## Deterministic Phase 12 generation summary and diagnostics.

var success := false
var generated_interior_count := 0
var preserved_interior_count := 0
var skipped_building_count := 0
var generated_floor_count := 0
var generated_room_count := 0
var generated_portal_count := 0
var generated_vertical_connector_count := 0
var generation_operation_count := 0
var diagnostics: Array[Dictionary] = []
var errors := PackedStringArray()


func add_diagnostic(kind: StringName, severity: StringName, details: Dictionary = {}) -> void:
	var diagnostic := details.duplicate(true)
	diagnostic["kind"] = String(kind)
	diagnostic["severity"] = String(severity)
	diagnostics.append(diagnostic)


func fail(message: String) -> FoundationInteriorGenerationResult:
	errors.append(message)
	success = false
	return self


func to_dict() -> Dictionary:
	return {
		"success": success,
		"generated_interior_count": generated_interior_count,
		"preserved_interior_count": preserved_interior_count,
		"skipped_building_count": skipped_building_count,
		"generated_floor_count": generated_floor_count,
		"generated_room_count": generated_room_count,
		"generated_portal_count": generated_portal_count,
		"generated_vertical_connector_count": generated_vertical_connector_count,
		"generation_operation_count": generation_operation_count,
		"diagnostics": diagnostics.duplicate(true),
		"errors": Array(errors),
	}
