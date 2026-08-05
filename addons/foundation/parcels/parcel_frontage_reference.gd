class_name FoundationParcelFrontageReference
extends RefCounted

## Road-backed provenance for one parcel boundary fragment.

const FORMAT_VERSION := 1
const CLASS_PRIMARY: StringName = &"primary"
const CLASS_SECONDARY: StringName = &"secondary"

var parcel_boundary_segment_index := 0
var block_boundary_segment_index := 0
var road_edge_id: StringName
var logical_road_id: StringName
var source_t_start := 0.0
var source_t_end := 1.0
var frontage_length := 0.0
var frontage_classification: StringName = CLASS_SECONDARY


func _init(
	p_parcel_boundary_segment_index := 0,
	p_block_boundary_segment_index := 0,
	p_road_edge_id: StringName = &"",
	p_logical_road_id: StringName = &"",
	p_source_t_start := 0.0,
	p_source_t_end := 1.0,
	p_frontage_length := 0.0,
	p_frontage_classification: StringName = CLASS_SECONDARY
) -> void:
	parcel_boundary_segment_index = p_parcel_boundary_segment_index
	block_boundary_segment_index = p_block_boundary_segment_index
	road_edge_id = p_road_edge_id
	logical_road_id = p_logical_road_id
	source_t_start = p_source_t_start
	source_t_end = p_source_t_end
	frontage_length = p_frontage_length
	frontage_classification = p_frontage_classification


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"parcel_boundary_segment_index": parcel_boundary_segment_index,
		"block_boundary_segment_index": block_boundary_segment_index,
		"road_edge_id": String(road_edge_id),
		"logical_road_id": String(logical_road_id),
		"source_t_start": source_t_start,
		"source_t_end": source_t_end,
		"frontage_length": frontage_length,
		"frontage_classification": String(frontage_classification),
	}


static func from_dict(data: Dictionary) -> FoundationParcelFrontageReference:
	return FoundationParcelFrontageReference.new(
		int(data.get("parcel_boundary_segment_index", 0)),
		int(data.get("block_boundary_segment_index", 0)),
		StringName(data.get("road_edge_id", "")),
		StringName(data.get("logical_road_id", "")),
		float(data.get("source_t_start", 0.0)),
		float(data.get("source_t_end", 1.0)),
		float(data.get("frontage_length", 0.0)),
		StringName(data.get("frontage_classification", String(CLASS_SECONDARY)))
	)


static func less(a: FoundationParcelFrontageReference, b: FoundationParcelFrontageReference) -> bool:
	if a.parcel_boundary_segment_index != b.parcel_boundary_segment_index:
		return a.parcel_boundary_segment_index < b.parcel_boundary_segment_index
	if a.block_boundary_segment_index != b.block_boundary_segment_index:
		return a.block_boundary_segment_index < b.block_boundary_segment_index
	if a.road_edge_id != b.road_edge_id:
		return String(a.road_edge_id) < String(b.road_edge_id)
	if a.logical_road_id != b.logical_road_id:
		return String(a.logical_road_id) < String(b.logical_road_id)
	return a.source_t_start < b.source_t_start
