class_name FoundationTerrainMesher
extends RefCounted

## Converts one TerrainData chunk into indexed visual geometry or exact triangle faces.


static func build_mesh(data: FoundationTerrainData, chunk: Vector2i, smooth_normals := true) -> ArrayMesh:
	assert(data.is_valid_chunk(chunk), "Chunk coordinate is outside TerrainData.")
	if not smooth_normals:
		return _build_flat_mesh(data, chunk)
	var rect := data.get_chunk_cell_rect(chunk)
	var local_vertex_size := rect.size + Vector2i.ONE
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(local_vertex_size.x * local_vertex_size.y)
	normals.resize(vertices.size())
	colors.resize(vertices.size())
	uvs.resize(vertices.size())
	indices.resize(rect.size.x * rect.size.y * 6)

	for local_y in range(local_vertex_size.y):
		for local_x in range(local_vertex_size.x):
			var local_vertex := Vector2i(local_x, local_y)
			var global_vertex := rect.position + local_vertex
			var index := local_y * local_vertex_size.x + local_x
			vertices[index] = Vector3(
				local_x * data.cell_size,
				data.get_vertex_height(global_vertex),
				local_y * data.cell_size
			)
			normals[index] = _calculate_vertex_normal(data, global_vertex)
			colors[index] = FoundationTerrainSurface.color(data.surface_at_vertex(global_vertex))
			uvs[index] = Vector2(local_x, local_y)

	var write_index := 0
	for local_y in range(rect.size.y):
		for local_x in range(rect.size.x):
			var cell := rect.position + Vector2i(local_x, local_y)
			var northwest := local_y * local_vertex_size.x + local_x
			var northeast := northwest + 1
			var southwest := northwest + local_vertex_size.x
			var southeast := southwest + 1
			if data.get_cell_diagonal(cell) == FoundationTerrainData.TriangleDiagonal.NORTHWEST_SOUTHEAST:
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


static func _build_flat_mesh(data: FoundationTerrainData, chunk: Vector2i) -> ArrayMesh:
	var rect := data.get_chunk_cell_rect(chunk)
	var vertices := build_collision_faces(data, chunk)
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
	for local_y in range(rect.size.y):
		for local_x in range(rect.size.x):
			var cell := rect.position + Vector2i(local_x, local_y)
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


static func build_collision_faces(data: FoundationTerrainData, chunk: Vector2i) -> PackedVector3Array:
	assert(data.is_valid_chunk(chunk), "Chunk coordinate is outside TerrainData.")
	var rect := data.get_chunk_cell_rect(chunk)
	var faces := PackedVector3Array()
	faces.resize(rect.size.x * rect.size.y * 6)
	var write_index := 0
	for local_y in range(rect.size.y):
		for local_x in range(rect.size.x):
			var cell := rect.position + Vector2i(local_x, local_y)
			var northwest := _local_vertex(data, rect.position, cell)
			var northeast := _local_vertex(data, rect.position, cell + Vector2i.RIGHT)
			var southwest := _local_vertex(data, rect.position, cell + Vector2i.DOWN)
			var southeast := _local_vertex(data, rect.position, cell + Vector2i.ONE)
			if data.get_cell_diagonal(cell) == FoundationTerrainData.TriangleDiagonal.NORTHWEST_SOUTHEAST:
				write_index = _write_face(faces, write_index, northwest, southeast, southwest)
				write_index = _write_face(faces, write_index, northwest, northeast, southeast)
			else:
				write_index = _write_face(faces, write_index, northwest, northeast, southwest)
				write_index = _write_face(faces, write_index, northeast, southeast, southwest)
	return faces


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
