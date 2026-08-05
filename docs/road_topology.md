# Foundation Phase 2 road-topology contract

Phase 2 turns Phase 1 city anchors, spatial records, and Phase 0 terrain into a deterministic renderer-independent road-planning graph. The visible output is disposable batched debug geometry. No road mesh, lane graph, gameplay navigation, traffic system, block, parcel, or terrain deformation is created.

## Data model

All authoritative types are `RefCounted` records with versioned dictionary serialization. No core road record inherits `Node`.

| Type | Responsibility |
| --- | --- |
| `FoundationRoadNode` | Stable graph vertex, terrain-sampled position, role, sorted incident edges, optional source anchor, anchor-connection intent, spatial ownership, and authorship state |
| `FoundationRoadEdge` | Ordered terrain-accurate centerline, endpoint IDs, functional class, physical-profile seam, direction/access/movement policy, logical-road ID, desired elevation, grading report, provenance, and spatial ownership |
| `FoundationLogicalRoad` | One continuing identity across an ordered edge chain, with continuity priority, provisional naming key, and endpoint semantic roles |
| `FoundationIntersectionRecord` | Abstract degree/connectivity, incoming/outgoing edge sets, class relationships, and provisional type at degree-three-or-higher nodes |
| `FoundationRoadPatternArea` | Minimal spatial input for district-style road growth; it is not a generated district |
| `FoundationRoadElevationSample` | Terrain elevation, desired elevation, cut/fill, grade violation, and bridge/retaining/water flags at one planning sample |
| `FoundationRoadValidationIssue` | Stable severity/code/message/record/location diagnostic consumed by serialization and debug presentation |
| `FoundationRoadGenerationResult` | Counts, terrain-search work, accepted/rejected candidates, mandatory-anchor count, validation issues, and errors |

`FoundationWorldData` registers dedicated `road_nodes`, `road_edges`, `logical_roads`, `road_intersections`, and `road_pattern_areas` layers. Nodes, edges, pattern areas, logical roads, and intersections use the existing chunk/region index and stable-ID ordering.

## Functional hierarchy versus physical form

The stable functional classes are:

1. `highway`
2. `arterial`
3. `collector`
4. `local`
5. `alley_service`
6. `dirt_road`

`road_class` describes network function. `physical_profile_key` is an independent future rendering seam. Directionality, access control, allowed movement modes, jurisdiction, abstract capacity, continuity priority, era, maintenance, and surface/style are likewise planning attributes rather than geometry. The generation profile defines hierarchy-sensitive preferred intersection spacing (64 m highway, 32 m arterial, 20 m collector, 12 m local, 8 m alley, and 24 m dirt by default). A validator reports spacing violations and direct highway-to-local/alley access as class-incompatible.

The centerline can represent orthogonal grids, 45-degree diagonals, stepped curves, low-segment polygonal curves, or selective smooth major-road curves. Future pixel-art materials, atlases, low-poly curbs, sidewalks, and intersection kits consume this data without changing topology identity.

## City-anchor connection logic

Every city anchor receives a stable road node and an explicit `optional`, `preferred`, or `mandatory` connection intent. City/civic centers, highway entrances, map exits, external destinations, and anchors with priority at least `0.9` are mandatory. High-priority endpoints reduce deterministic candidate selection cost, so major destinations participate before low-priority alternatives.

The generator terrain-routes every anchor pair, sorts candidates by weighted cost and stable pair identity, and applies a Kruskal minimum spanning tree. Preserved authored edges seed union-find from their actual valid endpoints. This guarantees major reachability while repairing the missing connection when an overridden edge changes endpoint identity. `extra_edge_count` adds deterministic resilience loops without perturbing the spanning tree.

Anchor nodes store source anchor ID, category, priority, connection intent, and terrain-sampled elevation. Anchors themselves are never mutated, including locked and overridden anchors.

## District-style pattern inputs

`FoundationRoadPatternArea` can be placed over a region, test area, mask envelope, or future anchor influence zone. It records orientation, spacing, segment limits, curvature/diagonal allowance, loop and branching preferences, cul-de-sac probability, intersection-spacing range, class weights, and terrain-following strength.

Built-in family keys are downtown grid, mixed-use grid, suburban loops and branches, industrial large-block rectilinear, rural terrain-following, trailer-park loop/spine, and custom/authored corridor. The current minimal generator demonstrates three visibly different families:

- downtown: orthogonal center/spokes with local streets and a collector connection;
- suburban: a low-segment loop with a branch and collector connection;
- rural: seed-varied terrain-following dirt spine with a collector connection.

Pattern nodes remain at or above configured intersection spacing and each pattern component connects to the nearest stable anchor node. This is a Phase 8 district-generation seam, not district generation.

## Terrain routing-cost model

The generation-only A* search reads authoritative `FoundationTerrainData` through `FoundationTerrainSampler`. Cost includes horizontal distance, squared slope, no-build/protected/water flags, explicit terrain surface penalties, and anchor importance. The profile also preserves weights for preferred corridors, existing-road connection bonuses, and district alignment so later passes can extend the cost function without changing edge serialization.

Neighbor order, heap comparison, equal-cost parent selection, candidate ordering, and result application all use explicit stable tie-breaks. If the expansion cap is reached, a deterministic straight-cell fallback preserves mandatory connectivity and records `used_fallback_route` plus an infeasible-segment grading requirement. Terrain arrays, revision, flags, surfaces, diagonals, and dirty state are never modified.

A deterministic downsampled cost field is stored in road-layer metadata for the batched routing-cost debug heatmap. It is planning/debug metadata, not a gameplay navigation grid.

## Desired elevation and grading reports

Authoritative route points stay terrain-accurate and terminate exactly at road-node positions. Desired road elevation is stored separately as samples along a linear endpoint profile. Each sample reports terrain elevation, desired elevation, cut depth, fill height, grade violation, retaining-wall candidate, bridge candidate, and water crossing.

Each edge summarizes maximum cut/fill, the functional-class grade limit, maximum violation, water/bridge/retaining candidates, and infeasible fallback state. This is unresolved planning data only. Phase 2 never calls terrain setters or emits cut, fill, bridge, retaining-wall, or approach geometry.

## Logical-road continuity

After adjacency is rebuilt, edges are considered in functional-class, generation-priority, and stable-ID order. At a node, continuation candidates must match functional class and physical profile. A deterministic score combines directional alignment, continuity priority, generation priority, and stable-ID tie-breaking. The best forward match keeps one logical-road identity; branches begin another identity.

Logical-road IDs derive from the canonical minimum edge ID in the chain. Records preserve ordered edge IDs, functional class, continuity priority, provisional naming key only, bounds, and start/end semantic roles. Final names and addresses are explicitly deferred.

## Abstract intersections and validation

Degree-three-or-higher nodes receive `FoundationIntersectionRecord` data with connected, incoming, and outgoing edges; degree; class-pair relationships; and `t_junction`, `crossroads`, or `complex_junction` classification. These are graph records only, with no lanes, turn paths, signals, signs, traffic controls, collision, or mesh.

`FoundationRoadTopologyValidator` reports:

- unreachable mandatory anchors and disconnected components;
- isolated nodes, missing endpoints, self-edges, and duplicate node-pair edges;
- centerline crossings without a shared abstract intersection node;
- edges below minimum length and overly close intersections;
- highway/local class incompatibility;
- desired-grade violations and unmarked water crossings;
- missing or inconsistent logical-road identity; and
- unsorted or duplicate adjacency that would expose nondeterministic ordering.

Crossing candidates are bounded through existing edge chunk buckets rather than a global all-edge inner-loop scan. Issues are sorted deterministically, serialized in road-layer metadata, and shown by the validation debug provider.

## Deterministic seed streams

Independent named streams are recorded in the generation profile and layer metadata:

- `road_anchor_candidates`
- `road_major_connections`
- `road_collectors`
- `road_local_growth`
- `road_loops`
- `road_dead_ends`
- `road_logical_identity`

Pattern variation derives a stable per-area seed from the appropriate named stream. No global random state, dictionary order, node instance ID, frame order, or thread completion order participates in graph identity.

## Regeneration, authorship, and serialization

Generated nodes, edges, logical roads, and intersections are replaceable. Locked and overridden records are re-registered in place, preserving authored object identity and refreshing chunk/region ownership after bounds changes. Generated edges route from preserved authored node positions. Derived incident adjacency is rebuilt from the actual surviving graph.

`regenerate_derived_topology()` rebuilds logical roads, intersections, adjacency, roles, and validation without rerouting terrain. `clear_generated_road_data()` removes only generated Phase 2 outputs and preserves authored records and pattern inputs.

World serialization restores typed records, stable IDs, centerlines, hierarchy/access fields, desired elevation/grading data, logical continuity, intersections, patterns, authorship, spatial ownership, generation profile, signed terrain origin, cost cells, candidates, counts, and validation issues.

## Batched debug and controls

Independent providers expose:

- road topology, hierarchy colors, node roles, logical identity, intersections, and dead ends;
- terrain routing-cost heatmap;
- accepted and rejected anchor connection candidates; and
- grading and topology validation warnings.

Lines and fills are appended to shared primitive buffers and rendered as one line mesh and one fill mesh. Debug labels are disposable. Visual elevation lift is applied only while copying authoritative points into the builder. A disabled provider performs no work, and visibility changes never regenerate topology.

The Phase 2 demo offers seed and road-profile selection; downtown, suburban, and rural test-area toggles; full versus logical/intersection-stage regeneration; clearing generated road data; debug-layer toggles; stable-record inspection; and generated/locked/overridden test-state controls. The editor debug dock exposes the same presentation layers and typed record details.

## Explicit Phase 2 non-goals

- final road, asphalt, dirt, curb, sidewalk, marking, retaining-wall, or bridge meshes;
- collision or physical intersection systems;
- blocks, parcels, buildings, or full districts;
- lane graphs, vehicle/pedestrian navigation, traffic lights/signs, or traffic simulation;
- terrain cuts, fills, pads, bridge approaches, or grading application;
- final road names or address generation.

## Validation commands

From the repository root with Godot 4.7:

```powershell
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_0_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_1_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_2_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --quit-after 5 --verbose
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --editor --path . --quit-after 5 --verbose
```
