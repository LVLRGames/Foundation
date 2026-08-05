class_name FoundationWorldData
extends RefCounted

## Renderer-independent owner of Foundation's abstract world state.

const FORMAT_VERSION := 1
const TERRAIN_LAYER: StringName = &"terrain"
const OVERRIDE_LAYER: StringName = &"override"

var metadata: FoundationWorldMetadata
var coordinate_system: FoundationCoordinateSystem
var spatial_index: FoundationSpatialIndex
var layer_registry := FoundationLayerRegistry.new()
var regions: Dictionary = {}
var chunks: Dictionary = {}


func _init(
	p_metadata: FoundationWorldMetadata = null,
	p_coordinate_system: FoundationCoordinateSystem = null
) -> void:
	metadata = p_metadata if p_metadata != null else FoundationWorldMetadata.new()
	coordinate_system = p_coordinate_system if p_coordinate_system != null else FoundationCoordinateSystem.new()
	spatial_index = FoundationSpatialIndex.new(coordinate_system)


func initialize_default_layers() -> void:
	register_layer_type(TERRAIN_LAYER)
	register_layer_type(OVERRIDE_LAYER)


func initialize_partitions() -> void:
	for chunk_coordinate in coordinate_system.world_bounds_to_chunks(metadata.world_bounds):
		ensure_chunk(chunk_coordinate)
		ensure_region(coordinate_system.chunk_to_region(chunk_coordinate))


func register_layer_type(layer_type: StringName) -> FoundationSpatialLayer:
	var existing := get_layer(layer_type)
	if existing != null:
		return existing
	var layer := FoundationSpatialLayer.new(layer_type, coordinate_system, spatial_index)
	layer_registry.register_layer(layer)
	return layer


func unregister_layer(layer_type: StringName) -> bool:
	var layer := get_layer(layer_type)
	if layer == null:
		return false
	for record in layer.get_records():
		unregister_record(record.stable_id)
	return layer_registry.unregister_layer(layer_type)


func get_layer(layer_type: StringName) -> FoundationSpatialLayer:
	return layer_registry.get_layer(layer_type)


func register_record(record: FoundationSpatialRecord) -> bool:
	var previous := get_record(record.stable_id)
	if previous != null:
		unregister_record(previous.stable_id)
	var layer := register_layer_type(record.layer_type)
	if not layer.register_record(record):
		return false
	for chunk_coordinate in record.owning_chunks:
		var chunk := ensure_chunk(chunk_coordinate)
		chunk.add_record_reference(record.layer_type, record.stable_id)
		chunk.mark_layer_dirty(record.layer_type)
		ensure_region(coordinate_system.chunk_to_region(chunk_coordinate))
	return true


func unregister_record(stable_id: StringName) -> bool:
	var record := get_record(stable_id)
	if record == null:
		return false
	for chunk_coordinate in record.owning_chunks:
		var chunk := get_chunk(chunk_coordinate)
		if chunk != null:
			chunk.remove_record_reference(record.layer_type, stable_id)
			chunk.mark_layer_dirty(record.layer_type)
	var layer := get_layer(record.layer_type)
	return layer.unregister_record(stable_id) if layer != null else false


func get_record(stable_id: StringName) -> FoundationSpatialRecord:
	return spatial_index.get_record(stable_id)


func query_bounds(bounds: Rect2, layer_types: Array[StringName] = []) -> Array[FoundationSpatialRecord]:
	return spatial_index.query_bounds(bounds, layer_types)


func get_chunk(chunk_coordinate: Vector2i) -> FoundationChunkData:
	return chunks.get(chunk_coordinate) as FoundationChunkData


func ensure_chunk(chunk_coordinate: Vector2i) -> FoundationChunkData:
	var existing := get_chunk(chunk_coordinate)
	if existing != null:
		return existing
	var chunk := FoundationChunkData.new(
		chunk_coordinate,
		coordinate_system.chunk_to_world_bounds(chunk_coordinate)
	)
	chunks[chunk_coordinate] = chunk
	return chunk


func get_region(region_coordinate: Vector2i) -> FoundationRegionData:
	return regions.get(region_coordinate) as FoundationRegionData


func ensure_region(region_coordinate: Vector2i) -> FoundationRegionData:
	var existing := get_region(region_coordinate)
	if existing != null:
		return existing
	var chunk_origin := region_coordinate * coordinate_system.region_chunks
	var region := FoundationRegionData.new(
		region_coordinate,
		coordinate_system.region_to_world_bounds(region_coordinate),
		Rect2i(chunk_origin, coordinate_system.region_chunks)
	)
	regions[region_coordinate] = region
	return region


func get_records_in_chunk(
	chunk_coordinate: Vector2i,
	layer_type: StringName = &""
) -> Array[FoundationSpatialRecord]:
	return spatial_index.get_records_in_chunk(chunk_coordinate, layer_type)


func get_chunks_intersecting(bounds: Rect2) -> Array[FoundationChunkData]:
	var result: Array[FoundationChunkData] = []
	for chunk_coordinate in coordinate_system.world_bounds_to_chunks(bounds):
		result.append(ensure_chunk(chunk_coordinate))
	return result


func mark_layer_dirty(layer_type: StringName, bounds: Rect2) -> Array[Vector2i]:
	var layer := register_layer_type(layer_type)
	var dirty_chunks := layer.mark_bounds_dirty(bounds)
	for chunk_coordinate in dirty_chunks:
		ensure_chunk(chunk_coordinate).mark_layer_dirty(layer_type)
	return dirty_chunks


func get_sorted_chunks() -> Array[FoundationChunkData]:
	var result: Array[FoundationChunkData] = []
	for chunk: FoundationChunkData in chunks.values():
		result.append(chunk)
	result.sort_custom(func(a: FoundationChunkData, b: FoundationChunkData) -> bool:
		return FoundationSpatialRecord._sort_vector2i(a.coordinate, b.coordinate)
	)
	return result


func get_sorted_regions() -> Array[FoundationRegionData]:
	var result: Array[FoundationRegionData] = []
	for region: FoundationRegionData in regions.values():
		result.append(region)
	result.sort_custom(func(a: FoundationRegionData, b: FoundationRegionData) -> bool:
		return FoundationSpatialRecord._sort_vector2i(a.coordinate, b.coordinate)
	)
	return result


func to_dict() -> Dictionary:
	var serialized_layers: Array[Dictionary] = []
	for layer in layer_registry.get_layers():
		serialized_layers.append(layer.to_dict())
	var serialized_regions: Array[Dictionary] = []
	for region in get_sorted_regions():
		serialized_regions.append(region.to_dict())
	var serialized_chunks: Array[Dictionary] = []
	for chunk in get_sorted_chunks():
		serialized_chunks.append(chunk.to_dict())
	return {
		"format_version": FORMAT_VERSION,
		"metadata": metadata.to_dict(),
		"coordinate_system": coordinate_system.to_dict(),
		"layers": serialized_layers,
		"regions": serialized_regions,
		"chunks": serialized_chunks,
	}


static func from_dict(data: Dictionary) -> FoundationWorldData:
	var world := FoundationWorldData.new(
		FoundationWorldMetadata.from_dict(data.get("metadata", {})),
		FoundationCoordinateSystem.from_dict(data.get("coordinate_system", {}))
	)
	for region_data: Dictionary in data.get("regions", []):
		var region := FoundationRegionData.from_dict(region_data)
		world.regions[region.coordinate] = region
	for chunk_data: Dictionary in data.get("chunks", []):
		var chunk := FoundationChunkData.from_dict(chunk_data)
		world.chunks[chunk.coordinate] = chunk
	for layer_data: Dictionary in data.get("layers", []):
		var layer := FoundationSpatialLayer.from_dict(layer_data, world.coordinate_system, world.spatial_index)
		world.layer_registry.register_layer(layer)
	return world
