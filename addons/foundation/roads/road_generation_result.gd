class_name FoundationRoadGenerationResult
extends RefCounted

## Deterministic generation summary for tests, tooling, and the demo.

var success := false
var generated_node_count := 0
var generated_edge_count := 0
var preserved_node_count := 0
var preserved_edge_count := 0
var generated_logical_road_count := 0
var generated_intersection_count := 0
var generated_pattern_node_count := 0
var generated_pattern_edge_count := 0
var mandatory_anchor_count := 0
var accepted_candidate_count := 0
var rejected_candidate_count := 0
var expanded_cell_count := 0
var total_terrain_cost := 0.0
var errors := PackedStringArray()
var validation_issues: Array[FoundationRoadValidationIssue] = []


func fail(message: String) -> FoundationRoadGenerationResult:
	errors.append(message)
	success = false
	return self


func to_dict() -> Dictionary:
	var serialized_issues: Array[Dictionary] = []
	for issue in validation_issues:
		serialized_issues.append(issue.to_dict())
	return {
		"success": success,
		"generated_node_count": generated_node_count,
		"generated_edge_count": generated_edge_count,
		"preserved_node_count": preserved_node_count,
		"preserved_edge_count": preserved_edge_count,
		"generated_logical_road_count": generated_logical_road_count,
		"generated_intersection_count": generated_intersection_count,
		"generated_pattern_node_count": generated_pattern_node_count,
		"generated_pattern_edge_count": generated_pattern_edge_count,
		"mandatory_anchor_count": mandatory_anchor_count,
		"accepted_candidate_count": accepted_candidate_count,
		"rejected_candidate_count": rejected_candidate_count,
		"expanded_cell_count": expanded_cell_count,
		"total_terrain_cost": total_terrain_cost,
		"errors": Array(errors),
		"validation_issues": serialized_issues,
	}
