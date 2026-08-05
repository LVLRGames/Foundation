class_name FoundationSpatialIndex
extends RefCounted

## Replaceable chunk-bucket index with stable ordering at query boundaries.

var coordinate_system: FoundationCoordinateSystem
var _records_by_id: Dictionary = {}
var _chunk_buckets: Dictionary = {}


func _init(p_coordinate_system: FoundationCoordinateSystem) -> void:
	coordinate_system = p_coordinate_system


func register_record(record: FoundationSpatialRecord) -> bool:
	if String(record.stable_id).is_empty():
		push_error("Cannot index a spatial record without a stable ID.")
		return false
	if _records_by_id.has(record.stable_id):
		unregister_record(record.stable_id)
	var chunks := coordinate_system.world_bounds_to_chunks(record.world_bounds)
	record.set_owning_chunks(chunks)
	_records_by_id[record.stable_id] = record
	for chunk in chunks:
		if not _chunk_buckets.has(chunk):
			_chunk_buckets[chunk] = {}
		var bucket: Dictionary = _chunk_buckets[chunk]
		bucket[record.stable_id] = true
	return true


func unregister_record(stable_id: StringName) -> bool:
	var record := get_record(stable_id)
	if record == null:
		return false
	for chunk in record.owning_chunks:
		var bucket: Dictionary = _chunk_buckets.get(chunk, {})
		bucket.erase(stable_id)
		if bucket.is_empty():
			_chunk_buckets.erase(chunk)
	_records_by_id.erase(stable_id)
	return true


func get_record(stable_id: StringName) -> FoundationSpatialRecord:
	return _records_by_id.get(stable_id) as FoundationSpatialRecord


func query_bounds(bounds: Rect2, layer_types: Array[StringName] = []) -> Array[FoundationSpatialRecord]:
	var unique_ids: Dictionary = {}
	for chunk in coordinate_system.world_bounds_to_chunks(bounds):
		var bucket: Dictionary = _chunk_buckets.get(chunk, {})
		for stable_id: StringName in bucket:
			unique_ids[stable_id] = true
	var result: Array[FoundationSpatialRecord] = []
	for stable_id: StringName in unique_ids:
		var record := get_record(stable_id)
		if record == null or not record.intersects(bounds):
			continue
		if not layer_types.is_empty() and record.layer_type not in layer_types:
			continue
		result.append(record)
	_sort_records(result)
	return result


func get_records_in_chunk(
	chunk: Vector2i,
	layer_type: StringName = &""
) -> Array[FoundationSpatialRecord]:
	var result: Array[FoundationSpatialRecord] = []
	var bucket: Dictionary = _chunk_buckets.get(chunk, {})
	for stable_id: StringName in bucket:
		var record := get_record(stable_id)
		if record != null and (String(layer_type).is_empty() or record.layer_type == layer_type):
			result.append(record)
	_sort_records(result)
	return result


func get_all_records() -> Array[FoundationSpatialRecord]:
	var result: Array[FoundationSpatialRecord] = []
	for record: FoundationSpatialRecord in _records_by_id.values():
		result.append(record)
	_sort_records(result)
	return result


func get_record_count() -> int:
	return _records_by_id.size()


func clear() -> void:
	_records_by_id.clear()
	_chunk_buckets.clear()


static func _sort_records(records: Array[FoundationSpatialRecord]) -> void:
	records.sort_custom(func(a: FoundationSpatialRecord, b: FoundationSpatialRecord) -> bool:
		return String(a.stable_id) < String(b.stable_id)
	)
