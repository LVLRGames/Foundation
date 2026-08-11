class_name FoundationChunkStreamingPlan
extends RefCounted

## Immutable-by-convention planner output. Building a plan never mutates world data.

const FORMAT_VERSION := 1

var success := true
var errors := PackedStringArray()
var requests: Array[FoundationChunkStreamingRequest] = []
var desired_chunks: Dictionary = {}
var planning_operation_count := 0
var transition_budget := 0


func fail(message: String) -> FoundationChunkStreamingPlan:
	success = false
	errors.append(message)
	requests.clear()
	desired_chunks.clear()
	return self


func get_desired(chunk_coordinate: Vector2i) -> Dictionary:
	return desired_chunks.get(chunk_coordinate, {}).duplicate(true)


func to_dict() -> Dictionary:
	var desired: Array[Dictionary] = []
	var coordinates: Array[Vector2i] = []
	for coordinate: Vector2i in desired_chunks:
		coordinates.append(coordinate)
	coordinates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	for coordinate in coordinates:
		var entry: Dictionary = desired_chunks[coordinate]
		desired.append({
			"coordinate": {"x": coordinate.x, "y": coordinate.y},
			"state": int(entry.get("state", FoundationChunkData.RuntimeState.UNLOADED)),
			"lod": int(entry.get("lod", -1)),
			"source_interest_id": String(entry.get("source_interest_id", &"")),
			"distance_chunks": int(entry.get("distance_chunks", 2147483647)),
		})
	var serialized_requests: Array[Dictionary] = []
	for request in requests:
		serialized_requests.append(request.to_dict())
	return {
		"format_version": FORMAT_VERSION,
		"success": success,
		"errors": Array(errors),
		"planning_operation_count": planning_operation_count,
		"transition_budget": transition_budget,
		"desired_chunks": desired,
		"requests": serialized_requests,
	}
