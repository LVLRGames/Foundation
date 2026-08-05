class_name FoundationRoadTopologyValidator
extends RefCounted

## Read-only deterministic validation for abstract Phase 2 road topology.

const EPSILON := 0.000001


static func validate(
	world: FoundationWorldData,
	profile: FoundationRoadGenerationProfile = null
) -> Array[FoundationRoadValidationIssue]:
	var issues: Array[FoundationRoadValidationIssue] = []
	if world == null:
		issues.append(FoundationRoadValidationIssue.new(
			&"missing_world", FoundationRoadValidationIssue.ERROR, "Road validation requires world data."
		))
		return issues
	var active_profile := profile if profile != null else FoundationRoadGenerationProfile.new()
	var nodes := world.get_road_nodes()
	var edges := world.get_road_edges()
	var node_ids: Dictionary = {}
	for node in nodes:
		node_ids[node.stable_id] = true
		if node.incident_edge_ids.is_empty():
			issues.append(_node_issue(&"isolated_node", FoundationRoadValidationIssue.ERROR,
				"Road node has no connected edge.", node))
		if not _ids_are_sorted_unique(node.incident_edge_ids):
			issues.append(_node_issue(&"nondeterministic_adjacency_order", FoundationRoadValidationIssue.ERROR,
				"Road-node adjacency is not sorted and unique.", node))

	var pair_ids: Dictionary = {}
	for edge in edges:
		if edge.from_node_id == edge.to_node_id:
			issues.append(_edge_issue(&"self_edge", FoundationRoadValidationIssue.ERROR,
				"Road edge connects a node to itself.", edge))
		var pair_key := _pair_key(edge.from_node_id, edge.to_node_id)
		if pair_ids.has(pair_key):
			issues.append(_edge_issue(&"duplicate_edge", FoundationRoadValidationIssue.ERROR,
				"Multiple road edges connect the same node pair.", edge,
				[StringName(pair_ids[pair_key])]))
		else:
			pair_ids[pair_key] = edge.stable_id
		if not node_ids.has(edge.from_node_id) or not node_ids.has(edge.to_node_id):
			issues.append(_edge_issue(&"missing_endpoint", FoundationRoadValidationIssue.ERROR,
				"Road edge references a missing endpoint node.", edge))
		if edge.planar_length + EPSILON < active_profile.minimum_edge_length:
			issues.append(_edge_issue(&"edge_below_minimum_length", FoundationRoadValidationIssue.WARNING,
				"Road edge is shorter than the class-independent minimum length.", edge))
		if float(edge.grading_requirements.get("maximum_grade_violation", 0.0)) > EPSILON:
			issues.append(_edge_issue(&"grade_violation", FoundationRoadValidationIssue.WARNING,
				"Road edge contains unresolved desired-grade violations.", edge))
		if (
			bool(edge.grading_requirements.get("water_crossing", false))
			and not bool(edge.grading_requirements.get("bridge_candidate", false))
		):
			issues.append(_edge_issue(&"water_crossing_without_bridge_candidate", FoundationRoadValidationIssue.ERROR,
				"Water-crossing road lacks bridge-candidate planning metadata.", edge))
		if String(edge.logical_road_id).is_empty():
			issues.append(_edge_issue(&"missing_logical_road", FoundationRoadValidationIssue.ERROR,
				"Road edge has no logical-road identity.", edge))
		else:
			var logical := world.get_record(edge.logical_road_id) as FoundationLogicalRoad
			if logical == null or edge.stable_id not in logical.edge_ids:
				issues.append(_edge_issue(&"logical_road_continuity_anomaly", FoundationRoadValidationIssue.ERROR,
					"Road edge and logical-road record disagree.", edge, [edge.logical_road_id]))

	_append_connectivity_issues(world, nodes, edges, issues)
	_append_hierarchy_issues(world, nodes, issues)
	_append_intersection_spacing_issues(world, active_profile, issues)
	_append_crossing_issues(world, edges, issues)
	issues.sort_custom(FoundationRoadValidationIssue.less)
	return issues


static func _append_connectivity_issues(
	world: FoundationWorldData,
	nodes: Array[FoundationRoadNode],
	edges: Array[FoundationRoadEdge],
	issues: Array[FoundationRoadValidationIssue]
) -> void:
	if nodes.is_empty():
		return
	var adjacency: Dictionary = {}
	for node in nodes:
		adjacency[node.stable_id] = []
	for edge in edges:
		if not adjacency.has(edge.from_node_id) or not adjacency.has(edge.to_node_id):
			continue
		(adjacency[edge.from_node_id] as Array).append(edge.to_node_id)
		(adjacency[edge.to_node_id] as Array).append(edge.from_node_id)
	var components: Array[Array] = []
	var visited: Dictionary = {}
	for node in nodes:
		if visited.has(node.stable_id):
			continue
		var component: Array[StringName] = []
		var pending: Array[StringName] = [node.stable_id]
		while not pending.is_empty():
			var current := pending.pop_back()
			if visited.has(current):
				continue
			visited[current] = true
			component.append(current)
			var neighbors: Array = adjacency.get(current, [])
			neighbors.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
			for neighbor: StringName in neighbors:
				if not visited.has(neighbor):
					pending.append(neighbor)
		component.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		components.append(component)
	if components.size() > 1:
		for component in components:
			var first_node := world.get_record(component[0]) as FoundationRoadNode
			issues.append(FoundationRoadValidationIssue.new(
				&"disconnected_component", FoundationRoadValidationIssue.ERROR,
				"Road graph contains a disconnected component of %d node(s)." % component.size(),
				component, first_node.world_position
			))
	var anchor_node_count := 0
	for node in nodes:
		anchor_node_count += 0 if String(node.source_anchor_id).is_empty() else 1
	for node in nodes:
		if node.anchor_connection_intent != FoundationRoadNode.INTENT_MANDATORY:
			continue
		if anchor_node_count <= 1:
			continue
		var anchor_reachable := false
		for component in components:
			if node.stable_id in component:
				for component_node_id: StringName in component:
					if component_node_id == node.stable_id:
						continue
					var component_node := world.get_record(component_node_id) as FoundationRoadNode
					anchor_reachable = anchor_reachable or (
						component_node != null
						and not String(component_node.source_anchor_id).is_empty()
					)
		if not anchor_reachable:
			issues.append(_node_issue(&"unreachable_mandatory_anchor", FoundationRoadValidationIssue.ERROR,
				"Mandatory city anchor is not reachable from another anchor.", node))


static func _append_hierarchy_issues(
	world: FoundationWorldData,
	nodes: Array[FoundationRoadNode],
	issues: Array[FoundationRoadValidationIssue]
) -> void:
	for node in nodes:
		var has_highway := false
		var local_edges: Array[StringName] = []
		for edge_id in node.incident_edge_ids:
			var edge := world.get_record(edge_id) as FoundationRoadEdge
			if edge == null:
				continue
			has_highway = has_highway or edge.road_class == FoundationRoadEdge.CLASS_HIGHWAY
			if edge.road_class in [FoundationRoadEdge.CLASS_LOCAL, FoundationRoadEdge.CLASS_ALLEY]:
				local_edges.append(edge.stable_id)
		if has_highway and not local_edges.is_empty():
			var ids: Array[StringName] = [node.stable_id]
			ids.append_array(local_edges)
			issues.append(FoundationRoadValidationIssue.new(
				&"class_incompatible_connection", FoundationRoadValidationIssue.ERROR,
				"Highways prohibit direct local or alley access.", ids, node.world_position
			))


static func _append_intersection_spacing_issues(
	world: FoundationWorldData,
	profile: FoundationRoadGenerationProfile,
	issues: Array[FoundationRoadValidationIssue]
) -> void:
	var intersections := world.get_road_intersections()
	var bucket_size := maxf(
		profile.intersection_spacing_highway,
		maxf(profile.intersection_spacing_arterial, maxf(profile.intersection_spacing_collector, profile.intersection_spacing_dirt))
	)
	var nodes: Array[FoundationRoadNode] = []
	var buckets: Dictionary = {}
	for index in range(intersections.size()):
		var node := world.get_record(intersections[index].node_id) as FoundationRoadNode
		nodes.append(node)
		if node == null:
			continue
		var bucket := Vector2i(
			floori(node.world_position.x / bucket_size),
			floori(node.world_position.z / bucket_size)
		)
		if not buckets.has(bucket):
			buckets[bucket] = []
		(buckets[bucket] as Array).append(index)
	var bucket_keys: Array[Vector2i] = []
	for bucket: Vector2i in buckets:
		bucket_keys.append(bucket)
	bucket_keys.sort_custom(FoundationSpatialRecord._sort_vector2i)
	var pair_indices: Dictionary = {}
	for bucket in bucket_keys:
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				var neighbor := bucket + Vector2i(offset_x, offset_y)
				if not buckets.has(neighbor):
					continue
				for first_index: int in buckets[bucket]:
					for second_index: int in buckets[neighbor]:
						if first_index >= second_index:
							continue
						pair_indices["%d:%d" % [first_index, second_index]] = Vector2i(first_index, second_index)
	var pair_keys: Array[String] = []
	for key: String in pair_indices:
		pair_keys.append(key)
	pair_keys.sort()
	for key in pair_keys:
		var pair: Vector2i = pair_indices[key]
		var first_node := nodes[pair.x]
		var second_node := nodes[pair.y]
		if first_node == null or second_node == null:
			continue
		var required_spacing := maxf(
			_intersection_spacing_for(world, intersections[pair.x], profile),
			_intersection_spacing_for(world, intersections[pair.y], profile)
		)
		if first_node.world_position.distance_to(second_node.world_position) + EPSILON < required_spacing:
			issues.append(FoundationRoadValidationIssue.new(
				&"excessive_intersection_proximity", FoundationRoadValidationIssue.WARNING,
				"Abstract intersections violate hierarchy-sensitive minimum spacing.",
				[intersections[pair.x].stable_id, intersections[pair.y].stable_id],
				(first_node.world_position + second_node.world_position) * 0.5
			))


static func _intersection_spacing_for(
	world: FoundationWorldData,
	intersection: FoundationIntersectionRecord,
	profile: FoundationRoadGenerationProfile
) -> float:
	var spacing := profile.minimum_intersection_spacing
	for edge_id in intersection.connected_edge_ids:
		var edge := world.get_record(edge_id) as FoundationRoadEdge
		if edge != null:
			spacing = maxf(spacing, profile.minimum_intersection_spacing_for(edge.road_class))
	return spacing


static func _append_crossing_issues(
	world: FoundationWorldData,
	edges: Array[FoundationRoadEdge],
	issues: Array[FoundationRoadValidationIssue]
) -> void:
	var edge_by_id: Dictionary = {}
	for edge in edges:
		edge_by_id[edge.stable_id] = edge
	var pairs: Dictionary = {}
	for chunk in world.get_sorted_chunks():
		var ids := chunk.get_record_ids(FoundationWorldData.ROAD_EDGE_LAYER)
		for first_index in range(ids.size() - 1):
			for second_index in range(first_index + 1, ids.size()):
				var key := _pair_key(ids[first_index], ids[second_index])
				pairs[key] = [ids[first_index], ids[second_index]]
	var keys: Array[String] = []
	for key: String in pairs:
		keys.append(key)
	keys.sort()
	for key in keys:
		var pair: Array = pairs[key]
		var first := edge_by_id.get(pair[0]) as FoundationRoadEdge
		var second := edge_by_id.get(pair[1]) as FoundationRoadEdge
		if first == null or second == null:
			continue
		if first.from_node_id in [second.from_node_id, second.to_node_id] or first.to_node_id in [second.from_node_id, second.to_node_id]:
			continue
		var crossing := _first_crossing(first.route_points, second.route_points)
		if crossing != Vector3.INF:
			issues.append(FoundationRoadValidationIssue.new(
				&"crossing_without_intersection", FoundationRoadValidationIssue.WARNING,
				"Road centerlines cross without a shared abstract intersection node.",
				[first.stable_id, second.stable_id], crossing
			))


static func _first_crossing(first: PackedVector3Array, second: PackedVector3Array) -> Vector3:
	for first_index in range(first.size() - 1):
		var a := Vector2(first[first_index].x, first[first_index].z)
		var b := Vector2(first[first_index + 1].x, first[first_index + 1].z)
		for second_index in range(second.size() - 1):
			var c := Vector2(second[second_index].x, second[second_index].z)
			var d := Vector2(second[second_index + 1].x, second[second_index + 1].z)
			var intersection := Geometry2D.segment_intersects_segment(a, b, c, d)
			if intersection is Vector2:
				var point := intersection as Vector2
				return Vector3(point.x, 0.0, point.y)
	return Vector3.INF


static func _ids_are_sorted_unique(ids: Array[StringName]) -> bool:
	for index in range(1, ids.size()):
		if String(ids[index - 1]) >= String(ids[index]):
			return false
	return true


static func _node_issue(
	code: StringName,
	severity: StringName,
	message: String,
	node: FoundationRoadNode
) -> FoundationRoadValidationIssue:
	return FoundationRoadValidationIssue.new(code, severity, message, [node.stable_id], node.world_position)


static func _edge_issue(
	code: StringName,
	severity: StringName,
	message: String,
	edge: FoundationRoadEdge,
	extra_ids: Array[StringName] = []
) -> FoundationRoadValidationIssue:
	var ids: Array[StringName] = [edge.stable_id]
	ids.append_array(extra_ids)
	var point := Vector3.ZERO
	if not edge.route_points.is_empty():
		point = edge.route_points[edge.route_points.size() / 2]
	return FoundationRoadValidationIssue.new(code, severity, message, ids, point)


static func _pair_key(first: StringName, second: StringName) -> String:
	return "%s|%s" % [first, second] if String(first) < String(second) else "%s|%s" % [second, first]
