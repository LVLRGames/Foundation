extends Node3D

@onready var world: FoundationWorld = $FoundationWorld
@onready var debug_view: FoundationDebugView = $FoundationWorld/FoundationDebugView
@onready var terrain: FoundationTerrain = $FoundationTerrain
@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label = %StatusLabel
@onready var pause_toggle: CheckBox = %PauseToggle

var streaming_profile := FoundationChunkStreamingProfile.new()
var camera_interest := FoundationChunkInterest.new(&"demo_camera")
var _elapsed := 0.0


func _ready() -> void:
	%StepButton.pressed.connect(_streaming_update)
	%ResetButton.pressed.connect(_reset_streaming)
	terrain.generate_terrain(false)
	camera.look_at(_terrain_center(), Vector3.UP)
	_streaming_update()


func _process(delta: float) -> void:
	if pause_toggle.button_pressed:
		return
	_elapsed += delta
	if _elapsed >= 0.2:
		_elapsed = 0.0
		_streaming_update()


func _streaming_update() -> void:
	camera_interest.world_position = camera.global_position
	var plan := FoundationChunkStreamingScheduler.build_plan(
		world.world_data,
		[camera_interest],
		streaming_profile
	)
	var applied := FoundationChunkStreamingScheduler.apply_plan(world.world_data, plan)
	terrain.apply_streaming_requests(applied)
	debug_view.rebuild()
	_update_status(plan, applied.size())


func _reset_streaming() -> void:
	for chunk in world.world_data.get_sorted_chunks():
		chunk.runtime_state = FoundationChunkData.RuntimeState.DATA_ONLY
		chunk.runtime_lod_level = -1
		chunk.runtime_transition_serial = 0
		terrain.apply_chunk_runtime_state(chunk.coordinate, chunk.runtime_state, chunk.runtime_lod_level)
	_streaming_update()


func _update_status(plan: FoundationChunkStreamingPlan, applied_count: int) -> void:
	var counts := PackedInt32Array()
	counts.resize(FoundationChunkData.RuntimeState.size())
	for chunk in world.world_data.get_sorted_chunks():
		counts[chunk.runtime_state] += 1
	status_label.text = (
		"Camera chunk %s | %d transitions | %d queued\n"
		+ "U %d | D %d | P %d | V %d | Ph %d | G %d | ops %d"
	) % [
		world.world_data.coordinate_system.world_to_chunk(camera.global_position),
		applied_count,
		plan.requests.size(),
		counts[FoundationChunkData.RuntimeState.UNLOADED],
		counts[FoundationChunkData.RuntimeState.DATA_ONLY],
		counts[FoundationChunkData.RuntimeState.PROXY_LOADED],
		counts[FoundationChunkData.RuntimeState.VISUAL_LOADED],
		counts[FoundationChunkData.RuntimeState.PHYSICS_LOADED],
		counts[FoundationChunkData.RuntimeState.GAMEPLAY_ACTIVE],
		plan.planning_operation_count,
	]


func _terrain_center() -> Vector3:
	return Vector3(
		terrain.profile.grid_cells.x * terrain.profile.cell_size * 0.5,
		0.0,
		terrain.profile.grid_cells.y * terrain.profile.cell_size * 0.5
	)
