class_name FoundationBlockExtractor
extends RefCounted

## Deterministic Phase 3 centerline planarization and bounded-face extraction.

const SOURCE_PASS: StringName = &"phase_3_block_extraction"
const EPSILON := 0.0000001


static func generate(
	world: FoundationWorldData,
	profile: FoundationBlockGenerationProfile = null
) -> FoundationBlockGenerationResult:
	var result := FoundationBlockGenerationResult.new()
	if world == null:
		return result.fail("Block extraction requires FoundationWorldData.")
	var active_profile := profile if profile != null else FoundationBlockGenerationProfile.new()
	var profile_errors := active_profile.validation_errors()
	if not profile_errors.is_empty():
		return result.fail("Invalid block generation profile: %s" % "; ".join(profile_errors))

	world.register_layer_type(FoundationWorldData.BLOCK_LAYER)
	result.preserved_block_count = _remove_replaceable_blocks(world)
	var raw_segments := _collect_road_segments(world, active_profile, result)
	result.input_segment_count = raw_segments.size()
	result.unrestricted_pair_count = raw_segments.size() * (raw_segments.size() - 1) / 2
	var split_values: Array = []
	for _segment in raw_segments:
		split_values.append([0.0, 1.0])
	var candidate_pairs := _build_bounded_candidate_pairs(raw_segments, active_profile, result)
	for pair in candidate_pairs:
		_accumulate_intersections(
			raw_segments[pair.x],
			raw_segments[pair.y],
			split_values[pair.x],
			split_values[pair.y],
			active_profile,
			result
		)
	var working_segments := _build_working_segments(
		raw_segments,
		split_values,
		active_profile,
		result
	)
	working_segments = _prune_open_chains(working_segments, result)
	result.planar_segment_count = working_segments.size()
	var faces := _extract_bounded_faces(working_segments, active_profile, result)
	for face in faces:
		_register_face(world, face, active_profile, result)
	result.diagnostics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a) < JSON.stringify(b)
	)
	result.success = true
	_set_layer_metadata(world, active_profile, result)
	return result


static func _remove_replaceable_blocks(world: FoundationWorldData) -> int:
	var retained: Array[FoundationBlockRecord] = []
	for block in world.get_blocks():
		if block.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(block.stable_id)
		else:
			retained.append(block)
	for block in retained:
		world.register_record(block)
	return retained.size()


static func _collect_road_segments(
	world: FoundationWorldData,
	profile: FoundationBlockGenerationProfile,
	result: FoundationBlockGenerationResult
) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	for edge in world.get_road_edges():
		for segment_index in range(edge.route_points.size() - 1):
			var a3 := edge.route_points[segment_index]
			var b3 := edge.route_points[segment_index + 1]
			var a := Vector2(a3.x, a3.z)
			var b := Vector2(b3.x, b3.z)
			if a.distance_to(b) < profile.point_quantization * 0.5:
				result.add_diagnostic(&"degenerate_source_segment", {
					"road_edge_id": String(edge.stable_id),
					"source_segment_index": segment_index,
					"point": _point_dict(a),
				})
				continue
			segments.append({
				"edge_id": edge.stable_id,
				"segment_index": segment_index,
				"a": a,
				"b": b,
				"grade_separated": bool(edge.metadata.get("grade_separated", false)),
				"grade_level": int(edge.metadata.get("grade_level", 0)),
			})
	return segments


static func _build_bounded_candidate_pairs(
	segments: Array[Dictionary],
	profile: FoundationBlockGenerationProfile,
	result: FoundationBlockGenerationResult
) -> Array[Vector2i]:
	var buckets: Dictionary = {}
	for index in range(segments.size()):
		var segment := segments[index]
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		var minimum := Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var maximum := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		var first_bucket := Vector2i(
			floori((minimum.x - profile.intersection_epsilon) / profile.intersection_bucket_size),
			floori((minimum.y - profile.intersection_epsilon) / profile.intersection_bucket_size)
		)
		var last_bucket := Vector2i(
			floori((maximum.x + profile.intersection_epsilon) / profile.intersection_bucket_size),
			floori((maximum.y + profile.intersection_epsilon) / profile.intersection_bucket_size)
		)
		for bucket_y in range(first_bucket.y, last_bucket.y + 1):
			for bucket_x in range(first_bucket.x, last_bucket.x + 1):
				var bucket := Vector2i(bucket_x, bucket_y)
				if not buckets.has(bucket):
					buckets[bucket] = []
				var entries: Array = buckets[bucket]
				entries.append(index)
	result.intersection_bucket_count = buckets.size()
	var bucket_keys: Array[Vector2i] = []
	for bucket: Vector2i in buckets:
		bucket_keys.append(bucket)
	bucket_keys.sort_custom(FoundationSpatialRecord._sort_vector2i)
	var unique_pairs: Dictionary = {}
	for bucket in bucket_keys:
		var entries: Array = buckets[bucket]
		entries.sort()
		for first_index in range(entries.size() - 1):
			for second_index in range(first_index + 1, entries.size()):
				var a_index := int(entries[first_index])
				var b_index := int(entries[second_index])
				var key := "%d:%d" % [a_index, b_index]
				unique_pairs[key] = Vector2i(a_index, b_index)
	var pairs: Array[Vector2i] = []
	for pair: Vector2i in unique_pairs.values():
		pairs.append(pair)
	pairs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	result.candidate_pair_count = pairs.size()
	return pairs


static func _accumulate_intersections(
	first: Dictionary,
	second: Dictionary,
	first_splits: Array,
	second_splits: Array,
	profile: FoundationBlockGenerationProfile,
	result: FoundationBlockGenerationResult
) -> void:
	var a: Vector2 = first["a"]
	var b: Vector2 = first["b"]
	var c: Vector2 = second["a"]
	var d: Vector2 = second["b"]
	if _crossing_is_grade_separated(first, second, profile.intersection_epsilon):
		return
	var r := b - a
	var s := d - c
	var denominator := r.cross(s)
	var q_minus_p := c - a
	var added_split := false
	if absf(denominator) <= profile.intersection_epsilon:
		if absf(q_minus_p.cross(r)) > profile.intersection_epsilon:
			return
		var r_length_squared := r.length_squared()
		var s_length_squared := s.length_squared()
		if r_length_squared <= EPSILON or s_length_squared <= EPSILON:
			return
		for point: Vector2 in [c, d]:
			var t: float = (point - a).dot(r) / r_length_squared
			if t >= -profile.intersection_epsilon and t <= 1.0 + profile.intersection_epsilon:
				added_split = _append_split(first_splits, t, profile.intersection_epsilon) or added_split
		for point: Vector2 in [a, b]:
			var u: float = (point - c).dot(s) / s_length_squared
			if u >= -profile.intersection_epsilon and u <= 1.0 + profile.intersection_epsilon:
				added_split = _append_split(second_splits, u, profile.intersection_epsilon) or added_split
	else:
		var t := q_minus_p.cross(s) / denominator
		var u := q_minus_p.cross(r) / denominator
		if (
			t >= -profile.intersection_epsilon
			and t <= 1.0 + profile.intersection_epsilon
			and u >= -profile.intersection_epsilon
			and u <= 1.0 + profile.intersection_epsilon
		):
			added_split = _append_split(first_splits, t, profile.intersection_epsilon) or added_split
			added_split = _append_split(second_splits, u, profile.intersection_epsilon) or added_split
	if added_split:
		result.split_intersection_count += 1


static func _crossing_is_grade_separated(
	first: Dictionary,
	second: Dictionary,
	epsilon: float
) -> bool:
	var explicitly_separated := (
		bool(first["grade_separated"])
		or bool(second["grade_separated"])
		or int(first["grade_level"]) != int(second["grade_level"])
	)
	if not explicitly_separated:
		return false
	return not _segments_share_endpoint(first, second, epsilon)


static func _segments_share_endpoint(first: Dictionary, second: Dictionary, epsilon: float) -> bool:
	for first_point: Vector2 in [first["a"], first["b"]]:
		for second_point: Vector2 in [second["a"], second["b"]]:
			if first_point.distance_to(second_point) <= epsilon:
				return true
	return false


static func _append_split(values: Array, value: float, epsilon: float) -> bool:
	var clamped := clampf(value, 0.0, 1.0)
	for existing in values:
		if absf(float(existing) - clamped) <= epsilon:
			return false
	values.append(clamped)
	return clamped > epsilon and clamped < 1.0 - epsilon


static func _build_working_segments(
	raw_segments: Array[Dictionary],
	split_values: Array,
	profile: FoundationBlockGenerationProfile,
	result: FoundationBlockGenerationResult
) -> Array[Dictionary]:
	var by_key: Dictionary = {}
	for segment_index in range(raw_segments.size()):
		var source := raw_segments[segment_index]
		var values: Array = split_values[segment_index]
		values.sort()
		for split_index in range(values.size() - 1):
			var t_start := float(values[split_index])
			var t_end := float(values[split_index + 1])
			if t_end - t_start <= profile.intersection_epsilon:
				continue
			var source_a: Vector2 = source["a"]
			var source_b: Vector2 = source["b"]
			var fragment_a := _quantize_point(source_a.lerp(source_b, t_start), profile)
			var fragment_b := _quantize_point(source_a.lerp(source_b, t_end), profile)
			var a_key := _point_key(fragment_a, profile)
			var b_key := _point_key(fragment_b, profile)
			if a_key == b_key:
				result.add_diagnostic(&"quantized_zero_length_fragment", {
					"road_edge_id": String(source["edge_id"]),
					"source_segment_index": int(source["segment_index"]),
					"point": _point_dict(fragment_a),
				})
				continue
			var key := _segment_key(a_key, b_key)
			if not by_key.has(key):
				var canonical_a_key := a_key if a_key < b_key else b_key
				var canonical_b_key := b_key if a_key < b_key else a_key
				by_key[key] = {
					"key": key,
					"a_key": canonical_a_key,
					"b_key": canonical_b_key,
					"a": fragment_a if canonical_a_key == a_key else fragment_b,
					"b": fragment_b if canonical_b_key == b_key else fragment_a,
					"provenance": [],
				}
			var working: Dictionary = by_key[key]
			var provenance: Array = working["provenance"]
			provenance.append({
				"road_edge_id": source["edge_id"],
				"source_segment_index": int(source["segment_index"]),
				"source_t_start": t_start,
				"source_t_end": t_end,
				"source_from_key": a_key,
				"source_to_key": b_key,
				"frontage_length": fragment_a.distance_to(fragment_b),
			})
	var keys: Array[String] = []
	for key: String in by_key:
		keys.append(key)
	keys.sort()
	var result_segments: Array[Dictionary] = []
	for key in keys:
		var segment: Dictionary = by_key[key]
		var provenance: Array = segment["provenance"]
		provenance.sort_custom(_provenance_less)
		result_segments.append(segment)
	return result_segments


static func _prune_open_chains(
	segments: Array[Dictionary],
	result: FoundationBlockGenerationResult
) -> Array[Dictionary]:
	var by_key: Dictionary = {}
	var incident: Dictionary = {}
	var degree: Dictionary = {}
	for segment in segments:
		var segment_key: String = segment["key"]
		by_key[segment_key] = segment
		for vertex_key: String in [segment["a_key"], segment["b_key"]]:
			if not incident.has(vertex_key):
				incident[vertex_key] = []
			var vertex_segments: Array = incident[vertex_key]
			vertex_segments.append(segment_key)
			degree[vertex_key] = int(degree.get(vertex_key, 0)) + 1
	for vertex_segments: Array in incident.values():
		vertex_segments.sort()
	var queue: Array[String] = []
	for vertex_key: String in degree:
		if int(degree[vertex_key]) < 2:
			queue.append(vertex_key)
	queue.sort()
	var queued: Dictionary = {}
	for vertex_key in queue:
		queued[vertex_key] = true
	while not queue.is_empty():
		var vertex_key := queue.pop_front()
		queued.erase(vertex_key)
		if int(degree.get(vertex_key, 0)) >= 2:
			continue
		var vertex_segments: Array = incident.get(vertex_key, [])
		for segment_key: String in vertex_segments:
			if not by_key.has(segment_key):
				continue
			var segment: Dictionary = by_key[segment_key]
			by_key.erase(segment_key)
			result.pruned_segment_count += 1
			for endpoint: String in [segment["a_key"], segment["b_key"]]:
				degree[endpoint] = maxi(0, int(degree.get(endpoint, 0)) - 1)
				if int(degree[endpoint]) < 2 and not queued.has(endpoint):
					queue.append(endpoint)
					queue.sort()
					queued[endpoint] = true
	var keys: Array[String] = []
	for key: String in by_key:
		keys.append(key)
	keys.sort()
	var retained: Array[Dictionary] = []
	for key in keys:
		retained.append(by_key[key])
	return retained


static func _extract_bounded_faces(
	segments: Array[Dictionary],
	profile: FoundationBlockGenerationProfile,
	result: FoundationBlockGenerationResult
) -> Array[Dictionary]:
	var segment_by_key: Dictionary = {}
	var positions: Dictionary = {}
	var neighbors: Dictionary = {}
	for segment in segments:
		segment_by_key[segment["key"]] = segment
		positions[segment["a_key"]] = segment["a"]
		positions[segment["b_key"]] = segment["b"]
		for pair in [
			[segment["a_key"], segment["b_key"]],
			[segment["b_key"], segment["a_key"]],
		]:
			var from_key: String = pair[0]
			var to_key: String = pair[1]
			if not neighbors.has(from_key):
				neighbors[from_key] = []
			var outgoing: Array = neighbors[from_key]
			if to_key not in outgoing:
				outgoing.append(to_key)
	var vertex_keys: Array[String] = []
	for vertex_key: String in positions:
		vertex_keys.append(vertex_key)
	vertex_keys.sort_custom(func(a: String, b: String) -> bool:
		return _point_less(positions[a], positions[b])
	)
	for vertex_key in vertex_keys:
		var center: Vector2 = positions[vertex_key]
		var outgoing: Array = neighbors[vertex_key]
		outgoing.sort_custom(func(a: String, b: String) -> bool:
			var a_delta: Vector2 = positions[a] - center
			var b_delta: Vector2 = positions[b] - center
			var a_angle := atan2(a_delta.y, a_delta.x)
			var b_angle := atan2(b_delta.y, b_delta.x)
			if not is_equal_approx(a_angle, b_angle):
				return a_angle < b_angle
			return a < b
		)
	var visited: Dictionary = {}
	var face_keys: Dictionary = {}
	var faces: Array[Dictionary] = []
	for from_key in vertex_keys:
		var outgoing: Array = neighbors[from_key]
		for to_key: String in outgoing:
			var directed_key := _directed_key(from_key, to_key)
			if visited.has(directed_key):
				continue
			var walk := _walk_face(
				from_key,
				to_key,
				neighbors,
				positions,
				segment_by_key,
				visited,
				profile.maximum_face_steps
			)
			if not bool(walk.get("closed", false)):
				result.rejected_face_count += 1
				result.add_diagnostic(&"open_or_guarded_face_walk", {
					"start": directed_key,
					"point": _point_dict(positions[from_key]),
				})
				continue
			var raw_points := PackedVector2Array()
			for key: String in walk["vertex_keys"]:
				raw_points.append(positions[key])
			var signed_area := FoundationBlockRecord._signed_area(raw_points)
			if signed_area < -profile.minimum_block_area:
				result.exterior_face_count += 1
				continue
			if signed_area <= profile.minimum_block_area:
				if signed_area > profile.intersection_epsilon:
					result.rejected_face_count += 1
					result.add_diagnostic(&"below_minimum_area", {
						"area": signed_area,
						"start": directed_key,
						"point": _point_dict(_average_points(raw_points)),
					})
				continue
			if _has_repeated_vertices(walk["vertex_keys"]):
				result.rejected_face_count += 1
				result.add_diagnostic(&"non_simple_face", {
					"start": directed_key,
					"point": _point_dict(_average_points(raw_points)),
				})
				continue
			var normalized := _normalize_face(walk, positions, profile)
			if normalized.is_empty():
				result.rejected_face_count += 1
				result.add_diagnostic(&"degenerate_normalized_face", {
					"start": directed_key,
					"point": _point_dict(_average_points(raw_points)),
				})
				continue
			var boundary: PackedVector2Array = normalized["boundary"]
			var normalized_area := FoundationBlockRecord._signed_area(boundary)
			if normalized_area <= profile.minimum_block_area or not _is_simple_polygon(boundary, profile):
				result.rejected_face_count += 1
				result.add_diagnostic(&"invalid_normalized_face", {
					"area": normalized_area,
					"boundary_key": normalized["boundary_key"],
					"point": _point_dict(_average_points(boundary)),
				})
				continue
			var boundary_key: String = normalized["boundary_key"]
			if face_keys.has(boundary_key):
				continue
			face_keys[boundary_key] = true
			faces.append(normalized)
	faces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["boundary_key"]) < String(b["boundary_key"])
	)
	return faces


static func _walk_face(
	start_from: String,
	start_to: String,
	neighbors: Dictionary,
	positions: Dictionary,
	segment_by_key: Dictionary,
	visited: Dictionary,
	maximum_steps: int
) -> Dictionary:
	var vertex_keys: Array[String] = []
	var walked_segments: Array[Dictionary] = []
	var current_from := start_from
	var current_to := start_to
	for _step in range(maximum_steps):
		var directed_key := _directed_key(current_from, current_to)
		if visited.has(directed_key):
			return {"closed": current_from == start_from and current_to == start_to,
				"vertex_keys": vertex_keys, "segments": walked_segments}
		visited[directed_key] = true
		vertex_keys.append(current_from)
		walked_segments.append({
			"segment": segment_by_key[_segment_key(current_from, current_to)],
			"from_key": current_from,
			"to_key": current_to,
		})
		var outgoing: Array = neighbors[current_to]
		var incoming_index := outgoing.find(current_from)
		if incoming_index < 0:
			return {"closed": false, "vertex_keys": vertex_keys, "segments": walked_segments}
		var next_index := (incoming_index - 1 + outgoing.size()) % outgoing.size()
		var next_to: String = outgoing[next_index]
		current_from = current_to
		current_to = next_to
		if current_from == start_from and current_to == start_to:
			return {"closed": true, "vertex_keys": vertex_keys, "segments": walked_segments}
	return {"closed": false, "vertex_keys": vertex_keys, "segments": walked_segments}


static func _normalize_face(
	walk: Dictionary,
	positions: Dictionary,
	profile: FoundationBlockGenerationProfile
) -> Dictionary:
	var raw_keys: Array = walk["vertex_keys"]
	var raw_segments: Array = walk["segments"]
	if raw_keys.size() < 3 or raw_segments.size() != raw_keys.size():
		return {}
	var keep_indices: Array[int] = []
	for index in range(raw_keys.size()):
		var previous: Vector2 = positions[raw_keys[(index - 1 + raw_keys.size()) % raw_keys.size()]]
		var current: Vector2 = positions[raw_keys[index]]
		var next: Vector2 = positions[raw_keys[(index + 1) % raw_keys.size()]]
		var incoming := current - previous
		var outgoing := next - current
		var scale := maxf(1.0, incoming.length() + outgoing.length())
		var collinear := absf(incoming.cross(outgoing)) <= profile.collinear_epsilon * scale
		if not collinear or incoming.dot(outgoing) < 0.0:
			keep_indices.append(index)
	if keep_indices.size() < 3:
		return {}
	var normalized_points: Array[Vector2] = []
	var raw_groups: Array[Array] = []
	for kept_index in range(keep_indices.size()):
		var raw_start := keep_indices[kept_index]
		var raw_end := keep_indices[(kept_index + 1) % keep_indices.size()]
		normalized_points.append(positions[raw_keys[raw_start]])
		var group: Array = []
		var cursor := raw_start
		while cursor != raw_end:
			group.append(cursor)
			cursor = (cursor + 1) % raw_keys.size()
		raw_groups.append(group)
	var canonical_start := 0
	for index in range(1, normalized_points.size()):
		if _point_less(normalized_points[index], normalized_points[canonical_start]):
			canonical_start = index
	var boundary := PackedVector2Array()
	var references: Array[FoundationBlockBoundaryReference] = []
	for normalized_index in range(normalized_points.size()):
		var source_group_index := (canonical_start + normalized_index) % normalized_points.size()
		boundary.append(normalized_points[source_group_index])
		for raw_segment_index: int in raw_groups[source_group_index]:
			var walked: Dictionary = raw_segments[raw_segment_index]
			var working: Dictionary = walked["segment"]
			for provenance: Dictionary in working["provenance"]:
				var t_start := float(provenance["source_t_start"])
				var t_end := float(provenance["source_t_end"])
				if not (
					String(provenance["source_from_key"]) == String(walked["from_key"])
					and String(provenance["source_to_key"]) == String(walked["to_key"])
				):
					var swap := t_start
					t_start = t_end
					t_end = swap
				references.append(FoundationBlockBoundaryReference.new(
					normalized_index,
					StringName(provenance["road_edge_id"]),
					int(provenance["source_segment_index"]),
					t_start,
					t_end,
					float(provenance["frontage_length"])
				))
	var boundary_key := _boundary_key(boundary, profile)
	return {
		"boundary": boundary,
		"references": references,
		"boundary_key": boundary_key,
	}


static func _register_face(
	world: FoundationWorldData,
	face: Dictionary,
	profile: FoundationBlockGenerationProfile,
	result: FoundationBlockGenerationResult
) -> void:
	var boundary: PackedVector2Array = face["boundary"]
	var boundary_key: String = face["boundary_key"]
	var stable_id := _block_id(world.metadata, profile, boundary_key)
	var existing := world.get_record(stable_id) as FoundationBlockRecord
	if existing != null:
		if _boundaries_equal(existing.outer_boundary, boundary, profile.intersection_epsilon):
			return
		stable_id = _repair_block_id(world, profile, boundary_key)
	var references: Array[FoundationBlockBoundaryReference] = []
	for reference: FoundationBlockBoundaryReference in face["references"]:
		references.append(reference)
	var block := FoundationBlockRecord.new(stable_id, boundary, references)
	block.source_pass = SOURCE_PASS
	block.source_version = profile.generator_version
	block.tags = PackedStringArray(["phase_3", "centerline_bounded", "abstract_block"])
	block.metadata = {
		"boundary_key": boundary_key,
		"validation_state": String(block.validation_state),
	}
	world.register_record(block)
	result.generated_block_count += 1


static func _set_layer_metadata(
	world: FoundationWorldData,
	profile: FoundationBlockGenerationProfile,
	result: FoundationBlockGenerationResult
) -> void:
	world.get_layer(FoundationWorldData.BLOCK_LAYER).metadata = {
		"format_version": 1,
		"source_pass": String(SOURCE_PASS),
		"generator_version": profile.generator_version,
		"profile": profile.to_dict(),
		"diagnostics": result.diagnostics.duplicate(true),
		"counts": result.to_dict(),
	}


static func _block_id(
	metadata: FoundationWorldMetadata,
	profile: FoundationBlockGenerationProfile,
	boundary_key: String
) -> StringName:
	return FoundationSpatialId.make(
		metadata.seed,
		profile.generator_version,
		metadata.content_pack_version,
		FoundationBlockRecord.ENTITY_TYPE,
		&"",
		boundary_key
	)


static func _repair_block_id(
	world: FoundationWorldData,
	profile: FoundationBlockGenerationProfile,
	boundary_key: String
) -> StringName:
	var ordinal := 1
	while true:
		var stable_id := FoundationSpatialId.make(
			world.metadata.seed,
			profile.generator_version,
			world.metadata.content_pack_version,
			FoundationBlockRecord.ENTITY_TYPE,
			&"",
			"%s|repair:%d" % [boundary_key, ordinal]
		)
		if world.get_record(stable_id) == null:
			return stable_id
		ordinal += 1
	return &""


static func _is_simple_polygon(
	boundary: PackedVector2Array,
	profile: FoundationBlockGenerationProfile
) -> bool:
	if boundary.size() < 3 or Geometry2D.triangulate_polygon(boundary).is_empty():
		return false
	for first_index in range(boundary.size()):
		var first_next := (first_index + 1) % boundary.size()
		for second_index in range(first_index + 1, boundary.size()):
			var second_next := (second_index + 1) % boundary.size()
			if (
				first_index == second_index
				or first_next == second_index
				or second_next == first_index
			):
				continue
			if _proper_segments_intersect(
				boundary[first_index],
				boundary[first_next],
				boundary[second_index],
				boundary[second_next],
				profile.intersection_epsilon
			):
				return false
	return true


static func _proper_segments_intersect(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	d: Vector2,
	epsilon: float
) -> bool:
	var r := b - a
	var s := d - c
	var denominator := r.cross(s)
	if absf(denominator) <= epsilon:
		return false
	var difference := c - a
	var t := difference.cross(s) / denominator
	var u := difference.cross(r) / denominator
	return t > epsilon and t < 1.0 - epsilon and u > epsilon and u < 1.0 - epsilon


static func _has_repeated_vertices(vertex_keys: Array) -> bool:
	var seen: Dictionary = {}
	for vertex_key in vertex_keys:
		if seen.has(vertex_key):
			return true
		seen[vertex_key] = true
	return false


static func _boundaries_equal(
	first: PackedVector2Array,
	second: PackedVector2Array,
	epsilon: float
) -> bool:
	if first.size() != second.size():
		return false
	for index in range(first.size()):
		if first[index].distance_to(second[index]) > epsilon:
			return false
	return true


static func _quantize_point(point: Vector2, profile: FoundationBlockGenerationProfile) -> Vector2:
	return Vector2(
		round(point.x / profile.point_quantization) * profile.point_quantization,
		round(point.y / profile.point_quantization) * profile.point_quantization
	)


static func _point_key(point: Vector2, profile: FoundationBlockGenerationProfile) -> String:
	return "%d,%d" % [
		roundi(point.x / profile.point_quantization),
		roundi(point.y / profile.point_quantization),
	]


static func _boundary_key(
	boundary: PackedVector2Array,
	profile: FoundationBlockGenerationProfile
) -> String:
	var parts := PackedStringArray()
	for point in boundary:
		parts.append(_point_key(point, profile))
	return ";".join(parts)


static func _segment_key(first: String, second: String) -> String:
	return "%s|%s" % [first, second] if first < second else "%s|%s" % [second, first]


static func _directed_key(first: String, second: String) -> String:
	return "%s>%s" % [first, second]


static func _point_less(a: Vector2, b: Vector2) -> bool:
	return a.x < b.x or (is_equal_approx(a.x, b.x) and a.y < b.y)


static func _average_points(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var result := Vector2.ZERO
	for point in points:
		result += point
	return result / float(points.size())


static func _point_dict(point: Vector2) -> Dictionary:
	return {"x": point.x, "y": point.y}


static func _provenance_less(a: Dictionary, b: Dictionary) -> bool:
	if String(a["road_edge_id"]) != String(b["road_edge_id"]):
		return String(a["road_edge_id"]) < String(b["road_edge_id"])
	if int(a["source_segment_index"]) != int(b["source_segment_index"]):
		return int(a["source_segment_index"]) < int(b["source_segment_index"])
	if not is_equal_approx(float(a["source_t_start"]), float(b["source_t_start"])):
		return float(a["source_t_start"]) < float(b["source_t_start"])
	return float(a["source_t_end"]) < float(b["source_t_end"])
