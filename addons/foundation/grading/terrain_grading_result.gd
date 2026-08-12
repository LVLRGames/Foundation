class_name FoundationTerrainGradingResult
extends RefCounted

## Summary for planning, application, or reversion without hiding diagnostics.

var success := false
var plan: FoundationTerrainGradingPlan
var applied := false
var reverted := false
var changed_vertex_count := 0
var dirty_chunk_count := 0
var diagnostics: Array[Dictionary] = []
var validation_issues: Array[FoundationTerrainGradingValidationIssue] = []


func to_dict() -> Dictionary:
	var serialized_issues: Array[Dictionary] = []
	for issue in validation_issues:
		serialized_issues.append(issue.to_dict())
	return {
		"success": success,
		"plan": plan.to_dict() if plan != null else {},
		"applied": applied,
		"reverted": reverted,
		"changed_vertex_count": changed_vertex_count,
		"dirty_chunk_count": dirty_chunk_count,
		"diagnostics": diagnostics.duplicate(true),
		"validation_issues": serialized_issues,
	}
