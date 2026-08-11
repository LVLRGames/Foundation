class_name FoundationTerrainData
extends RefCounted

## Authoritative terrain state. No scene-tree or renderer dependency is allowed here.

enum CellFlag {
	NO_BUILD = 1 << 0,
	PROTECTED = 1 << 1,
	WATER = 1 << 2,
}

enum ModificationSource {
	NATURAL,
	MANUAL,
	ROAD_CUT,
	ROAD_FILL,
	BUILDING_PAD,
	BRIDGE_APPROACH,
	RIVERBED,
	GAMEPLAY,
}

enum TriangleDiagonal {
	NORTHWEST_SOUTHEAST,
	NORTHEAST_SOUTHWEST,
}

var seed: int
var generator_version: int
var content_pack_version: StringName
var grid_cells: Vector2i
var cell_size: float
var height_step: float
var chunk_cells: Vector2i

var vertex_heights := PackedFloat32Array()
var vertex_flags := PackedByteArray()
var vertex_modification_sources := PackedByteArray()
var cell_surfaces := PackedInt32Array()
var cell_flags := PackedByteArray()
var cell_diagonals := PackedByteArray()

var revision := 0
var _dirty_chunks: Dictionary = {}


func _init(
	p_seed: int,
	p_grid_cells: Vector2i,
	p_cell_size: float,
	p_height_step: float,
	p_chunk_cells: Vector2i,
	p_generator_version: int = FoundationSeed.GENERATOR_VERSION,
	p_content_pack_version: StringName = &"phase-0"
) -> void:
	seed = p_seed
	grid_cells = p_grid_cells
	cell_size = p_cell_size
	height_step = p_height_step
	chunk_cells = p_chunk_cells
	generator_version = p_generator_version
	content_pack_version = p_content_pack_version

	var vertex_count := (grid_cells.x + 1) * (grid_cells.y + 1)
	vertex_heights.resize(vertex_count)
	vertex_flags.resize(vertex_count)
	vertex_modification_sources.resize(vertex_count)
	vertex_modification_sources.fill(ModificationSource.NATURAL)

	var cell_count := grid_cells.x * grid_cells.y
	cell_surfaces.resize(cell_count)
	cell_surfaces.fill(FoundationTerrainSurface.Type.GRASS)
	cell_flags.resize(cell_count)
	cell_diagonals.resize(cell_count)


func is_valid_vertex(vertex: Vector2i) -> bool:
	return vertex.x >= 0 and vertex.y >= 0 and vertex.x <= grid_cells.x and vertex.y <= grid_cells.y


func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_cells.x and cell.y < grid_cells.y


func vertex_index(vertex: Vector2i) -> int:
	return vertex.y * (grid_cells.x + 1) + vertex.x


func cell_index(cell: Vector2i) -> int:
	return cell.y * grid_cells.x + cell.x


func quantize_height(height: float) -> float:
	return round(height / height_step) * height_step


func get_vertex_height(vertex: Vector2i) -> float:
	assert(is_valid_vertex(vertex), "Vertex coordinate is outside TerrainData.")
	return vertex_heights[vertex_index(vertex)]


func set_vertex_height(
	vertex: Vector2i,
	height: float,
	source: ModificationSource = ModificationSource.MANUAL,
	mark_dirty := true
) -> bool:
	assert(is_valid_vertex(vertex), "Vertex coordinate is outside TerrainData.")
	var index := vertex_index(vertex)
	var quantized := quantize_height(height)
	if is_equal_approx(vertex_heights[index], quantized) and vertex_modification_sources[index] == source:
		return false
	vertex_heights[index] = quantized
	vertex_modification_sources[index] = source
	revision += 1
	if mark_dirty:
		mark_vertex_dirty(vertex)
		refresh_cell_diagonals_around_vertex(vertex)
	return true


func get_cell_surface(cell: Vector2i) -> int:
	assert(is_valid_cell(cell), "Cell coordinate is outside TerrainData.")
	return cell_surfaces[cell_index(cell)]


func set_cell_surface(cell: Vector2i, surface_id: int, mark_dirty := true) -> bool:
	assert(is_valid_cell(cell), "Cell coordinate is outside TerrainData.")
	assert(FoundationTerrainSurface.is_valid(surface_id), "Unknown terrain surface ID.")
	var index := cell_index(cell)
	if cell_surfaces[index] == surface_id:
		return false
	cell_surfaces[index] = surface_id
	revision += 1
	if mark_dirty:
		mark_cell_dirty(cell)
	return true


func get_cell_flags(cell: Vector2i) -> int:
	assert(is_valid_cell(cell), "Cell coordinate is outside TerrainData.")
	return cell_flags[cell_index(cell)]


func set_cell_flags(cell: Vector2i, flags: int, mark_dirty := true) -> bool:
	assert(is_valid_cell(cell), "Cell coordinate is outside TerrainData.")
	var index := cell_index(cell)
	if cell_flags[index] == flags:
		return false
	cell_flags[index] = flags
	revision += 1
	if mark_dirty:
		mark_cell_dirty(cell)
	return true


func get_cell_diagonal(cell: Vector2i) -> TriangleDiagonal:
	assert(is_valid_cell(cell), "Cell coordinate is outside TerrainData.")
	return cell_diagonals[cell_index(cell)] as TriangleDiagonal


func set_cell_diagonal(cell: Vector2i, diagonal: TriangleDiagonal, mark_dirty := true) -> bool:
	assert(is_valid_cell(cell), "Cell coordinate is outside TerrainData.")
	var index := cell_index(cell)
	if cell_diagonals[index] == diagonal:
		return false
	cell_diagonals[index] = diagonal
	revision += 1
	if mark_dirty:
		mark_cell_dirty(cell)
	return true


func calculate_preferred_diagonal(cell: Vector2i) -> TriangleDiagonal:
	assert(is_valid_cell(cell), "Cell coordinate is outside TerrainData.")
	var northwest := get_vertex_height(cell)
	var northeast := get_vertex_height(cell + Vector2i.RIGHT)
	var southwest := get_vertex_height(cell + Vector2i.DOWN)
	var southeast := get_vertex_height(cell + Vector2i.ONE)
	if absf(northwest - southeast) <= absf(northeast - southwest):
		return TriangleDiagonal.NORTHWEST_SOUTHEAST
	return TriangleDiagonal.NORTHEAST_SOUTHWEST


func refresh_cell_diagonals_around_vertex(vertex: Vector2i) -> void:
	for offset in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO]:
		var cell: Vector2i = vertex + offset
		if is_valid_cell(cell):
			set_cell_diagonal(cell, calculate_preferred_diagonal(cell), false)


func get_chunk_count() -> Vector2i:
	return Vector2i(
		ceili(float(grid_cells.x) / float(chunk_cells.x)),
		ceili(float(grid_cells.y) / float(chunk_cells.y))
	)


func get_chunk_cell_rect(chunk: Vector2i) -> Rect2i:
	var origin := chunk * chunk_cells
	var size := Vector2i(
		mini(chunk_cells.x, grid_cells.x - origin.x),
		mini(chunk_cells.y, grid_cells.y - origin.y)
	)
	return Rect2i(origin, size)


func is_valid_chunk(chunk: Vector2i) -> bool:
	var count := get_chunk_count()
	return chunk.x >= 0 and chunk.y >= 0 and chunk.x < count.x and chunk.y < count.y


func mark_cell_dirty(cell: Vector2i) -> void:
	if not is_valid_cell(cell):
		return
	mark_chunk_dirty(Vector2i(cell.x / chunk_cells.x, cell.y / chunk_cells.y))


func mark_vertex_dirty(vertex: Vector2i) -> void:
	if not is_valid_vertex(vertex):
		return
	# A shared vertex can affect up to four cells and therefore up to four chunks.
	for offset in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO]:
		var cell: Vector2i = vertex + offset
		if is_valid_cell(cell):
			mark_cell_dirty(cell)


func mark_chunk_dirty(chunk: Vector2i) -> void:
	if is_valid_chunk(chunk):
		_dirty_chunks[chunk] = true


func clear_chunk_dirty(chunk: Vector2i) -> void:
	_dirty_chunks.erase(chunk)


func mark_all_chunks_dirty() -> void:
	var count := get_chunk_count()
	for chunk_y in range(count.y):
		for chunk_x in range(count.x):
			_dirty_chunks[Vector2i(chunk_x, chunk_y)] = true


func clear_dirty_chunks() -> void:
	_dirty_chunks.clear()


func get_dirty_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for chunk: Vector2i in _dirty_chunks:
		result.append(chunk)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return result


func take_dirty_chunks() -> Array[Vector2i]:
	var result := get_dirty_chunks()
	_dirty_chunks.clear()
	return result


func surface_at_vertex(vertex: Vector2i) -> int:
	var counts: Dictionary = {}
	for offset in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO]:
		var cell: Vector2i = vertex + offset
		if is_valid_cell(cell):
			var surface_id := get_cell_surface(cell)
			counts[surface_id] = counts.get(surface_id, 0) + 1
	var best_surface := FoundationTerrainSurface.Type.GRASS
	var best_count := -1
	for surface_id: int in counts:
		var count: int = counts[surface_id]
		if count > best_count or (count == best_count and surface_id < best_surface):
			best_surface = surface_id
			best_count = count
	return best_surface
