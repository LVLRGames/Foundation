@tool
class_name FoundationWorld
extends Node3D

## Scene owner for a renderer-independent FoundationWorldData instance.

signal world_initialized(data: FoundationWorldData)

@export var seed := 1337
@export var world_bounds := Rect2(-256.0, -256.0, 512.0, 512.0)
@export var cell_size := FoundationCoordinateSystem.DEFAULT_CELL_SIZE
@export var height_step := FoundationCoordinateSystem.DEFAULT_HEIGHT_STEP
@export var chunk_cells := FoundationCoordinateSystem.DEFAULT_CHUNK_CELLS
@export var region_chunks := Vector2i(2, 2)
@export var initialize_on_ready := true

var world_data: FoundationWorldData
var terrain_data: FoundationTerrainData
var terrain_origin_cell := Vector2i.ZERO


func _ready() -> void:
	if initialize_on_ready and not Engine.is_editor_hint():
		initialize_world()


func initialize_world() -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = seed
	metadata.world_bounds = world_bounds
	metadata.content_pack_version = &"phase-1"
	metadata.generation_metadata = {"phase": 1}
	var coordinates := FoundationCoordinateSystem.new(
		cell_size,
		height_step,
		chunk_cells,
		region_chunks
	)
	world_data = FoundationWorldData.new(metadata, coordinates)
	terrain_data = null
	terrain_origin_cell = Vector2i.ZERO
	world_data.initialize_default_layers()
	world_data.initialize_partitions()
	world_initialized.emit(world_data)
	return world_data


func register_terrain_extent(
	terrain_data: FoundationTerrainData,
	origin_cell := Vector2i.ZERO
) -> FoundationSpatialRecord:
	if world_data == null:
		initialize_world()
	self.terrain_data = terrain_data
	terrain_origin_cell = origin_cell
	var extent_id := FoundationSpatialId.make(
		world_data.metadata.seed,
		world_data.metadata.generator_version,
		world_data.metadata.content_pack_version,
		&"terrain_extent",
		&"",
		"%d,%d:%d,%d" % [origin_cell.x, origin_cell.y, terrain_data.grid_cells.x, terrain_data.grid_cells.y]
	)
	var bounds := Rect2(
		Vector2(origin_cell) * terrain_data.cell_size,
		Vector2(terrain_data.grid_cells) * terrain_data.cell_size
	)
	var record := FoundationSpatialRecord.new(
		extent_id,
		&"terrain_extent",
		FoundationWorldData.TERRAIN_LAYER,
		bounds
	)
	record.source_pass = &"terrain_generation"
	record.source_version = terrain_data.generator_version
	record.metadata = {"terrain_revision": terrain_data.revision}
	world_data.register_record(record)
	return record


func to_manifest() -> Dictionary:
	return world_data.to_dict() if world_data != null else {}


func load_manifest(manifest: Dictionary) -> void:
	world_data = FoundationWorldData.from_dict(manifest)
	terrain_data = null
	terrain_origin_cell = Vector2i.ZERO
	seed = world_data.metadata.seed
	world_bounds = world_data.metadata.world_bounds
	cell_size = world_data.coordinate_system.cell_size
	height_step = world_data.coordinate_system.height_step
	chunk_cells = world_data.coordinate_system.chunk_cells
	region_chunks = world_data.coordinate_system.region_chunks
	world_initialized.emit(world_data)
