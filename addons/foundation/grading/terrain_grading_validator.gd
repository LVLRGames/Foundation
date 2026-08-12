class_name FoundationTerrainGradingValidator
extends RefCounted

## Read-only validation over a Phase 9 grading plan and optional applied terrain state.

const EPSILON := 0.000001


static func validate_plan(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	plan: FoundationTerrainGradingPlan,
	validate_applied_state := false
) -> Array[FoundationTerrainGradingValidationIssue]:
	var issues: Array[FoundationTerrainGradingValidationIssue] = []
	if world == null or terrain == null or plan == null:
		issues.append(FoundationTerrainGradingValidationIssue.new(
			&"missing_input", FoundationTerrainGradingValidationIssue.SEVERITY_ERROR,
			"Terrain-grading validation requires world, terrain, and plan data."
		))
		return issues
	for error in plan.profile.validation_errors():
		issues.append(FoundationTerrainGradingValidationIssue.new(
			&"invalid_profile", FoundationTerrainGradingValidationIssue.SEVERITY_ERROR, error
		))
	if plan.world_seed != world.metadata.seed:
		_add(issues, &"world_seed_mismatch", "Plan world seed does not match the world.")
	if plan.terrain_seed != terrain.seed:
		_add(issues, &"terrain_seed_mismatch", "Plan terrain seed does not match the terrain.")
	if plan.terrain_grid_cells != terrain.grid_cells or not is_equal_approx(plan.terrain_cell_size, terrain.cell_size) or not is_equal_approx(plan.terrain_height_step, terrain.height_step):
		_add(issues, &"terrain_shape_mismatch", "Plan terrain dimensions or quantization do not match the terrain.")
	if plan.candidate_vertex_checks > plan.profile.maximum_candidate_vertices:
		_add(issues, &"candidate_vertex_cap_exceeded", "Plan candidate work exceeds the configured cap.")

	var operation_ids: Dictionary = {}
	var last_operation: FoundationTerrainGradingOperation
	var expected_edit_keys: Dictionary = {}
	for operation in plan.operations:
		if String(operation.stable_id).is_empty() or operation_ids.has(operation.stable_id):
			_add(issues, &"invalid_operation_id", "Grading operation IDs must be non-empty and unique.", operation)
		operation_ids[operation.stable_id] = true
		if last_operation != null and FoundationTerrainGrader._sort_operations(operation, last_operation):
			_add(issues, &"operation_order_mismatch", "Grading operations are not in canonical priority/ID order.", operation)
		last_operation = operation
		var source := world.get_record(operation.source_record_id)
		if operation.operation_kind in [FoundationTerrainGradingOperation.KIND_ROAD_CORRIDOR, FoundationTerrainGradingOperation.KIND_BRIDGE_SPAN, FoundationTerrainGradingOperation.KIND_BRIDGE_APPROACH]:
			if not source is FoundationRoadEdge:
				_add(issues, &"invalid_road_source", "Road/bridge grading operation source is missing or not a road edge.", operation)
		elif operation.operation_kind == FoundationTerrainGradingOperation.KIND_BUILDING_PAD:
			if not source is FoundationBuildingRecord:
				_add(issues, &"invalid_building_source", "Building-pad operation source is missing or not a building.", operation)
		else:
			_add(issues, &"unknown_operation_kind", "Grading operation kind is unsupported.", operation)
		if source != null:
			var source_hash := JSON.stringify(source.to_dict(), "", true).sha256_text()
			if operation.source_record_hash.is_empty() or operation.source_record_hash != source_hash:
				_add(issues, &"source_record_hash_mismatch", "Grading operation source changed after the plan was created.", operation)
		if operation.priority <= 0:
			_add(issues, &"invalid_operation_priority", "Grading operation priority must be positive.", operation)
		if operation.operation_kind != FoundationTerrainGradingOperation.KIND_BRIDGE_SPAN and operation.edit_keys.is_empty():
			_add(issues, &"operation_without_edits", "Non-span grading operation owns no resolved edits.", operation, FoundationTerrainGradingValidationIssue.SEVERITY_WARNING)
		if operation.operation_kind == FoundationTerrainGradingOperation.KIND_BRIDGE_SPAN:
			if not operation.edit_keys.is_empty() or not bool(operation.metadata.get("preserves_underlying_terrain", false)):
				_add(issues, &"bridge_span_mutates_terrain", "Bridge-span operations must preserve terrain beneath the deck.", operation)
		if operation.target_elevation_max + EPSILON < operation.target_elevation_min:
			_add(issues, &"invalid_operation_elevation_range", "Operation elevation range is inverted.", operation)
		if operation.world_bounds.size.x < 0.0 or operation.world_bounds.size.y < 0.0:
			_add(issues, &"invalid_operation_bounds", "Operation world bounds are invalid.", operation)
		var local_keys: Dictionary = {}
		for key in operation.edit_keys:
			if local_keys.has(key):
				_add(issues, &"duplicate_operation_edit_key", "Operation contains a duplicate vertex edit key.", operation)
			local_keys[key] = true
			expected_edit_keys[String(key)] = operation.stable_id

	var edit_keys: Dictionary = {}
	var previous_vertex := Vector2i(-2147483648, -2147483648)
	for edit in plan.edits:
		var key := edit.vertex_key()
		var operation := plan.get_operation(edit.operation_id)
		if operation == null:
			_add_edit(issues, &"missing_edit_operation", "Grading edit references a missing operation.", edit)
		elif expected_edit_keys.get(key, &"") != edit.operation_id:
			_add_edit(issues, &"operation_edit_accounting_mismatch", "Operation edit keys do not account for the resolved edit.", edit, operation.source_record_id)
		elif not operation.world_bounds.grow(plan.profile.geometric_tolerance).has_point(
			Vector2(edit.grid_vertex + plan.terrain_origin_cell) * plan.terrain_cell_size
		):
			_add_edit(issues, &"edit_outside_operation_bounds", "Resolved edit lies outside its operation bounds.", edit, operation.source_record_id)
		if edit_keys.has(key):
			_add_edit(issues, &"duplicate_vertex_edit", "Resolved grading plan contains more than one edit for a vertex.", edit)
		edit_keys[key] = true
		if previous_vertex.y > edit.grid_vertex.y or (previous_vertex.y == edit.grid_vertex.y and previous_vertex.x > edit.grid_vertex.x):
			_add_edit(issues, &"edit_order_mismatch", "Resolved grading edits are not in canonical row-major order.", edit)
		previous_vertex = edit.grid_vertex
		if not terrain.is_valid_vertex(edit.grid_vertex):
			_add_edit(issues, &"edit_outside_terrain", "Resolved grading edit is outside the terrain vertex grid.", edit)
			continue
		if not is_equal_approx(terrain.quantize_height(edit.original_height), edit.original_height) or not is_equal_approx(terrain.quantize_height(edit.target_height), edit.target_height):
			_add_edit(issues, &"unquantized_edit_height", "Grading edit heights do not match terrain quantization.", edit)
		if edit.blend_weight < 0.0 or edit.blend_weight > 1.0:
			_add_edit(issues, &"invalid_blend_weight", "Grading edit blend weight is outside [0, 1].", edit)
		if edit.original_height - edit.target_height > plan.profile.maximum_cut_depth + plan.profile.geometric_tolerance:
			_add_edit(issues, &"cut_limit_exceeded", "Resolved grading edit exceeds the configured cut limit.", edit)
		if edit.target_height - edit.original_height > plan.profile.maximum_fill_height + plan.profile.geometric_tolerance:
			_add_edit(issues, &"fill_limit_exceeded", "Resolved grading edit exceeds the configured fill limit.", edit)
		if not plan.profile.allow_protected_grading and FoundationTerrainGrader._vertex_touches_flag(terrain, edit.grid_vertex, FoundationTerrainData.CellFlag.PROTECTED):
			_add_edit(issues, &"protected_vertex_edit", "Resolved grading edit touches protected terrain.", edit)
		if not plan.profile.allow_water_grading and FoundationTerrainGrader._vertex_touches_flag(terrain, edit.grid_vertex, FoundationTerrainData.CellFlag.WATER):
			_add_edit(issues, &"water_vertex_edit", "Resolved grading edit touches water terrain.", edit)
		if FoundationTerrainGrader.edit_is_under_bridge_span(world, plan, edit):
			_add_edit(issues, &"bridge_span_terrain_edit", "Resolved grading edit would mutate terrain beneath a bridge span.", edit)
		if edit.target_source not in [FoundationTerrainData.ModificationSource.ROAD_CUT, FoundationTerrainData.ModificationSource.ROAD_FILL, FoundationTerrainData.ModificationSource.BUILDING_PAD, FoundationTerrainData.ModificationSource.BRIDGE_APPROACH]:
			_add_edit(issues, &"invalid_edit_source", "Resolved grading edit has unsupported provenance.", edit)
		if validate_applied_state:
			if not is_equal_approx(terrain.get_vertex_height(edit.grid_vertex), edit.target_height):
				_add_edit(issues, &"applied_height_mismatch", "Applied terrain height does not match the plan.", edit)
			if terrain.get_vertex_modification_source(edit.grid_vertex) != edit.target_source:
				_add_edit(issues, &"applied_source_mismatch", "Applied terrain provenance does not match the plan.", edit)
		elif plan.state == FoundationTerrainGradingPlan.STATE_PLANNED:
			if not is_equal_approx(terrain.get_vertex_height(edit.grid_vertex), edit.original_height):
				_add_edit(issues, &"planned_original_height_mismatch", "Terrain no longer matches the edit's original height.", edit)
			if terrain.get_vertex_modification_source(edit.grid_vertex) != edit.original_source:
				_add_edit(issues, &"planned_original_source_mismatch", "Terrain no longer matches the edit's original provenance.", edit)
	for key in expected_edit_keys:
		if not edit_keys.has(key):
			var operation := plan.get_operation(expected_edit_keys[key])
			_add(issues, &"missing_accounted_edit", "An operation edit key has no resolved edit.", operation)
	for operation in plan.operations:
		if operation.edit_keys.is_empty():
			continue
		var recomputed_minimum := INF
		var recomputed_maximum := -INF
		for edit in plan.edits:
			if edit.operation_id == operation.stable_id:
				recomputed_minimum = minf(recomputed_minimum, edit.target_height)
				recomputed_maximum = maxf(recomputed_maximum, edit.target_height)
		if not is_equal_approx(operation.target_elevation_min, recomputed_minimum) or not is_equal_approx(operation.target_elevation_max, recomputed_maximum):
			_add(issues, &"operation_elevation_accounting_mismatch", "Operation elevation range does not match its resolved edits.", operation)
	return issues


static func _add(
	issues: Array[FoundationTerrainGradingValidationIssue],
	kind: StringName,
	message: String,
	operation: FoundationTerrainGradingOperation = null,
	severity: StringName = FoundationTerrainGradingValidationIssue.SEVERITY_ERROR
) -> void:
	issues.append(FoundationTerrainGradingValidationIssue.new(
		kind, severity, message,
		operation.stable_id if operation != null else &"",
		operation.source_record_id if operation != null else &""
	))


static func _add_edit(
	issues: Array[FoundationTerrainGradingValidationIssue],
	kind: StringName,
	message: String,
	edit: FoundationTerrainGradingEdit,
	source_id: StringName = &""
) -> void:
	issues.append(FoundationTerrainGradingValidationIssue.new(
		kind, FoundationTerrainGradingValidationIssue.SEVERITY_ERROR,
		message, edit.operation_id, source_id, edit.grid_vertex
	))
