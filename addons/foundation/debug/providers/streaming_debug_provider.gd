class_name FoundationStreamingDebugProvider
extends FoundationDebugProvider

## Disposable Phase 6 chunk lifecycle and LOD inspection.


func _init() -> void:
	super(&"streaming")


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	var selected_chunk: Vector2i = context.get(
		"selected_chunk",
		Vector2i(2147483647, 2147483647)
	)
	for chunk in world.get_sorted_chunks():
		var purpose := _purpose_for(chunk)
		builder.add_filled_rect(chunk.world_bounds, 0.055, purpose)
		builder.add_rect(chunk.world_bounds, 0.31, &"selected" if chunk.coordinate == selected_chunk else purpose)
		builder.add_text(
			Vector3(chunk.world_bounds.get_center().x, 1.2, chunk.world_bounds.get_center().y),
			"%d,%d\n%s | LOD %s\nT%d" % [
				chunk.coordinate.x,
				chunk.coordinate.y,
				_state_name(chunk.runtime_state),
				"-" if chunk.runtime_lod_level < 0 else str(chunk.runtime_lod_level),
				chunk.runtime_transition_serial,
			],
			purpose
		)


func _purpose_for(chunk: FoundationChunkData) -> StringName:
	match chunk.runtime_state:
		FoundationChunkData.RuntimeState.UNLOADED:
			return &"streaming_unloaded"
		FoundationChunkData.RuntimeState.DATA_ONLY:
			return &"streaming_data"
		FoundationChunkData.RuntimeState.PROXY_LOADED:
			return &"streaming_proxy"
		FoundationChunkData.RuntimeState.VISUAL_LOADED:
			return &"streaming_visual_near" if chunk.runtime_lod_level <= 0 else &"streaming_visual_far"
		FoundationChunkData.RuntimeState.PHYSICS_LOADED:
			return &"streaming_physics"
		FoundationChunkData.RuntimeState.GAMEPLAY_ACTIVE:
			return &"streaming_gameplay"
		_:
			return &"streaming_unloaded"


func _state_name(runtime_state: FoundationChunkData.RuntimeState) -> String:
	match runtime_state:
		FoundationChunkData.RuntimeState.UNLOADED: return "Unloaded"
		FoundationChunkData.RuntimeState.DATA_ONLY: return "Data"
		FoundationChunkData.RuntimeState.PROXY_LOADED: return "Proxy"
		FoundationChunkData.RuntimeState.VISUAL_LOADED: return "Visual"
		FoundationChunkData.RuntimeState.PHYSICS_LOADED: return "Physics"
		FoundationChunkData.RuntimeState.GAMEPLAY_ACTIVE: return "Gameplay"
		_: return "Unknown"
