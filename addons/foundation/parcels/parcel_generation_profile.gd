class_name FoundationParcelGenerationProfile
extends RefCounted

## Explicit deterministic Phase 4 parcel-subdivision inputs.

const FORMAT_VERSION := 2
const STREAM_SPLIT_ORIENTATION: StringName = &"parcel_split_orientation"
const STREAM_SPLIT_SPACING: StringName = &"parcel_split_spacing"
const STREAM_FRONTAGE_PRIORITY: StringName = &"parcel_frontage_priority"
const STREAM_REMAINDER_RESOLUTION: StringName = &"parcel_remainder_resolution"

var generator_version := 2
var target_parcel_area := 900.0
var minimum_parcel_area := 100.0
var maximum_parcel_area := 2400.0
var preferred_frontage := 24.0
var minimum_frontage := 8.0
var maximum_frontage := 64.0
var preferred_depth := 32.0
var minimum_depth := 8.0
var maximum_depth := 48.0
var maximum_frontage_rows := 4
var maximum_buildable_aspect_ratio := 3.0
var allow_long_form_parcels := false
var point_quantization := 0.01
var geometric_epsilon := 0.001
var allow_corner_parcels := true
var non_buildable_remainder_threshold := 32.0
var maximum_subdivision_operations := 200000
var debug_elevation_offset := 0.24


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if generator_version <= 0:
		errors.append("Parcel generator version must be positive.")
	if target_parcel_area <= 0.0:
		errors.append("Target parcel area must be positive.")
	if minimum_parcel_area < 0.0 or maximum_parcel_area < minimum_parcel_area:
		errors.append("Parcel area limits are invalid.")
	if minimum_frontage < 0.0 or preferred_frontage < minimum_frontage or maximum_frontage < preferred_frontage:
		errors.append("Parcel frontage limits are invalid.")
	if minimum_depth < 0.0 or preferred_depth < minimum_depth or maximum_depth < preferred_depth:
		errors.append("Parcel depth limits are invalid.")
	if maximum_frontage_rows <= 0 or maximum_frontage_rows > 4:
		errors.append("Maximum frontage rows must be between one and four.")
	if maximum_buildable_aspect_ratio < 1.0:
		errors.append("Maximum buildable parcel aspect ratio must be at least one.")
	if point_quantization <= 0.0 or geometric_epsilon <= 0.0:
		errors.append("Parcel geometric tolerances must be positive.")
	if maximum_subdivision_operations <= 0:
		errors.append("Maximum subdivision operations must be positive.")
	return errors


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"generator_version": generator_version,
		"target_parcel_area": target_parcel_area,
		"minimum_parcel_area": minimum_parcel_area,
		"maximum_parcel_area": maximum_parcel_area,
		"preferred_frontage": preferred_frontage,
		"minimum_frontage": minimum_frontage,
		"maximum_frontage": maximum_frontage,
		"preferred_depth": preferred_depth,
		"minimum_depth": minimum_depth,
		"maximum_depth": maximum_depth,
		"maximum_frontage_rows": maximum_frontage_rows,
		"maximum_buildable_aspect_ratio": maximum_buildable_aspect_ratio,
		"allow_long_form_parcels": allow_long_form_parcels,
		"point_quantization": point_quantization,
		"geometric_epsilon": geometric_epsilon,
		"allow_corner_parcels": allow_corner_parcels,
		"non_buildable_remainder_threshold": non_buildable_remainder_threshold,
		"maximum_subdivision_operations": maximum_subdivision_operations,
		"debug_elevation_offset": debug_elevation_offset,
		"seed_streams": [
			String(STREAM_SPLIT_ORIENTATION), String(STREAM_SPLIT_SPACING),
			String(STREAM_FRONTAGE_PRIORITY), String(STREAM_REMAINDER_RESOLUTION),
		],
	}


static func from_dict(data: Dictionary) -> FoundationParcelGenerationProfile:
	var profile := FoundationParcelGenerationProfile.new()
	profile.generator_version = int(data.get("generator_version", 1))
	profile.target_parcel_area = float(data.get("target_parcel_area", 900.0))
	profile.minimum_parcel_area = float(data.get("minimum_parcel_area", 100.0))
	profile.maximum_parcel_area = float(data.get("maximum_parcel_area", 2400.0))
	profile.preferred_frontage = float(data.get("preferred_frontage", 24.0))
	profile.minimum_frontage = float(data.get("minimum_frontage", 8.0))
	profile.maximum_frontage = float(data.get("maximum_frontage", 64.0))
	profile.preferred_depth = float(data.get("preferred_depth", 32.0))
	profile.minimum_depth = float(data.get("minimum_depth", 8.0))
	profile.maximum_depth = float(data.get("maximum_depth", 48.0))
	profile.maximum_frontage_rows = int(data.get("maximum_frontage_rows", 4))
	profile.maximum_buildable_aspect_ratio = float(data.get("maximum_buildable_aspect_ratio", 3.0))
	profile.allow_long_form_parcels = bool(data.get("allow_long_form_parcels", false))
	profile.point_quantization = float(data.get("point_quantization", 0.01))
	profile.geometric_epsilon = float(data.get("geometric_epsilon", 0.001))
	profile.allow_corner_parcels = bool(data.get("allow_corner_parcels", true))
	profile.non_buildable_remainder_threshold = float(data.get("non_buildable_remainder_threshold", 32.0))
	profile.maximum_subdivision_operations = int(data.get("maximum_subdivision_operations", 200000))
	profile.debug_elevation_offset = float(data.get("debug_elevation_offset", 0.24))
	return profile
