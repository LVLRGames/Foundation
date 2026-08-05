class_name FoundationTerrainGenerator
extends RefCounted

## Pure deterministic generation: profile in, authoritative data out.


static func generate(profile: FoundationTerrainProfile) -> FoundationTerrainData:
	var errors := profile.validation_errors()
	assert(errors.is_empty(), "Invalid FoundationTerrainProfile: %s" % "; ".join(errors))

	var data := FoundationTerrainData.new(
		profile.seed,
		profile.grid_cells,
		profile.cell_size,
		profile.height_step,
		profile.chunk_cells
	)
	var height_noise := _make_noise(profile, &"terrain_height")
	var surface_noise := _make_noise(profile, &"terrain_surface")

	for vertex_y in range(profile.grid_cells.y + 1):
		for vertex_x in range(profile.grid_cells.x + 1):
			var raw_height := height_noise.get_noise_2d(vertex_x, vertex_y) * profile.height_amplitude
			data.set_vertex_height(
				Vector2i(vertex_x, vertex_y),
				raw_height,
				FoundationTerrainData.ModificationSource.NATURAL,
				false
			)

	for cell_y in range(profile.grid_cells.y):
		for cell_x in range(profile.grid_cells.x):
			var cell := Vector2i(cell_x, cell_y)
			data.set_cell_diagonal(cell, data.calculate_preferred_diagonal(cell), false)
			data.set_cell_surface(
				cell,
				_classify_surface(data, profile, surface_noise, cell),
				false
			)

	data.clear_dirty_chunks()
	data.mark_all_chunks_dirty()
	return data


static func _make_noise(profile: FoundationTerrainProfile, stream_name: StringName) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = FoundationSeed.derive(profile.seed, stream_name)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = profile.noise_frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = profile.noise_octaves
	noise.fractal_gain = profile.noise_gain
	noise.fractal_lacunarity = profile.noise_lacunarity
	return noise


static func _classify_surface(
	data: FoundationTerrainData,
	profile: FoundationTerrainProfile,
	surface_noise: FastNoiseLite,
	cell: Vector2i
) -> int:
	var northwest := data.get_vertex_height(cell)
	var northeast := data.get_vertex_height(cell + Vector2i.RIGHT)
	var southwest := data.get_vertex_height(cell + Vector2i.DOWN)
	var southeast := data.get_vertex_height(cell + Vector2i.ONE)
	var average_height := (northwest + northeast + southwest + southeast) * 0.25
	var maximum_rise := maxf(
		maxf(absf(northwest - southeast), absf(northeast - southwest)),
		maxf(absf(northwest - northeast), absf(northwest - southwest))
	)
	var slope_degrees := rad_to_deg(atan(maximum_rise / data.cell_size))

	if average_height <= profile.sand_height:
		return FoundationTerrainSurface.Type.SAND
	if slope_degrees >= profile.rock_slope_degrees:
		return FoundationTerrainSurface.Type.ROCK
	if absf(surface_noise.get_noise_2d(cell.x, cell.y)) > profile.dirt_noise_threshold:
		return FoundationTerrainSurface.Type.DIRT
	return FoundationTerrainSurface.Type.GRASS
