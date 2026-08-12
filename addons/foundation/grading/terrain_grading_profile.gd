class_name FoundationTerrainGradingProfile
extends RefCounted

## Explicit deterministic Phase 9 terrain-grading policy. Owns no terrain or scene nodes.

const FORMAT_VERSION := 1

var generator_version := 1
var road_half_widths: Dictionary = {
	String(FoundationRoadEdge.CLASS_HIGHWAY): 7.5,
	String(FoundationRoadEdge.CLASS_ARTERIAL): 6.0,
	String(FoundationRoadEdge.CLASS_COLLECTOR): 5.0,
	String(FoundationRoadEdge.CLASS_LOCAL): 4.0,
	String(FoundationRoadEdge.CLASS_ALLEY): 2.5,
	String(FoundationRoadEdge.CLASS_DIRT): 3.0,
}
var road_priorities: Dictionary = {
	String(FoundationRoadEdge.CLASS_HIGHWAY): 180,
	String(FoundationRoadEdge.CLASS_ARTERIAL): 170,
	String(FoundationRoadEdge.CLASS_COLLECTOR): 160,
	String(FoundationRoadEdge.CLASS_LOCAL): 150,
	String(FoundationRoadEdge.CLASS_ALLEY): 140,
	String(FoundationRoadEdge.CLASS_DIRT): 130,
}
var road_blend_width := 6.0
var building_pad_apron := 1.0
var building_pad_blend_width := 6.0
var building_pad_priority := 300
var bridge_approach_priority_bonus := 50
var maximum_cut_depth := 8.0
var maximum_fill_height := 8.0
var bridge_clearance := 4.0
var bridge_approach_length := 20.0
var allow_protected_grading := false
var allow_water_grading := false
var maximum_candidate_vertices := 250000
var geometric_tolerance := 0.001
var debug_elevation_offset := 0.62


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if generator_version <= 0:
		errors.append("Terrain-grading generator version must be positive.")
	for road_class in _road_classes():
		if float(road_half_widths.get(String(road_class), 0.0)) <= 0.0:
			errors.append("Road half-widths must be positive for every supported road class.")
		if int(road_priorities.get(String(road_class), 0)) <= 0:
			errors.append("Road priorities must be positive for every supported road class.")
	if road_blend_width < 0.0 or building_pad_apron < 0.0 or building_pad_blend_width < 0.0:
		errors.append("Terrain-grading blend and apron distances cannot be negative.")
	if building_pad_priority <= 0 or bridge_approach_priority_bonus < 0:
		errors.append("Terrain-grading priorities are invalid.")
	if maximum_cut_depth < 0.0 or maximum_fill_height < 0.0:
		errors.append("Terrain-grading cut/fill limits cannot be negative.")
	if bridge_clearance < 0.0 or bridge_approach_length < 0.0:
		errors.append("Bridge clearance and approach length cannot be negative.")
	if maximum_candidate_vertices <= 0:
		errors.append("Terrain-grading candidate-vertex cap must be positive.")
	if geometric_tolerance <= 0.0:
		errors.append("Terrain-grading geometric tolerance must be positive.")
	return errors


func road_half_width_for(road_class: StringName) -> float:
	return float(road_half_widths.get(String(road_class), road_half_widths.get(String(FoundationRoadEdge.CLASS_LOCAL), 4.0)))


func road_priority_for(road_class: StringName) -> int:
	return int(road_priorities.get(String(road_class), road_priorities.get(String(FoundationRoadEdge.CLASS_LOCAL), 150)))


func to_dict() -> Dictionary:
	var policies: Array[Dictionary] = []
	for road_class in _road_classes():
		policies.append({
			"road_class": String(road_class),
			"half_width": road_half_width_for(road_class),
			"priority": road_priority_for(road_class),
		})
	return {
		"format_version": FORMAT_VERSION,
		"generator_version": generator_version,
		"road_policies": policies,
		"road_blend_width": road_blend_width,
		"building_pad_apron": building_pad_apron,
		"building_pad_blend_width": building_pad_blend_width,
		"building_pad_priority": building_pad_priority,
		"bridge_approach_priority_bonus": bridge_approach_priority_bonus,
		"maximum_cut_depth": maximum_cut_depth,
		"maximum_fill_height": maximum_fill_height,
		"bridge_clearance": bridge_clearance,
		"bridge_approach_length": bridge_approach_length,
		"allow_protected_grading": allow_protected_grading,
		"allow_water_grading": allow_water_grading,
		"maximum_candidate_vertices": maximum_candidate_vertices,
		"geometric_tolerance": geometric_tolerance,
		"debug_elevation_offset": debug_elevation_offset,
	}


static func from_dict(data: Dictionary) -> FoundationTerrainGradingProfile:
	var profile := FoundationTerrainGradingProfile.new()
	profile.generator_version = int(data.get("generator_version", 1))
	for policy_data: Dictionary in data.get("road_policies", []):
		var road_class := String(policy_data.get("road_class", ""))
		if road_class.is_empty():
			continue
		profile.road_half_widths[road_class] = float(policy_data.get("half_width", 4.0))
		profile.road_priorities[road_class] = int(policy_data.get("priority", 150))
	profile.road_blend_width = float(data.get("road_blend_width", 6.0))
	profile.building_pad_apron = float(data.get("building_pad_apron", 1.0))
	profile.building_pad_blend_width = float(data.get("building_pad_blend_width", 6.0))
	profile.building_pad_priority = int(data.get("building_pad_priority", 300))
	profile.bridge_approach_priority_bonus = int(data.get("bridge_approach_priority_bonus", 50))
	profile.maximum_cut_depth = float(data.get("maximum_cut_depth", 8.0))
	profile.maximum_fill_height = float(data.get("maximum_fill_height", 8.0))
	profile.bridge_clearance = float(data.get("bridge_clearance", 4.0))
	profile.bridge_approach_length = float(data.get("bridge_approach_length", 20.0))
	profile.allow_protected_grading = bool(data.get("allow_protected_grading", false))
	profile.allow_water_grading = bool(data.get("allow_water_grading", false))
	profile.maximum_candidate_vertices = int(data.get("maximum_candidate_vertices", 250000))
	profile.geometric_tolerance = float(data.get("geometric_tolerance", 0.001))
	profile.debug_elevation_offset = float(data.get("debug_elevation_offset", 0.62))
	return profile


static func _road_classes() -> Array[StringName]:
	return [
		FoundationRoadEdge.CLASS_HIGHWAY,
		FoundationRoadEdge.CLASS_ARTERIAL,
		FoundationRoadEdge.CLASS_COLLECTOR,
		FoundationRoadEdge.CLASS_LOCAL,
		FoundationRoadEdge.CLASS_ALLEY,
		FoundationRoadEdge.CLASS_DIRT,
	]
