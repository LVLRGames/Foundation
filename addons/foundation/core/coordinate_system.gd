class_name FoundationCoordinateSystem
extends RefCounted

## Single authority for Foundation's XZ-plane coordinate conversions.

const FORMAT_VERSION := 1
const DEFAULT_CELL_SIZE := 4.0
const DEFAULT_HEIGHT_STEP := 1.0
const DEFAULT_CHUNK_CELLS := Vector2i(32, 32)
const DEFAULT_REGION_CHUNKS := Vector2i(8, 8)

var cell_size: float
var height_step: float
var chunk_cells: Vector2i
var region_chunks: Vector2i


func _init(
	p_cell_size := DEFAULT_CELL_SIZE,
	p_height_step := DEFAULT_HEIGHT_STEP,
	p_chunk_cells := DEFAULT_CHUNK_CELLS,
	p_region_chunks := DEFAULT_REGION_CHUNKS
) -> void:
	assert(p_cell_size > 0.0, "Cell size must be positive.")
	assert(p_height_step > 0.0, "Height step must be positive.")
	assert(p_chunk_cells.x > 0 and p_chunk_cells.y > 0, "Chunk dimensions must be positive.")
	assert(p_region_chunks.x > 0 and p_region_chunks.y > 0, "Region dimensions must be positive.")
	cell_size = p_cell_size
	height_step = p_height_step
	chunk_cells = p_chunk_cells
	region_chunks = p_region_chunks


func get_chunk_world_size() -> Vector2:
	return Vector2(chunk_cells) * cell_size


func get_region_world_size() -> Vector2:
	return get_chunk_world_size() * Vector2(region_chunks)


func world_to_terrain_vertex(world_position: Vector3) -> Vector2i:
	return Vector2i(
		roundi(world_position.x / cell_size),
		roundi(world_position.z / cell_size)
	)


func terrain_vertex_to_world(vertex: Vector2i, elevation := 0.0) -> Vector3:
	return Vector3(vertex.x * cell_size, elevation, vertex.y * cell_size)


func world_to_terrain_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_position.x / cell_size),
		floori(world_position.z / cell_size)
	)


func terrain_cell_to_world(cell: Vector2i, elevation := 0.0) -> Vector3:
	return Vector3(cell.x * cell_size, elevation, cell.y * cell_size)


func world_to_chunk(world_position: Vector3) -> Vector2i:
	var chunk_world_size := get_chunk_world_size()
	return Vector2i(
		floori(world_position.x / chunk_world_size.x),
		floori(world_position.z / chunk_world_size.y)
	)


func terrain_cell_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floor_div(cell.x, chunk_cells.x),
		floor_div(cell.y, chunk_cells.y)
	)


func chunk_to_terrain_cell_origin(chunk: Vector2i) -> Vector2i:
	return chunk * chunk_cells


func chunk_local_cell_to_terrain_cell(chunk: Vector2i, local_cell: Vector2i) -> Vector2i:
	return chunk_to_terrain_cell_origin(chunk) + local_cell


func chunk_local_vertex_to_terrain_vertex(chunk: Vector2i, local_vertex: Vector2i) -> Vector2i:
	return chunk_to_terrain_cell_origin(chunk) + local_vertex


func chunk_to_region(chunk: Vector2i) -> Vector2i:
	return Vector2i(
		floor_div(chunk.x, region_chunks.x),
		floor_div(chunk.y, region_chunks.y)
	)


func local_cell_in_chunk(cell: Vector2i) -> Vector2i:
	var chunk := terrain_cell_to_chunk(cell)
	return cell - chunk * chunk_cells


func local_vertex_in_chunk(vertex: Vector2i, chunk: Vector2i) -> Vector2i:
	return vertex - chunk * chunk_cells


func world_to_local_cell(world_position: Vector3) -> Vector2i:
	return local_cell_in_chunk(world_to_terrain_cell(world_position))


func chunk_to_world_bounds(chunk: Vector2i) -> Rect2:
	var chunk_world_size := get_chunk_world_size()
	return Rect2(Vector2(chunk) * chunk_world_size, chunk_world_size)


func region_to_world_bounds(region: Vector2i) -> Rect2:
	var region_world_size := get_region_world_size()
	return Rect2(Vector2(region) * region_world_size, region_world_size)


func world_bounds_to_chunks(bounds: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var minimum := world_to_chunk(Vector3(bounds.position.x, 0.0, bounds.position.y))
	var maximum_point := bounds.position
	if bounds.size.x > 0.0:
		maximum_point.x = bounds.end.x - 0.000001
	if bounds.size.y > 0.0:
		maximum_point.y = bounds.end.y - 0.000001
	var maximum := world_to_chunk(Vector3(maximum_point.x, 0.0, maximum_point.y))
	for chunk_y in range(minimum.y, maximum.y + 1):
		for chunk_x in range(minimum.x, maximum.x + 1):
			result.append(Vector2i(chunk_x, chunk_y))
	return result


func snap_world(world_position: Vector3, grid_size: float) -> Vector3:
	assert(grid_size > 0.0, "Snap grid size must be positive.")
	return Vector3(
		round(world_position.x / grid_size) * grid_size,
		round(world_position.y / grid_size) * grid_size,
		round(world_position.z / grid_size) * grid_size
	)


func snap_1m(world_position: Vector3) -> Vector3:
	return snap_world(world_position, 1.0)


func snap_2m(world_position: Vector3) -> Vector3:
	return snap_world(world_position, 2.0)


func snap_4m(world_position: Vector3) -> Vector3:
	return snap_world(world_position, 4.0)


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"cell_size": cell_size,
		"height_step": height_step,
		"chunk_cells": {"x": chunk_cells.x, "y": chunk_cells.y},
		"region_chunks": {"x": region_chunks.x, "y": region_chunks.y},
	}


static func from_dict(data: Dictionary) -> FoundationCoordinateSystem:
	var chunk_data: Dictionary = data.get("chunk_cells", {})
	var region_data: Dictionary = data.get("region_chunks", {})
	return FoundationCoordinateSystem.new(
		float(data.get("cell_size", DEFAULT_CELL_SIZE)),
		float(data.get("height_step", DEFAULT_HEIGHT_STEP)),
		Vector2i(int(chunk_data.get("x", 32)), int(chunk_data.get("y", 32))),
		Vector2i(int(region_data.get("x", 8)), int(region_data.get("y", 8)))
	)


static func floor_div(value: int, divisor: int) -> int:
	assert(divisor > 0, "Floor-division divisor must be positive.")
	return floori(float(value) / float(divisor))
