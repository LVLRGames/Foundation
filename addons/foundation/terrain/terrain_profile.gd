@tool
class_name FoundationTerrainProfile
extends Resource

## Explicit generation inputs. Changing this resource never regenerates automatically.

@export_category("World")
@export var seed: int = 1337
@export var grid_cells := Vector2i(64, 64)
@export_range(0.01, 1024.0, 0.01, "or_greater") var cell_size := 4.0
@export_range(0.01, 1024.0, 0.01, "or_greater") var height_step := 1.0
@export var chunk_cells := Vector2i(32, 32)

@export_category("Noise")
@export_range(0.00001, 1.0, 0.00001) var noise_frequency := 0.015
@export_range(0.0, 10000.0, 0.1, "or_greater") var height_amplitude := 12.0
@export_range(1, 8, 1) var noise_octaves := 4
@export_range(0.0, 1.0, 0.01) var noise_gain := 0.5
@export_range(1.0, 4.0, 0.01) var noise_lacunarity := 2.0

@export_category("Surface classification")
@export var sand_height := -2.0
@export_range(0.0, 90.0, 0.1) var rock_slope_degrees := 28.0
@export_range(0.0, 1.0, 0.01) var dirt_noise_threshold := 0.35


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if grid_cells.x <= 0 or grid_cells.y <= 0:
		errors.append("Grid dimensions must both be positive.")
	if chunk_cells.x <= 0 or chunk_cells.y <= 0:
		errors.append("Chunk dimensions must both be positive.")
	if cell_size <= 0.0:
		errors.append("Cell size must be greater than zero.")
	if height_step <= 0.0:
		errors.append("Height step must be greater than zero.")
	if noise_frequency <= 0.0:
		errors.append("Noise frequency must be greater than zero.")
	return errors
