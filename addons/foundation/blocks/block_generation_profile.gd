class_name FoundationBlockGenerationProfile
extends RefCounted

## Explicit deterministic Phase 3 planarization and face-extraction inputs.

const FORMAT_VERSION := 1

var generator_version := 1
var point_quantization := 0.01
var intersection_epsilon := 0.0001
var collinear_epsilon := 0.001
var intersection_bucket_size := 128.0
var minimum_block_area := 16.0
var maximum_face_steps := 200000
var debug_elevation_offset := 0.18


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if generator_version <= 0:
		errors.append("Block generator version must be positive.")
	if point_quantization <= 0.0:
		errors.append("Point quantization must be greater than zero.")
	if intersection_epsilon <= 0.0:
		errors.append("Intersection epsilon must be greater than zero.")
	if collinear_epsilon < 0.0:
		errors.append("Collinear epsilon cannot be negative.")
	if intersection_bucket_size < point_quantization:
		errors.append("Intersection bucket size must be at least one quantization step.")
	if minimum_block_area < 0.0:
		errors.append("Minimum block area cannot be negative.")
	if maximum_face_steps <= 0:
		errors.append("Maximum face steps must be positive.")
	return errors


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"generator_version": generator_version,
		"point_quantization": point_quantization,
		"intersection_epsilon": intersection_epsilon,
		"collinear_epsilon": collinear_epsilon,
		"intersection_bucket_size": intersection_bucket_size,
		"minimum_block_area": minimum_block_area,
		"maximum_face_steps": maximum_face_steps,
		"debug_elevation_offset": debug_elevation_offset,
	}


static func from_dict(data: Dictionary) -> FoundationBlockGenerationProfile:
	var profile := FoundationBlockGenerationProfile.new()
	profile.generator_version = int(data.get("generator_version", 1))
	profile.point_quantization = float(data.get("point_quantization", 0.01))
	profile.intersection_epsilon = float(data.get("intersection_epsilon", 0.0001))
	profile.collinear_epsilon = float(data.get("collinear_epsilon", 0.001))
	profile.intersection_bucket_size = float(data.get("intersection_bucket_size", 128.0))
	profile.minimum_block_area = float(data.get("minimum_block_area", 16.0))
	profile.maximum_face_steps = int(data.get("maximum_face_steps", 200000))
	profile.debug_elevation_offset = float(data.get("debug_elevation_offset", 0.18))
	return profile
