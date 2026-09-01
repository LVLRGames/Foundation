class_name FoundationTrafficMetadataGenerationResult
extends RefCounted

## Deterministic Phase 13 generation summary and diagnostics.

var success := false
var generated_cross_section_count := 0
var generated_intersection_traffic_count := 0
var generated_lane_count := 0
var generated_approach_count := 0
var generated_movement_count := 0
var preserved_cross_section_count := 0
var preserved_intersection_traffic_count := 0
var generation_operation_count := 0
var diagnostics: Array[Dictionary] = []
var errors := PackedStringArray()


func add_diagnostic(kind: StringName, severity: StringName, details: Dictionary = {}) -> void:
	var diagnostic := details.duplicate(true)
	diagnostic["kind"] = String(kind)
	diagnostic["severity"] = String(severity)
	diagnostics.append(diagnostic)


func fail(message: String) -> FoundationTrafficMetadataGenerationResult:
	errors.append(message)
	success = false
	return self


func to_dict() -> Dictionary:
	return {
		"success": success,
		"generated_cross_section_count": generated_cross_section_count,
		"generated_intersection_traffic_count": generated_intersection_traffic_count,
		"generated_lane_count": generated_lane_count,
		"generated_approach_count": generated_approach_count,
		"generated_movement_count": generated_movement_count,
		"preserved_cross_section_count": preserved_cross_section_count,
		"preserved_intersection_traffic_count": preserved_intersection_traffic_count,
		"generation_operation_count": generation_operation_count,
		"diagnostics": diagnostics.duplicate(true),
		"errors": Array(errors),
	}
