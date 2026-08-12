class_name FoundationFacadeGenerationProfile
extends RefCounted

## Explicit deterministic inputs for the Phase 7 modular facade grammar.

const FORMAT_VERSION := 1
const STREAM_PATTERN: StringName = &"facade_module_pattern"
const STREAM_ENTRANCE: StringName = &"facade_entrance_bay"

var generator_version := 1
var grammar_id: StringName = &"modular_facade_v1"
var preferred_bay_width := 3.2
var minimum_bay_width := 2.2
var maximum_bay_width := 4.4
var maximum_bays_per_facade := 128
var horizontal_opening_margin := 0.4
var ground_window_sill := 1.0
var upper_window_sill := 0.9
var window_height := 1.5
var top_opening_margin := 0.35
var entrance_width := 1.5
var entrance_height := 2.4
var primary_window_probability := 0.82
var side_window_probability := 0.56
var rear_window_probability := 0.38
var minimum_facade_length := 1.0
var geometric_epsilon := 0.001
var maximum_generation_operations := 200000
var debug_surface_offset := 0.05


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if generator_version <= 0:
		errors.append("Facade generator version must be positive.")
	if String(grammar_id).is_empty():
		errors.append("Facade grammar ID cannot be empty.")
	if minimum_bay_width <= 0.0 or maximum_bay_width < minimum_bay_width or preferred_bay_width < minimum_bay_width or preferred_bay_width > maximum_bay_width:
		errors.append("Facade bay-width limits are invalid.")
	if maximum_bays_per_facade <= 0:
		errors.append("Maximum facade bays must be positive.")
	if horizontal_opening_margin < 0.0 or ground_window_sill < 0.0 or upper_window_sill < 0.0 or window_height <= 0.0 or top_opening_margin < 0.0:
		errors.append("Facade opening dimensions are invalid.")
	if entrance_width <= 0.0 or entrance_height <= 0.0:
		errors.append("Facade entrance dimensions must be positive.")
	for probability in [primary_window_probability, side_window_probability, rear_window_probability]:
		if probability < 0.0 or probability > 1.0:
			errors.append("Facade window probabilities must be between zero and one.")
			break
	if minimum_facade_length <= 0.0 or geometric_epsilon <= 0.0:
		errors.append("Facade geometric limits must be positive.")
	if maximum_generation_operations <= 0:
		errors.append("Maximum facade generation operations must be positive.")
	return errors


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"generator_version": generator_version,
		"grammar_id": String(grammar_id),
		"preferred_bay_width": preferred_bay_width,
		"minimum_bay_width": minimum_bay_width,
		"maximum_bay_width": maximum_bay_width,
		"maximum_bays_per_facade": maximum_bays_per_facade,
		"horizontal_opening_margin": horizontal_opening_margin,
		"ground_window_sill": ground_window_sill,
		"upper_window_sill": upper_window_sill,
		"window_height": window_height,
		"top_opening_margin": top_opening_margin,
		"entrance_width": entrance_width,
		"entrance_height": entrance_height,
		"primary_window_probability": primary_window_probability,
		"side_window_probability": side_window_probability,
		"rear_window_probability": rear_window_probability,
		"minimum_facade_length": minimum_facade_length,
		"geometric_epsilon": geometric_epsilon,
		"maximum_generation_operations": maximum_generation_operations,
		"debug_surface_offset": debug_surface_offset,
		"seed_streams": [String(STREAM_PATTERN), String(STREAM_ENTRANCE)],
	}


static func from_dict(data: Dictionary) -> FoundationFacadeGenerationProfile:
	var profile := FoundationFacadeGenerationProfile.new()
	profile.generator_version = int(data.get("generator_version", 1))
	profile.grammar_id = StringName(data.get("grammar_id", "modular_facade_v1"))
	profile.preferred_bay_width = float(data.get("preferred_bay_width", 3.2))
	profile.minimum_bay_width = float(data.get("minimum_bay_width", 2.2))
	profile.maximum_bay_width = float(data.get("maximum_bay_width", 4.4))
	profile.maximum_bays_per_facade = int(data.get("maximum_bays_per_facade", 128))
	profile.horizontal_opening_margin = float(data.get("horizontal_opening_margin", 0.4))
	profile.ground_window_sill = float(data.get("ground_window_sill", 1.0))
	profile.upper_window_sill = float(data.get("upper_window_sill", 0.9))
	profile.window_height = float(data.get("window_height", 1.5))
	profile.top_opening_margin = float(data.get("top_opening_margin", 0.35))
	profile.entrance_width = float(data.get("entrance_width", 1.5))
	profile.entrance_height = float(data.get("entrance_height", 2.4))
	profile.primary_window_probability = float(data.get("primary_window_probability", 0.82))
	profile.side_window_probability = float(data.get("side_window_probability", 0.56))
	profile.rear_window_probability = float(data.get("rear_window_probability", 0.38))
	profile.minimum_facade_length = float(data.get("minimum_facade_length", 1.0))
	profile.geometric_epsilon = float(data.get("geometric_epsilon", 0.001))
	profile.maximum_generation_operations = int(data.get("maximum_generation_operations", 200000))
	profile.debug_surface_offset = float(data.get("debug_surface_offset", 0.05))
	return profile
