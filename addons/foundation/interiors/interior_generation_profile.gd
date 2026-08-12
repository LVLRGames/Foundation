class_name FoundationInteriorGenerationProfile
extends RefCounted

## Explicit bounded inputs for deterministic Phase 12 selective interiors.

const FORMAT_VERSION := 1
const STREAM_GRID_VARIATION: StringName = &"interior_grid_variation"

var generator_version := 1
var exterior_wall_inset := 0.35
var preferred_room_span := 8.0
var preferred_room_depth := 8.0
var minimum_room_area := 6.0
var service_room_area_threshold := 12.0
var interior_door_width := 1.1
var exterior_door_width := 1.5
var minimum_shared_boundary := 1.4
var portal_end_margin := 0.15
var connector_size := Vector2(2.0, 3.0)
var maximum_selected_buildings := 8
var maximum_floors_per_building := 12
var maximum_rooms_per_floor := 96
var maximum_portals_per_floor := 192
var maximum_vertical_connectors := 32
var point_quantization := 0.01
var geometric_epsilon := 0.001
var maximum_generation_operations := 250000
var debug_floor_separation := 0.18


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if generator_version <= 0:
		errors.append("Interior generator version must be positive.")
	if exterior_wall_inset < 0.0:
		errors.append("Interior exterior-wall inset cannot be negative.")
	if preferred_room_span <= 0.0 or preferred_room_depth <= 0.0:
		errors.append("Preferred interior room dimensions must be positive.")
	if minimum_room_area <= 0.0 or service_room_area_threshold < minimum_room_area:
		errors.append("Interior room area limits are invalid.")
	if interior_door_width <= 0.0 or exterior_door_width <= 0.0:
		errors.append("Interior portal widths must be positive.")
	if minimum_shared_boundary <= 0.0 or portal_end_margin < 0.0:
		errors.append("Interior portal adjacency limits are invalid.")
	if connector_size.x <= 0.0 or connector_size.y <= 0.0:
		errors.append("Interior vertical-connector size must be positive.")
	if maximum_selected_buildings <= 0 or maximum_floors_per_building <= 0:
		errors.append("Interior selection caps must be positive.")
	if maximum_rooms_per_floor <= 0 or maximum_portals_per_floor <= 0 or maximum_vertical_connectors <= 0:
		errors.append("Interior topology caps must be positive.")
	if point_quantization <= 0.0 or geometric_epsilon <= 0.0:
		errors.append("Interior geometric tolerances must be positive.")
	if maximum_generation_operations <= 0:
		errors.append("Maximum interior generation operations must be positive.")
	return errors


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"generator_version": generator_version,
		"exterior_wall_inset": exterior_wall_inset,
		"preferred_room_span": preferred_room_span,
		"preferred_room_depth": preferred_room_depth,
		"minimum_room_area": minimum_room_area,
		"service_room_area_threshold": service_room_area_threshold,
		"interior_door_width": interior_door_width,
		"exterior_door_width": exterior_door_width,
		"minimum_shared_boundary": minimum_shared_boundary,
		"portal_end_margin": portal_end_margin,
		"connector_size": {"x": connector_size.x, "y": connector_size.y},
		"maximum_selected_buildings": maximum_selected_buildings,
		"maximum_floors_per_building": maximum_floors_per_building,
		"maximum_rooms_per_floor": maximum_rooms_per_floor,
		"maximum_portals_per_floor": maximum_portals_per_floor,
		"maximum_vertical_connectors": maximum_vertical_connectors,
		"point_quantization": point_quantization,
		"geometric_epsilon": geometric_epsilon,
		"maximum_generation_operations": maximum_generation_operations,
		"debug_floor_separation": debug_floor_separation,
		"seed_streams": [String(STREAM_GRID_VARIATION)],
	}


static func from_dict(data: Dictionary) -> FoundationInteriorGenerationProfile:
	var profile := FoundationInteriorGenerationProfile.new()
	profile.generator_version = int(data.get("generator_version", 1))
	profile.exterior_wall_inset = float(data.get("exterior_wall_inset", 0.35))
	profile.preferred_room_span = float(data.get("preferred_room_span", 8.0))
	profile.preferred_room_depth = float(data.get("preferred_room_depth", 8.0))
	profile.minimum_room_area = float(data.get("minimum_room_area", 6.0))
	profile.service_room_area_threshold = float(data.get("service_room_area_threshold", 12.0))
	profile.interior_door_width = float(data.get("interior_door_width", 1.1))
	profile.exterior_door_width = float(data.get("exterior_door_width", 1.5))
	profile.minimum_shared_boundary = float(data.get("minimum_shared_boundary", 1.4))
	profile.portal_end_margin = float(data.get("portal_end_margin", 0.15))
	var connector_data: Dictionary = data.get("connector_size", {})
	profile.connector_size = Vector2(float(connector_data.get("x", 2.0)), float(connector_data.get("y", 3.0)))
	profile.maximum_selected_buildings = int(data.get("maximum_selected_buildings", 8))
	profile.maximum_floors_per_building = int(data.get("maximum_floors_per_building", 12))
	profile.maximum_rooms_per_floor = int(data.get("maximum_rooms_per_floor", 96))
	profile.maximum_portals_per_floor = int(data.get("maximum_portals_per_floor", 192))
	profile.maximum_vertical_connectors = int(data.get("maximum_vertical_connectors", 32))
	profile.point_quantization = float(data.get("point_quantization", 0.01))
	profile.geometric_epsilon = float(data.get("geometric_epsilon", 0.001))
	profile.maximum_generation_operations = int(data.get("maximum_generation_operations", 250000))
	profile.debug_floor_separation = float(data.get("debug_floor_separation", 0.18))
	return profile
