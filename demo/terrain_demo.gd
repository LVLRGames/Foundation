extends Node3D

@onready var terrain: FoundationTerrain = $FoundationTerrain
@onready var camera: Camera3D = $Camera3D
@onready var seed_input: SpinBox = %SeedInput
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	seed_input.value = terrain.profile.seed
	%GenerateButton.pressed.connect(_generate_from_ui)
	%SameSeedButton.pressed.connect(_regenerate_same_seed)
	%NextSeedButton.pressed.connect(_generate_next_seed)
	terrain.terrain_generated.connect(_terrain_generated)
	camera.look_at(_terrain_center(), Vector3.UP)
	_update_status()


func _generate_from_ui() -> void:
	terrain.profile.seed = int(seed_input.value)
	terrain.generate_terrain()


func _regenerate_same_seed() -> void:
	terrain.generate_terrain()


func _generate_next_seed() -> void:
	seed_input.value = int(seed_input.value) + 1
	_generate_from_ui()


func _terrain_generated(_data: FoundationTerrainData) -> void:
	_update_status()


func _update_status() -> void:
	if terrain.terrain_data == null:
		status_label.text = "Terrain data has not been generated."
		return
	status_label.text = "Seed %d | %s cells | %d chunks | collision on" % [
		terrain.terrain_data.seed,
		terrain.terrain_data.grid_cells,
		terrain.get_loaded_chunk_coordinates().size(),
	]


func _terrain_center() -> Vector3:
	return Vector3(
		terrain.profile.grid_cells.x * terrain.profile.cell_size * 0.5,
		0.0,
		terrain.profile.grid_cells.y * terrain.profile.cell_size * 0.5
	)
