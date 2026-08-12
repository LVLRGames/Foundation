class_name FoundationTerrainGrader
extends RefCounted

## Deterministic Phase 9 planner and explicit apply/revert boundary.

const SOURCE_PASS: StringName = &"terrain_grading"
const OPERATION_ENTITY_TYPE: StringName = &"terrain_grading_operation"
const EPSILON := 0.000001


static func create_plan(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	terrain_origin_cell := Vector2i.ZERO,
	p_profile: FoundationTerrainGradingProfile = null
) -> FoundationTerrainGradingResult:
	var result := FoundationTerrainGradingResult.new()
	var profile := p_profile if p_profile != null else FoundationTerrainGradingProfile.new()
	if world == null or terrain == null:
		_add_diagnostic(result.diagnostics, &"missing_input", "Terrain grading requires world and terrain data.", &"error")
		return result
	var profile_errors := profile.validation_errors()
	if not profile_errors.is_empty():
		for error in profile_errors:
			_add_diagnostic(result.diagnostics, &"invalid_profile", error, &"error")
		return result

	var plan := FoundationTerrainGradingPlan.new()
	plan.generator_version = profile.generator_version
	plan.world_seed = world.metadata.seed
	plan.terrain_seed = terrain.seed
	plan.terrain_origin_cell = terrain_origin_cell
	plan.terrain_grid_cells = terrain.grid_cells
	plan.terrain_cell_size = terrain.cell_size
	plan.terrain_height_step = terrain.height_step
	plan.source_terrain_revision = terrain.revision
	plan.profile = FoundationTerrainGradingProfile.from_dict(profile.to_dict())
	result.plan = plan

	var operations: Dictionary = {}
	var contributions: Dictionary = {}
	for edge in world.get_road_edges():
		if not _plan_road(world, terrain, edge, plan, operations, contributions):
			result.diagnostics = plan.diagnostics.duplicate(true)
			return result
	for building in world.get_buildings():
		if not _plan_building(world, terrain, building, plan, operations, contributions):
			result.diagnostics = plan.diagnostics.duplicate(true)
			return result

	for operation in operations.values():
		plan.operations.append(operation as FoundationTerrainGradingOperation)
	plan.operations.sort_custom(_sort_operations)
	var contribution_values: Array = contributions.values()
	contribution_values.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var av: Vector2i = a["vertex"]
		var bv: Vector2i = b["vertex"]
		return av.y < bv.y or (av.y == bv.y and av.x < bv.x)
	)
	for contribution: Dictionary in contribution_values:
		var vertex: Vector2i = contribution["vertex"]
		var operation := operations.get(contribution["operation_id"]) as FoundationTerrainGradingOperation
		if operation == null:
			continue
		var edit := FoundationTerrainGradingEdit.new(
			vertex,
			terrain.get_vertex_height(vertex),
			float(contribution["target_height"]),
			terrain.get_vertex_modification_source(vertex),
			int(contribution["source"]),
			operation.stable_id,
			float(contribution["weight"])
		)
		plan.edits.append(edit)
		operation.edit_keys.append(edit.vertex_key())
		if operation.edit_keys.size() == 1:
			operation.target_elevation_min = edit.target_height
			operation.target_elevation_max = edit.target_height
		else:
			operation.target_elevation_min = minf(operation.target_elevation_min, edit.target_height)
			operation.target_elevation_max = maxf(operation.target_elevation_max, edit.target_height)

	result.validation_issues = FoundationTerrainGradingValidator.validate_plan(world, terrain, plan, false)
	result.diagnostics = plan.diagnostics.duplicate(true)
	result.success = not _has_errors(result.validation_issues) and not _diagnostics_have_errors(plan.diagnostics)
	return result


static func apply_plan(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	plan: FoundationTerrainGradingPlan
) -> FoundationTerrainGradingResult:
	var result := FoundationTerrainGradingResult.new()
	result.plan = plan
	if world == null or terrain == null or plan == null:
		_add_diagnostic(result.diagnostics, &"missing_input", "Applying terrain grading requires world, terrain, and plan data.", &"error")
		return result
	result.validation_issues = FoundationTerrainGradingValidator.validate_plan(world, terrain, plan, false)
	if plan.state != FoundationTerrainGradingPlan.STATE_PLANNED:
		result.validation_issues.append(FoundationTerrainGradingValidationIssue.new(
			&"plan_not_planned", FoundationTerrainGradingValidationIssue.SEVERITY_ERROR,
			"Only a planned terrain-grading plan can be applied."
		))
	if terrain.revision != plan.source_terrain_revision:
		result.validation_issues.append(FoundationTerrainGradingValidationIssue.new(
			&"stale_terrain_revision", FoundationTerrainGradingValidationIssue.SEVERITY_ERROR,
			"Terrain revision changed after the grading plan was created."
		))
	for edit in plan.edits:
		if not terrain.is_valid_vertex(edit.grid_vertex):
			continue
		if not is_equal_approx(terrain.get_vertex_height(edit.grid_vertex), edit.original_height):
			result.validation_issues.append(FoundationTerrainGradingValidationIssue.new(
				&"stale_vertex_height", FoundationTerrainGradingValidationIssue.SEVERITY_ERROR,
				"A planned vertex no longer matches its recorded original height.",
				edit.operation_id, &"", edit.grid_vertex
			))
		if terrain.get_vertex_modification_source(edit.grid_vertex) != edit.original_source:
			result.validation_issues.append(FoundationTerrainGradingValidationIssue.new(
				&"stale_vertex_source", FoundationTerrainGradingValidationIssue.SEVERITY_ERROR,
				"A planned vertex no longer matches its recorded original provenance.",
				edit.operation_id, &"", edit.grid_vertex
			))
	if _has_errors(result.validation_issues):
		return result

	var before_dirty := terrain.get_dirty_chunks().size()
	for edit in plan.edits:
		if terrain.set_vertex_height(edit.grid_vertex, edit.target_height, edit.target_source):
			result.changed_vertex_count += 1
	plan.state = FoundationTerrainGradingPlan.STATE_APPLIED
	plan.applied_terrain_revision = terrain.revision
	world.terrain_grading_plan = plan
	result.validation_issues = FoundationTerrainGradingValidator.validate_plan(world, terrain, plan, true)
	result.dirty_chunk_count = maxi(before_dirty, terrain.get_dirty_chunks().size())
	result.applied = true
	result.success = not _has_errors(result.validation_issues)
	return result


static func revert_plan(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	plan: FoundationTerrainGradingPlan
) -> FoundationTerrainGradingResult:
	var result := FoundationTerrainGradingResult.new()
	result.plan = plan
	if world == null or terrain == null or plan == null:
		_add_diagnostic(result.diagnostics, &"missing_input", "Reverting terrain grading requires world, terrain, and plan data.", &"error")
		return result
	if plan.state != FoundationTerrainGradingPlan.STATE_APPLIED:
		result.validation_issues.append(FoundationTerrainGradingValidationIssue.new(
			&"plan_not_applied", FoundationTerrainGradingValidationIssue.SEVERITY_ERROR,
			"Only an applied terrain-grading plan can be reverted."
		))
		return result
	for edit in plan.edits:
		if not terrain.is_valid_vertex(edit.grid_vertex):
			result.validation_issues.append(FoundationTerrainGradingValidationIssue.new(
				&"edit_outside_terrain", FoundationTerrainGradingValidationIssue.SEVERITY_ERROR,
				"A grading edit is outside the terrain vertex grid.", edit.operation_id, &"", edit.grid_vertex
			))
			continue
		if not is_equal_approx(terrain.get_vertex_height(edit.grid_vertex), edit.target_height) \
		or terrain.get_vertex_modification_source(edit.grid_vertex) != edit.target_source:
			result.validation_issues.append(FoundationTerrainGradingValidationIssue.new(
				&"unsafe_revert_mismatch", FoundationTerrainGradingValidationIssue.SEVERITY_ERROR,
				"Terrain changed after grading; revert was refused before any write.", edit.operation_id, &"", edit.grid_vertex
			))
	if _has_errors(result.validation_issues):
		return result
	for index in range(plan.edits.size() - 1, -1, -1):
		var edit := plan.edits[index]
		if terrain.set_vertex_height(edit.grid_vertex, edit.original_height, edit.original_source):
			result.changed_vertex_count += 1
	plan.state = FoundationTerrainGradingPlan.STATE_REVERTED
	plan.applied_terrain_revision = terrain.revision
	world.terrain_grading_plan = plan
	result.dirty_chunk_count = terrain.get_dirty_chunks().size()
	result.reverted = true
	result.success = true
	return result


static func _plan_road(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	edge: FoundationRoadEdge,
	plan: FoundationTerrainGradingPlan,
	operations: Dictionary,
	contributions: Dictionary
) -> bool:
	if edge.route_points.size() < 2:
		_add_plan_diagnostic(plan, &"invalid_road_route", "Road edge has fewer than two route points.", &"warning", edge.stable_id)
		return true
	var desired: Array[float] = []
	var bridge_samples: Array[bool] = []
	for index in range(edge.route_points.size()):
		var elevation := edge.route_points[index].y
		var bridge := false
		if index < edge.desired_elevation_samples.size():
			var sample := edge.desired_elevation_samples[index]
			elevation = sample.desired_elevation
			bridge = sample.bridge_candidate or sample.water_crossing
			if bridge:
				elevation = maxf(elevation, sample.terrain_elevation + plan.profile.bridge_clearance)
		desired.append(terrain.quantize_height(elevation))
		bridge_samples.append(bridge)
	var bridge_segments: Array[bool] = []
	for index in range(edge.route_points.size() - 1):
		bridge_segments.append(bridge_samples[index] and bridge_samples[index + 1])
	if not bridge_segments.has(true) and bool(edge.grading_requirements.get("bridge_candidate", false)):
		var candidate_index := _maximum_bridge_candidate_segment(edge)
		if candidate_index >= 0:
			bridge_segments[candidate_index] = true
			for sample_index in [candidate_index, candidate_index + 1]:
				if sample_index < edge.desired_elevation_samples.size():
					var sample := edge.desired_elevation_samples[sample_index]
					desired[sample_index] = terrain.quantize_height(maxf(desired[sample_index], sample.terrain_elevation + plan.profile.bridge_clearance))

	var cumulative: Array[float] = [0.0]
	for index in range(edge.route_points.size() - 1):
		var segment_length := _xz(edge.route_points[index]).distance_to(_xz(edge.route_points[index + 1]))
		cumulative.append(cumulative[-1] + segment_length)
	var bridge_intervals: Array[Vector2] = []
	var span_start := -1
	for index in range(bridge_segments.size() + 1):
		var is_bridge := index < bridge_segments.size() and bridge_segments[index]
		if is_bridge and span_start < 0:
			span_start = index
		elif not is_bridge and span_start >= 0:
			var span_end := index - 1
			bridge_intervals.append(Vector2(cumulative[span_start], cumulative[span_end + 1]))
			var span_operation := _make_operation(
				world, edge.stable_id, FoundationTerrainGradingOperation.KIND_BRIDGE_SPAN,
				plan.profile.road_priority_for(edge.road_class) + plan.profile.bridge_approach_priority_bonus + 1,
				"%d-%d" % [span_start, span_end]
			)
			var span_points := PackedVector2Array()
			for point_index in range(span_start, span_end + 2):
				span_points.append(_xz(edge.route_points[point_index]))
			span_operation.world_bounds = _bounds_for_points(span_points).grow(plan.profile.road_half_width_for(edge.road_class))
			span_operation.target_elevation_min = desired[span_start]
			span_operation.target_elevation_max = desired[span_start]
			for point_index in range(span_start + 1, span_end + 2):
				span_operation.target_elevation_min = minf(span_operation.target_elevation_min, desired[point_index])
				span_operation.target_elevation_max = maxf(span_operation.target_elevation_max, desired[point_index])
			span_operation.metadata = {
				"road_class": String(edge.road_class),
				"segment_start": span_start,
				"segment_end": span_end,
				"start_point": _vector3_dict(Vector3(edge.route_points[span_start].x, desired[span_start], edge.route_points[span_start].z)),
				"end_point": _vector3_dict(Vector3(edge.route_points[span_end + 1].x, desired[span_end + 1], edge.route_points[span_end + 1].z)),
				"clearance": plan.profile.bridge_clearance,
				"preserves_underlying_terrain": true,
			}
			operations[span_operation.stable_id] = span_operation
			span_start = -1

	var road_operation: FoundationTerrainGradingOperation
	var approach_operation: FoundationTerrainGradingOperation
	for index in range(edge.route_points.size() - 1):
		if bridge_segments[index]:
			continue
		var segment_interval := Vector2(cumulative[index], cumulative[index + 1])
		var is_approach := _interval_distance_to_intervals(segment_interval, bridge_intervals) <= plan.profile.bridge_approach_length
		var operation: FoundationTerrainGradingOperation
		var source := FoundationTerrainData.ModificationSource.ROAD_CUT
		if is_approach:
			if approach_operation == null:
				approach_operation = _make_operation(
					world, edge.stable_id, FoundationTerrainGradingOperation.KIND_BRIDGE_APPROACH,
					plan.profile.road_priority_for(edge.road_class) + plan.profile.bridge_approach_priority_bonus
				)
				approach_operation.metadata = {"road_class": String(edge.road_class), "segment_indices": []}
				operations[approach_operation.stable_id] = approach_operation
			operation = approach_operation
			source = FoundationTerrainData.ModificationSource.BRIDGE_APPROACH
		else:
			if road_operation == null:
				road_operation = _make_operation(
					world, edge.stable_id, FoundationTerrainGradingOperation.KIND_ROAD_CORRIDOR,
					plan.profile.road_priority_for(edge.road_class)
				)
				road_operation.metadata = {"road_class": String(edge.road_class), "segment_indices": []}
				operations[road_operation.stable_id] = road_operation
			operation = road_operation
		operation.metadata["segment_indices"].append(index)
		var segment_bounds := _segment_bounds(_xz(edge.route_points[index]), _xz(edge.route_points[index + 1]), plan.profile.road_half_width_for(edge.road_class) + plan.profile.road_blend_width)
		operation.world_bounds = _merge_bounds(operation.world_bounds, segment_bounds)
		if not _rasterize_road_segment(
			terrain, plan, operation, _xz(edge.route_points[index]), _xz(edge.route_points[index + 1]),
			desired[index], desired[index + 1], source, index, edge, bridge_segments,
			not bridge_intervals.is_empty(), contributions
		):
			return false
	return true


static func _plan_building(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	building: FoundationBuildingRecord,
	plan: FoundationTerrainGradingPlan,
	operations: Dictionary,
	contributions: Dictionary
) -> bool:
	if building.footprint.size() < 3 or building.footprint_area <= EPSILON:
		_add_plan_diagnostic(plan, &"invalid_building_footprint", "Building pad source has an invalid footprint.", &"warning", building.stable_id)
		return true
	var terrain_bounds := Rect2(
		Vector2(plan.terrain_origin_cell) * terrain.cell_size,
		Vector2(terrain.grid_cells) * terrain.cell_size
	)
	if not terrain_bounds.intersects(building.world_bounds, true):
		_add_plan_diagnostic(plan, &"building_outside_terrain", "Building pad footprint is outside the registered terrain extent.", &"warning", building.stable_id)
		return true
	if not terrain_bounds.encloses(building.world_bounds):
		_add_plan_diagnostic(plan, &"building_pad_clipped_to_terrain", "Building pad footprint crosses the registered terrain extent and was clipped.", &"warning", building.stable_id)
	var operation := _make_operation(
		world, building.stable_id, FoundationTerrainGradingOperation.KIND_BUILDING_PAD,
		plan.profile.building_pad_priority
	)
	var expansion := plan.profile.building_pad_apron + plan.profile.building_pad_blend_width
	operation.world_bounds = building.world_bounds.grow(expansion)
	var target_data := _building_pad_target(world, terrain, building, plan)
	var target_height := float(target_data["height"])
	operation.target_elevation_min = target_height
	operation.target_elevation_max = target_height
	operation.metadata = {
		"target_elevation": target_height,
		"target_source": target_data["source"],
		"primary_road_edge_id": String(building.primary_road_edge_id),
		"apron": plan.profile.building_pad_apron,
		"blend_width": plan.profile.building_pad_blend_width,
		"footprint": _polygon_dict(building.footprint),
	}
	operations[operation.stable_id] = operation
	var rect := _world_bounds_to_vertex_rect(operation.world_bounds, terrain, plan.terrain_origin_cell)
	for vertex_y in range(rect.position.y, rect.end.y):
		for vertex_x in range(rect.position.x, rect.end.x):
			if not _count_candidate(plan):
				return false
			var vertex := Vector2i(vertex_x, vertex_y)
			var world_point := _vertex_world(vertex, terrain, plan.terrain_origin_cell)
			var inside := _point_in_polygon(world_point, building.footprint)
			var distance := 0.0 if inside else _distance_to_polygon(world_point, building.footprint)
			if not inside and distance > expansion + EPSILON:
				continue
			if _skip_vertex(terrain, vertex, plan, false):
				continue
			var weight := 1.0
			if not inside and distance > plan.profile.building_pad_apron and plan.profile.building_pad_blend_width > EPSILON:
				weight = 1.0 - (distance - plan.profile.building_pad_apron) / plan.profile.building_pad_blend_width
			_consider_contribution(
				terrain, plan, contributions, vertex, target_height, weight,
				operation, FoundationTerrainData.ModificationSource.BUILDING_PAD,
				"building"
			)
	return true


static func _rasterize_road_segment(
	terrain: FoundationTerrainData,
	plan: FoundationTerrainGradingPlan,
	operation: FoundationTerrainGradingOperation,
	from: Vector2,
	to: Vector2,
	from_height: float,
	to_height: float,
	source: int,
	segment_index: int,
	edge: FoundationRoadEdge,
	bridge_segments: Array[bool],
	preserve_water: bool,
	contributions: Dictionary
) -> bool:
	var road_class := StringName(operation.metadata.get("road_class", String(FoundationRoadEdge.CLASS_LOCAL)))
	var half_width := plan.profile.road_half_width_for(road_class)
	var blend := plan.profile.road_blend_width
	var rect := _world_bounds_to_vertex_rect(_segment_bounds(from, to, half_width + blend), terrain, plan.terrain_origin_cell)
	for vertex_y in range(rect.position.y, rect.end.y):
		for vertex_x in range(rect.position.x, rect.end.x):
			if not _count_candidate(plan):
				return false
			var vertex := Vector2i(vertex_x, vertex_y)
			var world_point := _vertex_world(vertex, terrain, plan.terrain_origin_cell)
			if _point_under_bridge_segments(world_point, edge, bridge_segments, half_width):
				continue
			var closest := Geometry2D.get_closest_point_to_segment(world_point, from, to)
			var distance := world_point.distance_to(closest)
			if distance > half_width + blend + EPSILON:
				continue
			if _skip_vertex(terrain, vertex, plan, preserve_water):
				continue
			var segment_length_squared := from.distance_squared_to(to)
			var ratio := clampf((closest - from).dot(to - from) / segment_length_squared, 0.0, 1.0) if segment_length_squared > EPSILON else 0.0
			var desired := lerpf(from_height, to_height, ratio)
			var weight := 1.0
			if distance > half_width and blend > EPSILON:
				weight = 1.0 - (distance - half_width) / blend
			_consider_contribution(
				terrain, plan, contributions, vertex, desired, weight, operation, source,
				"%08d" % segment_index
			)
	return true


static func _consider_contribution(
	terrain: FoundationTerrainData,
	plan: FoundationTerrainGradingPlan,
	contributions: Dictionary,
	vertex: Vector2i,
	desired_height: float,
	weight: float,
	operation: FoundationTerrainGradingOperation,
	source: int,
	tie_key: String
) -> void:
	weight = clampf(weight, 0.0, 1.0)
	var original := terrain.get_vertex_height(vertex)
	var blended := lerpf(original, desired_height, weight)
	var minimum := original - plan.profile.maximum_cut_depth
	var maximum := original + plan.profile.maximum_fill_height
	var limited := clampf(blended, minimum, maximum)
	if not is_equal_approx(limited, blended):
		plan.clipped_edit_count += 1
		_add_plan_diagnostic(plan, &"cut_fill_clipped", "A requested grade exceeded the configured cut/fill limit.", &"warning", operation.source_record_id, vertex)
	var quantized_minimum: float = ceil(minimum / terrain.height_step) * terrain.height_step
	var quantized_maximum: float = floor(maximum / terrain.height_step) * terrain.height_step
	var target := clampf(terrain.quantize_height(limited), quantized_minimum, quantized_maximum)
	if source == FoundationTerrainData.ModificationSource.ROAD_CUT and target > original:
		source = FoundationTerrainData.ModificationSource.ROAD_FILL
	if is_equal_approx(target, original) and terrain.get_vertex_modification_source(vertex) == source:
		return
	var key := "%d,%d" % [vertex.x, vertex.y]
	var candidate := {
		"vertex": vertex,
		"target_height": target,
		"source": source,
		"operation_id": operation.stable_id,
		"priority": operation.priority,
		"weight": weight,
		"tie_key": "%s|%s" % [operation.stable_id, tie_key],
	}
	var existing: Dictionary = contributions.get(key, {})
	if existing.is_empty() or _contribution_precedes(candidate, existing):
		contributions[key] = candidate


static func _contribution_precedes(candidate: Dictionary, existing: Dictionary) -> bool:
	if int(candidate["priority"]) != int(existing["priority"]):
		return int(candidate["priority"]) > int(existing["priority"])
	if not is_equal_approx(float(candidate["weight"]), float(existing["weight"])):
		return float(candidate["weight"]) > float(existing["weight"])
	return String(candidate["tie_key"]) < String(existing["tie_key"])


static func _skip_vertex(
	terrain: FoundationTerrainData,
	vertex: Vector2i,
	plan: FoundationTerrainGradingPlan,
	preserve_water: bool
) -> bool:
	if not plan.profile.allow_protected_grading and _vertex_touches_flag(terrain, vertex, FoundationTerrainData.CellFlag.PROTECTED):
		plan.skipped_protected_count += 1
		return true
	if (preserve_water or not plan.profile.allow_water_grading) and _vertex_touches_flag(terrain, vertex, FoundationTerrainData.CellFlag.WATER):
		plan.skipped_water_count += 1
		return true
	return false


static func _vertex_touches_flag(terrain: FoundationTerrainData, vertex: Vector2i, flag: int) -> bool:
	for offset in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO]:
		var cell: Vector2i = vertex + offset
		if terrain.is_valid_cell(cell) and (terrain.get_cell_flags(cell) & flag) != 0:
			return true
	return false


static func edit_is_under_bridge_span(
	world: FoundationWorldData,
	plan: FoundationTerrainGradingPlan,
	edit: FoundationTerrainGradingEdit
) -> bool:
	var point := Vector2(edit.grid_vertex + plan.terrain_origin_cell) * plan.terrain_cell_size
	for operation in plan.operations:
		if operation.operation_kind != FoundationTerrainGradingOperation.KIND_BRIDGE_SPAN:
			continue
		var edge := world.get_record(operation.source_record_id) as FoundationRoadEdge
		if edge == null:
			continue
		var start := int(operation.metadata.get("segment_start", -1))
		var finish := int(operation.metadata.get("segment_end", -1))
		var bridge_segments: Array[bool] = []
		bridge_segments.resize(maxi(0, edge.route_points.size() - 1))
		for index in range(maxi(0, start), mini(bridge_segments.size(), finish + 1)):
			bridge_segments[index] = true
		if _point_under_bridge_segments(point, edge, bridge_segments, plan.profile.road_half_width_for(edge.road_class)):
			return true
	return false


static func _point_under_bridge_segments(
	point: Vector2,
	edge: FoundationRoadEdge,
	bridge_segments: Array[bool],
	half_width: float
) -> bool:
	for index in range(bridge_segments.size()):
		if not bridge_segments[index] or index + 1 >= edge.route_points.size():
			continue
		var closest := Geometry2D.get_closest_point_to_segment(point, _xz(edge.route_points[index]), _xz(edge.route_points[index + 1]))
		if point.distance_to(closest) <= half_width + EPSILON:
			return true
	return false


static func _building_pad_target(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	building: FoundationBuildingRecord,
	plan: FoundationTerrainGradingPlan
) -> Dictionary:
	var edge := world.get_record(building.primary_road_edge_id) as FoundationRoadEdge
	if edge != null and edge.route_points.size() >= 2:
		var nearest_distance := INF
		var nearest_height := 0.0
		for index in range(edge.route_points.size() - 1):
			var from := _xz(edge.route_points[index])
			var to := _xz(edge.route_points[index + 1])
			var closest := Geometry2D.get_closest_point_to_segment(building.centroid, from, to)
			var distance := building.centroid.distance_squared_to(closest)
			if distance >= nearest_distance:
				continue
			nearest_distance = distance
			var squared := from.distance_squared_to(to)
			var ratio := clampf((closest - from).dot(to - from) / squared, 0.0, 1.0) if squared > EPSILON else 0.0
			var from_height := edge.route_points[index].y
			var to_height := edge.route_points[index + 1].y
			if index < edge.desired_elevation_samples.size():
				from_height = edge.desired_elevation_samples[index].desired_elevation
			if index + 1 < edge.desired_elevation_samples.size():
				to_height = edge.desired_elevation_samples[index + 1].desired_elevation
			nearest_height = lerpf(from_height, to_height, ratio)
		return {"height": terrain.quantize_height(nearest_height), "source": "primary_road"}
	var samples: Array[float] = []
	var rect := _world_bounds_to_vertex_rect(building.world_bounds, terrain, plan.terrain_origin_cell)
	for vertex_y in range(rect.position.y, rect.end.y):
		for vertex_x in range(rect.position.x, rect.end.x):
			var vertex := Vector2i(vertex_x, vertex_y)
			if _point_in_polygon(_vertex_world(vertex, terrain, plan.terrain_origin_cell), building.footprint):
				samples.append(terrain.get_vertex_height(vertex))
	if samples.is_empty():
		var local := building.centroid / terrain.cell_size - Vector2(plan.terrain_origin_cell)
		var vertex := Vector2i(clampi(roundi(local.x), 0, terrain.grid_cells.x), clampi(roundi(local.y), 0, terrain.grid_cells.y))
		return {"height": terrain.get_vertex_height(vertex), "source": "centroid_terrain"}
	samples.sort()
	var midpoint := samples.size() / 2
	var median := samples[midpoint]
	if samples.size() % 2 == 0:
		median = (samples[midpoint - 1] + samples[midpoint]) * 0.5
	return {"height": terrain.quantize_height(median), "source": "footprint_median"}


static func _make_operation(
	world: FoundationWorldData,
	source_id: StringName,
	kind: StringName,
	priority: int,
	semantic_suffix := ""
) -> FoundationTerrainGradingOperation:
	var semantic := String(kind)
	if not semantic_suffix.is_empty():
		semantic += "|" + semantic_suffix
	var stable_id := FoundationSpatialId.make(
		world.metadata.seed,
		world.metadata.generator_version,
		world.metadata.content_pack_version,
		OPERATION_ENTITY_TYPE,
		source_id,
		semantic
	)
	var operation := FoundationTerrainGradingOperation.new(stable_id, kind, source_id, priority)
	var source := world.get_record(source_id)
	if source != null:
		operation.source_record_hash = JSON.stringify(source.to_dict(), "", true).sha256_text()
	return operation


static func _maximum_bridge_candidate_segment(edge: FoundationRoadEdge) -> int:
	if edge.route_points.size() < 2:
		return -1
	var best_index := 0
	var best_score := -1.0
	for index in range(edge.route_points.size() - 1):
		var score := 0.0
		for sample_index in [index, index + 1]:
			if sample_index < edge.desired_elevation_samples.size():
				var sample := edge.desired_elevation_samples[sample_index]
				score = maxf(score, sample.fill_height + (1000000.0 if sample.water_crossing else 0.0))
		if score > best_score:
			best_score = score
			best_index = index
	return best_index


static func _interval_distance_to_intervals(value: Vector2, intervals: Array[Vector2]) -> float:
	var best := INF
	for interval in intervals:
		if value.y >= interval.x and value.x <= interval.y:
			return 0.0
		best = minf(best, minf(absf(value.y - interval.x), absf(value.x - interval.y)))
	return best


static func _count_candidate(plan: FoundationTerrainGradingPlan) -> bool:
	plan.candidate_vertex_checks += 1
	if plan.candidate_vertex_checks <= plan.profile.maximum_candidate_vertices:
		return true
	if plan.candidate_vertex_checks == plan.profile.maximum_candidate_vertices + 1:
		_add_plan_diagnostic(plan, &"candidate_vertex_cap", "Terrain grading stopped at its explicit candidate-vertex cap.", &"error")
	return false


static func _world_bounds_to_vertex_rect(bounds: Rect2, terrain: FoundationTerrainData, origin_cell: Vector2i) -> Rect2i:
	var minimum := bounds.position / terrain.cell_size - Vector2(origin_cell)
	var maximum := bounds.end / terrain.cell_size - Vector2(origin_cell)
	var start := Vector2i(clampi(floori(minimum.x), 0, terrain.grid_cells.x), clampi(floori(minimum.y), 0, terrain.grid_cells.y))
	var inclusive_end := Vector2i(clampi(ceili(maximum.x), 0, terrain.grid_cells.x), clampi(ceili(maximum.y), 0, terrain.grid_cells.y))
	return Rect2i(start, inclusive_end - start + Vector2i.ONE)


static func _vertex_world(vertex: Vector2i, terrain: FoundationTerrainData, origin_cell: Vector2i) -> Vector2:
	return Vector2(vertex + origin_cell) * terrain.cell_size


static func _segment_bounds(from: Vector2, to: Vector2, expansion: float) -> Rect2:
	var minimum := Vector2(minf(from.x, to.x), minf(from.y, to.y)) - Vector2.ONE * expansion
	var maximum := Vector2(maxf(from.x, to.x), maxf(from.y, to.y)) + Vector2.ONE * expansion
	return Rect2(minimum, maximum - minimum)


static func _bounds_for_points(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


static func _merge_bounds(first: Rect2, second: Rect2) -> Rect2:
	return second if first.size == Vector2.ZERO else first.merge(second)


static func _point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon)


static func _distance_to_polygon(point: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	for index in range(polygon.size()):
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])))
	return best


static func _polygon_dict(polygon: PackedVector2Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point in polygon:
		result.append({"x": point.x, "y": point.y})
	return result


static func _vector3_dict(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


static func _xz(value: Vector3) -> Vector2:
	return Vector2(value.x, value.z)


static func _sort_operations(a: FoundationTerrainGradingOperation, b: FoundationTerrainGradingOperation) -> bool:
	if a.priority != b.priority:
		return a.priority > b.priority
	return String(a.stable_id) < String(b.stable_id)


static func _add_plan_diagnostic(
	plan: FoundationTerrainGradingPlan,
	kind: StringName,
	message: String,
	severity: StringName,
	source_id: StringName = &"",
	vertex := Vector2i(-1, -1)
) -> void:
	plan.diagnostics.append({
		"kind": String(kind),
		"severity": String(severity),
		"message": message,
		"source_record_id": String(source_id),
		"grid_vertex": {"x": vertex.x, "y": vertex.y},
	})


static func _add_diagnostic(diagnostics: Array[Dictionary], kind: StringName, message: String, severity: StringName) -> void:
	diagnostics.append({"kind": String(kind), "severity": String(severity), "message": message})


static func _diagnostics_have_errors(diagnostics: Array[Dictionary]) -> bool:
	for diagnostic in diagnostics:
		if diagnostic.get("severity", "") == "error":
			return true
	return false


static func _has_errors(issues: Array[FoundationTerrainGradingValidationIssue]) -> bool:
	for issue in issues:
		if issue.severity == FoundationTerrainGradingValidationIssue.SEVERITY_ERROR:
			return true
	return false
