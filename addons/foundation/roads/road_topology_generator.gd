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

	world.register_layer_type(FoundationWorldData.ROAD_NODE_LAYER)
	world.register_layer_type(FoundationWorldData.ROAD_EDGE_LAYER)
	var preserved := _remove_replaceable_records(world)
	result.preserved_node_count = int(preserved["nodes"])
	result.preserved_edge_count = int(preserved["edges"])
	_set_layer_generation_metadata(world, terrain, terrain_origin_cell, active_profile)

	var anchors := world.get_anchors()
	var node_by_anchor: Dictionary = {}
	for anchor in anchors:
		var node_id := _node_id(world.metadata, active_profile, anchor)
		var node := world.get_record(node_id) as FoundationRoadNode
		if node == null:
			node = FoundationRoadNode.new(
				node_id,
				_terrain_position(terrain, terrain_origin_cell, anchor.world_position),
				FoundationRoadNode.KIND_ANCHOR,
				anchor.stable_id
			)
			node.source_pass = SOURCE_PASS
			node.source_version = active_profile.generator_version
			node.tags = PackedStringArray(["phase_2", "anchor_node"])
			node.metadata = {
				"anchor_category": String(anchor.anchor_category),
				"anchor_priority": anchor.priority_weight,
			}
			world.register_record(node)
			result.generated_node_count += 1
		node_by_anchor[anchor.stable_id] = node

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
			edge.source_pass = SOURCE_PASS
			edge.source_version = active_profile.generator_version
			edge.tags = PackedStringArray(["phase_2", "terrain_aware", "abstract_topology"])
			edge.metadata = {
				"from_anchor_id": String(from_anchor.stable_id),
				"to_anchor_id": String(to_anchor.stable_id),
				"expanded_cells": int(candidate["expanded_cells"]),
				"terrain_revision": terrain.revision,
			}
			world.register_record(edge)
			result.generated_edge_count += 1

	_rebuild_incident_edges(world)
	if not _anchor_nodes_connected(world, anchors, node_by_anchor):
		return result.fail("Road generation could not connect every city-anchor node.")
	result.success = true
	return result


static func _remove_replaceable_records(world: FoundationWorldData) -> Dictionary:
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
	return {"nodes": preserved_nodes, "edges": preserved_edges}


static func _set_layer_generation_metadata(
	world: FoundationWorldData,
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	profile: FoundationRoadGenerationProfile
) -> void:
	var metadata := {
		"format_version": 1,
		"source_pass": String(SOURCE_PASS),
		"generator_version": profile.generator_version,
		"terrain_revision": terrain.revision,
		"terrain_origin_cell": {"x": terrain_origin_cell.x, "y": terrain_origin_cell.y},
		"profile": profile.to_dict(),
	}
	world.get_layer(FoundationWorldData.ROAD_NODE_LAYER).metadata = metadata.duplicate(true)
	world.get_layer(FoundationWorldData.ROAD_EDGE_LAYER).metadata = metadata.duplicate(true)


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
			var importance := maxf(0.25, (from_anchor.priority_weight + to_anchor.priority_weight) * 0.5)
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
	var major_categories: Array[StringName] = [
		FoundationCityAnchor.CATEGORY_CITY_CENTER,
		FoundationCityAnchor.CATEGORY_CIVIC_CENTER,
		FoundationCityAnchor.CATEGORY_HIGHWAY_ENTRANCE,
		FoundationCityAnchor.CATEGORY_MAP_EXIT,
		FoundationCityAnchor.CATEGORY_EXTERNAL_DESTINATION,
	]
	if from_anchor.anchor_category in major_categories or to_anchor.anchor_category in major_categories:
		return FoundationRoadEdge.CLASS_ARTERIAL_CONNECTOR
	return FoundationRoadEdge.CLASS_CONNECTOR


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
