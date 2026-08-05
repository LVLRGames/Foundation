class_name FoundationTerrainModifier
extends RefCounted

## Semantic editing operations over TerrainData. Rendering is deliberately not invoked here.

var data: FoundationTerrainData


func _init(p_data: FoundationTerrainData) -> void:
	data = p_data


func set_height(
	vertex: Vector2i,
	height: float,
	source: FoundationTerrainData.ModificationSource = FoundationTerrainData.ModificationSource.MANUAL
) -> bool:
	return data.set_vertex_height(vertex, height, source)


func add_height(
	vertex: Vector2i,
	delta: float,
	source: FoundationTerrainData.ModificationSource = FoundationTerrainData.ModificationSource.MANUAL
) -> bool:
	return data.set_vertex_height(vertex, data.get_vertex_height(vertex) + delta, source)


func flatten(
	vertex_rect: Rect2i,
	target_height: float,
	source: FoundationTerrainData.ModificationSource = FoundationTerrainData.ModificationSource.MANUAL
) -> int:
	var changed_count := 0
	var clipped := vertex_rect.intersection(Rect2i(Vector2i.ZERO, data.grid_cells + Vector2i.ONE))
	for vertex_y in range(clipped.position.y, clipped.end.y):
		for vertex_x in range(clipped.position.x, clipped.end.x):
			if data.set_vertex_height(Vector2i(vertex_x, vertex_y), target_height, source):
				changed_count += 1
	return changed_count


func set_surface(cell: Vector2i, surface_id: int) -> bool:
	return data.set_cell_surface(cell, surface_id)


func set_buildable(cell: Vector2i, buildable: bool) -> bool:
	var flags := data.get_cell_flags(cell)
	if buildable:
		flags &= ~FoundationTerrainData.CellFlag.NO_BUILD
	else:
		flags |= FoundationTerrainData.CellFlag.NO_BUILD
	return data.set_cell_flags(cell, flags)
