class_name FoundationWorldData
extends RefCounted

## Renderer-independent owner of Foundation's abstract world state.

const FORMAT_VERSION := 1
const TERRAIN_LAYER: StringName = &"terrain"
const OVERRIDE_LAYER: StringName = &"override"
const CITY_ANCHOR_LAYER: StringName = FoundationCityAnchor.LAYER_TYPE
const ROAD_NODE_LAYER: StringName = FoundationRoadNode.LAYER_TYPE
const ROAD_EDGE_LAYER: StringName = FoundationRoadEdge.LAYER_TYPE
const ROAD_PATTERN_LAYER: StringName = FoundationRoadPatternArea.LAYER_TYPE
const LOGICAL_ROAD_LAYER: StringName = FoundationLogicalRoad.LAYER_TYPE
const ROAD_INTERSECTION_LAYER: StringName = FoundationIntersectionRecord.LAYER_TYPE
const BLOCK_LAYER: StringName = FoundationBlockRecord.LAYER_TYPE
const PARCEL_LAYER: StringName = FoundationParcelRecord.LAYER_TYPE
const BUILDING_LAYER: StringName = FoundationBuildingRecord.LAYER_TYPE
const FACADE_LAYER: StringName = FoundationFacadeRecord.LAYER_TYPE
const DISTRICT_LAYER: StringName = FoundationDistrictRecord.LAYER_TYPE

var metadata: FoundationWorldMetadata
var coordinate_system: FoundationCoordinateSystem
var spatial_index: FoundationSpatialIndex
var layer_registry := FoundationLayerRegistry.new()
var regions: Dictionary = {}
var chunks: Dictionary = {}
var terrain_grading_plan: FoundationTerrainGradingPlan


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
	register_layer_type(CITY_ANCHOR_LAYER)
	register_layer_type(ROAD_NODE_LAYER)
	register_layer_type(ROAD_EDGE_LAYER)
	register_layer_type(ROAD_PATTERN_LAYER)
	register_layer_type(LOGICAL_ROAD_LAYER)
	register_layer_type(ROAD_INTERSECTION_LAYER)
	register_layer_type(BLOCK_LAYER)
	register_layer_type(PARCEL_LAYER)
	register_layer_type(BUILDING_LAYER)
	register_layer_type(FACADE_LAYER)
	register_layer_type(DISTRICT_LAYER)


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


func get_anchors() -> Array[FoundationCityAnchor]:
	var result: Array[FoundationCityAnchor] = []
	var layer := get_layer(CITY_ANCHOR_LAYER)
	if layer == null:
		return result
	for record in layer.get_records():
		if record is FoundationCityAnchor:
			result.append(record as FoundationCityAnchor)
	return result


func get_road_nodes() -> Array[FoundationRoadNode]:
	var result: Array[FoundationRoadNode] = []
	var layer := get_layer(ROAD_NODE_LAYER)
	if layer == null:
		return result
	for record in layer.get_records():
		if record is FoundationRoadNode:
			result.append(record as FoundationRoadNode)
	return result


func get_road_edges() -> Array[FoundationRoadEdge]:
	var result: Array[FoundationRoadEdge] = []
	var layer := get_layer(ROAD_EDGE_LAYER)
	if layer == null:
		return result
	for record in layer.get_records():
		if record is FoundationRoadEdge:
			result.append(record as FoundationRoadEdge)
	return result


func get_road_pattern_areas() -> Array[FoundationRoadPatternArea]:
	var result: Array[FoundationRoadPatternArea] = []
	var layer := get_layer(ROAD_PATTERN_LAYER)
	if layer == null:
		return result
	for record in layer.get_records():
		if record is FoundationRoadPatternArea:
			result.append(record as FoundationRoadPatternArea)
	return result


func get_logical_roads() -> Array[FoundationLogicalRoad]:
	var result: Array[FoundationLogicalRoad] = []
	var layer := get_layer(LOGICAL_ROAD_LAYER)
	if layer == null:
		return result
	for record in layer.get_records():
		if record is FoundationLogicalRoad:
			result.append(record as FoundationLogicalRoad)
	return result


func get_road_intersections() -> Array[FoundationIntersectionRecord]:
	var result: Array[FoundationIntersectionRecord] = []
	var layer := get_layer(ROAD_INTERSECTION_LAYER)
	if layer == null:
		return result
	for record in layer.get_records():
		if record is FoundationIntersectionRecord:
			result.append(record as FoundationIntersectionRecord)
	return result


func get_blocks() -> Array[FoundationBlockRecord]:
	var result: Array[FoundationBlockRecord] = []
	var layer := get_layer(BLOCK_LAYER)
	if layer == null:
		return result
	for record in layer.get_records():
		if record is FoundationBlockRecord:
			result.append(record as FoundationBlockRecord)
	return result


func get_parcels() -> Array[FoundationParcelRecord]:
	var result: Array[FoundationParcelRecord] = []
	var layer := get_layer(PARCEL_LAYER)
	if layer == null:
		return result
	for record in layer.get_records():
		if record is FoundationParcelRecord:
			result.append(record as FoundationParcelRecord)
	return result


func get_buildings() -> Array[FoundationBuildingRecord]:
	var result: Array[FoundationBuildingRecord] = []
	var layer := get_layer(BUILDING_LAYER)
	if layer == null:
		return result
	for record in layer.get_records():
		if record is FoundationBuildingRecord:
			result.append(record as FoundationBuildingRecord)
	return result


func get_facades() -> Array[FoundationFacadeRecord]:
	var result: Array[FoundationFacadeRecord] = []
	var layer := get_layer(FACADE_LAYER)
	if layer == null:
		return result
	for record in layer.get_records():
		if record is FoundationFacadeRecord:
			result.append(record as FoundationFacadeRecord)
	return result


func get_districts() -> Array[FoundationDistrictRecord]:
	var result: Array[FoundationDistrictRecord] = []
	var layer := get_layer(DISTRICT_LAYER)
	if layer == null:
		return result
	for record in layer.get_records():
		if record is FoundationDistrictRecord:
			result.append(record as FoundationDistrictRecord)
	return result


func get_district_for_block(block_id: StringName) -> FoundationDistrictRecord:
	for district in get_districts():
		if district.member_block_ids.has(block_id):
			return district
	return null


func get_district_for_parcel(parcel_id: StringName) -> FoundationDistrictRecord:
	var parcel := get_record(parcel_id) as FoundationParcelRecord
	return get_district_for_block(parcel.parent_id) if parcel != null else null


func get_district_for_building(building_id: StringName) -> FoundationDistrictRecord:
	var building := get_record(building_id) as FoundationBuildingRecord
	return get_district_for_block(building.parent_block_id) if building != null else null


func get_district_for_facade(facade_id: StringName) -> FoundationDistrictRecord:
	var facade := get_record(facade_id) as FoundationFacadeRecord
	return get_district_for_block(facade.parent_block_id) if facade != null else null


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


func get_records_in_region(
	region_coordinate: Vector2i,
	layer_type: StringName = &""
) -> Array[FoundationSpatialRecord]:
	return spatial_index.get_records_in_region(region_coordinate, layer_type)


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
		"terrain_grading_plan": terrain_grading_plan.to_dict() if terrain_grading_plan != null else {},
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
	var grading_data: Dictionary = data.get("terrain_grading_plan", {})
	if not grading_data.is_empty():
		world.terrain_grading_plan = FoundationTerrainGradingPlan.from_dict(grading_data)
	return world
