class_name FoundationBlockBoundaryReference
extends RefCounted

## Provenance for one source-road fragment contributing to a canonical block side.

const FORMAT_VERSION := 1

var boundary_segment_index := 0
var road_edge_id: StringName
var source_segment_index := 0
var source_t_start := 0.0
var source_t_end := 1.0
var frontage_length := 0.0


func _init(
	p_boundary_segment_index := 0,
	p_road_edge_id: StringName = &"",
	p_source_segment_index := 0,
	p_source_t_start := 0.0,
	p_source_t_end := 1.0,
	p_frontage_length := 0.0
) -> void:
	boundary_segment_index = p_boundary_segment_index
	road_edge_id = p_road_edge_id
	source_segment_index = p_source_segment_index
	source_t_start = p_source_t_start
	source_t_end = p_source_t_end
	frontage_length = p_frontage_length


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"boundary_segment_index": boundary_segment_index,
		"road_edge_id": String(road_edge_id),
		"source_segment_index": source_segment_index,
		"source_t_start": source_t_start,
		"source_t_end": source_t_end,
		"frontage_length": frontage_length,
	}


static func from_dict(data: Dictionary) -> FoundationBlockBoundaryReference:
	return FoundationBlockBoundaryReference.new(
		int(data.get("boundary_segment_index", 0)),
		StringName(data.get("road_edge_id", "")),
		int(data.get("source_segment_index", 0)),
		float(data.get("source_t_start", 0.0)),
		float(data.get("source_t_end", 1.0)),
		float(data.get("frontage_length", 0.0))
	)


static func less(a: FoundationBlockBoundaryReference, b: FoundationBlockBoundaryReference) -> bool:
	if a.boundary_segment_index != b.boundary_segment_index:
		return a.boundary_segment_index < b.boundary_segment_index
	if a.road_edge_id != b.road_edge_id:
		return String(a.road_edge_id) < String(b.road_edge_id)
	if a.source_segment_index != b.source_segment_index:
		return a.source_segment_index < b.source_segment_index
	if not is_equal_approx(a.source_t_start, b.source_t_start):
		return a.source_t_start < b.source_t_start
	return a.source_t_end < b.source_t_end
