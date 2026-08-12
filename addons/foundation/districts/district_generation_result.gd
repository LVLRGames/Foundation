class_name FoundationDistrictGenerationResult
extends RefCounted

## Deterministic Phase 8 allocation summary and diagnostics.

var success := false
var generated_district_count := 0
var preserved_district_count := 0
var assigned_block_count := 0
var skipped_block_count := 0
var adjacency_candidate_comparisons := 0
var unrestricted_pair_reference_count := 0
var adjacency_edge_count := 0
var generation_operation_count := 0
var diagnostics: Array[Dictionary] = []
var errors := PackedStringArray()


func add_diagnostic(kind: StringName, severity: StringName, details: Dictionary = {}) -> void:
	var diagnostic := details.duplicate(true)
	diagnostic["kind"] = String(kind)
	diagnostic["severity"] = String(severity)
	diagnostics.append(diagnostic)


func fail(message: String) -> FoundationDistrictGenerationResult:
	errors.append(message)
	success = false
	return self


func to_dict() -> Dictionary:
	return {
		"success": success,
		"generated_district_count": generated_district_count,
		"preserved_district_count": preserved_district_count,
		"assigned_block_count": assigned_block_count,
		"skipped_block_count": skipped_block_count,
		"adjacency_candidate_comparisons": adjacency_candidate_comparisons,
		"unrestricted_pair_reference_count": unrestricted_pair_reference_count,
		"adjacency_edge_count": adjacency_edge_count,
		"generation_operation_count": generation_operation_count,
		"diagnostics": diagnostics.duplicate(true),
		"errors": Array(errors),
	}
