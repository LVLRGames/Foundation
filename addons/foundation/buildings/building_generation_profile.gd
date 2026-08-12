class_name FoundationBuildingGenerationProfile
extends RefCounted

## Explicit deterministic Phase 5 footprint and primitive-massing inputs.

const FORMAT_VERSION := 2
const STREAM_COVERAGE: StringName = &"building_footprint_coverage"
const STREAM_FLOOR_COUNT: StringName = &"building_floor_count"

var generator_version := 2
var front_setback := 4.0
var side_setback := 2.0
var rear_setback := 4.0
var corner_side_setback := 3.0
var minimum_footprint_area := 24.0
var minimum_coverage_ratio := 0.32
var maximum_coverage_ratio := 0.68
var maximum_footprint_depth := 40.0
var maximum_frontage_span := 48.0
var maximum_footprint_aspect_ratio := 3.0
var allow_long_form_massing := false
var minimum_floor_count := 1
var maximum_floor_count := 4
var floor_height := 3.2
var maximum_building_height := 24.0
var base_elevation := 0.0
var point_quantization := 0.01
var geometric_epsilon := 0.001
var coverage_search_iterations := 20
var maximum_generation_operations := 200000
var debug_elevation_offset := 0.34


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if generator_version <= 0:
		errors.append("Building generator version must be positive.")
	if front_setback < 0.0 or side_setback < 0.0 or rear_setback < 0.0 or corner_side_setback < 0.0:
		errors.append("Building setbacks cannot be negative.")
	if minimum_footprint_area <= 0.0:
		errors.append("Minimum building footprint area must be positive.")
	if minimum_coverage_ratio <= 0.0 or maximum_coverage_ratio < minimum_coverage_ratio or maximum_coverage_ratio > 1.0:
		errors.append("Building coverage limits are invalid.")
	if maximum_footprint_depth <= 0.0 or maximum_frontage_span <= 0.0:
		errors.append("Building footprint depth and frontage-span limits must be positive.")
	if maximum_footprint_aspect_ratio < 1.0:
		errors.append("Maximum building footprint aspect ratio must be at least one.")
	if minimum_floor_count <= 0 or maximum_floor_count < minimum_floor_count:
		errors.append("Building floor-count limits are invalid.")
	if floor_height <= 0.0 or maximum_building_height < floor_height:
		errors.append("Building height limits are invalid.")
	elif float(minimum_floor_count) * floor_height > maximum_building_height:
		errors.append("Minimum building floors exceed the maximum building height.")
	if point_quantization <= 0.0 or geometric_epsilon <= 0.0:
		errors.append("Building geometric tolerances must be positive.")
	if coverage_search_iterations <= 0:
		errors.append("Building coverage search iterations must be positive.")
	if maximum_generation_operations <= 0:
		errors.append("Maximum building generation operations must be positive.")
	return errors


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"generator_version": generator_version,
		"front_setback": front_setback,
		"side_setback": side_setback,
		"rear_setback": rear_setback,
		"corner_side_setback": corner_side_setback,
		"minimum_footprint_area": minimum_footprint_area,
		"minimum_coverage_ratio": minimum_coverage_ratio,
		"maximum_coverage_ratio": maximum_coverage_ratio,
		"maximum_footprint_depth": maximum_footprint_depth,
		"maximum_frontage_span": maximum_frontage_span,
		"maximum_footprint_aspect_ratio": maximum_footprint_aspect_ratio,
		"allow_long_form_massing": allow_long_form_massing,
		"minimum_floor_count": minimum_floor_count,
		"maximum_floor_count": maximum_floor_count,
		"floor_height": floor_height,
		"maximum_building_height": maximum_building_height,
		"base_elevation": base_elevation,
		"point_quantization": point_quantization,
		"geometric_epsilon": geometric_epsilon,
		"coverage_search_iterations": coverage_search_iterations,
		"maximum_generation_operations": maximum_generation_operations,
		"debug_elevation_offset": debug_elevation_offset,
		"seed_streams": [String(STREAM_COVERAGE), String(STREAM_FLOOR_COUNT)],
	}


static func from_dict(data: Dictionary) -> FoundationBuildingGenerationProfile:
	var profile := FoundationBuildingGenerationProfile.new()
	profile.generator_version = int(data.get("generator_version", 1))
	profile.front_setback = float(data.get("front_setback", 4.0))
	profile.side_setback = float(data.get("side_setback", 2.0))
	profile.rear_setback = float(data.get("rear_setback", 4.0))
	profile.corner_side_setback = float(data.get("corner_side_setback", 3.0))
	profile.minimum_footprint_area = float(data.get("minimum_footprint_area", 24.0))
	profile.minimum_coverage_ratio = float(data.get("minimum_coverage_ratio", 0.32))
	profile.maximum_coverage_ratio = float(data.get("maximum_coverage_ratio", 0.68))
	profile.maximum_footprint_depth = float(data.get("maximum_footprint_depth", 40.0))
	profile.maximum_frontage_span = float(data.get("maximum_frontage_span", 48.0))
	profile.maximum_footprint_aspect_ratio = float(data.get("maximum_footprint_aspect_ratio", 3.0))
	profile.allow_long_form_massing = bool(data.get("allow_long_form_massing", false))
	profile.minimum_floor_count = int(data.get("minimum_floor_count", 1))
	profile.maximum_floor_count = int(data.get("maximum_floor_count", 4))
	profile.floor_height = float(data.get("floor_height", 3.2))
	profile.maximum_building_height = float(data.get("maximum_building_height", 24.0))
	profile.base_elevation = float(data.get("base_elevation", 0.0))
	profile.point_quantization = float(data.get("point_quantization", 0.01))
	profile.geometric_epsilon = float(data.get("geometric_epsilon", 0.001))
	profile.coverage_search_iterations = int(data.get("coverage_search_iterations", 20))
	profile.maximum_generation_operations = int(data.get("maximum_generation_operations", 200000))
	profile.debug_elevation_offset = float(data.get("debug_elevation_offset", 0.34))
	return profile
