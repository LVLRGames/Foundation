class_name FoundationRoadPatternArea
extends FoundationSpatialRecord

## Minimal Phase 2 district-style road-pattern input. It generates topology, not districts.

const ROAD_PATTERN_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"road_pattern_area"
const ENTITY_TYPE: StringName = &"road_pattern_area"
const LAYER_TYPE: StringName = &"road_pattern_areas"

const DOWNTOWN_GRID: StringName = &"downtown_grid"
const MIXED_USE_GRID: StringName = &"mixed_use_grid"
const SUBURBAN_LOOPS: StringName = &"suburban_loops_and_branches"
const INDUSTRIAL_RECTILINEAR: StringName = &"industrial_large_block_rectilinear"
const RURAL_TERRAIN_FOLLOWING: StringName = &"rural_terrain_following"
const TRAILER_PARK_SPINE: StringName = &"trailer_park_loop_spine"
const CUSTOM_CORRIDOR: StringName = &"custom_authored_corridor"

var pattern_family: StringName = DOWNTOWN_GRID
var preferred_orientation_degrees := 0.0
var grid_strength := 1.0
var preferred_spacing := 32.0
var minimum_segment_length := 12.0
var maximum_segment_length := 96.0
var curvature_allowance := 0.0
var diagonal_allowance := 0.0
var loop_preference := 0.5
var branching_preference := 0.5
var cul_de_sac_probability := 0.0
var minimum_intersection_spacing := 12.0
var maximum_intersection_spacing := 96.0
var terrain_following_strength := 0.5
var road_class_weights: Dictionary = {}


func _init(
	p_stable_id: StringName = &"",
	p_bounds := Rect2(),
	p_family: StringName = DOWNTOWN_GRID
) -> void:
	super(p_stable_id, ENTITY_TYPE, LAYER_TYPE, p_bounds)
	pattern_family = p_family
	road_class_weights = {
		String(FoundationRoadEdge.CLASS_COLLECTOR): 0.35,
		String(FoundationRoadEdge.CLASS_LOCAL): 0.55,
		String(FoundationRoadEdge.CLASS_DIRT): 0.10,
	}


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(pattern_family).is_empty():
		errors.append("Road-pattern family cannot be empty.")
	if world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		errors.append("Road-pattern areas require positive bounds.")
	if preferred_spacing <= 0.0:
		errors.append("Preferred road spacing must be positive.")
	if minimum_segment_length <= 0.0 or maximum_segment_length < minimum_segment_length:
		errors.append("Road-pattern segment limits are invalid.")
	if minimum_intersection_spacing <= 0.0 or maximum_intersection_spacing < minimum_intersection_spacing:
		errors.append("Road-pattern intersection spacing is invalid.")
	if (
		world_bounds.size.x < minimum_intersection_spacing * 2.0
		or world_bounds.size.y < minimum_intersection_spacing * 2.0
	):
		errors.append("Road-pattern bounds are too small for the configured intersection spacing.")
	return errors


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["record_kind"] = String(RECORD_KIND)
	data["road_pattern_format_version"] = ROAD_PATTERN_FORMAT_VERSION
	data["pattern_family"] = String(pattern_family)
	data["preferred_orientation_degrees"] = preferred_orientation_degrees
	data["grid_strength"] = grid_strength
	data["preferred_spacing"] = preferred_spacing
	data["minimum_segment_length"] = minimum_segment_length
	data["maximum_segment_length"] = maximum_segment_length
	data["curvature_allowance"] = curvature_allowance
	data["diagonal_allowance"] = diagonal_allowance
	data["loop_preference"] = loop_preference
	data["branching_preference"] = branching_preference
	data["cul_de_sac_probability"] = cul_de_sac_probability
	data["minimum_intersection_spacing"] = minimum_intersection_spacing
	data["maximum_intersection_spacing"] = maximum_intersection_spacing
	data["terrain_following_strength"] = terrain_following_strength
	var serialized_weights: Array[Dictionary] = []
	var weight_keys: Array[String] = []
	for key in road_class_weights:
		weight_keys.append(String(key))
	weight_keys.sort()
	for key in weight_keys:
		serialized_weights.append({
			"road_class": key,
			"weight": float(road_class_weights.get(key, road_class_weights.get(StringName(key), 0.0))),
		})
	data["road_class_weights"] = serialized_weights
	return data


static func from_dict(data: Dictionary) -> FoundationRoadPatternArea:
	var base_bounds := FoundationSpatialRecord._rect_from_dict(data.get("world_bounds", {}))
	var area := FoundationRoadPatternArea.new(
		StringName(data.get("stable_id", "")),
		base_bounds,
		StringName(data.get("pattern_family", String(DOWNTOWN_GRID)))
	)
	FoundationSpatialRecord.apply_serialized_fields(area, data)
	area.entity_type = ENTITY_TYPE
	area.layer_type = LAYER_TYPE
	area.preferred_orientation_degrees = float(data.get("preferred_orientation_degrees", 0.0))
	area.grid_strength = float(data.get("grid_strength", 1.0))
	area.preferred_spacing = float(data.get("preferred_spacing", 32.0))
	area.minimum_segment_length = float(data.get("minimum_segment_length", 12.0))
	area.maximum_segment_length = float(data.get("maximum_segment_length", 96.0))
	area.curvature_allowance = float(data.get("curvature_allowance", 0.0))
	area.diagonal_allowance = float(data.get("diagonal_allowance", 0.0))
	area.loop_preference = float(data.get("loop_preference", 0.5))
	area.branching_preference = float(data.get("branching_preference", 0.5))
	area.cul_de_sac_probability = float(data.get("cul_de_sac_probability", 0.0))
	area.minimum_intersection_spacing = float(data.get("minimum_intersection_spacing", 12.0))
	area.maximum_intersection_spacing = float(data.get("maximum_intersection_spacing", 96.0))
	area.terrain_following_strength = float(data.get("terrain_following_strength", 0.5))
	if data.get("road_class_weights", null) is Array:
		area.road_class_weights.clear()
		for weight_data: Dictionary in data.get("road_class_weights", []):
			area.road_class_weights[String(weight_data.get("road_class", ""))] = float(weight_data.get("weight", 0.0))
	elif data.get("road_class_weights", null) is Dictionary:
		area.road_class_weights = data.get("road_class_weights", {}).duplicate(true)
	return area


static func create(
	metadata: FoundationWorldMetadata,
	semantic_key: String,
	bounds: Rect2,
	family: StringName
) -> FoundationRoadPatternArea:
	var stable_id := FoundationSpatialId.make(
		metadata.seed,
		metadata.generator_version,
		metadata.content_pack_version,
		ENTITY_TYPE,
		&"",
		"%s|%s" % [family, semantic_key]
	)
	return FoundationRoadPatternArea.new(stable_id, bounds, family)
