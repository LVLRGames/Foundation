class_name FoundationTerrainMesher
extends RefCounted

## Converts one TerrainData chunk into indexed visual geometry or exact triangle faces.


static func build_mesh(
	data: FoundationTerrainData,
	chunk: Vector2i,
	smooth_normals := true,
	lod_level := 0
) -> ArrayMesh:
	assert(data.is_valid_chunk(chunk), "Chunk coordinate is outside TerrainData.")
	if not smooth_normals:
		return _build_flat_mesh(data, chunk, lod_level)
	var rect := data.get_chunk_cell_rect(chunk)
	var stride := 1 << clampi(lod_level, 0, 16)
	var x_offsets := _sample_offsets(rect.size.x, stride)
	var y_offsets := _sample_offsets(rect.size.y, stride)
	var local_vertex_size := Vector2i(x_offsets.size(), y_offsets.size())
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(local_vertex_size.x * local_vertex_size.y)
	normals.resize(vertices.size())
	colors.resize(vertices.size())
	uvs.resize(vertices.size())
	indices.resize((local_vertex_size.x - 1) * (local_vertex_size.y - 1) * 6)

	for local_y in range(local_vertex_size.y):
		for local_x in range(local_vertex_size.x):
			var local_vertex := Vector2i(x_offsets[local_x], y_offsets[local_y])
			var global_vertex := rect.position + local_vertex
			var index := local_y * local_vertex_size.x + local_x
			vertices[index] = Vector3(
				local_vertex.x * data.cell_size,
				data.get_vertex_height(global_vertex),
				local_vertex.y * data.cell_size
			)
			normals[index] = _calculate_vertex_normal(data, global_vertex)
			colors[index] = FoundationTerrainSurface.color(data.surface_at_vertex(global_vertex))
			uvs[index] = Vector2(local_vertex)

	var write_index := 0
	for local_y in range(local_vertex_size.y - 1):
		for local_x in range(local_vertex_size.x - 1):
			var cell := rect.position + Vector2i(x_offsets[local_x], y_offsets[local_y])
			var northwest := local_y * local_vertex_size.x + local_x
			var northeast := northwest + 1
			var southwest := northwest + local_vertex_size.x
			var southeast := southwest + 1
			var diagonal := _lod_diagonal(
				data,
				cell,
				Vector2i(x_offsets[local_x + 1] - x_offsets[local_x], y_offsets[local_y + 1] - y_offsets[local_y]),
				lod_level
			)
			if diagonal == FoundationTerrainData.TriangleDiagonal.NORTHWEST_SOUTHEAST:
				write_index = _write_triangle(indices, write_index, northwest, southeast, southwest)
				write_index = _write_triangle(indices, write_index, northwest, northeast, southeast)
			else:
				write_index = _write_triangle(indices, write_index, northwest, northeast, southwest)
				write_index = _write_triangle(indices, write_index, northeast, southeast, southwest)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _build_flat_mesh(data: FoundationTerrainData, chunk: Vector2i, lod_level: int) -> ArrayMesh:
	var rect := data.get_chunk_cell_rect(chunk)
	var stride := 1 << clampi(lod_level, 0, 16)
	var x_offsets := _sample_offsets(rect.size.x, stride)
	var y_offsets := _sample_offsets(rect.size.y, stride)
	var vertices := build_collision_faces(data, chunk, lod_level)
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	normals.resize(vertices.size())
	colors.resize(vertices.size())
	uvs.resize(vertices.size())
	for triangle_start in range(0, vertices.size(), 3):
		var normal := (
			vertices[triangle_start + 1] - vertices[triangle_start]
		).cross(vertices[triangle_start + 2] - vertices[triangle_start]).normalized()
		# Godot front faces use clockwise winding, whose geometric cross product points
		# opposite the authored lighting normal for this XZ terrain convention.
		if normal.y < 0.0:
			normal = -normal
		for offset in range(3):
			normals[triangle_start + offset] = normal
	var write_index := 0
	for local_y in range(y_offsets.size() - 1):
		for local_x in range(x_offsets.size() - 1):
			var cell := rect.position + Vector2i(x_offsets[local_x], y_offsets[local_y])
			var cell_color := FoundationTerrainSurface.color(data.get_cell_surface(cell))
			for offset in range(6):
				colors[write_index + offset] = cell_color
				uvs[write_index + offset] = Vector2(
					vertices[write_index + offset].x / data.cell_size,
					vertices[write_index + offset].z / data.cell_size
				)
			write_index += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func build_collision_faces(
	data: FoundationTerrainData,
	chunk: Vector2i,
	lod_level := 0
) -> PackedVector3Array:
	assert(data.is_valid_chunk(chunk), "Chunk coordinate is outside TerrainData.")
	var rect := data.get_chunk_cell_rect(chunk)
	var stride := 1 << clampi(lod_level, 0, 16)
	var x_offsets := _sample_offsets(rect.size.x, stride)
	var y_offsets := _sample_offsets(rect.size.y, stride)
	var faces := PackedVector3Array()
	faces.resize((x_offsets.size() - 1) * (y_offsets.size() - 1) * 6)
	var write_index := 0
	for local_y in range(y_offsets.size() - 1):
		for local_x in range(x_offsets.size() - 1):
			var cell := rect.position + Vector2i(x_offsets[local_x], y_offsets[local_y])
			var extent := Vector2i(
				x_offsets[local_x + 1] - x_offsets[local_x],
				y_offsets[local_y + 1] - y_offsets[local_y]
			)
			var northwest := _local_vertex(data, rect.position, cell)
			var northeast := _local_vertex(data, rect.position, cell + Vector2i(extent.x, 0))
			var southwest := _local_vertex(data, rect.position, cell + Vector2i(0, extent.y))
			var southeast := _local_vertex(data, rect.position, cell + extent)
			if _lod_diagonal(data, cell, extent, lod_level) == FoundationTerrainData.TriangleDiagonal.NORTHWEST_SOUTHEAST:
				write_index = _write_face(faces, write_index, northwest, southeast, southwest)
				write_index = _write_face(faces, write_index, northwest, northeast, southeast)
			else:
				write_index = _write_face(faces, write_index, northwest, northeast, southwest)
				write_index = _write_face(faces, write_index, northeast, southeast, southwest)
	return faces


static func _sample_offsets(cell_count: int, stride: int) -> PackedInt32Array:
	var offsets := PackedInt32Array([0])
	var offset := stride
	while offset < cell_count:
		offsets.append(offset)
		offset += stride
	if offsets[offsets.size() - 1] != cell_count:
		offsets.append(cell_count)
	return offsets


static func _lod_diagonal(
	data: FoundationTerrainData,
	cell: Vector2i,
	extent: Vector2i,
	lod_level: int
) -> FoundationTerrainData.TriangleDiagonal:
	if lod_level <= 0 and extent == Vector2i.ONE:
		return data.get_cell_diagonal(cell)
	var northwest := data.get_vertex_height(cell)
	var northeast := data.get_vertex_height(cell + Vector2i(extent.x, 0))
	var southwest := data.get_vertex_height(cell + Vector2i(0, extent.y))
	var southeast := data.get_vertex_height(cell + extent)
	if absf(northwest - southeast) <= absf(northeast - southwest):
		return FoundationTerrainData.TriangleDiagonal.NORTHWEST_SOUTHEAST
	return FoundationTerrainData.TriangleDiagonal.NORTHEAST_SOUTHWEST


static func _calculate_vertex_normal(data: FoundationTerrainData, vertex: Vector2i) -> Vector3:
	# Sample authoritative neighbors so border normals are identical in adjacent chunks.
	var left := data.get_vertex_height(Vector2i(maxi(vertex.x - 1, 0), vertex.y))
	var right := data.get_vertex_height(Vector2i(mini(vertex.x + 1, data.grid_cells.x), vertex.y))
	var north := data.get_vertex_height(Vector2i(vertex.x, maxi(vertex.y - 1, 0)))
	var south := data.get_vertex_height(Vector2i(vertex.x, mini(vertex.y + 1, data.grid_cells.y)))
	return Vector3(left - right, data.cell_size * 2.0, north - south).normalized()


static func _local_vertex(data: FoundationTerrainData, chunk_origin: Vector2i, vertex: Vector2i) -> Vector3:
	var local := vertex - chunk_origin
	return Vector3(local.x * data.cell_size, data.get_vertex_height(vertex), local.y * data.cell_size)


static func _write_triangle(
	indices: PackedInt32Array,
	write_index: int,
	a: int,
	b: int,
	c: int
) -> int:
	indices[write_index] = a
	indices[write_index + 1] = b
	indices[write_index + 2] = c
	return write_index + 3


static func _write_face(
	faces: PackedVector3Array,
	write_index: int,
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> int:
	faces[write_index] = a
	faces[write_index + 1] = b
	faces[write_index + 2] = c
	return write_index + 3
