class_name FoundationDebugProvider
extends RefCounted

## Provider interface: append disposable primitives, never mutate world data.

var provider_id: StringName
var invocation_count := 0


func _init(p_provider_id: StringName = &"provider") -> void:
	provider_id = p_provider_id


func append_debug(
	_world: FoundationWorldData,
	_builder: FoundationDebugGeometryBuilder,
	_context: Dictionary
) -> void:
	invocation_count += 1
