@tool
class_name FoundationDebugView
extends Node3D

## Disposable runtime/editor debug renderer. World data remains authoritative.

@export var debug_enabled := true
@export var world_path: NodePath = NodePath("..")
@export var style: FoundationDebugStyle = FoundationDebugStyle.new()
@export var show_world_bounds := true
@export var show_regions := true
@export var show_chunks := true
@export var show_terrain_grid := false
@export var show_records := true
@export var show_anchors := true
@export var show_road_topology := true
@export var show_road_costs := false
@export var show_road_candidates := false
@export var show_road_validation := true
@export var show_blocks := true
@export var show_parcels := true
@export var show_buildings := true
@export var show_facades := true
@export var show_streaming := false
@export var show_relationships := true
@export var selected_record_id: StringName = &""
@export var selected_chunk := Vector2i(2147483647, 2147483647)

var layer_registry := FoundationDebugLayerRegistry.new()
var last_primitive_count := 0
var _line_mesh_instance: MeshInstance3D
var _fill_mesh_instance: MeshInstance3D
var _label_root: Node3D
var _material: StandardMaterial3D


func _ready() -> void:
	_ensure_registry()
	if debug_enabled and not Engine.is_editor_hint():
		rebuild()


func set_debug_enabled(value: bool) -> void:
	debug_enabled = value
	if not debug_enabled:
		clear_debug()


func rebuild() -> int:
	_ensure_registry()
	if not debug_enabled:
		layer_registry.enabled = false
		clear_debug()
		return 0
	var world_node := get_node_or_null(world_path) as FoundationWorld
	if world_node == null:
		push_warning("FoundationDebugView requires a FoundationWorld at world_path.")
		clear_debug()
		return 0
	if world_node.world_data == null:
		world_node.initialize_world()
	_sync_layer_visibility()
	layer_registry.enabled = true
	var builder := layer_registry.build(world_node.world_data, {
		"selected_record_id": selected_record_id,
		"selected_chunk": selected_chunk,
	})
	_render_builder(builder)
	last_primitive_count = builder.get_primitive_count()
	return last_primitive_count


func clear_debug() -> void:
	if is_instance_valid(_line_mesh_instance):
		_line_mesh_instance.mesh = null
	if is_instance_valid(_fill_mesh_instance):
		_fill_mesh_instance.mesh = null
	if is_instance_valid(_label_root):
		for child in _label_root.get_children():
			_label_root.remove_child(child)
			child.queue_free()
	last_primitive_count = 0


func _ensure_registry() -> void:
	if layer_registry.get_provider_ids().is_empty():
		layer_registry.register_phase_1_defaults()


func _sync_layer_visibility() -> void:
	layer_registry.set_layer_enabled(&"world_bounds", show_world_bounds)
	layer_registry.set_layer_enabled(&"regions", show_regions)
	layer_registry.set_layer_enabled(&"chunks", show_chunks)
	layer_registry.set_layer_enabled(&"terrain_grid", show_terrain_grid)
	layer_registry.set_layer_enabled(&"records", show_records)
	layer_registry.set_layer_enabled(&"anchors", show_anchors)
	layer_registry.set_layer_enabled(&"road_topology", show_road_topology)
	layer_registry.set_layer_enabled(&"road_costs", show_road_costs)
	layer_registry.set_layer_enabled(&"road_candidates", show_road_candidates)
	layer_registry.set_layer_enabled(&"road_validation", show_road_validation)
	layer_registry.set_layer_enabled(&"blocks", show_blocks)
	layer_registry.set_layer_enabled(&"parcels", show_parcels)
	layer_registry.set_layer_enabled(&"buildings", show_buildings)
	layer_registry.set_layer_enabled(&"facades", show_facades)
	layer_registry.set_layer_enabled(&"streaming", show_streaming)
	layer_registry.set_layer_enabled(&"relationships", show_relationships)


func _render_builder(builder: FoundationDebugGeometryBuilder) -> void:
	_ensure_render_nodes()
	_line_mesh_instance.mesh = _build_mesh(
		Mesh.PRIMITIVE_LINES,
		builder.line_vertices,
		builder.line_purposes,
		false
	)
	_fill_mesh_instance.mesh = _build_mesh(
		Mesh.PRIMITIVE_TRIANGLES,
		builder.triangle_vertices,
		builder.triangle_purposes,
		true
	)
	for child in _label_root.get_children():
		_label_root.remove_child(child)
		child.queue_free()
	for label_data in builder.labels:
		var label_node := Label3D.new()
		label_node.text = label_data["text"]
		label_node.position = label_data["position"]
		label_node.modulate = style.color_for(label_data["purpose"])
		label_node.font_size = 24
		label_node.outline_size = 6
		label_node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label_node.no_depth_test = true
		_label_root.add_child(label_node)


func _build_mesh(
	primitive: Mesh.PrimitiveType,
	vertices: PackedVector3Array,
	purposes: Array[StringName],
	fill: bool
) -> ArrayMesh:
	if vertices.is_empty():
		return null
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	for index in range(vertices.size()):
		var color := style.color_for(purposes[index])
		if fill:
			color.a = style.fill_alpha
		colors[index] = color
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(primitive, arrays)
	mesh.surface_set_material(0, _get_material())
	return mesh


func _ensure_render_nodes() -> void:
	if not is_instance_valid(_line_mesh_instance):
		_line_mesh_instance = MeshInstance3D.new()
		_line_mesh_instance.name = "BatchedLines"
		add_child(_line_mesh_instance)
	if not is_instance_valid(_fill_mesh_instance):
		_fill_mesh_instance = MeshInstance3D.new()
		_fill_mesh_instance.name = "BatchedFills"
		add_child(_fill_mesh_instance)
	if not is_instance_valid(_label_root):
		_label_root = Node3D.new()
		_label_root.name = "DisposableLabels"
		add_child(_label_root)


func _get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.no_depth_test = true
	return _material
