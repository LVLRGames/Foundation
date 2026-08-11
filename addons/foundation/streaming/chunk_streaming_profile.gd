@tool
class_name FoundationChunkStreamingProfile
extends Resource

## Deterministic distance bands and work caps for Phase 6 chunk streaming.

const FORMAT_VERSION := 1
const SOURCE_VERSION := 1

@export_range(0, 1024, 1) var gameplay_radius_chunks := 0
@export_range(0, 1024, 1) var physics_radius_chunks := 1
@export var visual_lod_radii_chunks := PackedInt32Array([2, 4])
@export_range(0, 1024, 1) var proxy_radius_chunks := 6
@export_range(0, 1024, 1) var data_radius_chunks := 8
@export_range(0, 32, 1) var hysteresis_chunks := 1
@export_range(1, 4096, 1) var max_transitions_per_update := 24
@export_range(1, 10000000, 1) var maximum_planning_operations := 200000


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if gameplay_radius_chunks < 0:
		errors.append("Gameplay radius must be non-negative.")
	if physics_radius_chunks < gameplay_radius_chunks:
		errors.append("Physics radius must contain the gameplay radius.")
	if visual_lod_radii_chunks.is_empty():
		errors.append("At least one visual LOD radius is required.")
	var previous := physics_radius_chunks
	for radius in visual_lod_radii_chunks:
		if radius < previous:
			errors.append("Visual LOD radii must be ordered and contain the physics radius.")
			break
		previous = radius
	if proxy_radius_chunks < previous:
		errors.append("Proxy radius must contain every visual LOD radius.")
	if data_radius_chunks < proxy_radius_chunks:
		errors.append("Data radius must contain the proxy radius.")
	if hysteresis_chunks < 0:
		errors.append("Hysteresis must be non-negative.")
	if max_transitions_per_update <= 0:
		errors.append("Transition budget must be positive.")
	if maximum_planning_operations <= 0:
		errors.append("Planning operation cap must be positive.")
	return errors


func target_for_distance(distance_chunks: int) -> Vector2i:
	if distance_chunks <= gameplay_radius_chunks:
		return Vector2i(FoundationChunkData.RuntimeState.GAMEPLAY_ACTIVE, 0)
	if distance_chunks <= physics_radius_chunks:
		return Vector2i(FoundationChunkData.RuntimeState.PHYSICS_LOADED, 0)
	for lod_level in range(visual_lod_radii_chunks.size()):
		if distance_chunks <= visual_lod_radii_chunks[lod_level]:
			return Vector2i(FoundationChunkData.RuntimeState.VISUAL_LOADED, lod_level)
	if distance_chunks <= proxy_radius_chunks:
		return Vector2i(FoundationChunkData.RuntimeState.PROXY_LOADED, get_proxy_lod_level())
	if distance_chunks <= data_radius_chunks:
		return Vector2i(FoundationChunkData.RuntimeState.DATA_ONLY, -1)
	return Vector2i(FoundationChunkData.RuntimeState.UNLOADED, -1)


func radius_for_state(runtime_state: FoundationChunkData.RuntimeState, lod_level: int) -> int:
	match runtime_state:
		FoundationChunkData.RuntimeState.GAMEPLAY_ACTIVE:
			return gameplay_radius_chunks
		FoundationChunkData.RuntimeState.PHYSICS_LOADED:
			return physics_radius_chunks
		FoundationChunkData.RuntimeState.VISUAL_LOADED:
			var safe_lod := clampi(lod_level, 0, visual_lod_radii_chunks.size() - 1)
			return visual_lod_radii_chunks[safe_lod]
		FoundationChunkData.RuntimeState.PROXY_LOADED:
			return proxy_radius_chunks
		FoundationChunkData.RuntimeState.DATA_ONLY:
			return data_radius_chunks
		_:
			return -1


func lod_for_state(runtime_state: FoundationChunkData.RuntimeState, requested_lod: int) -> int:
	match runtime_state:
		FoundationChunkData.RuntimeState.GAMEPLAY_ACTIVE, FoundationChunkData.RuntimeState.PHYSICS_LOADED:
			return 0
		FoundationChunkData.RuntimeState.VISUAL_LOADED:
			return clampi(requested_lod, 0, visual_lod_radii_chunks.size() - 1)
		FoundationChunkData.RuntimeState.PROXY_LOADED:
			return get_proxy_lod_level()
		_:
			return -1


func get_proxy_lod_level() -> int:
	return visual_lod_radii_chunks.size()


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"source_version": SOURCE_VERSION,
		"gameplay_radius_chunks": gameplay_radius_chunks,
		"physics_radius_chunks": physics_radius_chunks,
		"visual_lod_radii_chunks": Array(visual_lod_radii_chunks),
		"proxy_radius_chunks": proxy_radius_chunks,
		"data_radius_chunks": data_radius_chunks,
		"hysteresis_chunks": hysteresis_chunks,
		"max_transitions_per_update": max_transitions_per_update,
		"maximum_planning_operations": maximum_planning_operations,
	}


static func from_dict(data: Dictionary) -> FoundationChunkStreamingProfile:
	var profile := FoundationChunkStreamingProfile.new()
	profile.gameplay_radius_chunks = int(data.get("gameplay_radius_chunks", 0))
	profile.physics_radius_chunks = int(data.get("physics_radius_chunks", 1))
	profile.visual_lod_radii_chunks = PackedInt32Array(data.get("visual_lod_radii_chunks", [2, 4]))
	profile.proxy_radius_chunks = int(data.get("proxy_radius_chunks", 6))
	profile.data_radius_chunks = int(data.get("data_radius_chunks", 8))
	profile.hysteresis_chunks = int(data.get("hysteresis_chunks", 1))
	profile.max_transitions_per_update = int(data.get("max_transitions_per_update", 24))
	profile.maximum_planning_operations = int(data.get("maximum_planning_operations", 200000))
	return profile
