class_name FoundationTerrainGradingEdit
extends RefCounted

## One resolved, reversible vertex edit owned by a deterministic grading operation.

const FORMAT_VERSION := 1

var grid_vertex := Vector2i.ZERO
var original_height := 0.0
var target_height := 0.0
var original_source := FoundationTerrainData.ModificationSource.NATURAL
var target_source := FoundationTerrainData.ModificationSource.MANUAL
var operation_id: StringName
var blend_weight := 1.0


func _init(
	p_grid_vertex := Vector2i.ZERO,
	p_original_height := 0.0,
	p_target_height := 0.0,
	p_original_source := FoundationTerrainData.ModificationSource.NATURAL,
	p_target_source := FoundationTerrainData.ModificationSource.MANUAL,
	p_operation_id: StringName = &"",
	p_blend_weight := 1.0
) -> void:
	grid_vertex = p_grid_vertex
	original_height = p_original_height
	target_height = p_target_height
	original_source = p_original_source
	target_source = p_target_source
	operation_id = p_operation_id
	blend_weight = p_blend_weight


func vertex_key() -> String:
	return "%d,%d" % [grid_vertex.x, grid_vertex.y]


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"grid_vertex": {"x": grid_vertex.x, "y": grid_vertex.y},
		"original_height": original_height,
		"target_height": target_height,
		"original_source": original_source,
		"target_source": target_source,
		"operation_id": String(operation_id),
		"blend_weight": blend_weight,
	}


static func from_dict(data: Dictionary) -> FoundationTerrainGradingEdit:
	var vertex_data: Dictionary = data.get("grid_vertex", {})
	return FoundationTerrainGradingEdit.new(
		Vector2i(int(vertex_data.get("x", 0)), int(vertex_data.get("y", 0))),
		float(data.get("original_height", 0.0)),
		float(data.get("target_height", 0.0)),
		int(data.get("original_source", FoundationTerrainData.ModificationSource.NATURAL)),
		int(data.get("target_source", FoundationTerrainData.ModificationSource.MANUAL)),
		StringName(data.get("operation_id", "")),
		float(data.get("blend_weight", 1.0))
	)
