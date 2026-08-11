extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_profile_and_interest_round_trip()
	_test_deterministic_planning_and_bands()
	_test_hysteresis()
	_test_bounded_transitions_and_convergence()
	_test_chunk_runtime_serialization()
	_test_record_identity_and_authorship_preservation()
	_test_lod_meshes()
	_test_terrain_presentation_lifecycle()
	_test_debug_contract()
	_test_demo_contract()
	_test_scope_exclusions()

	if _failures.is_empty():
		print("Foundation Phase 6 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 6 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_profile_and_interest_round_trip() -> void:
	var profile := _profile()
	var restored := FoundationChunkStreamingProfile.from_dict(profile.to_dict())
	_check(restored.to_dict() == profile.to_dict(), "streaming profile has a versioned deterministic round trip")
	_check(restored.validation_errors().is_empty(), "default Phase 6 distance bands form a valid nested lifecycle")
	var interest := FoundationChunkInterest.new(&"camera_primary", Vector3(-129.0, 12.0, 128.0), 2.5)
	interest.enabled = false
	var restored_interest := FoundationChunkInterest.from_dict(interest.to_dict())
	_check(
		restored_interest.stable_id == interest.stable_id
		and restored_interest.world_position == interest.world_position
		and is_equal_approx(restored_interest.priority_weight, interest.priority_weight)
		and restored_interest.enabled == interest.enabled,
		"Node-free streaming interest identity, position, priority, and state round-trip"
	)


func _test_deterministic_planning_and_bands() -> void:
	var first := _make_world(Rect2(-896.0, -896.0, 1664.0, 1664.0))
	var second := FoundationWorldData.from_dict(first.to_dict())
	var primary := FoundationChunkInterest.new(&"primary", Vector3(64.0, 0.0, 64.0), 2.0)
	var secondary := FoundationChunkInterest.new(&"secondary", Vector3(-320.0, 0.0, -320.0), 1.0)
	var before := JSON.stringify(first.to_dict())
	var first_plan := FoundationChunkStreamingScheduler.build_plan(first, [primary, secondary], _profile())
	var second_plan := FoundationChunkStreamingScheduler.build_plan(second, [secondary, primary], _profile())
	_check(first_plan.success and second_plan.success, "valid multi-interest streaming plans succeed")
	_check(first_plan.to_dict() == second_plan.to_dict(), "interest registration order does not perturb streaming plans")
	_check(JSON.stringify(first.to_dict()) == before, "building a streaming plan does not mutate world or chunk data")

	var single_plan := FoundationChunkStreamingScheduler.build_plan(first, [primary], _profile())
	_check(_desired_matches(single_plan, Vector2i.ZERO, FoundationChunkData.RuntimeState.GAMEPLAY_ACTIVE, 0), "interest chunk requests gameplay-active LOD 0")
	_check(_desired_matches(single_plan, Vector2i(1, 0), FoundationChunkData.RuntimeState.PHYSICS_LOADED, 0), "adjacent ring requests physics and exact visual LOD")
	_check(_desired_matches(single_plan, Vector2i(2, 0), FoundationChunkData.RuntimeState.VISUAL_LOADED, 0), "near visual ring requests LOD 0")
	_check(_desired_matches(single_plan, Vector2i(3, 0), FoundationChunkData.RuntimeState.VISUAL_LOADED, 1), "far visual ring requests LOD 1")
	_check(_desired_matches(single_plan, Vector2i(4, 0), FoundationChunkData.RuntimeState.PROXY_LOADED, 2), "proxy ring requests the coarsest presentation LOD")
	_check(_desired_matches(single_plan, Vector2i(5, 0), FoundationChunkData.RuntimeState.DATA_ONLY, -1), "data ring retains data without presentation")
	_check(_desired_matches(single_plan, Vector2i(-7, 0), FoundationChunkData.RuntimeState.UNLOADED, -1), "chunks outside all bands and hysteresis request unloaded runtime state")
	_check(
		single_plan.planning_operation_count == first.get_sorted_chunks().size(),
		"single-interest planning work is bounded to one operation per known chunk"
	)


func _test_hysteresis() -> void:
	var world := _make_world(Rect2(-256.0, -256.0, 640.0, 640.0))
	var chunk := world.get_chunk(Vector2i.ZERO)
	chunk.runtime_state = FoundationChunkData.RuntimeState.GAMEPLAY_ACTIVE
	chunk.runtime_lod_level = 0
	var interest := FoundationChunkInterest.new(&"camera", Vector3(192.0, 0.0, 64.0))
	var within_margin := FoundationChunkStreamingScheduler.build_plan(world, [interest], _profile())
	_check(
		_desired_matches(within_margin, Vector2i.ZERO, FoundationChunkData.RuntimeState.GAMEPLAY_ACTIVE, 0),
		"one-chunk hysteresis retains gameplay state at its exit boundary"
	)
	interest.world_position = Vector3(320.0, 0.0, 64.0)
	var beyond_margin := FoundationChunkStreamingScheduler.build_plan(world, [interest], _profile())
	_check(
		beyond_margin.get_desired(Vector2i.ZERO).get("state") == FoundationChunkData.RuntimeState.VISUAL_LOADED,
		"lifecycle demotion begins after leaving the hysteresis margin"
	)
	chunk.runtime_state = FoundationChunkData.RuntimeState.VISUAL_LOADED
	chunk.runtime_lod_level = 0
	interest.world_position = Vector3(448.0, 0.0, 64.0)
	var lod_margin := FoundationChunkStreamingScheduler.build_plan(world, [interest], _profile())
	_check(
		lod_margin.get_desired(Vector2i.ZERO).get("lod") == 0,
		"visual LOD hysteresis prevents near/far boundary thrashing"
	)


func _test_bounded_transitions_and_convergence() -> void:
	var world := _make_world(Rect2(0.0, 0.0, 640.0, 128.0))
	var profile := _profile()
	profile.max_transitions_per_update = 2
	var interest := FoundationChunkInterest.new(&"camera", Vector3(320.0, 0.0, 64.0))
	var first_plan := FoundationChunkStreamingScheduler.build_plan(world, [interest], profile)
	var first_applied := FoundationChunkStreamingScheduler.apply_plan(world, first_plan)
	_check(first_applied.size() == 2, "streaming apply obeys its strict per-update transition budget")
	_check(_transition_serial_sum(world) == 2, "each applied lifecycle transition increments exactly one chunk serial")
	var iterations := 0
	while iterations < 20:
		var plan := FoundationChunkStreamingScheduler.build_plan(world, [interest], profile)
		if plan.requests.is_empty():
			break
		FoundationChunkStreamingScheduler.apply_plan(world, plan)
		iterations += 1
	var converged := FoundationChunkStreamingScheduler.build_plan(world, [interest], profile)
	_check(converged.requests.is_empty(), "bounded one-step transitions converge to the deterministic target state")
	var empty_plan := FoundationChunkStreamingScheduler.build_plan(world, [], profile)
	_check(
		empty_plan.requests[0].is_release(),
		"release work is prioritized when runtime interest disappears"
	)
	var stale_request := empty_plan.requests[0]
	world.get_chunk(stale_request.chunk_coordinate).runtime_state = FoundationChunkData.RuntimeState.DATA_ONLY
	world.get_chunk(stale_request.chunk_coordinate).runtime_lod_level = -1
	var stale_applied := FoundationChunkStreamingScheduler.apply_plan(world, empty_plan, 1)
	_check(
		stale_applied.is_empty() or stale_applied[0].chunk_coordinate != stale_request.chunk_coordinate,
		"stale transition requests are rejected without overwriting newer chunk state"
	)
	_check(
		world.get_chunk(stale_request.chunk_coordinate).runtime_state == FoundationChunkData.RuntimeState.DATA_ONLY,
		"rejecting a stale request preserves the newer chunk lifecycle"
	)


func _test_chunk_runtime_serialization() -> void:
	var world := _make_world(Rect2(-128.0, -128.0, 256.0, 256.0))
	var chunk := world.get_chunk(Vector2i(-1, -1))
	chunk.runtime_state = FoundationChunkData.RuntimeState.VISUAL_LOADED
	chunk.runtime_lod_level = 1
	chunk.runtime_transition_serial = 7
	var restored := FoundationWorldData.from_dict(world.to_dict()).get_chunk(Vector2i(-1, -1))
	_check(
		restored.runtime_state == FoundationChunkData.RuntimeState.VISUAL_LOADED
		and restored.runtime_lod_level == 1
		and restored.runtime_transition_serial == 7,
		"chunk lifecycle, LOD, and transition serial survive world manifest round-trip"
	)


func _test_record_identity_and_authorship_preservation() -> void:
	var world := _make_world(Rect2(0.0, 0.0, 512.0, 512.0))
	world.register_layer_type(&"phase_6_fixture")
	var states := [
		FoundationSpatialRecord.AuthorshipState.GENERATED,
		FoundationSpatialRecord.AuthorshipState.LOCKED,
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN,
	]
	var records: Array[FoundationSpatialRecord] = []
	for index in range(states.size()):
		var record := FoundationSpatialRecord.new(
			StringName("phase_6_record_%d" % index),
			&"phase_6_fixture",
			&"phase_6_fixture",
			Rect2(index * 132.0, 8.0, 96.0, 96.0)
		)
		record.authorship_state = states[index]
		world.register_record(record)
		records.append(record)
	var before: Array[Dictionary] = []
	for record in records:
		before.append(record.to_dict())
	var interest := FoundationChunkInterest.new(&"camera", Vector3(64.0, 0.0, 64.0))
	var plan := FoundationChunkStreamingScheduler.build_plan(world, [interest], _profile())
	FoundationChunkStreamingScheduler.apply_plan(world, plan, 64)
	var after: Array[Dictionary] = []
	for record in records:
		after.append(record.to_dict())
	_check(before == after, "streaming preserves record geometry, stable IDs, ownership, and generated/locked/overridden states")
	_check(world.spatial_index.get_record_count() == 3, "runtime unloading never deletes authoritative spatial records")


func _test_lod_meshes() -> void:
	var terrain_profile := FoundationTerrainProfile.new()
	terrain_profile.grid_cells = Vector2i(64, 32)
	var data := FoundationTerrainGenerator.generate(terrain_profile)
	var before := JSON.stringify({"heights": Array(data.vertex_heights), "diagonals": Array(data.cell_diagonals), "revision": data.revision})
	var lod_0 := FoundationTerrainMesher.build_mesh(data, Vector2i.ZERO, true, 0)
	var lod_1 := FoundationTerrainMesher.build_mesh(data, Vector2i.ZERO, true, 1)
	var lod_2 := FoundationTerrainMesher.build_mesh(data, Vector2i.ZERO, true, 2)
	var count_0 := (lod_0.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var count_1 := (lod_1.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var count_2 := (lod_2.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	_check(count_0 > count_1 and count_1 > count_2, "terrain visual LODs reduce vertex work monotonically")
	_check(_mesh_faces_up(lod_0) and _mesh_faces_up(lod_1) and _mesh_faces_up(lod_2), "every terrain LOD preserves upward-visible winding")
	_check(_lod_shared_border_matches(data, 2), "adjacent coarse terrain LOD chunks share exact authoritative border heights")
	_check(
		FoundationTerrainMesher.build_collision_faces(data, Vector2i.ZERO).size() == 32 * 32 * 6,
		"physics collision remains full resolution regardless of visual LOD"
	)
	_check(JSON.stringify({"heights": Array(data.vertex_heights), "diagonals": Array(data.cell_diagonals), "revision": data.revision}) == before, "LOD meshing never mutates authoritative terrain")


func _test_terrain_presentation_lifecycle() -> void:
	var terrain := FoundationTerrain.new()
	terrain.generate_on_ready = false
	terrain.profile = FoundationTerrainProfile.new()
	terrain.profile.grid_cells = Vector2i(64, 64)
	root.add_child(terrain)
	_check(terrain.generate_terrain(false), "terrain can generate authoritative data without eagerly creating views")
	_check(terrain.get_loaded_chunk_coordinates().is_empty(), "data-only terrain generation creates no chunk scene nodes")
	var revision_before := terrain.terrain_data.revision
	terrain.apply_chunk_runtime_state(Vector2i.ZERO, FoundationChunkData.RuntimeState.PROXY_LOADED, 2)
	var proxy := terrain.get_chunk(Vector2i.ZERO)
	_check(proxy != null and proxy.has_visual() and not proxy.has_collision() and proxy.visual_lod_level == 2, "proxy state creates only coarse visual presentation")
	terrain.apply_chunk_runtime_state(Vector2i.ZERO, FoundationChunkData.RuntimeState.PHYSICS_LOADED, 0)
	var physics := terrain.get_chunk(Vector2i.ZERO)
	_check(physics.has_visual() and physics.has_collision() and physics.visual_lod_level == 0, "physics state refines visual LOD and creates full collision")
	var previous_mesh := physics.get_mesh_instance().mesh
	var previous_height := terrain.terrain_data.get_vertex_height(Vector2i(1, 1))
	terrain.terrain_data.set_vertex_height(Vector2i(1, 1), previous_height + terrain.terrain_data.height_step)
	var revision_after_edit := terrain.terrain_data.revision
	_check(
		terrain.rebuild_dirty_chunks() == 1
		and physics.get_mesh_instance().mesh != previous_mesh,
		"dirty rebuild refreshes only currently streamed terrain presentations"
	)
	terrain.apply_chunk_runtime_state(Vector2i.ZERO, FoundationChunkData.RuntimeState.DATA_ONLY, -1)
	_check(terrain.get_chunk(Vector2i.ZERO) == null, "data-only demotion disposes the chunk presentation node")
	_check(revision_after_edit > revision_before, "the explicit terrain edit advances authoritative terrain revision")
	_check(terrain.terrain_data.revision == revision_after_edit, "presentation lifecycle changes never mutate terrain authority")
	terrain.free()


func _test_debug_contract() -> void:
	var world := _make_world(Rect2(0.0, 0.0, 384.0, 128.0))
	world.get_chunk(Vector2i(0, 0)).runtime_state = FoundationChunkData.RuntimeState.GAMEPLAY_ACTIVE
	world.get_chunk(Vector2i(0, 0)).runtime_lod_level = 0
	world.get_chunk(Vector2i(1, 0)).runtime_state = FoundationChunkData.RuntimeState.VISUAL_LOADED
	world.get_chunk(Vector2i(1, 0)).runtime_lod_level = 1
	world.get_chunk(Vector2i(2, 0)).runtime_state = FoundationChunkData.RuntimeState.PROXY_LOADED
	world.get_chunk(Vector2i(2, 0)).runtime_lod_level = 2
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id == &"streaming")
	var before := JSON.stringify(world.to_dict())
	var builder := registry.build(world)
	_check(builder.triangle_purposes.has(&"streaming_gameplay"), "streaming debug exposes gameplay-active chunks")
	_check(builder.triangle_purposes.has(&"streaming_visual_far"), "streaming debug distinguishes visual LOD")
	_check(builder.triangle_purposes.has(&"streaming_proxy"), "streaming debug exposes proxy chunks")
	_check(JSON.stringify(world.to_dict()) == before, "streaming debug never mutates runtime or authoritative data")
	var provider := registry.get_provider(&"streaming")
	var invocation_count := provider.invocation_count
	registry.set_layer_enabled(&"streaming", false)
	_check(registry.build(world).get_primitive_count() == 0 and provider.invocation_count == invocation_count, "disabled streaming debug performs zero provider work")


func _test_demo_contract() -> void:
	var scene := load("res://demo/streaming_demo.tscn") as PackedScene
	var demo := scene.instantiate()
	root.add_child(demo)
	var world := demo.get_node("FoundationWorld") as FoundationWorld
	var terrain := demo.get_node("FoundationTerrain") as FoundationTerrain
	var debug_view := demo.get_node("FoundationWorld/FoundationDebugView") as FoundationDebugView
	var camera := demo.get_node("Camera3D") as Camera3D
	_check(world.world_data.get_sorted_chunks().size() == 64, "Phase 6 demo initializes an eight-by-eight abstract chunk field")
	_check(terrain.terrain_data != null and not terrain.get_loaded_chunk_coordinates().is_empty(), "Phase 6 demo streams terrain presentation from data-only generation")
	_check(debug_view.show_streaming and debug_view.last_primitive_count > 0, "Phase 6 demo exposes lifecycle and LOD debug inspection")
	_check(camera.has_method("movement_direction"), "Phase 6 demo uses the reusable fly camera as its runtime interest source")
	var serial_before := _transition_serial_sum(world.world_data)
	demo.call("_streaming_update")
	var serial_delta := _transition_serial_sum(world.world_data) - serial_before
	_check(serial_delta >= 0 and serial_delta <= 24, "Phase 6 demo applies only the configured transition budget per update")
	demo.free()


func _test_scope_exclusions() -> void:
	_check(
		ClassDB.is_parent_class(FoundationChunkInterest.new().get_class(), "RefCounted")
		and not ClassDB.is_parent_class(FoundationChunkInterest.new().get_class(), "Node"),
		"streaming interests remain Node-free data"
	)
	var scheduler := FoundationChunkStreamingScheduler.new()
	var forbidden := false
	for method_name in [&"save_chunk", &"load_chunk_file", &"start_thread", &"build_navigation", &"spawn_gameplay", &"generate_building_mesh"]:
		forbidden = forbidden or scheduler.has_method(method_name)
	_check(not forbidden, "Phase 6 adds no persistence backend, threading, navigation, gameplay spawning, or production city meshes")


func _profile() -> FoundationChunkStreamingProfile:
	var profile := FoundationChunkStreamingProfile.new()
	profile.gameplay_radius_chunks = 0
	profile.physics_radius_chunks = 1
	profile.visual_lod_radii_chunks = PackedInt32Array([2, 3])
	profile.proxy_radius_chunks = 4
	profile.data_radius_chunks = 5
	profile.hysteresis_chunks = 1
	profile.max_transitions_per_update = 8
	return profile


func _make_world(bounds: Rect2) -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = 6101
	metadata.generator_version = 6
	metadata.content_pack_version = &"phase-6-tests"
	metadata.world_bounds = bounds
	var world := FoundationWorldData.new(metadata, FoundationCoordinateSystem.new())
	world.initialize_default_layers()
	world.initialize_partitions()
	return world


func _desired_matches(
	plan: FoundationChunkStreamingPlan,
	coordinate: Vector2i,
	state: FoundationChunkData.RuntimeState,
	lod_level: int
) -> bool:
	var desired := plan.get_desired(coordinate)
	return desired.get("state", -1) == state and desired.get("lod", -99) == lod_level


func _transition_serial_sum(world: FoundationWorldData) -> int:
	var total := 0
	for chunk in world.get_sorted_chunks():
		total += chunk.runtime_transition_serial
	return total


func _mesh_faces_up(mesh: ArrayMesh) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for triangle_start in range(0, indices.size(), 3):
		var first := vertices[indices[triangle_start]]
		var second := vertices[indices[triangle_start + 1]]
		var third := vertices[indices[triangle_start + 2]]
		if (second - first).cross(third - first).y >= 0.0:
			return false
	return true


func _lod_shared_border_matches(data: FoundationTerrainData, lod_level: int) -> bool:
	var left_arrays := FoundationTerrainMesher.build_mesh(data, Vector2i.ZERO, true, lod_level).surface_get_arrays(0)
	var right_arrays := FoundationTerrainMesher.build_mesh(data, Vector2i(1, 0), true, lod_level).surface_get_arrays(0)
	var left: PackedVector3Array = left_arrays[Mesh.ARRAY_VERTEX]
	var right: PackedVector3Array = right_arrays[Mesh.ARRAY_VERTEX]
	var border_x := data.chunk_cells.x * data.cell_size
	var left_heights: Dictionary = {}
	for vertex in left:
		if is_equal_approx(vertex.x, border_x):
			left_heights[vertex.z] = vertex.y
	var right_heights: Dictionary = {}
	for vertex in right:
		if is_zero_approx(vertex.x):
			right_heights[vertex.z] = vertex.y
	if left_heights.size() != right_heights.size() or left_heights.is_empty():
		return false
	for sample_z: float in left_heights:
		if not right_heights.has(sample_z) or not is_equal_approx(left_heights[sample_z], right_heights[sample_z]):
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
