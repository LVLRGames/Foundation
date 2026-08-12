class_name FoundationSiteFeatureGenerationProfile
extends RefCounted

## Explicit deterministic Phase 10 parking and public-feature policy.

const FORMAT_VERSION := 1
const STREAM_PARKING_PRIORITY: StringName = &"parking_facility_priority"
const STREAM_PARKING_LAYOUT: StringName = &"parking_layout"
const STREAM_PUBLIC_PRIORITY: StringName = &"public_feature_priority"
const STREAM_PUBLIC_VARIATION: StringName = &"public_feature_variation"

var generator_version := 1
var policy_id: StringName = &"foundation_site_feature_policy_v1"
var demand_area_per_space: Dictionary = {}
var minimum_parking_demand := 2
var maximum_spaces_per_facility := 96
var parking_area_per_space := 31.0
var minimum_parking_area := 42.0
var maximum_parking_fraction := 0.42
var stall_width := 2.6
var stall_length := 5.2
var accessible_stall_width := 3.6
var accessible_ratio := 0.04
var aisle_width := 6.0
var site_clearance := 1.0
var public_feature_fraction := 0.18
var public_feature_fraction_by_use: Dictionary = {}
var minimum_public_feature_area := 25.0
var maximum_public_feature_area := 625.0
var public_service_radius := 180.0
var anchor_influence_distance := 220.0
var maximum_site_slope_degrees := 22.0
var maximum_site_elevation_delta := 6.0
var maximum_candidates_per_parcel := 144
var maximum_parking_facilities := 4096
var maximum_public_features := 2048
var maximum_generation_operations := 250000
var geometric_tolerance := 0.01
var point_quantization := 0.01
var debug_elevation_offset := 0.58


func _init() -> void:
	demand_area_per_space = {
		String(FoundationDistrictRecord.USE_RESIDENTIAL): 90.0,
		String(FoundationDistrictRecord.USE_COMMERCIAL): 55.0,
		String(FoundationDistrictRecord.USE_MIXED): 70.0,
		String(FoundationDistrictRecord.USE_INDUSTRIAL): 105.0,
		String(FoundationDistrictRecord.USE_CIVIC): 80.0,
		String(FoundationDistrictRecord.USE_INSTITUTIONAL): 85.0,
	}
	public_feature_fraction_by_use = {
		String(FoundationDistrictRecord.USE_OPEN_SPACE): 0.30,
		String(FoundationDistrictRecord.USE_CIVIC): 0.22,
		String(FoundationDistrictRecord.USE_INSTITUTIONAL): 0.14,
	}


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if generator_version <= 0 or String(policy_id).is_empty():
		errors.append("Site-feature generator version and policy identity must be defined.")
	if minimum_parking_demand < 0 or maximum_spaces_per_facility <= 0:
		errors.append("Parking demand and facility caps are invalid.")
	if minf(parking_area_per_space, minf(stall_width, minf(stall_length, aisle_width))) <= 0.0:
		errors.append("Parking dimensions must be positive.")
	if accessible_stall_width < stall_width or accessible_ratio < 0.0 or accessible_ratio > 1.0:
		errors.append("Accessible-space policy is invalid.")
	if maximum_parking_fraction <= 0.0 or maximum_parking_fraction > 1.0:
		errors.append("Maximum parking fraction must be in (0, 1].")
	if public_feature_fraction <= 0.0 or public_feature_fraction > 1.0:
		errors.append("Public-feature fraction must be in (0, 1].")
	for use_key in public_feature_fraction_by_use:
		var fraction := float(public_feature_fraction_by_use[use_key])
		if fraction <= 0.0 or fraction > 1.0:
			errors.append("Public-feature use ratios must be in (0, 1].")
	if minimum_public_feature_area <= 0.0 or maximum_public_feature_area < minimum_public_feature_area:
		errors.append("Public-feature area limits are invalid.")
	if maximum_candidates_per_parcel <= 0 or maximum_generation_operations <= 0:
		errors.append("Generation work caps must be positive.")
	if maximum_parking_facilities <= 0 or maximum_public_features <= 0:
		errors.append("Record caps must be positive.")
	if maximum_site_slope_degrees < 0.0 or maximum_site_slope_degrees > 90.0 or maximum_site_elevation_delta < 0.0:
		errors.append("Terrain suitability limits are invalid.")
	if geometric_tolerance <= 0.0 or point_quantization <= 0.0:
		errors.append("Geometry tolerances must be positive.")
	for use_key in demand_area_per_space:
		if float(demand_area_per_space[use_key]) <= 0.0:
			errors.append("Parking demand ratios must be positive.")
	return errors


func to_dict() -> Dictionary:
	var ratios: Array[Dictionary] = []
	var keys: Array[String] = []
	for key in demand_area_per_space:
		keys.append(String(key))
	keys.sort()
	for key in keys:
		ratios.append({"use": key, "area_per_space": float(demand_area_per_space[key])})
	var public_ratios: Array[Dictionary] = []
	var public_keys: Array[String] = []
	for key in public_feature_fraction_by_use:
		public_keys.append(String(key))
	public_keys.sort()
	for key in public_keys:
		public_ratios.append({"use": key, "fraction": float(public_feature_fraction_by_use[key])})
	return {
		"format_version": FORMAT_VERSION,
		"generator_version": generator_version,
		"policy_id": String(policy_id),
		"demand_area_per_space": ratios,
		"minimum_parking_demand": minimum_parking_demand,
		"maximum_spaces_per_facility": maximum_spaces_per_facility,
		"parking_area_per_space": parking_area_per_space,
		"minimum_parking_area": minimum_parking_area,
		"maximum_parking_fraction": maximum_parking_fraction,
		"stall_width": stall_width,
		"stall_length": stall_length,
		"accessible_stall_width": accessible_stall_width,
		"accessible_ratio": accessible_ratio,
		"aisle_width": aisle_width,
		"site_clearance": site_clearance,
		"public_feature_fraction": public_feature_fraction,
		"public_feature_fraction_by_use": public_ratios,
		"minimum_public_feature_area": minimum_public_feature_area,
		"maximum_public_feature_area": maximum_public_feature_area,
		"public_service_radius": public_service_radius,
		"anchor_influence_distance": anchor_influence_distance,
		"maximum_site_slope_degrees": maximum_site_slope_degrees,
		"maximum_site_elevation_delta": maximum_site_elevation_delta,
		"maximum_candidates_per_parcel": maximum_candidates_per_parcel,
		"maximum_parking_facilities": maximum_parking_facilities,
		"maximum_public_features": maximum_public_features,
		"maximum_generation_operations": maximum_generation_operations,
		"geometric_tolerance": geometric_tolerance,
		"point_quantization": point_quantization,
		"debug_elevation_offset": debug_elevation_offset,
		"parking_kinds": _names(FoundationParkingFacilityRecord.builtin_kinds()),
		"public_feature_kinds": _names(FoundationPublicFeatureRecord.builtin_kinds()),
		"seed_streams": _names([STREAM_PARKING_PRIORITY, STREAM_PARKING_LAYOUT, STREAM_PUBLIC_PRIORITY, STREAM_PUBLIC_VARIATION]),
	}


static func from_dict(data: Dictionary) -> FoundationSiteFeatureGenerationProfile:
	var profile := FoundationSiteFeatureGenerationProfile.new()
	profile.generator_version = int(data.get("generator_version", 1))
	profile.policy_id = StringName(data.get("policy_id", "foundation_site_feature_policy_v1"))
	if data.get("demand_area_per_space", null) is Array:
		profile.demand_area_per_space.clear()
		for entry: Dictionary in data.get("demand_area_per_space", []):
			profile.demand_area_per_space[String(entry.get("use", ""))] = float(entry.get("area_per_space", 1.0))
	profile.minimum_parking_demand = int(data.get("minimum_parking_demand", 2))
	profile.maximum_spaces_per_facility = int(data.get("maximum_spaces_per_facility", 96))
	profile.parking_area_per_space = float(data.get("parking_area_per_space", 31.0))
	profile.minimum_parking_area = float(data.get("minimum_parking_area", 42.0))
	profile.maximum_parking_fraction = float(data.get("maximum_parking_fraction", 0.42))
	profile.stall_width = float(data.get("stall_width", 2.6))
	profile.stall_length = float(data.get("stall_length", 5.2))
	profile.accessible_stall_width = float(data.get("accessible_stall_width", 3.6))
	profile.accessible_ratio = float(data.get("accessible_ratio", 0.04))
	profile.aisle_width = float(data.get("aisle_width", 6.0))
	profile.site_clearance = float(data.get("site_clearance", 1.0))
	profile.public_feature_fraction = float(data.get("public_feature_fraction", 0.18))
	if data.get("public_feature_fraction_by_use", null) is Array:
		profile.public_feature_fraction_by_use.clear()
		for entry: Dictionary in data.get("public_feature_fraction_by_use", []):
			profile.public_feature_fraction_by_use[String(entry.get("use", ""))] = float(entry.get("fraction", profile.public_feature_fraction))
	profile.minimum_public_feature_area = float(data.get("minimum_public_feature_area", 25.0))
	profile.maximum_public_feature_area = float(data.get("maximum_public_feature_area", 625.0))
	profile.public_service_radius = float(data.get("public_service_radius", 180.0))
	profile.anchor_influence_distance = float(data.get("anchor_influence_distance", 220.0))
	profile.maximum_site_slope_degrees = float(data.get("maximum_site_slope_degrees", 22.0))
	profile.maximum_site_elevation_delta = float(data.get("maximum_site_elevation_delta", 6.0))
	profile.maximum_candidates_per_parcel = int(data.get("maximum_candidates_per_parcel", 144))
	profile.maximum_parking_facilities = int(data.get("maximum_parking_facilities", 4096))
	profile.maximum_public_features = int(data.get("maximum_public_features", 2048))
	profile.maximum_generation_operations = int(data.get("maximum_generation_operations", 250000))
	profile.geometric_tolerance = float(data.get("geometric_tolerance", 0.01))
	profile.point_quantization = float(data.get("point_quantization", 0.01))
	profile.debug_elevation_offset = float(data.get("debug_elevation_offset", 0.58))
	return profile


static func _names(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result
