class_name FoundationRoadGenerationResult
extends RefCounted

## Deterministic generation summary for tests, tooling, and the demo.

var success := false
var generated_node_count := 0
var generated_edge_count := 0
var preserved_node_count := 0
var preserved_edge_count := 0
var expanded_cell_count := 0
var total_terrain_cost := 0.0
var errors := PackedStringArray()


func fail(message: String) -> FoundationRoadGenerationResult:
	errors.append(message)
	success = false
	return self
