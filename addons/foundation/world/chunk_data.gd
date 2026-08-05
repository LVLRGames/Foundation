class_name FoundationChunkData
extends RefCounted

## Abstract chunk metadata; never the same object as a rendered chunk node.

const FORMAT_VERSION := 1

enum GenerationState {
	UNINITIALIZED,
	PLANNED,
	GENERATED,
	DIRTY,
}

enum RuntimeState {
	UNLOADED,
	DATA_ONLY,
	PROXY_LOADED,
	VISUAL_LOADED,
	PHYSICS_LOADED,
	GAMEPLAY_ACTIVE,
}

var stable_id: StringName
var coordinate := Vector2i.ZERO
var world_bounds := Rect2()
var generation_state := GenerationState.UNINITIALIZED
var runtime_state := RuntimeState.DATA_ONLY
var metadata: Dictionary = {}
var _layer_record_ids: Dictionary = {}
var _dirty_layers: Dictionary = {}


func _init(p_coordinate := Vector2i.ZERO, p_world_bounds := Rect2()) -> void:
	coordinate = p_coordinate
	stable_id = FoundationSpatialId.for_chunk(coordinate)
	world_bounds = p_world_bounds


func add_record_reference(layer_type: StringName, record_id: StringName) -> void:
	if not _layer_record_ids.has(layer_type):
		_layer_record_ids[layer_type] = {}
	var records: Dictionary = _layer_record_ids[layer_type]
	records[record_id] = true


func remove_record_reference(layer_type: StringName, record_id: StringName) -> void:
	var records: Dictionary = _layer_record_ids.get(layer_type, {})
	records.erase(record_id)
	if records.is_empty():
		_layer_record_ids.erase(layer_type)


func get_record_ids(layer_type: StringName = &"") -> Array[StringName]:
	var unique_ids: Dictionary = {}
	if String(layer_type).is_empty():
		for records: Dictionary in _layer_record_ids.values():
			for record_id: StringName in records:
				unique_ids[record_id] = true
	else:
		var records: Dictionary = _layer_record_ids.get(layer_type, {})
		for record_id: StringName in records:
			unique_ids[record_id] = true
	var result: Array[StringName] = []
	for record_id: StringName in unique_ids:
		result.append(record_id)
	result.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return result


func mark_layer_dirty(layer_type: StringName) -> void:
	_dirty_layers[layer_type] = true
	generation_state = GenerationState.DIRTY


func clear_layer_dirty(layer_type: StringName) -> void:
	_dirty_layers.erase(layer_type)
	if _dirty_layers.is_empty() and generation_state == GenerationState.DIRTY:
		generation_state = GenerationState.GENERATED


func is_layer_dirty(layer_type: StringName) -> bool:
	return _dirty_layers.has(layer_type)


func get_dirty_layers() -> Array[StringName]:
	var result: Array[StringName] = []
	for layer_type: StringName in _dirty_layers:
		result.append(layer_type)
	result.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return result


func to_dict() -> Dictionary:
	var serialized_layers: Array[Dictionary] = []
	var layer_types: Array[StringName] = []
	for layer_type: StringName in _layer_record_ids:
		layer_types.append(layer_type)
	layer_types.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	for layer_type in layer_types:
		var serialized_ids: Array[String] = []
		for record_id in get_record_ids(layer_type):
			serialized_ids.append(String(record_id))
		serialized_layers.append({"layer_type": String(layer_type), "record_ids": serialized_ids})
	var serialized_dirty_layers: Array[String] = []
	for layer_type in get_dirty_layers():
		serialized_dirty_layers.append(String(layer_type))
	return {
		"format_version": FORMAT_VERSION,
		"stable_id": String(stable_id),
		"coordinate": {"x": coordinate.x, "y": coordinate.y},
		"world_bounds": FoundationSpatialRecord._rect_to_dict(world_bounds),
		"generation_state": generation_state,
		"runtime_state": runtime_state,
		"metadata": metadata.duplicate(true),
		"layer_records": serialized_layers,
		"dirty_layers": serialized_dirty_layers,
	}


static func from_dict(data: Dictionary) -> FoundationChunkData:
	var coordinate_data: Dictionary = data.get("coordinate", {})
	var chunk := FoundationChunkData.new(
		Vector2i(int(coordinate_data.get("x", 0)), int(coordinate_data.get("y", 0))),
		FoundationSpatialRecord._rect_from_dict(data.get("world_bounds", {}))
	)
	chunk.stable_id = StringName(data.get("stable_id", String(chunk.stable_id)))
	chunk.generation_state = int(data.get("generation_state", GenerationState.UNINITIALIZED)) as GenerationState
	chunk.runtime_state = int(data.get("runtime_state", RuntimeState.DATA_ONLY)) as RuntimeState
	chunk.metadata = data.get("metadata", {}).duplicate(true)
	for layer_data: Dictionary in data.get("layer_records", []):
		var layer_type := StringName(layer_data.get("layer_type", ""))
		for record_id: String in layer_data.get("record_ids", []):
			chunk.add_record_reference(layer_type, StringName(record_id))
	for layer_type: String in data.get("dirty_layers", []):
		chunk._dirty_layers[StringName(layer_type)] = true
	return chunk
