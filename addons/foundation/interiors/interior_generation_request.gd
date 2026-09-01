class_name FoundationInteriorGenerationRequest
extends RefCounted

## Explicit selection of buildings and floors. An empty request means no work.

const FORMAT_VERSION := 1

var request_id: StringName = &"selective_interiors"
var building_ids: Array[StringName] = []
var floor_indices_by_building: Dictionary = {}
var include_all_floors := false


func normalized_building_ids() -> Array[StringName]:
	var unique: Dictionary = {}
	for building_id in building_ids:
		if not String(building_id).is_empty():
			unique[building_id] = true
	var result: Array[StringName] = []
	for building_id: StringName in unique:
		result.append(building_id)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result


func floor_indices_for(building_id: StringName, floor_count: int) -> Array[int]:
	var result: Array[int] = []
	if include_all_floors:
		for floor_index in range(floor_count):
			result.append(floor_index)
		return result
	var values: Array = floor_indices_by_building.get(String(building_id), [])
	if values.is_empty():
		if floor_count > 0:
			result.append(0)
		return result
	var unique: Dictionary = {}
	for value in values:
		unique[int(value)] = true
	for floor_index: int in unique:
		result.append(floor_index)
	result.sort()
	return result


func validation_errors(profile: FoundationInteriorGenerationProfile) -> PackedStringArray:
	var errors := PackedStringArray()
	if String(request_id).is_empty():
		errors.append("Interior request ID cannot be empty.")
	if profile != null and normalized_building_ids().size() > profile.maximum_selected_buildings:
		errors.append("Interior request exceeds the selected-building cap.")
	for key in floor_indices_by_building:
		if StringName(key) not in normalized_building_ids():
			errors.append("Interior floor selection references an unselected building: %s." % key)
		for value in floor_indices_by_building[key]:
			if int(value) < 0:
				errors.append("Interior floor indices cannot be negative.")
	return errors


func to_dict() -> Dictionary:
	var serialized_ids: Array[String] = []
	for building_id in normalized_building_ids():
		serialized_ids.append(String(building_id))
	var serialized_floors: Dictionary = {}
	var keys: Array[String] = []
	for key in floor_indices_by_building:
		keys.append(String(key))
	keys.sort()
	for key in keys:
		var values: Array[int] = []
		var unique: Dictionary = {}
		for value in floor_indices_by_building[key]:
			unique[int(value)] = true
		for value: int in unique:
			values.append(value)
		values.sort()
		serialized_floors[key] = values
	return {
		"format_version": FORMAT_VERSION,
		"request_id": String(request_id),
		"building_ids": serialized_ids,
		"floor_indices_by_building": serialized_floors,
		"include_all_floors": include_all_floors,
	}


static func from_dict(data: Dictionary) -> FoundationInteriorGenerationRequest:
	var request := FoundationInteriorGenerationRequest.new()
	request.request_id = StringName(data.get("request_id", "selective_interiors"))
	for value: String in data.get("building_ids", []):
		request.building_ids.append(StringName(value))
	request.floor_indices_by_building = data.get("floor_indices_by_building", {}).duplicate(true)
	request.include_all_floors = bool(data.get("include_all_floors", false))
	return request
