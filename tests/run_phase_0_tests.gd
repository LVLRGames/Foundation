extends SceneTree

var _failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile := FoundationTerrainProfile.new()
	profile.seed = 424242
	profile.grid_cells = Vector2i(64, 64)
	profile.chunk_cells = Vector2i(32, 32)
	profile.cell_size = 4.0
	profile.height_step = 1.0

	var first := FoundationTerrainGenerator.generate(profile)
	var second := FoundationTerrainGenerator.generate(profile)
	_check(_float_arrays_equal(first.vertex_heights, second.vertex_heights), "same seed/profile reproduces height data")
	_check(first.cell_surfaces == second.cell_surfaces, "same seed/profile reproduces surface IDs")
	_check(first.cell_diagonals == second.cell_diagonals, "same seed/profile reproduces triangulation")
	var generated_surfaces: Dictionary = {}
	for surface_id in first.cell_surfaces:
		generated_surfaces[surface_id] = true
	print("Generated surface IDs: ", generated_surfaces.keys())
	_check(generated_surfaces.size() >= 3, "demo profile generates at least three explicit surface appearances")

	var different_profile := profile.duplicate() as FoundationTerrainProfile
	different_profile.seed = profile.seed + 1
	var different := FoundationTerrainGenerator.generate(different_profile)
	var changed_heights := 0
	for index in range(first.vertex_heights.size()):
		if not is_equal_approx(first.vertex_heights[index], different.vertex_heights[index]):
			changed_heights += 1
	_check(changed_heights > first.vertex_heights.size() / 10, "different seeds meaningfully change height data")

	var all_quantized := true
	for height in first.vertex_heights:
		var steps := height / first.height_step
		if absf(steps - round(steps)) > 0.00001:
			all_quantized = false
			break
	_check(all_quantized, "heights are exact multiples of height_step")

	_test_shared_mesh_border(first)
	_test_dirty_chunk_propagation(first)
	_test_meshing_is_read_only(first)
	_test_sampler(first)
	_test_runtime_chunks(profile)

	if _failures.is_empty():
		print("Foundation Phase 0 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 0 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_shared_mesh_border(data: FoundationTerrainData) -> void:
	var left_mesh := FoundationTerrainMesher.build_mesh(data, Vector2i(0, 0))
	var right_mesh := FoundationTerrainMesher.build_mesh(data, Vector2i(1, 0))
	var left_vertices: PackedVector3Array = left_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var right_vertices: PackedVector3Array = right_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var row_width := data.chunk_cells.x + 1
	var borders_match := true
	for row in range(data.chunk_cells.y + 1):
		var left_height := left_vertices[row * row_width + data.chunk_cells.x].y
		var right_height := right_vertices[row * row_width].y
		if not is_equal_approx(left_height, right_height):
			borders_match = false
			break
	_check(borders_match, "adjacent chunk meshes resolve identical shared-border heights")


func _test_dirty_chunk_propagation(data: FoundationTerrainData) -> void:
	data.clear_dirty_chunks()
	var modifier := FoundationTerrainModifier.new(data)
	var shared_vertex := Vector2i(data.chunk_cells.x, 10)
	modifier.add_height(shared_vertex, data.height_step)
	var dirty := data.get_dirty_chunks()
	_check(dirty.has(Vector2i(0, 0)), "shared boundary edit dirties the left chunk")
	_check(dirty.has(Vector2i(1, 0)), "shared boundary edit dirties the right chunk")
	_check(dirty.size() == 2, "shared edge edit dirties only affected chunks")
	var diagonals_refreshed := true
	for cell in [Vector2i(31, 9), Vector2i(32, 9), Vector2i(31, 10), Vector2i(32, 10)]:
		if data.get_cell_diagonal(cell) != data.calculate_preferred_diagonal(cell):
			diagonals_refreshed = false
			break
	_check(diagonals_refreshed, "height edits refresh adjacent preferred diagonals")


func _test_meshing_is_read_only(data: FoundationTerrainData) -> void:
	var heights_before := data.vertex_heights.duplicate()
	var surfaces_before := data.cell_surfaces.duplicate()
	var diagonals_before := data.cell_diagonals.duplicate()
	var revision_before := data.revision
	FoundationTerrainMesher.build_mesh(data, Vector2i.ZERO)
	FoundationTerrainMesher.build_mesh(data, Vector2i.ZERO, false)
	FoundationTerrainMesher.build_collision_faces(data, Vector2i.ZERO)
	_check(_float_arrays_equal(heights_before, data.vertex_heights), "meshing does not mutate vertex heights")
	_check(surfaces_before == data.cell_surfaces, "meshing does not mutate surface IDs")
	_check(diagonals_before == data.cell_diagonals, "meshing does not mutate triangulation")
	_check(revision_before == data.revision, "meshing does not mutate TerrainData revision")


func _test_sampler(data: FoundationTerrainData) -> void:
	var sampler := FoundationTerrainSampler.new(data)
	var cell := Vector2i(3, 4)
	var world_position := Vector2(cell.x * data.cell_size, cell.y * data.cell_size)
	_check(
		is_equal_approx(sampler.get_height_at_world(world_position), data.get_vertex_height(cell)),
		"TerrainSampler world height agrees at grid vertices"
	)
	_check(
		sampler.get_surface_at_world(world_position) == data.get_cell_surface(cell),
		"TerrainSampler returns explicit surface IDs"
	)
	_check(sampler.get_slope_degrees_at_grid(cell) >= 0.0, "TerrainSampler exposes slope")


func _test_runtime_chunks(profile: FoundationTerrainProfile) -> void:
	var terrain := FoundationTerrain.new()
	terrain.generate_on_ready = false
	terrain.profile = profile.duplicate() as FoundationTerrainProfile
	root.add_child(terrain)
	_check(terrain.generate_terrain(), "runtime terrain generation succeeds")
	_check(terrain.get_loaded_chunk_coordinates().size() == 4, "64x64 terrain creates four 32x32 chunks")
	var chunk := terrain.get_chunk(Vector2i.ZERO)
	_check(chunk != null and chunk.has_visual(), "active chunk has visual geometry")
	_check(chunk != null and chunk.has_collision(), "active chunk has collision")
	if chunk != null and chunk.has_collision():
		var shape := chunk.get_collision_shape().shape as ConcavePolygonShape3D
		_check(shape.get_faces().size() == 32 * 32 * 6, "collision uses the authoritative cell triangulation")
	terrain.queue_free()


func _float_arrays_equal(left: PackedFloat32Array, right: PackedFloat32Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if not is_equal_approx(left[index], right[index]):
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
