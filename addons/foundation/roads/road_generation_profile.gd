class_name FoundationRoadGenerationProfile
extends RefCounted

## Explicit deterministic Phase 2 routing inputs. This profile creates topology, never geometry.

const FORMAT_VERSION := 1

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
	return profile
