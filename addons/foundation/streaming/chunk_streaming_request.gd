class_name FoundationChunkStreamingRequest
extends RefCounted

## One deterministic, one-step lifecycle or LOD transition.

const FORMAT_VERSION := 1

var chunk_coordinate := Vector2i.ZERO
var source_interest_id: StringName = &""
var distance_chunks := 2147483647
var priority_weight := 0.0
var from_state := FoundationChunkData.RuntimeState.DATA_ONLY
var to_state := FoundationChunkData.RuntimeState.DATA_ONLY
var from_lod := -1
var to_lod := -1
var final_state := FoundationChunkData.RuntimeState.DATA_ONLY
var final_lod := -1


func is_release() -> bool:
	return to_state < from_state or (to_state == from_state and to_lod > from_lod)


func is_acquire() -> bool:
	return to_state > from_state or (to_state == from_state and to_lod < from_lod)


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"chunk_coordinate": {"x": chunk_coordinate.x, "y": chunk_coordinate.y},
		"source_interest_id": String(source_interest_id),
		"distance_chunks": distance_chunks,
		"priority_weight": priority_weight,
		"from_state": from_state,
		"to_state": to_state,
		"from_lod": from_lod,
		"to_lod": to_lod,
		"final_state": final_state,
		"final_lod": final_lod,
	}
