class_name FoundationBlockGenerationResult
extends RefCounted

## Deterministic Phase 3 generation summary and diagnostics.

var success := false
var generated_block_count := 0
var preserved_block_count := 0
var rejected_face_count := 0
var exterior_face_count := 0
var input_segment_count := 0
var planar_segment_count := 0
var pruned_segment_count := 0
var split_intersection_count := 0
var intersection_bucket_count := 0
var candidate_pair_count := 0
var unrestricted_pair_count := 0
var diagnostics: Array[Dictionary] = []
var errors := PackedStringArray()


func add_diagnostic(kind: StringName, details: Dictionary = {}) -> void:
	var diagnostic := details.duplicate(true)
	diagnostic["kind"] = String(kind)
	diagnostics.append(diagnostic)


func fail(message: String) -> FoundationBlockGenerationResult:
	errors.append(message)
	success = false
	return self


func to_dict() -> Dictionary:
	return {
		"success": success,
		"generated_block_count": generated_block_count,
		"preserved_block_count": preserved_block_count,
		"rejected_face_count": rejected_face_count,
		"exterior_face_count": exterior_face_count,
		"input_segment_count": input_segment_count,
		"planar_segment_count": planar_segment_count,
		"pruned_segment_count": pruned_segment_count,
		"split_intersection_count": split_intersection_count,
		"intersection_bucket_count": intersection_bucket_count,
		"candidate_pair_count": candidate_pair_count,
		"unrestricted_pair_count": unrestricted_pair_count,
		"diagnostics": diagnostics.duplicate(true),
		"errors": Array(errors),
	}
