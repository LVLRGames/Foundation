# Foundation Phase 2 road-topology contract

Phase 2 adds deterministic, terrain-aware abstract road topology to the Phase 1 spatial model. It produces data records only: no road mesh, lane geometry, gameplay navigation, traffic, intersection geometry, or terrain grading is part of this phase.

## Authoritative data model

`FoundationWorldData` owns two new default layers:

- `road_nodes`: `FoundationRoadNode` records, currently one anchor-kind node per city anchor
- `road_edges`: `FoundationRoadEdge` records connecting node stable IDs and storing a sampled route polyline

Both record types extend `FoundationSpatialRecord`, remain `RefCounted`, and serialize without scene-tree references. A road node stores its source anchor and sorted incident edge IDs. A road edge stores endpoint IDs, an open road-class vocabulary, terrain metrics, fallback status, and a `PackedVector3Array` route. Bounds are derived from that polyline so the existing chunk/region index can directly query every spatial bucket it crosses.

The route polyline is a generation artifact for later systems to consume. It is not a navigation path, does not expose a runtime route-query API, and does not instantiate geometry.

## Generator contract

`FoundationRoadTopologyGenerator.generate()` takes:

1. initialized `FoundationWorldData` containing Phase 1 city anchors;
2. authoritative `FoundationTerrainData`;
3. the signed global terrain-cell coordinate corresponding to local terrain cell `(0, 0)`; and
4. an optional `FoundationRoadGenerationProfile`.

The generator samples terrain but never mutates it or its anchors. Each eligible anchor receives a stable road-node ID derived from world seed/version context and anchor identity. Every anchor pair receives a deterministic route candidate. Candidates are sorted by weighted terrain cost and stable identity, then a Kruskal spanning tree selects the minimum connected topology. `extra_edge_count` may add the next cheapest non-tree candidates without changing the connectivity guarantee.

Anchor priority reduces a candidate's comparison weight, allowing important anchors to influence which terrain-routed links become topology edges while retaining deterministic tie-breaking. Public nodes, edges, ownership lists, adjacency, and queries are sorted by stable identity.

Example:

```gdscript
var profile := FoundationRoadGenerationProfile.new()
profile.slope_cost_weight = 18.0
profile.extra_edge_count = 1

var result := FoundationRoadTopologyGenerator.generate(
    world_data,
    terrain_data,
    Vector2i(-64, -64), # local terrain cell (0, 0) is global cell (-64, -64)
    profile
)
assert(result.success)

var nodes: Array[FoundationRoadNode] = world_data.get_road_nodes()
var edges: Array[FoundationRoadEdge] = world_data.get_road_edges()
```

## Deterministic terrain routing

The private generation-time cost-grid search uses fixed neighbor order and explicit cost, heuristic, coordinate, and stable-identity tie-breaks. It reads:

- sampled terrain height and the resulting slope between cell centers;
- no-build, protected, and water flags;
- rock, mud, wetland, and waterbed surface IDs; and
- the explicit weights in `FoundationRoadGenerationProfile`.

Slope cost is continuous. Flags and surfaces are penalties rather than absolute blockers so disconnected terrain still yields an abstract topology. If the configured expansion cap is reached, a stable straight-cell fallback is recorded on the edge instead of silently dropping anchor connectivity.

The same world metadata, anchors, terrain arrays, signed terrain origin, and profile reproduce the same stable IDs, selected edges, route points, and metrics. No global random state, instance ID, dictionary order, frame order, or scene-tree order participates in generation.

## Signed coordinates and spatial boundaries

Terrain arrays remain locally indexed from zero, while `terrain_origin_cell` maps them into the shared signed world grid. Global cell conversion floors toward negative infinity, matching `FoundationCoordinateSystem`: world `-1 m` belongs to chunk `-1`, and world `-128 m` begins chunk `-1` with the default 128 m chunk size.

Road-node point records resolve to one owning chunk. Road-edge bounds cover the entire route and are registered in every intersected chunk and region bucket, including routes that cross zero or a signed chunk/region boundary.

## Regeneration and serialization

Road layers carry the serialized generation profile, signed terrain origin, and terrain revision used to generate them. Road records use inherited authorship states:

- `GENERATED`: replaceable by the road-topology pass;
- `LOCKED`: preserved exactly on regeneration;
- `OVERRIDDEN`: preserved as authored data.

Generated edges route from preserved locked or overridden node positions, so an authored node adjustment remains meaningful on the next pass. Locked edges themselves are retained exactly. After generation, adjacency is rebuilt from the complete generated-and-preserved edge set. World serialization restores typed road nodes and edges, stable IDs, route points, terrain metrics, authorship, ownership, adjacency, and layer metadata. The format is versioned and Resource/JSON-friendly; it is not yet a final persistence backend.

## Debug visualization

`FoundationRoadTopologyDebugProvider` emits node crosses, route polylines, and optional labels containing node degree or edge class, ID, length, terrain cost, maximum slope, and ownership counts. Semantic colors distinguish generated, locked, and overridden records.

All topology line primitives flow through the existing `FoundationDebugGeometryBuilder` and are projected into one batched line mesh. Labels are disposable `Label3D` debug objects. Disabling the provider prevents its invocation and primitive allocation. Debug output is read-only and non-authoritative.

## Explicit Phase 2 exclusions

- road meshes or materials
- lane or carriageway geometry
- gameplay navigation, route-query APIs, or navigation meshes
- traffic simulation or agents
- intersection geometry or control logic
- terrain grading, cutting, filling, bridges, or retaining structures

The abstract IDs, open road class, route polylines, metadata, authorship states, and spatial ownership are deliberate extension seams for later phases.

## Validation

From the repository root with the configured Godot 4.7 executable:

```powershell
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_0_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_1_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_2_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --quit-after 5 --verbose
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --editor --path . --quit-after 5 --verbose
```

The Phase 2 suite covers complete deterministic reproduction, anchor connectivity and adjacency, height/slope/flag/surface influence, typed serialization, generated/locked/overridden regeneration behavior, negative coordinates, chunk/region boundaries, batched debug metadata, input non-mutation, and scope exclusions.
