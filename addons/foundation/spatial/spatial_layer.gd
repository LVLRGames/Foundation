class_name FoundationSpatialLayer
extends RefCounted

## Renderer-independent record collection sharing the world's spatial index.

const FORMAT_VERSION := 1

var layer_type: StringName
var coordinate_system: FoundationCoordinateSystem
var spatial_index: FoundationSpatialIndex
var metadata: Dictionary = {}
var _records: Dictionary = {}
var _dirty_chunks: Dictionary = {}


func _init(
	p_layer_type: StringName = &"feature",
	p_coordinate_system: FoundationCoordinateSystem = null,
	p_spatial_index: FoundationSpatialIndex = null
) -> void:
	layer_type = p_layer_type
	coordinate_system = p_coordinate_system
	spatial_index = p_spatial_index


func register_record(record: FoundationSpatialRecord) -> bool:
	assert(spatial_index != null, "Spatial layer is not attached to an index.")
	var previous := get_record(record.stable_id)
	if previous != null:
		for chunk in previous.owning_chunks:
			_dirty_chunks[chunk] = true
	record.layer_type = layer_type
	if not spatial_index.register_record(record):
		return false
	_records[record.stable_id] = record
	for chunk in record.owning_chunks:
		_dirty_chunks[chunk] = true
	return true


func unregister_record(stable_id: StringName) -> bool:
	var record := get_record(stable_id)
	if record == null:
		return false
	for chunk in record.owning_chunks:
		_dirty_chunks[chunk] = true
	_records.erase(stable_id)
	return spatial_index.unregister_record(stable_id)


func get_record(stable_id: StringName) -> FoundationSpatialRecord:
	return _records.get(stable_id) as FoundationSpatialRecord


func get_records() -> Array[FoundationSpatialRecord]:
	var result: Array[FoundationSpatialRecord] = []
	for record: FoundationSpatialRecord in _records.values():
		result.append(record)
	FoundationSpatialIndex._sort_records(result)
	return result


func query_bounds(bounds: Rect2) -> Array[FoundationSpatialRecord]:
	return spatial_index.query_bounds(bounds, [layer_type])


func mark_bounds_dirty(bounds: Rect2) -> Array[Vector2i]:
	var chunks := coordinate_system.world_bounds_to_chunks(bounds)
	for chunk in chunks:
		_dirty_chunks[chunk] = true
	return chunks


func mark_record_dirty(stable_id: StringName) -> Array[Vector2i]:
	var record := get_record(stable_id)
	return mark_bounds_dirty(record.world_bounds) if record != null else []


func get_dirty_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for chunk: Vector2i in _dirty_chunks:
		result.append(chunk)
	result.sort_custom(FoundationSpatialRecord._sort_vector2i)
	return result


func clear_dirty_chunks() -> void:
	_dirty_chunks.clear()


func get_debug_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for record in get_records():
		snapshot.append({
			"stable_id": record.stable_id,
			"entity_type": record.entity_type,
			"layer_type": layer_type,
			"bounds": record.world_bounds,
			"parent_id": record.parent_id,
			"state": record.authorship_state,
		})
	return snapshot


func to_dict() -> Dictionary:
	var serialized_records: Array[Dictionary] = []
	for record in get_records():
		serialized_records.append(record.to_dict())
	var serialized_dirty_chunks: Array[Dictionary] = []
	for chunk in get_dirty_chunks():
		serialized_dirty_chunks.append({"x": chunk.x, "y": chunk.y})
	return {
		"format_version": FORMAT_VERSION,
		"layer_type": String(layer_type),
		"metadata": metadata.duplicate(true),
		"records": serialized_records,
		"dirty_chunks": serialized_dirty_chunks,
	}


static func from_dict(
	data: Dictionary,
	coordinate_system: FoundationCoordinateSystem,
	spatial_index: FoundationSpatialIndex
) -> FoundationSpatialLayer:
	var layer := FoundationSpatialLayer.new(
		StringName(data.get("layer_type", "feature")),
		coordinate_system,
		spatial_index
	)
	layer.metadata = data.get("metadata", {}).duplicate(true)
	for record_data: Dictionary in data.get("records", []):
		var record_kind := StringName(record_data.get("record_kind", "spatial_record"))
		var record: FoundationSpatialRecord
		match record_kind:
			FoundationCityAnchor.RECORD_KIND:
				record = FoundationCityAnchor.from_dict(record_data)
			FoundationRoadNode.RECORD_KIND:
				record = FoundationRoadNode.from_dict(record_data)
			FoundationRoadEdge.RECORD_KIND:
				record = FoundationRoadEdge.from_dict(record_data)
			FoundationRoadPatternArea.RECORD_KIND:
				record = FoundationRoadPatternArea.from_dict(record_data)
			FoundationLogicalRoad.RECORD_KIND:
				record = FoundationLogicalRoad.from_dict(record_data)
			FoundationIntersectionRecord.RECORD_KIND:
				record = FoundationIntersectionRecord.from_dict(record_data)
			FoundationBlockRecord.RECORD_KIND:
				record = FoundationBlockRecord.from_dict(record_data)
			FoundationParcelRecord.RECORD_KIND:
				record = FoundationParcelRecord.from_dict(record_data)
			FoundationBuildingRecord.RECORD_KIND:
				record = FoundationBuildingRecord.from_dict(record_data)
			FoundationFacadeRecord.RECORD_KIND:
				record = FoundationFacadeRecord.from_dict(record_data)
			FoundationDistrictRecord.RECORD_KIND:
				record = FoundationDistrictRecord.from_dict(record_data)
			FoundationParkingFacilityRecord.RECORD_KIND:
				record = FoundationParkingFacilityRecord.from_dict(record_data)
			FoundationPublicFeatureRecord.RECORD_KIND:
				record = FoundationPublicFeatureRecord.from_dict(record_data)
			_:
				record = FoundationSpatialRecord.from_dict(record_data)
		layer.register_record(record)
	layer.clear_dirty_chunks()
	for chunk_data: Dictionary in data.get("dirty_chunks", []):
		layer._dirty_chunks[Vector2i(int(chunk_data.get("x", 0)), int(chunk_data.get("y", 0)))] = true
	return layer
