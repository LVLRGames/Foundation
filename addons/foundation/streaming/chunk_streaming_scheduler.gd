class_name FoundationChunkStreamingScheduler
extends RefCounted

## Pure planning plus an explicit bounded apply step over abstract chunk metadata.


static func build_plan(
	world: FoundationWorldData,
	interests: Array,
	profile: FoundationChunkStreamingProfile = null
) -> FoundationChunkStreamingPlan:
	var plan := FoundationChunkStreamingPlan.new()
	if world == null:
		return plan.fail("Streaming planning requires FoundationWorldData.")
	var active_profile := profile if profile != null else FoundationChunkStreamingProfile.new()
	var profile_errors := active_profile.validation_errors()
	if not profile_errors.is_empty():
		return plan.fail("Invalid streaming profile: %s" % "; ".join(profile_errors))
	plan.transition_budget = active_profile.max_transitions_per_update
	var active_interests: Array[FoundationChunkInterest] = []
	var seen_ids: Dictionary = {}
	for value in interests:
		if not value is FoundationChunkInterest:
			return plan.fail("Every streaming interest must be FoundationChunkInterest data.")
		var interest := value as FoundationChunkInterest
		if not interest.enabled:
			continue
		if String(interest.stable_id).is_empty():
			return plan.fail("Streaming interests require stable non-empty IDs.")
		if seen_ids.has(interest.stable_id):
			return plan.fail("Duplicate streaming interest ID: %s" % interest.stable_id)
		seen_ids[interest.stable_id] = true
		active_interests.append(interest)
	active_interests.sort_custom(func(a: FoundationChunkInterest, b: FoundationChunkInterest) -> bool:
		return String(a.stable_id) < String(b.stable_id)
	)

	for chunk in world.get_sorted_chunks():
		plan.planning_operation_count += maxi(1, active_interests.size())
		if plan.planning_operation_count > active_profile.maximum_planning_operations:
			return plan.fail("Streaming planning exceeded its explicit operation cap.")
		var desired := _resolve_desired(world, chunk, active_interests, active_profile)
		plan.desired_chunks[chunk.coordinate] = desired
		var request := _make_request(chunk, desired, active_profile)
		if request != null:
			plan.requests.append(request)
	plan.requests.sort_custom(_request_precedes)
	return plan


static func apply_plan(
	world: FoundationWorldData,
	plan: FoundationChunkStreamingPlan,
	maximum_transitions := -1
) -> Array[FoundationChunkStreamingRequest]:
	var applied: Array[FoundationChunkStreamingRequest] = []
	if world == null or plan == null or not plan.success:
		return applied
	var budget := plan.transition_budget if maximum_transitions < 0 else maximum_transitions
	budget = maxi(0, budget)
	for request in plan.requests:
		if applied.size() >= budget:
			break
		var chunk := world.get_chunk(request.chunk_coordinate)
		if chunk == null:
			continue
		if chunk.runtime_state != request.from_state or chunk.runtime_lod_level != request.from_lod:
			continue
		chunk.runtime_state = request.to_state as FoundationChunkData.RuntimeState
		chunk.runtime_lod_level = request.to_lod
		chunk.runtime_transition_serial += 1
		applied.append(request)
	return applied


static func _resolve_desired(
	world: FoundationWorldData,
	chunk: FoundationChunkData,
	interests: Array[FoundationChunkInterest],
	profile: FoundationChunkStreamingProfile
) -> Dictionary:
	var target_state := FoundationChunkData.RuntimeState.UNLOADED
	var target_lod := -1
	var source_id: StringName = &""
	var source_priority := 0.0
	var source_distance := 2147483647
	var minimum_distance := 2147483647
	for interest in interests:
		var interest_chunk := world.coordinate_system.world_to_chunk(interest.world_position)
		var delta := chunk.coordinate - interest_chunk
		var distance := maxi(absi(delta.x), absi(delta.y))
		minimum_distance = mini(minimum_distance, distance)
		var target := profile.target_for_distance(distance)
		if _candidate_is_better(
			target.x, target.y, interest.priority_weight, distance, interest.stable_id,
			target_state, target_lod, source_priority, source_distance, source_id
		):
			target_state = target.x as FoundationChunkData.RuntimeState
			target_lod = target.y
			source_id = interest.stable_id
			source_priority = interest.priority_weight
			source_distance = distance

	if minimum_distance != 2147483647 and target_state < chunk.runtime_state:
		var exit_radius := profile.radius_for_state(chunk.runtime_state, chunk.runtime_lod_level)
		if minimum_distance <= exit_radius + profile.hysteresis_chunks:
			target_state = chunk.runtime_state
			target_lod = profile.lod_for_state(target_state, chunk.runtime_lod_level)
	if (
		minimum_distance != 2147483647
		and target_state == FoundationChunkData.RuntimeState.VISUAL_LOADED
		and chunk.runtime_state == FoundationChunkData.RuntimeState.VISUAL_LOADED
		and target_lod > chunk.runtime_lod_level
	):
		var lod_exit_radius := profile.radius_for_state(chunk.runtime_state, chunk.runtime_lod_level)
		if minimum_distance <= lod_exit_radius + profile.hysteresis_chunks:
			target_lod = chunk.runtime_lod_level
	target_lod = profile.lod_for_state(target_state, target_lod)
	return {
		"state": target_state,
		"lod": target_lod,
		"source_interest_id": source_id,
		"priority_weight": source_priority,
		"distance_chunks": source_distance,
	}


static func _candidate_is_better(
	state: int,
	lod: int,
	priority: float,
	distance: int,
	source_id: StringName,
	best_state: int,
	best_lod: int,
	best_priority: float,
	best_distance: int,
	best_source_id: StringName
) -> bool:
	if state != best_state:
		return state > best_state
	if lod != best_lod:
		return lod < best_lod
	if not is_equal_approx(priority, best_priority):
		return priority > best_priority
	if distance != best_distance:
		return distance < best_distance
	return String(source_id) < String(best_source_id)


static func _make_request(
	chunk: FoundationChunkData,
	desired: Dictionary,
	profile: FoundationChunkStreamingProfile
) -> FoundationChunkStreamingRequest:
	var final_state: int = desired["state"]
	var final_lod: int = desired["lod"]
	if chunk.runtime_state == final_state and chunk.runtime_lod_level == final_lod:
		return null
	var request := FoundationChunkStreamingRequest.new()
	request.chunk_coordinate = chunk.coordinate
	request.source_interest_id = desired["source_interest_id"]
	request.distance_chunks = desired["distance_chunks"]
	request.priority_weight = desired["priority_weight"]
	request.from_state = chunk.runtime_state
	request.from_lod = chunk.runtime_lod_level
	request.final_state = final_state as FoundationChunkData.RuntimeState
	request.final_lod = final_lod
	if chunk.runtime_state < final_state:
		request.to_state = (chunk.runtime_state + 1) as FoundationChunkData.RuntimeState
		request.to_lod = profile.lod_for_state(request.to_state, final_lod)
	elif chunk.runtime_state > final_state:
		request.to_state = (chunk.runtime_state - 1) as FoundationChunkData.RuntimeState
		request.to_lod = profile.lod_for_state(request.to_state, final_lod)
	else:
		request.to_state = chunk.runtime_state
		request.to_lod = chunk.runtime_lod_level + signi(final_lod - chunk.runtime_lod_level)
	return request


static func _request_precedes(a: FoundationChunkStreamingRequest, b: FoundationChunkStreamingRequest) -> bool:
	if a.is_release() != b.is_release():
		return a.is_release()
	if a.is_release():
		if a.distance_chunks != b.distance_chunks:
			return a.distance_chunks > b.distance_chunks
	else:
		if not is_equal_approx(a.priority_weight, b.priority_weight):
			return a.priority_weight > b.priority_weight
		if a.distance_chunks != b.distance_chunks:
			return a.distance_chunks < b.distance_chunks
	if a.chunk_coordinate.y != b.chunk_coordinate.y:
		return a.chunk_coordinate.y < b.chunk_coordinate.y
	return a.chunk_coordinate.x < b.chunk_coordinate.x
