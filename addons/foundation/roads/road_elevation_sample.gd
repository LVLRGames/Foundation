class_name FoundationRoadElevationSample
extends RefCounted

## Planning-only desired elevation and unresolved grading data at one road sample.

const FORMAT_VERSION := 1

var world_position := Vector3.ZERO
var terrain_elevation := 0.0
var desired_elevation := 0.0
var cut_depth := 0.0
var fill_height := 0.0
var grade_violation := 0.0
var retaining_wall_candidate := false
var bridge_candidate := false
var water_crossing := false


func _init(
	p_world_position := Vector3.ZERO,
	p_terrain_elevation := 0.0,
	p_desired_elevation := 0.0
) -> void:
	world_position = p_world_position
	terrain_elevation = p_terrain_elevation
	desired_elevation = p_desired_elevation
	cut_depth = maxf(0.0, terrain_elevation - desired_elevation)
	fill_height = maxf(0.0, desired_elevation - terrain_elevation)


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"world_position": {"x": world_position.x, "y": world_position.y, "z": world_position.z},
		"terrain_elevation": terrain_elevation,
		"desired_elevation": desired_elevation,
		"cut_depth": cut_depth,
		"fill_height": fill_height,
		"grade_violation": grade_violation,
		"retaining_wall_candidate": retaining_wall_candidate,
		"bridge_candidate": bridge_candidate,
		"water_crossing": water_crossing,
	}


static func from_dict(data: Dictionary) -> FoundationRoadElevationSample:
	var point: Dictionary = data.get("world_position", {})
	var sample := FoundationRoadElevationSample.new(
		Vector3(float(point.get("x", 0.0)), float(point.get("y", 0.0)), float(point.get("z", 0.0))),
		float(data.get("terrain_elevation", 0.0)),
		float(data.get("desired_elevation", 0.0))
	)
	sample.cut_depth = float(data.get("cut_depth", sample.cut_depth))
	sample.fill_height = float(data.get("fill_height", sample.fill_height))
	sample.grade_violation = float(data.get("grade_violation", 0.0))
	sample.retaining_wall_candidate = bool(data.get("retaining_wall_candidate", false))
	sample.bridge_candidate = bool(data.get("bridge_candidate", false))
	sample.water_crossing = bool(data.get("water_crossing", false))
	return sample
