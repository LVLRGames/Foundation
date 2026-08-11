@tool
class_name FoundationTerrainChunk
extends Node3D

## Scene representation for one chunk. Visual and collision lifetimes are independent.

enum State {
	UNLOADED,
	DATA_ONLY,
	PROXY_LOADED,
	VISUAL_LOADED,
	PHYSICS_LOADED,
	GAMEPLAY_ACTIVE,
}

var chunk_coordinate := Vector2i.ZERO
var terrain_data: FoundationTerrainData
var state := State.UNLOADED
var visual_lod_level := -1

var _mesh_instance: MeshInstance3D
var _static_body: StaticBody3D
var _collision_shape: CollisionShape3D


func configure(
	data: FoundationTerrainData,
	coordinate: Vector2i,
	shared_material: Material,
	include_collision := true,
	smooth_normals := true
) -> void:
	terrain_data = data
	chunk_coordinate = coordinate
	name = "TerrainChunk_%d_%d" % [coordinate.x, coordinate.y]
	var rect := terrain_data.get_chunk_cell_rect(coordinate)
	position = Vector3(rect.position.x * data.cell_size, 0.0, rect.position.y * data.cell_size)
	state = State.DATA_ONLY
	rebuild_visual(shared_material, smooth_normals, 0)
	if include_collision:
		rebuild_collision()
	else:
		clear_collision()


func configure_streamed(
	data: FoundationTerrainData,
	coordinate: Vector2i,
	shared_material: Material,
	target_state: State,
	lod_level: int,
	smooth_normals := true,
	force_rebuild := false
) -> void:
	terrain_data = data
	chunk_coordinate = coordinate
	name = "TerrainChunk_%d_%d" % [coordinate.x, coordinate.y]
	var rect := terrain_data.get_chunk_cell_rect(coordinate)
	position = Vector3(rect.position.x * data.cell_size, 0.0, rect.position.y * data.cell_size)
	if target_state >= State.PROXY_LOADED:
		if force_rebuild or not has_visual() or visual_lod_level != lod_level:
			rebuild_visual(shared_material, smooth_normals, lod_level)
	else:
		clear_visual()
	if target_state >= State.PHYSICS_LOADED:
		if force_rebuild or not has_collision():
			rebuild_collision()
	else:
		clear_collision()
	state = target_state


func rebuild_visual(shared_material: Material, smooth_normals := true, lod_level := 0) -> void:
	_ensure_visual_node()
	_mesh_instance.mesh = FoundationTerrainMesher.build_mesh(
		terrain_data,
		chunk_coordinate,
		smooth_normals,
		lod_level
	)
	if _mesh_instance.mesh.get_surface_count() > 0:
		_mesh_instance.mesh.surface_set_material(0, shared_material)
	visual_lod_level = lod_level
	state = maxi(state, State.VISUAL_LOADED) as State


func rebuild_collision() -> void:
	_ensure_collision_nodes()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(FoundationTerrainMesher.build_collision_faces(terrain_data, chunk_coordinate))
	_collision_shape.shape = shape
	state = maxi(state, State.PHYSICS_LOADED) as State


func clear_visual() -> void:
	if is_instance_valid(_mesh_instance):
		_mesh_instance.mesh = null
	visual_lod_level = -1
	state = State.DATA_ONLY if not has_collision() else State.PHYSICS_LOADED


func clear_collision() -> void:
	if is_instance_valid(_collision_shape):
		_collision_shape.shape = null
	state = State.DATA_ONLY if not has_visual() else State.VISUAL_LOADED


func has_visual() -> bool:
	return is_instance_valid(_mesh_instance) and _mesh_instance.mesh != null


func has_collision() -> bool:
	return is_instance_valid(_collision_shape) and _collision_shape.shape != null


func get_mesh_instance() -> MeshInstance3D:
	return _mesh_instance


func get_collision_shape() -> CollisionShape3D:
	return _collision_shape


func _ensure_visual_node() -> void:
	if is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Visual"
	add_child(_mesh_instance)


func _ensure_collision_nodes() -> void:
	if not is_instance_valid(_static_body):
		_static_body = StaticBody3D.new()
		_static_body.name = "Collision"
		add_child(_static_body)
	if not is_instance_valid(_collision_shape):
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "Shape"
		_static_body.add_child(_collision_shape)
