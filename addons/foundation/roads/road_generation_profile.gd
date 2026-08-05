class_name FoundationRoadGenerationProfile
extends RefCounted

## Explicit deterministic Phase 2 routing inputs. This profile creates topology, never geometry.

const FORMAT_VERSION := 2

const SEED_STREAMS: Array[StringName] = [
	&"road_anchor_candidates",
	&"road_major_connections",
	&"road_collectors",
	&"road_local_growth",
	&"road_loops",
	&"road_dead_ends",
	&"road_logical_identity",
]

var generator_version := 1
var slope_cost_weight := 18.0
var no_build_penalty := 40.0
var protected_penalty := 500.0
var water_penalty := 160.0
var rock_penalty := 12.0
var mud_penalty := 8.0
var wetland_penalty := 20.0
var search_diagonals := true
var max_expanded_cells := 200000
var extra_edge_count := 0
var debug_elevation_offset := 0.35
var minimum_edge_length := 4.0
var minimum_intersection_spacing := 12.0
var intersection_spacing_highway := 64.0
var intersection_spacing_arterial := 32.0
var intersection_spacing_collector := 20.0
var intersection_spacing_local := 12.0
var intersection_spacing_alley := 8.0
var intersection_spacing_dirt := 24.0
var preferred_corridor_weight := 1.0
var district_alignment_weight := 3.0
var existing_road_connection_bonus := 4.0
var maximum_grade_highway := 6.0
var maximum_grade_arterial := 8.0
var maximum_grade_collector := 10.0
var maximum_grade_local := 14.0
var maximum_grade_dirt := 18.0
var retaining_wall_threshold := 2.5
var bridge_fill_threshold := 4.0
var enable_pattern_topology := true


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if generator_version <= 0:
		errors.append("Road generator version must be positive.")
	if slope_cost_weight < 0.0:
		errors.append("Slope cost weight cannot be negative.")
	if no_build_penalty < 0.0 or protected_penalty < 0.0 or water_penalty < 0.0:
		errors.append("Terrain flag penalties cannot be negative.")
	if rock_penalty < 0.0 or mud_penalty < 0.0 or wetland_penalty < 0.0:
		errors.append("Terrain surface penalties cannot be negative.")
	if max_expanded_cells <= 0:
		errors.append("Maximum expanded cell count must be positive.")
	if extra_edge_count < 0:
		errors.append("Extra edge count cannot be negative.")
	if minimum_edge_length <= 0.0 or minimum_intersection_spacing <= 0.0:
		errors.append("Road length and intersection-spacing limits must be positive.")
	if minf(intersection_spacing_highway, minf(intersection_spacing_arterial, intersection_spacing_collector)) <= 0.0:
		errors.append("Major-road intersection spacing must be positive.")
	if minf(intersection_spacing_local, minf(intersection_spacing_alley, intersection_spacing_dirt)) <= 0.0:
		errors.append("Local-road intersection spacing must be positive.")
	if preferred_corridor_weight < 0.0 or district_alignment_weight < 0.0:
		errors.append("Road alignment weights cannot be negative.")
	if existing_road_connection_bonus < 0.0:
		errors.append("Existing-road connection bonus cannot be negative.")
	if minf(maximum_grade_highway, minf(maximum_grade_arterial, maximum_grade_collector)) <= 0.0:
		errors.append("Major-road maximum grades must be positive.")
	if minf(maximum_grade_local, maximum_grade_dirt) <= 0.0:
		errors.append("Local-road maximum grades must be positive.")
	if retaining_wall_threshold < 0.0 or bridge_fill_threshold < 0.0:
		errors.append("Grading thresholds cannot be negative.")
	return errors


func surface_penalty(surface_id: int) -> float:
	match surface_id:
		FoundationTerrainSurface.Type.ROCK:
			return rock_penalty
		FoundationTerrainSurface.Type.MUD:
			return mud_penalty
		FoundationTerrainSurface.Type.WETLAND, FoundationTerrainSurface.Type.WATERBED:
			return wetland_penalty
		_:
			return 0.0


func maximum_grade_for(road_class: StringName) -> float:
	match road_class:
		FoundationRoadEdge.CLASS_HIGHWAY:
			return maximum_grade_highway
		FoundationRoadEdge.CLASS_ARTERIAL:
			return maximum_grade_arterial
		FoundationRoadEdge.CLASS_COLLECTOR:
			return maximum_grade_collector
		FoundationRoadEdge.CLASS_DIRT:
			return maximum_grade_dirt
		_:
			return maximum_grade_local


func minimum_intersection_spacing_for(road_class: StringName) -> float:
	match road_class:
		FoundationRoadEdge.CLASS_HIGHWAY:
			return intersection_spacing_highway
		FoundationRoadEdge.CLASS_ARTERIAL:
			return intersection_spacing_arterial
		FoundationRoadEdge.CLASS_COLLECTOR:
			return intersection_spacing_collector
		FoundationRoadEdge.CLASS_ALLEY:
			return intersection_spacing_alley
		FoundationRoadEdge.CLASS_DIRT:
			return intersection_spacing_dirt
		_:
			return intersection_spacing_local


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"generator_version": generator_version,
		"slope_cost_weight": slope_cost_weight,
		"no_build_penalty": no_build_penalty,
		"protected_penalty": protected_penalty,
		"water_penalty": water_penalty,
		"rock_penalty": rock_penalty,
		"mud_penalty": mud_penalty,
		"wetland_penalty": wetland_penalty,
		"search_diagonals": search_diagonals,
		"max_expanded_cells": max_expanded_cells,
		"extra_edge_count": extra_edge_count,
		"debug_elevation_offset": debug_elevation_offset,
		"minimum_edge_length": minimum_edge_length,
		"minimum_intersection_spacing": minimum_intersection_spacing,
		"intersection_spacing_highway": intersection_spacing_highway,
		"intersection_spacing_arterial": intersection_spacing_arterial,
		"intersection_spacing_collector": intersection_spacing_collector,
		"intersection_spacing_local": intersection_spacing_local,
		"intersection_spacing_alley": intersection_spacing_alley,
		"intersection_spacing_dirt": intersection_spacing_dirt,
		"preferred_corridor_weight": preferred_corridor_weight,
		"district_alignment_weight": district_alignment_weight,
		"existing_road_connection_bonus": existing_road_connection_bonus,
		"maximum_grade_highway": maximum_grade_highway,
		"maximum_grade_arterial": maximum_grade_arterial,
		"maximum_grade_collector": maximum_grade_collector,
		"maximum_grade_local": maximum_grade_local,
		"maximum_grade_dirt": maximum_grade_dirt,
		"retaining_wall_threshold": retaining_wall_threshold,
		"bridge_fill_threshold": bridge_fill_threshold,
		"enable_pattern_topology": enable_pattern_topology,
		"seed_streams": Array(SEED_STREAMS),
	}


static func from_dict(data: Dictionary) -> FoundationRoadGenerationProfile:
	var profile := FoundationRoadGenerationProfile.new()
	profile.generator_version = int(data.get("generator_version", 1))
	profile.slope_cost_weight = float(data.get("slope_cost_weight", 18.0))
	profile.no_build_penalty = float(data.get("no_build_penalty", 40.0))
	profile.protected_penalty = float(data.get("protected_penalty", 500.0))
	profile.water_penalty = float(data.get("water_penalty", 160.0))
	profile.rock_penalty = float(data.get("rock_penalty", 12.0))
	profile.mud_penalty = float(data.get("mud_penalty", 8.0))
	profile.wetland_penalty = float(data.get("wetland_penalty", 20.0))
	profile.search_diagonals = bool(data.get("search_diagonals", true))
	profile.max_expanded_cells = int(data.get("max_expanded_cells", 200000))
	profile.extra_edge_count = int(data.get("extra_edge_count", 0))
	profile.debug_elevation_offset = float(data.get("debug_elevation_offset", 0.35))
	profile.minimum_edge_length = float(data.get("minimum_edge_length", 4.0))
	profile.minimum_intersection_spacing = float(data.get("minimum_intersection_spacing", 12.0))
	profile.intersection_spacing_highway = float(data.get("intersection_spacing_highway", 64.0))
	profile.intersection_spacing_arterial = float(data.get("intersection_spacing_arterial", 32.0))
	profile.intersection_spacing_collector = float(data.get("intersection_spacing_collector", 20.0))
	profile.intersection_spacing_local = float(data.get("intersection_spacing_local", 12.0))
	profile.intersection_spacing_alley = float(data.get("intersection_spacing_alley", 8.0))
	profile.intersection_spacing_dirt = float(data.get("intersection_spacing_dirt", 24.0))
	profile.preferred_corridor_weight = float(data.get("preferred_corridor_weight", 1.0))
	profile.district_alignment_weight = float(data.get("district_alignment_weight", 3.0))
	profile.existing_road_connection_bonus = float(data.get("existing_road_connection_bonus", 4.0))
	profile.maximum_grade_highway = float(data.get("maximum_grade_highway", 6.0))
	profile.maximum_grade_arterial = float(data.get("maximum_grade_arterial", 8.0))
	profile.maximum_grade_collector = float(data.get("maximum_grade_collector", 10.0))
	profile.maximum_grade_local = float(data.get("maximum_grade_local", 14.0))
	profile.maximum_grade_dirt = float(data.get("maximum_grade_dirt", 18.0))
	profile.retaining_wall_threshold = float(data.get("retaining_wall_threshold", 2.5))
	profile.bridge_fill_threshold = float(data.get("bridge_fill_threshold", 4.0))
	profile.enable_pattern_topology = bool(data.get("enable_pattern_topology", true))
	return profile
