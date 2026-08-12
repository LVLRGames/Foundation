class_name FoundationDistrictGenerationProfile
extends RefCounted

## Explicit deterministic Phase 8 allocation and planning-policy inputs.

const FORMAT_VERSION := 1
const STREAM_SEED_PRIORITY: StringName = &"district_seed_priority"
const STREAM_CHARACTER: StringName = &"district_character"
const STREAM_MEMBER_USE: StringName = &"district_member_use"
const STREAM_POLICY_VARIATION: StringName = &"district_policy_variation"

var generator_version := 1
var policy_id: StringName = &"foundation_district_policy_v1"
var target_blocks_per_district := 3
var maximum_blocks_per_district := 5
var maximum_district_area := 160000.0
var maximum_neighbor_expansion_operations := 50000
var shared_boundary_weight := 1.0
var local_crossing_penalty := 0.0
var collector_crossing_penalty := 8.0
var arterial_crossing_penalty := 96.0
var highway_crossing_penalty := 256.0
var anchor_influence_weight := 80.0
var pattern_influence_weight := 48.0
var density_evidence_weight := 12.0
var geometric_tolerance := 0.01
var maximum_generation_operations := 250000
var debug_elevation_offset := 0.46
var anchor_character_preferences: Dictionary = {}
var pattern_character_preferences: Dictionary = {}
var character_policies: Dictionary = {}


func _init() -> void:
	anchor_character_preferences = {
		String(FoundationCityAnchor.CATEGORY_CITY_CENTER): String(FoundationDistrictRecord.CHARACTER_DOWNTOWN),
		String(FoundationCityAnchor.CATEGORY_CIVIC_CENTER): String(FoundationDistrictRecord.CHARACTER_CIVIC),
		String(FoundationCityAnchor.CATEGORY_PUBLIC_SQUARE): String(FoundationDistrictRecord.CHARACTER_CIVIC),
		String(FoundationCityAnchor.CATEGORY_INDUSTRIAL_CENTER): String(FoundationDistrictRecord.CHARACTER_INDUSTRIAL),
		String(FoundationCityAnchor.CATEGORY_COMMERCIAL_CENTER): String(FoundationDistrictRecord.CHARACTER_MIXED_USE),
		String(FoundationCityAnchor.CATEGORY_TRANSIT_NODE): String(FoundationDistrictRecord.CHARACTER_MIXED_USE),
	}
	pattern_character_preferences = {
		String(FoundationRoadPatternArea.DOWNTOWN_GRID): String(FoundationDistrictRecord.CHARACTER_DOWNTOWN),
		String(FoundationRoadPatternArea.MIXED_USE_GRID): String(FoundationDistrictRecord.CHARACTER_MIXED_USE),
		String(FoundationRoadPatternArea.INDUSTRIAL_RECTILINEAR): String(FoundationDistrictRecord.CHARACTER_INDUSTRIAL),
		String(FoundationRoadPatternArea.SUBURBAN_LOOPS): String(FoundationDistrictRecord.CHARACTER_SUBURBAN),
		String(FoundationRoadPatternArea.TRAILER_PARK_SPINE): String(FoundationDistrictRecord.CHARACTER_SUBURBAN),
		String(FoundationRoadPatternArea.RURAL_TERRAIN_FOLLOWING): String(FoundationDistrictRecord.CHARACTER_RURAL),
	}
	character_policies = {
		String(FoundationDistrictRecord.CHARACTER_DOWNTOWN): _policy(0.90, 12.0, 96.0, 0.95, 0.08, 0.75),
		String(FoundationDistrictRecord.CHARACTER_MIXED_USE): _policy(0.72, 6.0, 48.0, 0.78, 0.12, 0.60),
		String(FoundationDistrictRecord.CHARACTER_INDUSTRIAL): _policy(0.58, 5.0, 32.0, 0.82, 0.10, 0.10),
		String(FoundationDistrictRecord.CHARACTER_CIVIC): _policy(0.48, 4.0, 36.0, 0.60, 0.28, 0.25),
		String(FoundationDistrictRecord.CHARACTER_SUBURBAN): _policy(0.30, 3.0, 18.0, 0.34, 0.30, 0.12),
		String(FoundationDistrictRecord.CHARACTER_RURAL): _policy(0.12, 3.0, 12.0, 0.16, 0.55, 0.04),
		String(FoundationDistrictRecord.CHARACTER_RESIDENTIAL): _policy(0.44, 3.0, 24.0, 0.50, 0.22, 0.18),
	}


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if generator_version <= 0 or String(policy_id).is_empty():
		errors.append("District generator version and policy identity must be defined.")
	if target_blocks_per_district <= 0 or maximum_blocks_per_district < target_blocks_per_district:
		errors.append("District block-count limits are invalid.")
	if maximum_district_area <= 0.0:
		errors.append("Maximum district area must be positive.")
	if maximum_neighbor_expansion_operations <= 0 or maximum_generation_operations <= 0:
		errors.append("District operation caps must be positive.")
	if minf(shared_boundary_weight, minf(anchor_influence_weight, pattern_influence_weight)) < 0.0:
		errors.append("District influence weights cannot be negative.")
	if minf(local_crossing_penalty, minf(collector_crossing_penalty, minf(arterial_crossing_penalty, highway_crossing_penalty))) < 0.0:
		errors.append("District road-crossing penalties cannot be negative.")
	if geometric_tolerance <= 0.0:
		errors.append("District geometric tolerance must be positive.")
	for character in FoundationDistrictRecord.builtin_characters():
		if not character_policies.has(String(character)):
			errors.append("District character policy is missing: %s." % character)
	return errors


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"generator_version": generator_version,
		"policy_id": String(policy_id),
		"target_blocks_per_district": target_blocks_per_district,
		"maximum_blocks_per_district": maximum_blocks_per_district,
		"maximum_district_area": maximum_district_area,
		"maximum_neighbor_expansion_operations": maximum_neighbor_expansion_operations,
		"shared_boundary_weight": shared_boundary_weight,
		"local_crossing_penalty": local_crossing_penalty,
		"collector_crossing_penalty": collector_crossing_penalty,
		"arterial_crossing_penalty": arterial_crossing_penalty,
		"highway_crossing_penalty": highway_crossing_penalty,
		"anchor_influence_weight": anchor_influence_weight,
		"pattern_influence_weight": pattern_influence_weight,
		"density_evidence_weight": density_evidence_weight,
		"geometric_tolerance": geometric_tolerance,
		"maximum_generation_operations": maximum_generation_operations,
		"debug_elevation_offset": debug_elevation_offset,
		"anchor_character_preferences": _serialize_name_map(anchor_character_preferences),
		"pattern_character_preferences": _serialize_name_map(pattern_character_preferences),
		"character_policies": _serialize_character_policies(character_policies),
		"characters": _string_array(FoundationDistrictRecord.builtin_characters()),
		"uses": _string_array(FoundationDistrictRecord.builtin_uses()),
		"seed_streams": _string_array([STREAM_SEED_PRIORITY, STREAM_CHARACTER, STREAM_MEMBER_USE, STREAM_POLICY_VARIATION]),
	}


static func from_dict(data: Dictionary) -> FoundationDistrictGenerationProfile:
	var profile := FoundationDistrictGenerationProfile.new()
	profile.generator_version = int(data.get("generator_version", 1))
	profile.policy_id = StringName(data.get("policy_id", "foundation_district_policy_v1"))
	profile.target_blocks_per_district = int(data.get("target_blocks_per_district", 3))
	profile.maximum_blocks_per_district = int(data.get("maximum_blocks_per_district", 5))
	profile.maximum_district_area = float(data.get("maximum_district_area", 160000.0))
	profile.maximum_neighbor_expansion_operations = int(data.get("maximum_neighbor_expansion_operations", 50000))
	profile.shared_boundary_weight = float(data.get("shared_boundary_weight", 1.0))
	profile.local_crossing_penalty = float(data.get("local_crossing_penalty", 0.0))
	profile.collector_crossing_penalty = float(data.get("collector_crossing_penalty", 8.0))
	profile.arterial_crossing_penalty = float(data.get("arterial_crossing_penalty", 96.0))
	profile.highway_crossing_penalty = float(data.get("highway_crossing_penalty", 256.0))
	profile.anchor_influence_weight = float(data.get("anchor_influence_weight", 80.0))
	profile.pattern_influence_weight = float(data.get("pattern_influence_weight", 48.0))
	profile.density_evidence_weight = float(data.get("density_evidence_weight", 12.0))
	profile.geometric_tolerance = float(data.get("geometric_tolerance", 0.01))
	profile.maximum_generation_operations = int(data.get("maximum_generation_operations", 250000))
	profile.debug_elevation_offset = float(data.get("debug_elevation_offset", 0.46))
	if data.get("anchor_character_preferences", null) is Array:
		profile.anchor_character_preferences = _deserialize_name_map(data.get("anchor_character_preferences", []))
	if data.get("pattern_character_preferences", null) is Array:
		profile.pattern_character_preferences = _deserialize_name_map(data.get("pattern_character_preferences", []))
	if data.get("character_policies", null) is Array:
		profile.character_policies.clear()
		for entry: Dictionary in data.get("character_policies", []):
			var character := String(entry.get("character", ""))
			var policy: Dictionary = entry.get("policy", {}).duplicate(true)
			profile.character_policies[character] = policy
	return profile


static func _string_array(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result


static func _policy(density: float, minimum_height: float, maximum_height: float, intensity: float, open_space: float, mixed_use: float) -> Dictionary:
	return {
		"density": density, "minimum_height": minimum_height, "maximum_height": maximum_height,
		"intensity": intensity, "open_space": open_space, "mixed_use": mixed_use,
	}


static func _serialize_name_map(values: Dictionary) -> Array[Dictionary]:
	var keys: Array[String] = []
	for key in values:
		keys.append(String(key))
	keys.sort()
	var result: Array[Dictionary] = []
	for key in keys:
		result.append({"input": key, "character": String(values[key])})
	return result


static func _deserialize_name_map(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in values:
		result[String(entry.get("input", ""))] = String(entry.get("character", ""))
	return result


static func _serialize_character_policies(values: Dictionary) -> Array[Dictionary]:
	var keys: Array[String] = []
	for key in values:
		keys.append(String(key))
	keys.sort()
	var result: Array[Dictionary] = []
	for key in keys:
		result.append({"character": key, "policy": (values[key] as Dictionary).duplicate(true)})
	return result
