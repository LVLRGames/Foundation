class_name FoundationRegionData
extends RefCounted

## Logical scheduling/streaming partition above chunks.

const FORMAT_VERSION := 1

enum GenerationState {
	UNINITIALIZED,
	PLANNED,
	GENERATED,
	DIRTY,
}

var stable_id: StringName
var coordinate := Vector2i.ZERO
var world_bounds := Rect2()
var chunk_bounds := Rect2i()
var tags := PackedStringArray()
var metadata: Dictionary = {}
var generation_state := GenerationState.UNINITIALIZED


func _init(
	p_coordinate := Vector2i.ZERO,
	p_world_bounds := Rect2(),
	p_chunk_bounds := Rect2i()
) -> void:
	coordinate = p_coordinate
	stable_id = FoundationSpatialId.for_region(coordinate)
	world_bounds = p_world_bounds
	chunk_bounds = p_chunk_bounds


func get_chunk_coordinates() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for chunk_y in range(chunk_bounds.position.y, chunk_bounds.end.y):
		for chunk_x in range(chunk_bounds.position.x, chunk_bounds.end.x):
			result.append(Vector2i(chunk_x, chunk_y))
	return result


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"stable_id": String(stable_id),
		"coordinate": {"x": coordinate.x, "y": coordinate.y},
		"world_bounds": FoundationSpatialRecord._rect_to_dict(world_bounds),
		"chunk_bounds": {
			"x": chunk_bounds.position.x,
			"y": chunk_bounds.position.y,
			"width": chunk_bounds.size.x,
			"height": chunk_bounds.size.y,
		},
		"tags": Array(tags),
		"metadata": metadata.duplicate(true),
		"generation_state": generation_state,
	}


static func from_dict(data: Dictionary) -> FoundationRegionData:
	var coordinate_data: Dictionary = data.get("coordinate", {})
	var chunk_data: Dictionary = data.get("chunk_bounds", {})
	var region := FoundationRegionData.new(
		Vector2i(int(coordinate_data.get("x", 0)), int(coordinate_data.get("y", 0))),
		FoundationSpatialRecord._rect_from_dict(data.get("world_bounds", {})),
		Rect2i(
			int(chunk_data.get("x", 0)),
			int(chunk_data.get("y", 0)),
			int(chunk_data.get("width", 0)),
			int(chunk_data.get("height", 0))
		)
	)
	region.stable_id = StringName(data.get("stable_id", String(region.stable_id)))
	region.tags = PackedStringArray(data.get("tags", []))
	region.metadata = data.get("metadata", {}).duplicate(true)
	region.generation_state = int(data.get("generation_state", GenerationState.UNINITIALIZED)) as GenerationState
	return region
