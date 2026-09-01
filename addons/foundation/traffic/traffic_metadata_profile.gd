class_name FoundationTrafficMetadataProfile
extends RefCounted

## Explicit bounded Phase 13 road cross-section and intersection-control policy.

const FORMAT_VERSION := 1

var policy_id: StringName = &"foundation_right_hand_traffic_v1"
var generator_version := 1
var geometric_tolerance := 0.001
var debug_elevation_offset := 0.72
var default_lane_width := 3.2
var alley_lane_width := 2.8
var highway_lane_width := 3.6
var median_width_divided := 3.0
var shoulder_width_highway := 2.4
var sidewalk_width_urban := 1.8
var maximum_cross_sections := 16384
var maximum_intersection_records := 4096
var maximum_lanes_per_edge := 8
var maximum_movements_per_intersection := 96
var maximum_generation_operations := 500000
var signal_minimum_degree := 4
var enable_signal_plans := true


func lane_count_per_direction(road_class: StringName) -> int:
	match road_class:
		FoundationRoadEdge.CLASS_HIGHWAY, FoundationRoadEdge.CLASS_ARTERIAL:
			return 2
		_:
			return 1


func lane_width_for(road_class: StringName) -> float:
	match road_class:
		FoundationRoadEdge.CLASS_HIGHWAY:
			return highway_lane_width
		FoundationRoadEdge.CLASS_ALLEY:
			return alley_lane_width
		_:
			return default_lane_width


func speed_limit_for(road_class: StringName) -> float:
	match road_class:
		FoundationRoadEdge.CLASS_HIGHWAY: return 100.0
		FoundationRoadEdge.CLASS_ARTERIAL: return 60.0
		FoundationRoadEdge.CLASS_COLLECTOR: return 50.0
		FoundationRoadEdge.CLASS_LOCAL: return 35.0
		FoundationRoadEdge.CLASS_ALLEY: return 20.0
		FoundationRoadEdge.CLASS_DIRT: return 30.0
		_: return 35.0


func capacity_per_lane_for(road_class: StringName) -> int:
	match road_class:
		FoundationRoadEdge.CLASS_HIGHWAY: return 1900
		FoundationRoadEdge.CLASS_ARTERIAL: return 1500
		FoundationRoadEdge.CLASS_COLLECTOR: return 1200
		FoundationRoadEdge.CLASS_LOCAL: return 900
		FoundationRoadEdge.CLASS_ALLEY: return 300
		FoundationRoadEdge.CLASS_DIRT: return 450
		_: return 900


func priority_rank_for(road_class: StringName) -> int:
	match road_class:
		FoundationRoadEdge.CLASS_HIGHWAY: return 0
		FoundationRoadEdge.CLASS_ARTERIAL: return 1
		FoundationRoadEdge.CLASS_COLLECTOR: return 2
		FoundationRoadEdge.CLASS_LOCAL: return 3
		FoundationRoadEdge.CLASS_DIRT: return 4
		FoundationRoadEdge.CLASS_ALLEY: return 5
		_: return 6


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(policy_id).is_empty() or generator_version <= 0:
		errors.append("Traffic metadata policy identity/version must be defined.")
	if geometric_tolerance <= 0.0 or debug_elevation_offset < 0.0:
		errors.append("Traffic geometric tolerance must be positive and debug offset non-negative.")
	if minf(default_lane_width, minf(alley_lane_width, highway_lane_width)) <= 0.0:
		errors.append("Lane widths must be positive.")
	if minf(median_width_divided, minf(shoulder_width_highway, sidewalk_width_urban)) < 0.0:
		errors.append("Cross-section accessory widths cannot be negative.")
	if maximum_cross_sections <= 0 or maximum_intersection_records <= 0:
		errors.append("Traffic record caps must be positive.")
	if maximum_lanes_per_edge <= 0 or maximum_movements_per_intersection <= 0 or maximum_generation_operations <= 0:
		errors.append("Lane, movement, and operation caps must be positive.")
	if signal_minimum_degree < 3:
		errors.append("Signal minimum degree cannot be below three.")
	return errors


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"policy_id": String(policy_id),
		"generator_version": generator_version,
		"geometric_tolerance": geometric_tolerance,
		"debug_elevation_offset": debug_elevation_offset,
		"default_lane_width": default_lane_width,
		"alley_lane_width": alley_lane_width,
		"highway_lane_width": highway_lane_width,
		"median_width_divided": median_width_divided,
		"shoulder_width_highway": shoulder_width_highway,
		"sidewalk_width_urban": sidewalk_width_urban,
		"maximum_cross_sections": maximum_cross_sections,
		"maximum_intersection_records": maximum_intersection_records,
		"maximum_lanes_per_edge": maximum_lanes_per_edge,
		"maximum_movements_per_intersection": maximum_movements_per_intersection,
		"maximum_generation_operations": maximum_generation_operations,
		"signal_minimum_degree": signal_minimum_degree,
		"enable_signal_plans": enable_signal_plans,
	}


static func from_dict(data: Dictionary) -> FoundationTrafficMetadataProfile:
	var profile := FoundationTrafficMetadataProfile.new()
	profile.policy_id = StringName(data.get("policy_id", "foundation_right_hand_traffic_v1"))
	profile.generator_version = int(data.get("generator_version", 1))
	profile.geometric_tolerance = float(data.get("geometric_tolerance", 0.001))
	profile.debug_elevation_offset = float(data.get("debug_elevation_offset", 0.72))
	profile.default_lane_width = float(data.get("default_lane_width", 3.2))
	profile.alley_lane_width = float(data.get("alley_lane_width", 2.8))
	profile.highway_lane_width = float(data.get("highway_lane_width", 3.6))
	profile.median_width_divided = float(data.get("median_width_divided", 3.0))
	profile.shoulder_width_highway = float(data.get("shoulder_width_highway", 2.4))
	profile.sidewalk_width_urban = float(data.get("sidewalk_width_urban", 1.8))
	profile.maximum_cross_sections = int(data.get("maximum_cross_sections", 16384))
	profile.maximum_intersection_records = int(data.get("maximum_intersection_records", 4096))
	profile.maximum_lanes_per_edge = int(data.get("maximum_lanes_per_edge", 8))
	profile.maximum_movements_per_intersection = int(data.get("maximum_movements_per_intersection", 96))
	profile.maximum_generation_operations = int(data.get("maximum_generation_operations", 500000))
	profile.signal_minimum_degree = int(data.get("signal_minimum_degree", 4))
	profile.enable_signal_plans = bool(data.get("enable_signal_plans", true))
	return profile
