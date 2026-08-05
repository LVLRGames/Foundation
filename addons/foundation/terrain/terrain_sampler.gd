class_name FoundationTerrainSampler
extends RefCounted

## Renderer-independent read API for roads, parcels, buildings, and gameplay.

var data: FoundationTerrainData


func _init(p_data: FoundationTerrainData) -> void:
	data = p_data


func get_height_at_grid(vertex: Vector2i) -> float:
	return data.get_vertex_height(vertex)


func get_height_at_world(world_xz: Vector2) -> float:
	var grid_position := world_xz / data.cell_size
	var cell := Vector2i(floori(grid_position.x), floori(grid_position.y))
	cell.x = clampi(cell.x, 0, data.grid_cells.x - 1)
	cell.y = clampi(cell.y, 0, data.grid_cells.y - 1)
	var fraction := Vector2(
		clampf(grid_position.x - cell.x, 0.0, 1.0),
		clampf(grid_position.y - cell.y, 0.0, 1.0)
	)

	var northwest := data.get_vertex_height(cell)
	var northeast := data.get_vertex_height(cell + Vector2i.RIGHT)
	var southwest := data.get_vertex_height(cell + Vector2i.DOWN)
	var southeast := data.get_vertex_height(cell + Vector2i.ONE)
	var diagonal := data.get_cell_diagonal(cell)

	if diagonal == FoundationTerrainData.TriangleDiagonal.NORTHWEST_SOUTHEAST:
		if fraction.y >= fraction.x:
			return northwest + fraction.y * (southwest - northwest) + fraction.x * (southeast - southwest)
		return northwest + fraction.x * (northeast - northwest) + fraction.y * (southeast - northeast)

	if fraction.x + fraction.y <= 1.0:
		return northwest + fraction.x * (northeast - northwest) + fraction.y * (southwest - northwest)
	return southeast + (1.0 - fraction.y) * (northeast - southeast) + (1.0 - fraction.x) * (southwest - southeast)


func get_surface_at_grid(cell: Vector2i) -> int:
	return data.get_cell_surface(cell)


func get_surface_at_world(world_xz: Vector2) -> int:
	return data.get_cell_surface(_world_to_cell(world_xz))


func get_slope_degrees_at_grid(cell: Vector2i) -> float:
	assert(data.is_valid_cell(cell), "Cell coordinate is outside TerrainData.")
	var northwest := data.get_vertex_height(cell)
	var northeast := data.get_vertex_height(cell + Vector2i.RIGHT)
	var southwest := data.get_vertex_height(cell + Vector2i.DOWN)
	var southeast := data.get_vertex_height(cell + Vector2i.ONE)
	var maximum_rise := maxf(
		maxf(absf(northwest - southeast), absf(northeast - southwest)),
		maxf(absf(northwest - northeast), absf(northwest - southwest))
	)
	return rad_to_deg(atan(maximum_rise / data.cell_size))


func get_slope_degrees_at_world(world_xz: Vector2) -> float:
	return get_slope_degrees_at_grid(_world_to_cell(world_xz))


func is_buildable_at_grid(cell: Vector2i, maximum_slope_degrees := 15.0) -> bool:
	if not data.is_valid_cell(cell):
		return false
	var blocked_flags := (
		FoundationTerrainData.CellFlag.NO_BUILD
		| FoundationTerrainData.CellFlag.PROTECTED
		| FoundationTerrainData.CellFlag.WATER
	)
	return (
		(data.get_cell_flags(cell) & blocked_flags) == 0
		and get_slope_degrees_at_grid(cell) <= maximum_slope_degrees
	)


func is_buildable_at_world(world_xz: Vector2, maximum_slope_degrees := 15.0) -> bool:
	return is_buildable_at_grid(_world_to_cell(world_xz), maximum_slope_degrees)


func _world_to_cell(world_xz: Vector2) -> Vector2i:
	return Vector2i(
		clampi(floori(world_xz.x / data.cell_size), 0, data.grid_cells.x - 1),
		clampi(floori(world_xz.y / data.cell_size), 0, data.grid_cells.y - 1)
	)
