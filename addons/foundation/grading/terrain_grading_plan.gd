class_name FoundationTerrainGradingPlan
extends RefCounted

## Node-free plan that separates deterministic grading decisions from explicit mutation.

const FORMAT_VERSION := 1
const STATE_PLANNED: StringName = &"planned"
const STATE_APPLIED: StringName = &"applied"
const STATE_REVERTED: StringName = &"reverted"

var generator_version := 1
var world_seed := 0
var terrain_seed := 0
var terrain_origin_cell := Vector2i.ZERO
var terrain_grid_cells := Vector2i.ZERO
var terrain_cell_size := 0.0
var terrain_height_step := 0.0
var source_terrain_revision := 0
var applied_terrain_revision := -1
var state: StringName = STATE_PLANNED
var profile := FoundationTerrainGradingProfile.new()
var operations: Array[FoundationTerrainGradingOperation] = []
var edits: Array[FoundationTerrainGradingEdit] = []
var diagnostics: Array[Dictionary] = []
var candidate_vertex_checks := 0
var clipped_edit_count := 0
var skipped_protected_count := 0
var skipped_water_count := 0


func get_operation(operation_id: StringName) -> FoundationTerrainGradingOperation:
	for operation in operations:
		if operation.stable_id == operation_id:
			return operation
	return null


func to_dict() -> Dictionary:
	var serialized_operations: Array[Dictionary] = []
	for operation in operations:
		serialized_operations.append(operation.to_dict())
	var serialized_edits: Array[Dictionary] = []
	for edit in edits:
		serialized_edits.append(edit.to_dict())
	return {
		"format_version": FORMAT_VERSION,
		"generator_version": generator_version,
		"world_seed": world_seed,
		"terrain_seed": terrain_seed,
		"terrain_origin_cell": {"x": terrain_origin_cell.x, "y": terrain_origin_cell.y},
		"terrain_grid_cells": {"x": terrain_grid_cells.x, "y": terrain_grid_cells.y},
		"terrain_cell_size": terrain_cell_size,
		"terrain_height_step": terrain_height_step,
		"source_terrain_revision": source_terrain_revision,
		"applied_terrain_revision": applied_terrain_revision,
		"state": String(state),
		"profile": profile.to_dict(),
		"operations": serialized_operations,
		"edits": serialized_edits,
		"diagnostics": diagnostics.duplicate(true),
		"candidate_vertex_checks": candidate_vertex_checks,
		"clipped_edit_count": clipped_edit_count,
		"skipped_protected_count": skipped_protected_count,
		"skipped_water_count": skipped_water_count,
	}


static func from_dict(data: Dictionary) -> FoundationTerrainGradingPlan:
	var plan := FoundationTerrainGradingPlan.new()
	plan.generator_version = int(data.get("generator_version", 1))
	plan.world_seed = int(data.get("world_seed", 0))
	plan.terrain_seed = int(data.get("terrain_seed", 0))
	var origin_data: Dictionary = data.get("terrain_origin_cell", {})
	plan.terrain_origin_cell = Vector2i(int(origin_data.get("x", 0)), int(origin_data.get("y", 0)))
	var grid_data: Dictionary = data.get("terrain_grid_cells", {})
	plan.terrain_grid_cells = Vector2i(int(grid_data.get("x", 0)), int(grid_data.get("y", 0)))
	plan.terrain_cell_size = float(data.get("terrain_cell_size", 0.0))
	plan.terrain_height_step = float(data.get("terrain_height_step", 0.0))
	plan.source_terrain_revision = int(data.get("source_terrain_revision", 0))
	plan.applied_terrain_revision = int(data.get("applied_terrain_revision", -1))
	plan.state = StringName(data.get("state", String(STATE_PLANNED)))
	plan.profile = FoundationTerrainGradingProfile.from_dict(data.get("profile", {}))
	for operation_data: Dictionary in data.get("operations", []):
		plan.operations.append(FoundationTerrainGradingOperation.from_dict(operation_data))
	for edit_data: Dictionary in data.get("edits", []):
		plan.edits.append(FoundationTerrainGradingEdit.from_dict(edit_data))
	plan.diagnostics = data.get("diagnostics", []).duplicate(true)
	plan.candidate_vertex_checks = int(data.get("candidate_vertex_checks", 0))
	plan.clipped_edit_count = int(data.get("clipped_edit_count", 0))
	plan.skipped_protected_count = int(data.get("skipped_protected_count", 0))
	plan.skipped_water_count = int(data.get("skipped_water_count", 0))
	return plan
