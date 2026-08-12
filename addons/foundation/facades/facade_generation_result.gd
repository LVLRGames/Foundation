class_name FoundationFacadeGenerationResult
extends RefCounted

## Deterministic Phase 7 generation summary and diagnostics.

var success := false
var generated_facade_count := 0
var preserved_facade_count := 0
var skipped_building_count := 0
var generated_module_count := 0
var window_module_count := 0
var entrance_module_count := 0
var generation_operation_count := 0
var diagnostics: Array[Dictionary] = []
var errors := PackedStringArray()


func add_diagnostic(kind: StringName, severity: StringName, details: Dictionary = {}) -> void:
	var diagnostic := details.duplicate(true)
	diagnostic["kind"] = String(kind)
	diagnostic["severity"] = String(severity)
	diagnostics.append(diagnostic)


func fail(message: String) -> FoundationFacadeGenerationResult:
	errors.append(message)
	success = false
	return self


func to_dict() -> Dictionary:
	return {
		"success": success,
		"generated_facade_count": generated_facade_count,
		"preserved_facade_count": preserved_facade_count,
		"skipped_building_count": skipped_building_count,
		"generated_module_count": generated_module_count,
		"window_module_count": window_module_count,
		"entrance_module_count": entrance_module_count,
		"generation_operation_count": generation_operation_count,
		"diagnostics": diagnostics.duplicate(true),
		"errors": Array(errors),
	}
