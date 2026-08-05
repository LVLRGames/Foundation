@tool
class_name FoundationTerrain
extends Node3D

## Phase 0 orchestration only: generation, dirty rebuilds, and chunk scene nodes.

signal terrain_generated(data: FoundationTerrainData)
signal chunks_rebuilt(chunks: Array[Vector2i])

@export var profile: FoundationTerrainProfile = FoundationTerrainProfile.new()
@export var generate_on_ready := true
@export var collision_enabled := true
@export var smooth_normals := true
@export var terrain_material: Material

var terrain_data: FoundationTerrainData
var _chunks: Dictionary = {}
var _shared_fallback_material: StandardMaterial3D


func _ready() -> void:
	if generate_on_ready and not Engine.is_editor_hint():
		generate_terrain()


func generate_terrain() -> bool:
	if profile == null:
		push_error("FoundationTerrain requires a FoundationTerrainProfile.")
		return false
	var errors := profile.validation_errors()
	if not errors.is_empty():
		push_error("Cannot generate Foundation terrain: %s" % "; ".join(errors))
		return false

	_clear_chunks()
	terrain_data = FoundationTerrainGenerator.generate(profile)
	rebuild_dirty_chunks()
	terrain_generated.emit(terrain_data)
	return true


func rebuild_dirty_chunks() -> int:
	if terrain_data == null:
		return 0
	var dirty_chunks := terrain_data.take_dirty_chunks()
	for coordinate in dirty_chunks:
		var chunk := _ensure_chunk(coordinate)
		chunk.configure(
			terrain_data,
			coordinate,
			_get_material(),
			collision_enabled,
			smooth_normals
		)
	chunks_rebuilt.emit(dirty_chunks)
	return dirty_chunks.size()


func rebuild_all_chunks() -> int:
	if terrain_data == null:
		return 0
	terrain_data.mark_all_chunks_dirty()
	return rebuild_dirty_chunks()


func get_sampler() -> FoundationTerrainSampler:
	return FoundationTerrainSampler.new(terrain_data) if terrain_data != null else null


func get_modifier() -> FoundationTerrainModifier:
	return FoundationTerrainModifier.new(terrain_data) if terrain_data != null else null


func get_chunk(coordinate: Vector2i) -> FoundationTerrainChunk:
	return _chunks.get(coordinate) as FoundationTerrainChunk


func get_loaded_chunk_coordinates() -> Array[Vector2i]:
	var coordinates: Array[Vector2i] = []
	for coordinate: Vector2i in _chunks:
		coordinates.append(coordinate)
	coordinates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return coordinates


func _ensure_chunk(coordinate: Vector2i) -> FoundationTerrainChunk:
	var existing := get_chunk(coordinate)
	if is_instance_valid(existing):
		return existing
	var chunk := FoundationTerrainChunk.new()
	_chunks[coordinate] = chunk
	add_child(chunk)
	return chunk


func _clear_chunks() -> void:
	for chunk: FoundationTerrainChunk in _chunks.values():
		if is_instance_valid(chunk):
			remove_child(chunk)
			chunk.queue_free()
	_chunks.clear()


func _get_material() -> Material:
	if terrain_material != null:
		return terrain_material
	if _shared_fallback_material == null:
		_shared_fallback_material = StandardMaterial3D.new()
		_shared_fallback_material.vertex_color_use_as_albedo = true
		_shared_fallback_material.roughness = 0.95
		_shared_fallback_material.metallic = 0.0
	return _shared_fallback_material
