class_name FoundationRoadTopologyGenerator
extends RefCounted

## Deterministic generation-time terrain routing. This is not a gameplay navigation API.

const SOURCE_PASS: StringName = &"phase_2_road_topology"
const EPSILON := 0.000001


static func generate(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	terrain_origin_cell := Vector2i.ZERO,
	profile: FoundationRoadGenerationProfile = null
) -> FoundationRoadGenerationResult:
	var result := FoundationRoadGenerationResult.new()
	if world == null:
		return result.fail("Road topology requires FoundationWorldData.")
	if terrain == null:
		return result.fail("Road topology requires authoritative FoundationTerrainData.")
	var active_profile := profile if profile != null else FoundationRoadGenerationProfile.new()
	var profile_errors := active_profile.validation_errors()
	if not profile_errors.is_empty():
		return result.fail("Invalid road generation profile: %s" % "; ".join(profile_errors))
	if not is_equal_approx(terrain.cell_size, world.coordinate_system.cell_size):
		return result.fail("Terrain and world coordinate systems must use the same cell size.")
	for pattern in world.get_road_pattern_areas():
		var pattern_errors := pattern.validation_errors()
		if not pattern_errors.is_empty():
			return result.fail("Invalid road-pattern area %s: %s" % [pattern.stable_id, "; ".join(pattern_errors)])

	world.register_layer_type(FoundationWorldData.ROAD_NODE_LAYER)
	world.register_layer_type(FoundationWorldData.ROAD_EDGE_LAYER)
	world.register_layer_type(FoundationWorldData.LOGICAL_ROAD_LAYER)
	world.register_layer_type(FoundationWorldData.ROAD_INTERSECTION_LAYER)
	var preserved := _remove_replaceable_records(world)
	result.preserved_node_count = int(preserved["nodes"])
	result.preserved_edge_count = int(preserved["edges"])

	var anchors := world.get_anchors()
	var node_by_anchor: Dictionary = {}
	for anchor in anchors:
		var connection_intent := _connection_intent_for_anchor(anchor)
		if connection_intent == FoundationRoadNode.INTENT_MANDATORY:
			result.mandatory_anchor_count += 1
		var node_id := _node_id(world.metadata, active_profile, anchor)
		var node := world.get_record(node_id) as FoundationRoadNode
		if node == null:
			node = FoundationRoadNode.new(
				node_id,
				_terrain_position(terrain, terrain_origin_cell, anchor.world_position),
				FoundationRoadNode.ROLE_MAP_EXIT if anchor.anchor_category == FoundationCityAnchor.CATEGORY_MAP_EXIT else FoundationRoadNode.KIND_ANCHOR,
				anchor.stable_id
			)
			node.source_pass = SOURCE_PASS
			node.source_version = active_profile.generator_version
			node.tags = PackedStringArray(["phase_2", "anchor_node"])
			node.metadata = {
				"anchor_category": String(anchor.anchor_category),
				"anchor_priority": anchor.priority_weight,
				"anchor_connection_intent": String(connection_intent),
			}
			world.register_record(node)
			result.generated_node_count += 1
		if node.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			node.anchor_connection_intent = connection_intent
		node_by_anchor[anchor.stable_id] = node

	var connection_candidates: Array[Dictionary] = []
	if anchors.size() >= 2:
		var candidates := _build_candidates(
			world,
			terrain,
			terrain_origin_cell,
			active_profile,
			anchors,
			node_by_anchor
		)
		var selected := _select_connected_edges(
			anchors,
			candidates,
			active_profile.extra_edge_count,
			node_by_anchor,
			world.get_road_edges()
		)
		var selected_pair_keys: Dictionary = {}
		for candidate: Dictionary in selected:
			selected_pair_keys[String(candidate["pair_key"])] = true
		for candidate: Dictionary in candidates:
			var accepted := selected_pair_keys.has(String(candidate["pair_key"]))
			connection_candidates.append(_candidate_debug_data(candidate, accepted))
			if accepted:
				result.accepted_candidate_count += 1
			else:
				result.rejected_candidate_count += 1
		for candidate: Dictionary in selected:
			result.expanded_cell_count += int(candidate["expanded_cells"])
			result.total_terrain_cost += float(candidate["terrain_cost"])
			var from_anchor := candidate["from_anchor"] as FoundationCityAnchor
			var to_anchor := candidate["to_anchor"] as FoundationCityAnchor
			var from_node := node_by_anchor[from_anchor.stable_id] as FoundationRoadNode
			var to_node := node_by_anchor[to_anchor.stable_id] as FoundationRoadNode
			var edge_id := _edge_id(
				world.metadata,
				active_profile,
				from_anchor.stable_id,
				to_anchor.stable_id
			)
			var existing := world.get_record(edge_id) as FoundationRoadEdge
			if existing != null:
				if _edge_connects(existing, from_node.stable_id, to_node.stable_id):
					continue
				edge_id = _repair_edge_id(
					world,
					active_profile,
					from_anchor.stable_id,
					to_anchor.stable_id
				)
			var edge := FoundationRoadEdge.new(
				edge_id,
				from_node.stable_id,
				to_node.stable_id,
				candidate["route_points"] as PackedVector3Array,
				_road_class_for_anchors(from_anchor, to_anchor)
			)
			edge.terrain_cost = float(candidate["terrain_cost"])
			edge.used_fallback_route = bool(candidate["used_fallback"])
			edge.generation_priority = maxf(from_anchor.priority_weight, to_anchor.priority_weight)
			edge.source_pass = SOURCE_PASS
			edge.source_version = active_profile.generator_version
			edge.tags = PackedStringArray(["phase_2", "terrain_aware", "abstract_topology"])
			edge.metadata = {
				"from_anchor_id": String(from_anchor.stable_id),
				"to_anchor_id": String(to_anchor.stable_id),
				"expanded_cells": int(candidate["expanded_cells"]),
				"terrain_revision": terrain.revision,
				"selection_cost": float(candidate["selection_cost"]),
			}
			_configure_edge_contract(edge)
			_calculate_grading_requirements(edge, terrain, terrain_origin_cell, active_profile)
			world.register_record(edge)
			result.generated_edge_count += 1

	if active_profile.enable_pattern_topology:
		_generate_pattern_topology(world, terrain, terrain_origin_cell, active_profile, result)
	_rebuild_incident_edges(world)
	_rebuild_node_roles(world)
	_assign_logical_roads(world, active_profile, result)
	_build_intersection_records(world, active_profile, result)
	if not _anchor_nodes_connected(world, anchors, node_by_anchor):
		return result.fail("Road generation could not connect every city-anchor node.")
	result.success = true
	result.validation_issues = FoundationRoadTopologyValidator.validate(world, active_profile)
	_set_layer_generation_metadata(
		world, terrain, terrain_origin_cell, active_profile, result, connection_candidates
	)
	return result


static func regenerate_derived_topology(
	world: FoundationWorldData,
	profile: FoundationRoadGenerationProfile = null
) -> FoundationRoadGenerationResult:
	var result := FoundationRoadGenerationResult.new()
	if world == null:
		return result.fail("Derived road-topology regeneration requires FoundationWorldData.")
	var active_profile := profile if profile != null else FoundationRoadGenerationProfile.new()
	_remove_generated_logical_roads(world)
	for intersection in world.get_road_intersections():
		if intersection.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(intersection.stable_id)
	_rebuild_incident_edges(world)
	_rebuild_node_roles(world)
	_assign_logical_roads(world, active_profile, result)
	_build_intersection_records(world, active_profile, result)
	result.validation_issues = FoundationRoadTopologyValidator.validate(world, active_profile)
	var validation_data: Array[Dictionary] = []
	for issue in result.validation_issues:
		validation_data.append(issue.to_dict())
	for layer_type in [
		FoundationWorldData.ROAD_NODE_LAYER,
		FoundationWorldData.ROAD_EDGE_LAYER,
		FoundationWorldData.LOGICAL_ROAD_LAYER,
		FoundationWorldData.ROAD_INTERSECTION_LAYER,
	]:
		var layer := world.get_layer(layer_type)
		if layer != null:
			layer.metadata["validation_issues"] = validation_data.duplicate(true)
			layer.metadata["generation_counts"] = result.to_dict()
	result.success = true
	return result


static func clear_generated_road_data(world: FoundationWorldData) -> int:
	if world == null:
		return 0
	var removed := 0
	var protected_node_ids: Dictionary = {}
	var protected_logical_ids: Dictionary = {}
	for edge in world.get_road_edges():
		if edge.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
			protected_node_ids[edge.from_node_id] = true
			protected_node_ids[edge.to_node_id] = true
			if not String(edge.logical_road_id).is_empty():
				protected_logical_ids[edge.logical_road_id] = true
	for intersection in world.get_road_intersections():
		if intersection.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			removed += 1 if world.unregister_record(intersection.stable_id) else 0
	for logical in world.get_logical_roads():
		if (
			logical.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED
			and not protected_logical_ids.has(logical.stable_id)
		):
			removed += 1 if world.unregister_record(logical.stable_id) else 0
	for edge in world.get_road_edges():
		if edge.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			removed += 1 if world.unregister_record(edge.stable_id) else 0
	for node in world.get_road_nodes():
		if (
			node.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED
			and not protected_node_ids.has(node.stable_id)
		):
			removed += 1 if world.unregister_record(node.stable_id) else 0
	_rebuild_incident_edges(world)
	return removed


static func _remove_replaceable_records(world: FoundationWorldData) -> Dictionary:
	var retained_logical_roads := _remove_generated_logical_roads(world)
	var retained_intersections: Array[FoundationIntersectionRecord] = []
	for intersection in world.get_road_intersections():
		if intersection.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(intersection.stable_id)
		else:
			retained_intersections.append(intersection)
	var protected_node_ids: Dictionary = {}
	var retained_edges: Array[FoundationRoadEdge] = []
	var preserved_edges := 0
	for edge in world.get_road_edges():
		if edge.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(edge.stable_id)
		else:
			protected_node_ids[edge.from_node_id] = true
			protected_node_ids[edge.to_node_id] = true
			retained_edges.append(edge)
			preserved_edges += 1
	var retained_nodes: Array[FoundationRoadNode] = []
	var preserved_nodes := 0
	for node in world.get_road_nodes():
		if (
			node.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED
			and not protected_node_ids.has(node.stable_id)
		):
			world.unregister_record(node.stable_id)
		else:
			retained_nodes.append(node)
			preserved_nodes += 1
	# Authored setters update record bounds, while index ownership is registration-time data.
	# Re-register the same objects so preserved data and identity survive with fresh buckets.
	for edge in retained_edges:
		world.register_record(edge)
	for node in retained_nodes:
		world.register_record(node)
	for logical_road in retained_logical_roads:
		world.register_record(logical_road)
	for intersection in retained_intersections:
		world.register_record(intersection)
	return {"nodes": preserved_nodes, "edges": preserved_edges}


static func _remove_generated_logical_roads(
	world: FoundationWorldData
) -> Array[FoundationLogicalRoad]:
	var retained: Array[FoundationLogicalRoad] = []
	var generated_ids: Dictionary = {}
	for logical_road in world.get_logical_roads():
		if logical_road.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			generated_ids[logical_road.stable_id] = true
		else:
			retained.append(logical_road)
	for edge in world.get_road_edges():
		if generated_ids.has(edge.logical_road_id):
			edge.logical_road_id = &""
	for logical_id: StringName in generated_ids:
		world.unregister_record(logical_id)
	return retained


static func _set_layer_generation_metadata(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	profile: FoundationRoadGenerationProfile,
	result: FoundationRoadGenerationResult,
	connection_candidates: Array[Dictionary]
) -> void:
	var validation_data: Array[Dictionary] = []
	for issue in result.validation_issues:
		validation_data.append(issue.to_dict())
	var metadata := {
		"format_version": 2,
		"source_pass": String(SOURCE_PASS),
		"generator_version": profile.generator_version,
		"terrain_revision": terrain.revision,
		"terrain_origin_cell": {"x": terrain_origin_cell.x, "y": terrain_origin_cell.y},
		"profile": profile.to_dict(),
		"seed_streams": Array(FoundationRoadGenerationProfile.SEED_STREAMS),
		"connection_candidates": connection_candidates.duplicate(true),
		"routing_cost_cells": _build_routing_cost_debug_cells(terrain, terrain_origin_cell, profile),
		"validation_issues": validation_data,
		"generation_counts": result.to_dict(),
	}
	world.get_layer(FoundationWorldData.ROAD_NODE_LAYER).metadata = metadata.duplicate(true)
	world.get_layer(FoundationWorldData.ROAD_EDGE_LAYER).metadata = metadata.duplicate(true)
	world.get_layer(FoundationWorldData.LOGICAL_ROAD_LAYER).metadata = metadata.duplicate(true)
	world.get_layer(FoundationWorldData.ROAD_INTERSECTION_LAYER).metadata = metadata.duplicate(true)


static func _build_candidates(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	profile: FoundationRoadGenerationProfile,
	anchors: Array[FoundationCityAnchor],
	node_by_anchor: Dictionary
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for from_index in range(anchors.size() - 1):
		for to_index in range(from_index + 1, anchors.size()):
			var from_anchor := anchors[from_index]
			var to_anchor := anchors[to_index]
			var from_node := node_by_anchor[from_anchor.stable_id] as FoundationRoadNode
			var to_node := node_by_anchor[to_anchor.stable_id] as FoundationRoadNode
			var route := _find_terrain_route(
				terrain,
				terrain_origin_cell,
				from_node.world_position,
				to_node.world_position,
				profile
			)
			var importance := maxf(0.25, (
				_anchor_connection_weight(from_anchor) + _anchor_connection_weight(to_anchor)
			) * 0.5)
			candidates.append({
				"from_anchor": from_anchor,
				"to_anchor": to_anchor,
				"from_node_id": from_node.stable_id,
				"to_node_id": to_node.stable_id,
				"pair_key": "%s|%s" % [from_anchor.stable_id, to_anchor.stable_id],
				"selection_cost": float(route["terrain_cost"]) / importance,
				"terrain_cost": route["terrain_cost"],
				"route_points": route["route_points"],
				"expanded_cells": route["expanded_cells"],
				"used_fallback": route["used_fallback"],
			})
	candidates.sort_custom(_candidate_less)
	return candidates


static func _select_connected_edges(
	anchors: Array[FoundationCityAnchor],
	candidates: Array[Dictionary],
	extra_edge_count: int,
	node_by_anchor: Dictionary,
	preserved_edges: Array[FoundationRoadEdge]
) -> Array[Dictionary]:
	var parents: Dictionary = {}
	for anchor in anchors:
		var node := node_by_anchor[anchor.stable_id] as FoundationRoadNode
		parents[node.stable_id] = node.stable_id
	var selected: Array[Dictionary] = []
	var selected_keys: Dictionary = {}
	var component_count := parents.size()
	for edge in preserved_edges:
		if (
			not parents.has(edge.from_node_id)
			or not parents.has(edge.to_node_id)
			or edge.from_node_id == edge.to_node_id
		):
			continue
		selected_keys[_node_pair_key(edge.from_node_id, edge.to_node_id)] = true
		var preserved_from_root := _find_root(parents, edge.from_node_id)
		var preserved_to_root := _find_root(parents, edge.to_node_id)
		if preserved_from_root != preserved_to_root:
			parents[preserved_to_root] = preserved_from_root
			component_count -= 1
	for candidate in candidates:
		var from_node_id := StringName(candidate["from_node_id"])
		var to_node_id := StringName(candidate["to_node_id"])
		var from_root := _find_root(parents, from_node_id)
		var to_root := _find_root(parents, to_node_id)
		if from_root == to_root:
			continue
		parents[to_root] = from_root
		selected.append(candidate)
		selected_keys[_node_pair_key(from_node_id, to_node_id)] = true
		component_count -= 1
		if component_count == 1:
			break
	var remaining_extras := extra_edge_count
	if remaining_extras > 0:
		for candidate in candidates:
			var pair_key := _node_pair_key(
				StringName(candidate["from_node_id"]),
				StringName(candidate["to_node_id"])
			)
			if selected_keys.has(pair_key):
				continue
			selected.append(candidate)
			selected_keys[pair_key] = true
			remaining_extras -= 1
			if remaining_extras == 0:
				break
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["pair_key"]) < String(b["pair_key"])
	)
	return selected


static func _find_root(parents: Dictionary, stable_id: StringName) -> StringName:
	var root := stable_id
	while StringName(parents[root]) != root:
		root = StringName(parents[root])
	var current := stable_id
	while StringName(parents[current]) != root:
		var next := StringName(parents[current])
		parents[current] = root
		current = next
	return root


static func _find_terrain_route(
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	from_world: Vector3,
	to_world: Vector3,
	profile: FoundationRoadGenerationProfile
) -> Dictionary:
	var start := _clamped_local_cell(terrain, terrain_origin_cell, from_world)
	var goal := _clamped_local_cell(terrain, terrain_origin_cell, to_world)
	var open_heap: Array[Dictionary] = []
	var g_score: Dictionary = {start: 0.0}
	var came_from: Dictionary = {}
	var closed: Dictionary = {}
	var height_cache: Dictionary = {}
	var sampler := FoundationTerrainSampler.new(terrain)
	_heap_push(open_heap, {
		"cell": start,
		"g": 0.0,
		"h": _heuristic(terrain, start, goal),
		"f": _heuristic(terrain, start, goal),
	})
	var expanded := 0
	var found := false
	while not open_heap.is_empty() and expanded < profile.max_expanded_cells:
		var entry := _heap_pop(open_heap)
		var current: Vector2i = entry["cell"]
		if closed.has(current):
			continue
		var current_best := float(g_score.get(current, INF))
		if float(entry["g"]) > current_best + EPSILON:
			continue
		closed[current] = true
		expanded += 1
		if current == goal:
			found = true
			break
		for neighbor in _neighbors(current, profile.search_diagonals):
			if not terrain.is_valid_cell(neighbor) or closed.has(neighbor):
				continue
			var tentative := current_best + _movement_cost(
				terrain,
				sampler,
				height_cache,
				current,
				neighbor,
				profile
			)
			var previous := float(g_score.get(neighbor, INF))
			var should_update := tentative < previous - EPSILON
			if is_equal_approx(tentative, previous) and came_from.has(neighbor):
				should_update = _cell_less(current, came_from[neighbor])
			if not should_update:
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative
			var heuristic := _heuristic(terrain, neighbor, goal)
			_heap_push(open_heap, {
				"cell": neighbor,
				"g": tentative,
				"h": heuristic,
				"f": tentative + heuristic,
			})

	var route_cells: Array[Vector2i]
	var used_fallback := not found
	if found:
		route_cells = _reconstruct_cells(came_from, start, goal)
	else:
		route_cells = _fallback_cells(start, goal)
	var terrain_cost := _route_cost(
		terrain,
		sampler,
		height_cache,
		route_cells,
		profile
	)
	var route_points := _world_route_points(
		terrain,
		sampler,
		terrain_origin_cell,
		from_world,
		to_world,
		route_cells
	)
	return {
		"route_points": route_points,
		"terrain_cost": terrain_cost,
		"expanded_cells": expanded,
		"used_fallback": used_fallback,
	}


static func _movement_cost(
	terrain: FoundationTerrainData,
	sampler: FoundationTerrainSampler,
	height_cache: Dictionary,
	from_cell: Vector2i,
	to_cell: Vector2i,
	profile: FoundationRoadGenerationProfile
) -> float:
	var offset := to_cell - from_cell
	var horizontal := terrain.cell_size * (sqrt(2.0) if offset.x != 0 and offset.y != 0 else 1.0)
	var from_height := _cell_height(terrain, sampler, height_cache, from_cell)
	var to_height := _cell_height(terrain, sampler, height_cache, to_cell)
	var slope_ratio := absf(to_height - from_height) / horizontal
	var cost := horizontal * (1.0 + profile.slope_cost_weight * slope_ratio * slope_ratio)
	var flags := terrain.get_cell_flags(to_cell)
	if (flags & FoundationTerrainData.CellFlag.NO_BUILD) != 0:
		cost += profile.no_build_penalty
	if (flags & FoundationTerrainData.CellFlag.PROTECTED) != 0:
		cost += profile.protected_penalty
	if (flags & FoundationTerrainData.CellFlag.WATER) != 0:
		cost += profile.water_penalty
	cost += profile.surface_penalty(terrain.get_cell_surface(to_cell))
	return cost


static func _route_cost(
	terrain: FoundationTerrainData,
	sampler: FoundationTerrainSampler,
	height_cache: Dictionary,
	cells: Array[Vector2i],
	profile: FoundationRoadGenerationProfile
) -> float:
	var total := 0.0
	for index in range(cells.size() - 1):
		total += _movement_cost(terrain, sampler, height_cache, cells[index], cells[index + 1], profile)
	return total


static func _cell_height(
	terrain: FoundationTerrainData,
	sampler: FoundationTerrainSampler,
	cache: Dictionary,
	cell: Vector2i
) -> float:
	if not cache.has(cell):
		cache[cell] = sampler.get_height_at_world((Vector2(cell) + Vector2(0.5, 0.5)) * terrain.cell_size)
	return float(cache[cell])


static func _world_route_points(
	terrain: FoundationTerrainData,
	sampler: FoundationTerrainSampler,
	terrain_origin_cell: Vector2i,
	from_world: Vector3,
	to_world: Vector3,
	cells: Array[Vector2i]
) -> PackedVector3Array:
	var points := PackedVector3Array()
	_append_unique_point(points, from_world)
	for cell in cells:
		var global_cell := terrain_origin_cell + cell
		var xz := (Vector2(global_cell) + Vector2(0.5, 0.5)) * terrain.cell_size
		var height := sampler.get_height_at_world((Vector2(cell) + Vector2(0.5, 0.5)) * terrain.cell_size)
		_append_unique_point(points, Vector3(xz.x, height, xz.y))
	_append_unique_point(points, to_world)
	return points


static func _append_unique_point(points: PackedVector3Array, point: Vector3) -> void:
	if points.is_empty() or points[points.size() - 1].distance_squared_to(point) > EPSILON:
		points.append(point)


static func _terrain_position(
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	world_position: Vector3
) -> Vector3:
	var terrain_origin := Vector2(terrain_origin_cell) * terrain.cell_size
	var local_xz := Vector2(world_position.x, world_position.z) - terrain_origin
	var height := FoundationTerrainSampler.new(terrain).get_height_at_world(local_xz)
	return Vector3(world_position.x, height, world_position.z)


static func _clamped_local_cell(
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	world_position: Vector3
) -> Vector2i:
	var global_cell := Vector2i(
		floori(world_position.x / terrain.cell_size),
		floori(world_position.z / terrain.cell_size)
	)
	var local := global_cell - terrain_origin_cell
	return Vector2i(
		clampi(local.x, 0, terrain.grid_cells.x - 1),
		clampi(local.y, 0, terrain.grid_cells.y - 1)
	)


static func _neighbors(cell: Vector2i, include_diagonals: bool) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = [
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.LEFT,
		Vector2i.UP,
	]
	if include_diagonals:
		offsets.append_array([
			Vector2i(1, 1),
			Vector2i(-1, 1),
			Vector2i(-1, -1),
			Vector2i(1, -1),
		])
	var result: Array[Vector2i] = []
	for offset in offsets:
		result.append(cell + offset)
	return result


static func _heuristic(terrain: FoundationTerrainData, cell: Vector2i, goal: Vector2i) -> float:
	return Vector2(cell - goal).length() * terrain.cell_size


static func _reconstruct_cells(
	came_from: Dictionary,
	start: Vector2i,
	goal: Vector2i
) -> Array[Vector2i]:
	var reversed: Array[Vector2i] = [goal]
	var current := goal
	while current != start:
		if not came_from.has(current):
			return _fallback_cells(start, goal)
		current = came_from[current]
		reversed.append(current)
	reversed.reverse()
	return reversed


static func _fallback_cells(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var delta := goal - start
	var steps := maxi(absi(delta.x), absi(delta.y))
	if steps == 0:
		return [start]
	for index in range(steps + 1):
		var ratio := float(index) / float(steps)
		var cell := Vector2i(
			roundi(lerpf(start.x, goal.x, ratio)),
			roundi(lerpf(start.y, goal.y, ratio))
		)
		if result.is_empty() or result[result.size() - 1] != cell:
			result.append(cell)
	return result


static func _heap_push(heap: Array[Dictionary], entry: Dictionary) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if not _heap_less(heap[index], heap[parent]):
			break
		var swap := heap[parent]
		heap[parent] = heap[index]
		heap[index] = swap
		index = parent


static func _heap_pop(heap: Array[Dictionary]) -> Dictionary:
	var result := heap[0]
	var last := heap.pop_back() as Dictionary
	if heap.is_empty():
		return result
	heap[0] = last
	var index := 0
	while true:
		var left := index * 2 + 1
		var right := left + 1
		var smallest := index
		if left < heap.size() and _heap_less(heap[left], heap[smallest]):
			smallest = left
		if right < heap.size() and _heap_less(heap[right], heap[smallest]):
			smallest = right
		if smallest == index:
			break
		var swap := heap[index]
		heap[index] = heap[smallest]
		heap[smallest] = swap
		index = smallest
	return result


static func _heap_less(a: Dictionary, b: Dictionary) -> bool:
	var a_f := float(a["f"])
	var b_f := float(b["f"])
	if not is_equal_approx(a_f, b_f):
		return a_f < b_f
	var a_h := float(a["h"])
	var b_h := float(b["h"])
	if not is_equal_approx(a_h, b_h):
		return a_h < b_h
	return _cell_less(a["cell"], b["cell"])


static func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func _candidate_less(a: Dictionary, b: Dictionary) -> bool:
	var a_cost := float(a["selection_cost"])
	var b_cost := float(b["selection_cost"])
	if not is_equal_approx(a_cost, b_cost):
		return a_cost < b_cost
	return String(a["pair_key"]) < String(b["pair_key"])


static func _node_id(
	metadata: FoundationWorldMetadata,
	profile: FoundationRoadGenerationProfile,
	anchor: FoundationCityAnchor
) -> StringName:
	return FoundationSpatialId.make(
		metadata.seed,
		profile.generator_version,
		metadata.content_pack_version,
		FoundationRoadNode.ENTITY_TYPE,
		anchor.stable_id,
		"anchor_node"
	)


static func _edge_id(
	metadata: FoundationWorldMetadata,
	profile: FoundationRoadGenerationProfile,
	from_anchor_id: StringName,
	to_anchor_id: StringName
) -> StringName:
	var first := from_anchor_id
	var second := to_anchor_id
	if String(second) < String(first):
		first = to_anchor_id
		second = from_anchor_id
	return FoundationSpatialId.make(
		metadata.seed,
		profile.generator_version,
		metadata.content_pack_version,
		FoundationRoadEdge.ENTITY_TYPE,
		&"",
		"%s|%s" % [first, second]
	)


static func _repair_edge_id(
	world: FoundationWorldData,
	profile: FoundationRoadGenerationProfile,
	from_anchor_id: StringName,
	to_anchor_id: StringName
) -> StringName:
	var first := from_anchor_id
	var second := to_anchor_id
	if String(second) < String(first):
		first = to_anchor_id
		second = from_anchor_id
	var ordinal := 1
	while true:
		var stable_id := FoundationSpatialId.make(
			world.metadata.seed,
			profile.generator_version,
			world.metadata.content_pack_version,
			FoundationRoadEdge.ENTITY_TYPE,
			&"",
			"%s|%s|repair:%d" % [first, second, ordinal]
		)
		if world.get_record(stable_id) == null:
			return stable_id
		ordinal += 1
	return &""


static func _edge_connects(
	edge: FoundationRoadEdge,
	first_node_id: StringName,
	second_node_id: StringName
) -> bool:
	return (
		(edge.from_node_id == first_node_id and edge.to_node_id == second_node_id)
		or (edge.from_node_id == second_node_id and edge.to_node_id == first_node_id)
	)


static func _node_pair_key(first_node_id: StringName, second_node_id: StringName) -> String:
	if String(second_node_id) < String(first_node_id):
		return "%s|%s" % [second_node_id, first_node_id]
	return "%s|%s" % [first_node_id, second_node_id]


static func _road_class_for_anchors(
	from_anchor: FoundationCityAnchor,
	to_anchor: FoundationCityAnchor
) -> StringName:
	var highway_categories: Array[StringName] = [
		FoundationCityAnchor.CATEGORY_HIGHWAY_ENTRANCE,
		FoundationCityAnchor.CATEGORY_MAP_EXIT,
		FoundationCityAnchor.CATEGORY_EXTERNAL_DESTINATION,
	]
	if from_anchor.anchor_category in highway_categories and to_anchor.anchor_category in highway_categories:
		return FoundationRoadEdge.CLASS_HIGHWAY
	var major_categories: Array[StringName] = [
		FoundationCityAnchor.CATEGORY_CITY_CENTER,
		FoundationCityAnchor.CATEGORY_CIVIC_CENTER,
		FoundationCityAnchor.CATEGORY_HIGHWAY_ENTRANCE,
		FoundationCityAnchor.CATEGORY_MAP_EXIT,
		FoundationCityAnchor.CATEGORY_EXTERNAL_DESTINATION,
	]
	if from_anchor.anchor_category in major_categories or to_anchor.anchor_category in major_categories:
		return FoundationRoadEdge.CLASS_ARTERIAL
	return FoundationRoadEdge.CLASS_COLLECTOR


static func _rebuild_incident_edges(world: FoundationWorldData) -> void:
	for node in world.get_road_nodes():
		node.clear_incident_edges()
	for edge in world.get_road_edges():
		var from_node := world.get_record(edge.from_node_id) as FoundationRoadNode
		var to_node := world.get_record(edge.to_node_id) as FoundationRoadNode
		if from_node != null:
			from_node.add_incident_edge(edge.stable_id)
		if to_node != null:
			to_node.add_incident_edge(edge.stable_id)


static func _anchor_nodes_connected(
	world: FoundationWorldData,
	anchors: Array[FoundationCityAnchor],
	node_by_anchor: Dictionary
) -> bool:
	if anchors.size() <= 1:
		return true
	var target_ids: Dictionary = {}
	for anchor in anchors:
		var node := node_by_anchor.get(anchor.stable_id) as FoundationRoadNode
		if node == null:
			return false
		target_ids[node.stable_id] = true
	var first_node := node_by_anchor[anchors[0].stable_id] as FoundationRoadNode
	var pending: Array[StringName] = [first_node.stable_id]
	var visited: Dictionary = {}
	while not pending.is_empty():
		var node_id: StringName = pending.pop_back()
		if visited.has(node_id):
			continue
		visited[node_id] = true
		var node := world.get_record(node_id) as FoundationRoadNode
		if node == null:
			continue
		for edge_id in node.incident_edge_ids:
			var edge := world.get_record(edge_id) as FoundationRoadEdge
			if edge == null:
				continue
			var other_id := edge.other_node(node_id)
			if target_ids.has(other_id) and not visited.has(other_id):
				pending.append(other_id)
	for target_id: StringName in target_ids:
		if not visited.has(target_id):
			return false
	return true


static func _connection_intent_for_anchor(anchor: FoundationCityAnchor) -> StringName:
	if bool(anchor.metadata.get("mandatory_road_connection", false)) or (
		"mandatory" in anchor.tags or "required" in anchor.tags
	):
		return FoundationRoadNode.INTENT_MANDATORY
	if anchor.anchor_category in [
		FoundationCityAnchor.CATEGORY_CITY_CENTER,
		FoundationCityAnchor.CATEGORY_CIVIC_CENTER,
		FoundationCityAnchor.CATEGORY_HIGHWAY_ENTRANCE,
		FoundationCityAnchor.CATEGORY_MAP_EXIT,
		FoundationCityAnchor.CATEGORY_EXTERNAL_DESTINATION,
	] or anchor.priority_weight >= 0.9:
		return FoundationRoadNode.INTENT_MANDATORY
	if anchor.priority_weight >= 0.5:
		return FoundationRoadNode.INTENT_PREFERRED
	return FoundationRoadNode.INTENT_OPTIONAL


static func _anchor_connection_weight(anchor: FoundationCityAnchor) -> float:
	var weight := anchor.priority_weight
	if _connection_intent_for_anchor(anchor) == FoundationRoadNode.INTENT_MANDATORY:
		weight += 0.5
	weight += minf(0.35, anchor.influence_radius / 256.0)
	if anchor.has_explicit_influence_bounds:
		weight += minf(0.35, sqrt(anchor.influence_bounds.get_area()) / 512.0)
	if "primary" in anchor.tags or "major" in anchor.tags:
		weight += 0.2
	if anchor.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
		weight += 0.1
	return maxf(0.1, weight)


static func _candidate_debug_data(candidate: Dictionary, accepted: bool) -> Dictionary:
	var points: PackedVector3Array = candidate["route_points"]
	return {
		"pair_key": String(candidate["pair_key"]),
		"from_node_id": String(candidate["from_node_id"]),
		"to_node_id": String(candidate["to_node_id"]),
		"from": _vector3_to_dict(points[0] if not points.is_empty() else Vector3.ZERO),
		"to": _vector3_to_dict(points[-1] if not points.is_empty() else Vector3.ZERO),
		"selection_cost": float(candidate["selection_cost"]),
		"terrain_cost": float(candidate["terrain_cost"]),
		"accepted": accepted,
	}


static func _generate_pattern_topology(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	profile: FoundationRoadGenerationProfile,
	result: FoundationRoadGenerationResult
) -> void:
	var anchor_nodes: Array[FoundationRoadNode] = []
	var edge_pairs: Dictionary = {}
	for existing_edge in world.get_road_edges():
		edge_pairs[_node_pair_key(existing_edge.from_node_id, existing_edge.to_node_id)] = existing_edge.stable_id
	for node in world.get_road_nodes():
		if not String(node.source_anchor_id).is_empty():
			anchor_nodes.append(node)
	for pattern in world.get_road_pattern_areas():
		var spec := _pattern_spec(world.metadata.seed, pattern, profile)
		var points: Array[Vector2] = spec["points"]
		var pattern_nodes: Array[FoundationRoadNode] = []
		for index in range(points.size()):
			var node_id := FoundationSpatialId.make(
				world.metadata.seed,
				profile.generator_version,
				world.metadata.content_pack_version,
				FoundationRoadNode.ENTITY_TYPE,
				pattern.stable_id,
				"%s|node:%d" % [pattern.pattern_family, index]
			)
			var node := world.get_record(node_id) as FoundationRoadNode
			if node == null:
				node = FoundationRoadNode.new(
					node_id,
					_terrain_position(terrain, terrain_origin_cell, Vector3(points[index].x, 0.0, points[index].y)),
					FoundationRoadNode.ROLE_BEND
				)
				node.source_pass = SOURCE_PASS
				node.source_version = profile.generator_version
				node.tags = PackedStringArray(["phase_2", "pattern_node", String(pattern.pattern_family)])
				node.metadata = {
					"pattern_area_id": String(pattern.stable_id),
					"pattern_family": String(pattern.pattern_family),
					"seed_stream": String(spec["seed_stream"]),
					"cul_de_sac": (
						pattern.pattern_family in [FoundationRoadPatternArea.SUBURBAN_LOOPS, FoundationRoadPatternArea.TRAILER_PARK_SPINE]
						and index == points.size() - 1
					),
				}
				world.register_record(node)
				result.generated_node_count += 1
				result.generated_pattern_node_count += 1
			pattern_nodes.append(node)
		var links: Array[Vector2i] = spec["links"]
		for link in links:
			_create_pattern_edge(
				world, terrain, terrain_origin_cell, profile, result,
				pattern_nodes[link.x], pattern_nodes[link.y],
				StringName(spec["road_class"]), pattern, edge_pairs
			)
		if not anchor_nodes.is_empty() and not pattern_nodes.is_empty():
			var connection_index := clampi(int(spec["connection_index"]), 0, pattern_nodes.size() - 1)
			var nearest_anchor := _nearest_node(pattern_nodes[connection_index], anchor_nodes)
			if nearest_anchor != null:
				_create_pattern_edge(
					world, terrain, terrain_origin_cell, profile, result,
					pattern_nodes[connection_index], nearest_anchor,
					FoundationRoadEdge.CLASS_COLLECTOR, pattern, edge_pairs, true
				)


static func _pattern_spec(
	world_seed: int,
	pattern: FoundationRoadPatternArea,
	profile: FoundationRoadGenerationProfile
) -> Dictionary:
	var center := pattern.world_bounds.get_center()
	var preferred_spacing := clampf(
		pattern.preferred_spacing,
		pattern.minimum_segment_length,
		pattern.maximum_segment_length
	)
	var spacing := maxf(
		profile.minimum_intersection_spacing,
		maxf(pattern.minimum_intersection_spacing, preferred_spacing)
	)
	var available_x := maxf(spacing, pattern.world_bounds.size.x * 0.38)
	var available_y := maxf(spacing, pattern.world_bounds.size.y * 0.38)
	available_x = minf(available_x, pattern.world_bounds.size.x * 0.46)
	available_y = minf(available_y, pattern.world_bounds.size.y * 0.46)
	available_x = minf(available_x, pattern.maximum_segment_length)
	available_y = minf(available_y, pattern.maximum_segment_length)
	var base_angle := deg_to_rad(pattern.preferred_orientation_degrees)
	var local_variation := _seed_fraction(world_seed, &"road_local_growth", pattern.stable_id)
	var loop_variation := _seed_fraction(world_seed, &"road_loops", pattern.stable_id)
	var angle := base_angle
	var points: Array[Vector2] = []
	var links: Array[Vector2i] = []
	var road_class := FoundationRoadEdge.CLASS_LOCAL
	var connection_index := 0
	var seed_stream: StringName = &"road_local_growth"

	match pattern.pattern_family:
		FoundationRoadPatternArea.SUBURBAN_LOOPS, FoundationRoadPatternArea.TRAILER_PARK_SPINE:
			seed_stream = &"road_loops"
			angle += (loop_variation - 0.5) * deg_to_rad(24.0) * maxf(0.25, pattern.curvature_allowance + 0.25)
			for index in range(6):
				var theta := angle + TAU * float(index) / 6.0
				points.append(_clamp_pattern_point(
					center + Vector2(cos(theta) * available_x, sin(theta) * available_y), pattern.world_bounds
				))
				links.append(Vector2i(index, (index + 1) % 6))
			points.append(center)
			links.append(Vector2i(0, 6))
			connection_index = 3
		FoundationRoadPatternArea.RURAL_TERRAIN_FOLLOWING, FoundationRoadPatternArea.CUSTOM_CORRIDOR:
			seed_stream = &"road_dead_ends"
			angle += (local_variation - 0.5) * deg_to_rad(36.0) * maxf(0.2, pattern.terrain_following_strength)
			var direction := Vector2(cos(angle), sin(angle))
			var lateral := Vector2(-direction.y, direction.x)
			var step := minf(spacing, minf(available_x, available_y))
			for index in range(4):
				var offset := (float(index) - 1.5) * step
				var wiggle := (local_variation - 0.5) * step * 0.7 * (1.0 if index % 2 == 0 else -1.0)
				points.append(_clamp_pattern_point(center + direction * offset + lateral * wiggle, pattern.world_bounds))
				if index > 0:
					links.append(Vector2i(index - 1, index))
			road_class = FoundationRoadEdge.CLASS_DIRT if pattern.pattern_family == FoundationRoadPatternArea.RURAL_TERRAIN_FOLLOWING else FoundationRoadEdge.CLASS_COLLECTOR
			connection_index = 1
		FoundationRoadPatternArea.INDUSTRIAL_RECTILINEAR:
			var direction := Vector2(cos(angle), sin(angle))
			var lateral := Vector2(-direction.y, direction.x)
			for signs in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				points.append(_clamp_pattern_point(center + direction * available_x * signs.x + lateral * available_y * signs.y, pattern.world_bounds))
			links = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0)]
			road_class = FoundationRoadEdge.CLASS_COLLECTOR
		FoundationRoadPatternArea.MIXED_USE_GRID:
			var direction := Vector2(cos(angle), sin(angle))
			var lateral := Vector2(-direction.y, direction.x)
			points = [
				center,
				_clamp_pattern_point(center + direction * available_x, pattern.world_bounds),
				_clamp_pattern_point(center - direction * available_x, pattern.world_bounds),
				_clamp_pattern_point(center + lateral * available_y, pattern.world_bounds),
				_clamp_pattern_point(center - lateral * available_y, pattern.world_bounds),
				_clamp_pattern_point(center + (direction + lateral).normalized() * minf(available_x, available_y), pattern.world_bounds),
			]
			links = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5)]
			road_class = FoundationRoadEdge.CLASS_COLLECTOR
		_:
			var direction := Vector2(cos(angle), sin(angle))
			var lateral := Vector2(-direction.y, direction.x)
			points = [
				center,
				_clamp_pattern_point(center + direction * available_x, pattern.world_bounds),
				_clamp_pattern_point(center - direction * available_x, pattern.world_bounds),
				_clamp_pattern_point(center + lateral * available_y, pattern.world_bounds),
				_clamp_pattern_point(center - lateral * available_y, pattern.world_bounds),
			]
			links = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4)]
	return {
		"points": points,
		"links": links,
		"road_class": road_class,
		"connection_index": connection_index,
		"seed_stream": seed_stream,
	}


static func _clamp_pattern_point(point: Vector2, bounds: Rect2) -> Vector2:
	var inset := minf(1.0, minf(bounds.size.x, bounds.size.y) * 0.05)
	return Vector2(
		clampf(point.x, bounds.position.x + inset, bounds.end.x - inset),
		clampf(point.y, bounds.position.y + inset, bounds.end.y - inset)
	)


static func _seed_fraction(world_seed: int, stream: StringName, semantic_id: StringName) -> float:
	var derived := FoundationSeed.derive(world_seed, StringName("%s:%s" % [stream, semantic_id]))
	return float(derived % 100000) / 99999.0


static func _nearest_node(
	from_node: FoundationRoadNode,
	candidates: Array[FoundationRoadNode]
) -> FoundationRoadNode:
	var best: FoundationRoadNode
	var best_distance := INF
	for candidate in candidates:
		var distance := from_node.world_position.distance_squared_to(candidate.world_position)
		if distance < best_distance - EPSILON or (
			is_equal_approx(distance, best_distance)
			and (best == null or String(candidate.stable_id) < String(best.stable_id))
		):
			best = candidate
			best_distance = distance
	return best


static func _create_pattern_edge(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	profile: FoundationRoadGenerationProfile,
	result: FoundationRoadGenerationResult,
	from_node: FoundationRoadNode,
	to_node: FoundationRoadNode,
	road_class: StringName,
	pattern: FoundationRoadPatternArea,
	edge_pairs: Dictionary,
	connection_edge := false
) -> void:
	if from_node == null or to_node == null or from_node.stable_id == to_node.stable_id:
		return
	var pair_key := _node_pair_key(from_node.stable_id, to_node.stable_id)
	if edge_pairs.has(pair_key):
		return
	if from_node.world_position.distance_to(to_node.world_position) + EPSILON < maxf(profile.minimum_edge_length, pattern.minimum_segment_length):
		return
	var route := _find_terrain_route(
		terrain, terrain_origin_cell, from_node.world_position, to_node.world_position, profile
	)
	var semantic_key := "%s|%s|%s|%s" % [
		pattern.stable_id,
		_node_pair_key(from_node.stable_id, to_node.stable_id),
		road_class,
		"connection" if connection_edge else "internal",
	]
	var edge_id := FoundationSpatialId.make(
		world.metadata.seed,
		profile.generator_version,
		world.metadata.content_pack_version,
		FoundationRoadEdge.ENTITY_TYPE,
		pattern.stable_id,
		semantic_key
	)
	if world.get_record(edge_id) != null:
		edge_id = _repair_record_id(world, profile, FoundationRoadEdge.ENTITY_TYPE, pattern.stable_id, semantic_key)
	var edge := FoundationRoadEdge.new(
		edge_id, from_node.stable_id, to_node.stable_id,
		route["route_points"] as PackedVector3Array, road_class
	)
	edge.terrain_cost = float(route["terrain_cost"])
	edge.used_fallback_route = bool(route["used_fallback"])
	edge.generation_source = &"pattern_connection" if connection_edge else &"pattern_growth"
	edge.generation_priority = 0.45 if connection_edge else 0.25
	edge.source_pass = SOURCE_PASS
	edge.source_version = profile.generator_version
	edge.tags = PackedStringArray(["phase_2", "pattern_topology", String(pattern.pattern_family)])
	edge.metadata = {
		"pattern_area_id": String(pattern.stable_id),
		"pattern_family": String(pattern.pattern_family),
		"terrain_revision": terrain.revision,
		"expanded_cells": int(route["expanded_cells"]),
	}
	_configure_edge_contract(edge)
	_calculate_grading_requirements(edge, terrain, terrain_origin_cell, profile)
	world.register_record(edge)
	edge_pairs[pair_key] = edge.stable_id
	result.generated_edge_count += 1
	result.generated_pattern_edge_count += 1
	result.expanded_cell_count += int(route["expanded_cells"])
	result.total_terrain_cost += float(route["terrain_cost"])


static func _repair_record_id(
	world: FoundationWorldData,
	profile: FoundationRoadGenerationProfile,
	entity_type: StringName,
	parent_id: StringName,
	semantic_key: String
) -> StringName:
	var ordinal := 1
	while true:
		var stable_id := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			entity_type, parent_id, "%s|repair:%d" % [semantic_key, ordinal]
		)
		if world.get_record(stable_id) == null:
			return stable_id
		ordinal += 1
	return &""


static func _configure_edge_contract(edge: FoundationRoadEdge) -> void:
	match edge.road_class:
		FoundationRoadEdge.CLASS_HIGHWAY:
			edge.physical_profile_key = &"highway_concept"
			edge.directionality = FoundationRoadEdge.DIRECTION_DIVIDED_CONCEPT
			edge.access_control_policy = FoundationRoadEdge.ACCESS_CONTROLLED
			edge.allowed_movement_modes = PackedStringArray(["motor_vehicle", "transit"])
			edge.ownership_jurisdiction = &"regional"
			edge.abstract_capacity = 5.0
			edge.continuity_priority = 10.0
		FoundationRoadEdge.CLASS_ARTERIAL:
			edge.physical_profile_key = &"arterial_two_way"
			edge.access_control_policy = FoundationRoadEdge.ACCESS_LIMITED
			edge.abstract_capacity = 4.0
			edge.continuity_priority = 8.0
		FoundationRoadEdge.CLASS_COLLECTOR:
			edge.physical_profile_key = &"collector_two_way"
			edge.access_control_policy = FoundationRoadEdge.ACCESS_FRONTAGE
			edge.abstract_capacity = 3.0
			edge.continuity_priority = 6.0
		FoundationRoadEdge.CLASS_ALLEY:
			edge.physical_profile_key = &"service_single_carriageway"
			edge.access_control_policy = FoundationRoadEdge.ACCESS_SERVICE
			edge.abstract_capacity = 0.5
			edge.continuity_priority = 1.0
		FoundationRoadEdge.CLASS_DIRT:
			edge.physical_profile_key = &"terrain_following_dirt"
			edge.access_control_policy = FoundationRoadEdge.ACCESS_FRONTAGE
			edge.abstract_capacity = 0.75
			edge.continuity_priority = 2.0
			edge.surface_style_key = &"dirt"
			edge.maintenance_level_key = &"seasonal"
		_:
			edge.physical_profile_key = &"local_two_way"
			edge.access_control_policy = FoundationRoadEdge.ACCESS_FRONTAGE
			edge.abstract_capacity = 1.5
			edge.continuity_priority = 3.0


static func _calculate_grading_requirements(
	edge: FoundationRoadEdge,
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	profile: FoundationRoadGenerationProfile
) -> void:
	edge.desired_elevation_samples.clear()
	var max_cut := 0.0
	var max_fill := 0.0
	var max_violation := 0.0
	var retaining := false
	var bridge := false
	var water := false
	var total_length := edge.planar_length
	var traveled := 0.0
	var maximum_grade := profile.maximum_grade_for(edge.road_class)
	for index in range(edge.route_points.size()):
		if index > 0:
			var delta := edge.route_points[index] - edge.route_points[index - 1]
			traveled += Vector2(delta.x, delta.z).length()
		var ratio := traveled / total_length if total_length > EPSILON else 0.0
		var desired := lerpf(edge.route_points[0].y, edge.route_points[-1].y, ratio)
		var sample := FoundationRoadElevationSample.new(
			edge.route_points[index], edge.route_points[index].y, desired
		)
		var global_cell := Vector2i(
			floori(edge.route_points[index].x / terrain.cell_size),
			floori(edge.route_points[index].z / terrain.cell_size)
		)
		var local_cell := global_cell - terrain_origin_cell
		if terrain.is_valid_cell(local_cell):
			var flags := terrain.get_cell_flags(local_cell)
			sample.water_crossing = (flags & FoundationTerrainData.CellFlag.WATER) != 0
		water = water or sample.water_crossing
		sample.retaining_wall_candidate = maxf(sample.cut_depth, sample.fill_height) >= profile.retaining_wall_threshold
		sample.bridge_candidate = sample.water_crossing or sample.fill_height >= profile.bridge_fill_threshold
		retaining = retaining or sample.retaining_wall_candidate
		bridge = bridge or sample.bridge_candidate
		max_cut = maxf(max_cut, sample.cut_depth)
		max_fill = maxf(max_fill, sample.fill_height)
		edge.desired_elevation_samples.append(sample)
	for index in range(edge.desired_elevation_samples.size() - 1):
		var from_sample := edge.desired_elevation_samples[index]
		var to_sample := edge.desired_elevation_samples[index + 1]
		var horizontal := Vector2(
			to_sample.world_position.x - from_sample.world_position.x,
			to_sample.world_position.z - from_sample.world_position.z
		).length()
		if horizontal <= EPSILON:
			continue
		var grade := absf(to_sample.desired_elevation - from_sample.desired_elevation) / horizontal * 100.0
		var violation := maxf(0.0, grade - maximum_grade)
		to_sample.grade_violation = violation
		max_violation = maxf(max_violation, violation)
	edge.grading_requirements = {
		"maximum_cut_depth": max_cut,
		"maximum_fill_height": max_fill,
		"maximum_grade_percent": maximum_grade,
		"maximum_grade_violation": max_violation,
		"retaining_wall_candidate": retaining,
		"bridge_candidate": bridge,
		"water_crossing": water,
		"infeasible_segment": edge.used_fallback_route or max_violation > EPSILON,
	}


static func _rebuild_node_roles(world: FoundationWorldData) -> void:
	for node in world.get_road_nodes():
		if node.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
			continue
		if not String(node.source_anchor_id).is_empty():
			var anchor := world.get_record(node.source_anchor_id) as FoundationCityAnchor
			if anchor != null and anchor.anchor_category == FoundationCityAnchor.CATEGORY_MAP_EXIT:
				node.node_kind = FoundationRoadNode.ROLE_MAP_EXIT
			elif anchor != null and anchor.anchor_category == FoundationCityAnchor.CATEGORY_BRIDGE_CANDIDATE:
				node.node_kind = FoundationRoadNode.ROLE_BRIDGE_CANDIDATE
			else:
				node.node_kind = FoundationRoadNode.ROLE_ANCHOR_CONNECTION
		elif node.incident_edge_ids.size() >= 3:
			node.node_kind = FoundationRoadNode.ROLE_INTERSECTION
		elif node.incident_edge_ids.size() <= 1:
			node.node_kind = FoundationRoadNode.ROLE_DEAD_END
		else:
			node.node_kind = FoundationRoadNode.ROLE_BEND


static func _assign_logical_roads(
	world: FoundationWorldData,
	profile: FoundationRoadGenerationProfile,
	result: FoundationRoadGenerationResult
) -> void:
	var assigned: Dictionary = {}
	for logical in world.get_logical_roads():
		for edge_id in logical.edge_ids:
			if world.get_record(edge_id) is FoundationRoadEdge:
				assigned[edge_id] = logical.stable_id
	for authored_edge in world.get_road_edges():
		if (
			authored_edge.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED
			or String(authored_edge.logical_road_id).is_empty()
		):
			continue
		assigned[authored_edge.stable_id] = authored_edge.logical_road_id
		if world.get_record(authored_edge.logical_road_id) == null:
			var authored_logical := FoundationLogicalRoad.new(
				authored_edge.logical_road_id,
				[authored_edge.stable_id],
				authored_edge.road_class,
				authored_edge.world_bounds
			)
			authored_logical.continuity_priority = authored_edge.continuity_priority
			authored_logical.provisional_naming_key = StringName("road_%s" % authored_edge.logical_road_id)
			authored_logical.source_pass = SOURCE_PASS
			authored_logical.source_version = profile.generator_version
			world.register_record(authored_logical)
	var edges := world.get_road_edges()
	edges.sort_custom(_continuity_edge_less)
	for seed_edge in edges:
		if assigned.has(seed_edge.stable_id):
			seed_edge.logical_road_id = StringName(assigned[seed_edge.stable_id])
			continue
		var ordered: Array[FoundationRoadEdge] = [seed_edge]
		assigned[seed_edge.stable_id] = true
		_expand_logical_chain(world, ordered, assigned, true)
		_expand_logical_chain(world, ordered, assigned, false)
		var edge_ids: Array[StringName] = []
		var bounds := ordered[0].world_bounds
		var canonical_edge_id := ordered[0].stable_id
		for edge in ordered:
			edge_ids.append(edge.stable_id)
			bounds = bounds.merge(edge.world_bounds)
			if String(edge.stable_id) < String(canonical_edge_id):
				canonical_edge_id = edge.stable_id
		var logical_id := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			FoundationLogicalRoad.ENTITY_TYPE, &"", "continuity|%s" % canonical_edge_id
		)
		if world.get_record(logical_id) != null:
			logical_id = _repair_record_id(world, profile, FoundationLogicalRoad.ENTITY_TYPE, &"", "continuity|%s" % canonical_edge_id)
		var logical := FoundationLogicalRoad.new(logical_id, edge_ids, seed_edge.road_class, bounds)
		logical.continuity_priority = seed_edge.continuity_priority
		logical.provisional_naming_key = StringName("road_%s" % String(logical_id).trim_prefix("logical_road_"))
		logical.start_semantic_role = _logical_chain_endpoint_role(world, ordered, true)
		logical.end_semantic_role = _logical_chain_endpoint_role(world, ordered, false)
		logical.source_pass = SOURCE_PASS
		logical.source_version = profile.generator_version
		logical.tags = PackedStringArray(["phase_2", "logical_identity"])
		world.register_record(logical)
		for edge in ordered:
			edge.logical_road_id = logical_id
			assigned[edge.stable_id] = logical_id
		result.generated_logical_road_count += 1


static func _expand_logical_chain(
	world: FoundationWorldData,
	ordered: Array[FoundationRoadEdge],
	assigned: Dictionary,
	prepend: bool
) -> void:
	var current := ordered[0] if prepend else ordered[-1]
	var node_id := current.from_node_id if prepend else current.to_node_id
	var previous_other := current.to_node_id if prepend else current.from_node_id
	while true:
		var next := _best_continuation(world, current, node_id, previous_other, assigned)
		if next == null:
			return
		var next_outer_node := next.other_node(node_id)
		assigned[next.stable_id] = true
		if prepend:
			ordered.push_front(next)
		else:
			ordered.append(next)
		previous_other = node_id
		node_id = next_outer_node
		current = next


static func _best_continuation(
	world: FoundationWorldData,
	current: FoundationRoadEdge,
	node_id: StringName,
	previous_other_id: StringName,
	assigned: Dictionary
) -> FoundationRoadEdge:
	var node := world.get_record(node_id) as FoundationRoadNode
	var previous_other := world.get_record(previous_other_id) as FoundationRoadNode
	if node == null or previous_other == null:
		return null
	var incoming := Vector2(
		node.world_position.x - previous_other.world_position.x,
		node.world_position.z - previous_other.world_position.z
	).normalized()
	var best: FoundationRoadEdge
	var best_score := -INF
	for edge_id in node.incident_edge_ids:
		var candidate := world.get_record(edge_id) as FoundationRoadEdge
		if candidate == null or candidate == current or assigned.has(candidate.stable_id):
			continue
		if candidate.road_class != current.road_class or candidate.physical_profile_key != current.physical_profile_key:
			continue
		var other := world.get_record(candidate.other_node(node_id)) as FoundationRoadNode
		if other == null:
			continue
		var outgoing := Vector2(
			other.world_position.x - node.world_position.x,
			other.world_position.z - node.world_position.z
		).normalized()
		var score := incoming.dot(outgoing) * 100.0 + candidate.continuity_priority + candidate.generation_priority
		if score > best_score + EPSILON or (
			is_equal_approx(score, best_score)
			and (best == null or String(candidate.stable_id) < String(best.stable_id))
		):
			best = candidate
			best_score = score
	return best


static func _continuity_edge_less(a: FoundationRoadEdge, b: FoundationRoadEdge) -> bool:
	var a_rank := _road_class_rank(a.road_class)
	var b_rank := _road_class_rank(b.road_class)
	if a_rank != b_rank:
		return a_rank > b_rank
	if not is_equal_approx(a.generation_priority, b.generation_priority):
		return a.generation_priority > b.generation_priority
	return String(a.stable_id) < String(b.stable_id)


static func _road_class_rank(road_class: StringName) -> int:
	match road_class:
		FoundationRoadEdge.CLASS_HIGHWAY: return 6
		FoundationRoadEdge.CLASS_ARTERIAL: return 5
		FoundationRoadEdge.CLASS_COLLECTOR: return 4
		FoundationRoadEdge.CLASS_LOCAL: return 3
		FoundationRoadEdge.CLASS_ALLEY: return 2
		FoundationRoadEdge.CLASS_DIRT: return 1
		_: return 0


static func _logical_chain_endpoint_role(
	world: FoundationWorldData,
	ordered: Array[FoundationRoadEdge],
	start: bool
) -> StringName:
	var edge := ordered[0] if start else ordered[-1]
	var node_id := edge.from_node_id if start else edge.to_node_id
	if ordered.size() > 1:
		var neighbor := ordered[1] if start else ordered[-2]
		if edge.from_node_id in [neighbor.from_node_id, neighbor.to_node_id]:
			node_id = edge.to_node_id
		elif edge.to_node_id in [neighbor.from_node_id, neighbor.to_node_id]:
			node_id = edge.from_node_id
	var node := world.get_record(node_id) as FoundationRoadNode
	return node.node_kind if node != null else &"unknown"


static func _build_intersection_records(
	world: FoundationWorldData,
	profile: FoundationRoadGenerationProfile,
	result: FoundationRoadGenerationResult
) -> void:
	for node in world.get_road_nodes():
		if node.incident_edge_ids.size() < 3:
			continue
		var stable_id := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			FoundationIntersectionRecord.ENTITY_TYPE, node.stable_id, "abstract_intersection"
		)
		var existing := world.get_record(stable_id) as FoundationIntersectionRecord
		if existing != null:
			continue
		if world.get_record(stable_id) != null:
			stable_id = _repair_record_id(world, profile, FoundationIntersectionRecord.ENTITY_TYPE, node.stable_id, "abstract_intersection")
		var intersection := FoundationIntersectionRecord.new(stable_id, node.stable_id, node.world_position)
		intersection.connected_edge_ids = node.incident_edge_ids.duplicate()
		intersection.intersection_degree = intersection.connected_edge_ids.size()
		intersection.provisional_intersection_type = (
			&"t_junction" if intersection.intersection_degree == 3
			else &"crossroads" if intersection.intersection_degree == 4
			else &"complex_junction"
		)
		var classes: Array[StringName] = []
		for edge_id in intersection.connected_edge_ids:
			var edge := world.get_record(edge_id) as FoundationRoadEdge
			if edge == null:
				continue
			if edge.directionality == FoundationRoadEdge.DIRECTION_TWO_WAY or edge.directionality == FoundationRoadEdge.DIRECTION_DIVIDED_CONCEPT:
				intersection.incoming_edge_ids.append(edge_id)
				intersection.outgoing_edge_ids.append(edge_id)
			elif (
				edge.directionality == FoundationRoadEdge.DIRECTION_ONE_WAY_FORWARD
				and edge.to_node_id == node.stable_id
			) or (
				edge.directionality == FoundationRoadEdge.DIRECTION_ONE_WAY_REVERSE
				and edge.from_node_id == node.stable_id
			):
				intersection.incoming_edge_ids.append(edge_id)
			else:
				intersection.outgoing_edge_ids.append(edge_id)
			classes.append(edge.road_class)
		intersection.incoming_edge_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		intersection.outgoing_edge_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		classes.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		for first_index in range(classes.size() - 1):
			for second_index in range(first_index + 1, classes.size()):
				intersection.road_class_relationships.append({
					"from_class": String(classes[first_index]),
					"to_class": String(classes[second_index]),
				})
		intersection.source_pass = SOURCE_PASS
		intersection.source_version = profile.generator_version
		intersection.tags = PackedStringArray(["phase_2", "abstract_intersection"])
		world.register_record(intersection)
		result.generated_intersection_count += 1


static func _vector3_to_dict(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


static func _build_routing_cost_debug_cells(
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	profile: FoundationRoadGenerationProfile
) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	var stride := maxi(1, ceili(float(maxi(terrain.grid_cells.x, terrain.grid_cells.y)) / 32.0))
	var sampler := FoundationTerrainSampler.new(terrain)
	for cell_y in range(0, terrain.grid_cells.y, stride):
		for cell_x in range(0, terrain.grid_cells.x, stride):
			var cell := Vector2i(cell_x, cell_y)
			var flags := terrain.get_cell_flags(cell)
			var cost := 1.0 + sampler.get_slope_degrees_at_grid(cell) * profile.slope_cost_weight * 0.05
			if (flags & FoundationTerrainData.CellFlag.NO_BUILD) != 0:
				cost += profile.no_build_penalty
			if (flags & FoundationTerrainData.CellFlag.PROTECTED) != 0:
				cost += profile.protected_penalty
			if (flags & FoundationTerrainData.CellFlag.WATER) != 0:
				cost += profile.water_penalty
			cost += profile.surface_penalty(terrain.get_cell_surface(cell))
			var global_cell := terrain_origin_cell + cell
			cells.append({
				"cell": {"x": global_cell.x, "y": global_cell.y},
				"stride": stride,
				"cell_size": terrain.cell_size,
				"cost": cost,
			})
	return cells
