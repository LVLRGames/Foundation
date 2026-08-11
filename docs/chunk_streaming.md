# Foundation Phase 6 deterministic chunk streaming and terrain LOD

Phase 6 turns the runtime-state seam established in Phase 1 into a deterministic, bounded streaming planner. The planner operates on `FoundationWorldData` and `FoundationChunkData`; it does not require scene nodes, cameras, renderers, files, threads, or frame timing. Terrain presentation is a separate consumer of applied transitions.

## Runtime data contract

Each abstract `FoundationChunkData` stores:

- the cumulative runtime state `Unloaded`, `DataOnly`, `ProxyLoaded`, `VisualLoaded`, `PhysicsLoaded`, or `GameplayActive`;
- `runtime_lod_level`, where `-1` means no visual presentation, `0` is the most detailed visual mesh, and larger values are progressively coarser;
- a monotonic `runtime_transition_serial` incremented once per applied lifecycle or LOD step;
- all existing layer references, dirty layers, generation state, and stable chunk identity.

These runtime fields serialize through the world manifest. Streaming never removes spatial records, changes stable IDs, changes generated/locked/overridden state, or mutates authoritative terrain arrays.

## Interest planning

`FoundationChunkInterest` is Node-free runtime data with a stable ID, world position, non-negative priority, and enabled state. Callers may create interests for cameras, players, editor probes, servers, or other consumers without putting those semantics into the planner.

`FoundationChunkStreamingProfile` defines nested chunk-distance bands for gameplay, physics, one or more visual LODs, proxy presentation, and data-only residency. Distance is deterministic Chebyshev chunk-ring distance, so every band is an axis-aligned ring in the canonical chunk grid and behaves consistently across signed coordinates.

`FoundationChunkStreamingScheduler.build_plan()`:

1. validates and stable-ID sorts enabled interests;
2. visits known chunks in canonical signed-coordinate order;
3. selects the strongest requested state and finest requested LOD from all interests;
4. applies an explicit exit hysteresis to state and LOD demotions;
5. emits at most one lifecycle or LOD step per chunk;
6. sorts release work first, farthest first, then acquisition work by interest priority, distance, and chunk coordinate.

The plan is immutable by convention and building it does not mutate world data. Duplicate or empty interest IDs, invalid bands, non-interest inputs, and work beyond `maximum_planning_operations` fail explicitly.

`apply_plan()` is the only metadata mutation step. It applies no more than `max_transitions_per_update`, rejects stale requests whose recorded source state no longer matches, and returns the exact transitions that were accepted. Replanning after each bounded apply deterministically converges on the same target regardless of interest registration order.

## Terrain presentation and LOD

`FoundationTerrain.generate_terrain(false)` creates authoritative terrain without eagerly creating chunk nodes. Applied transitions can then be projected through `apply_streaming_requests()`:

| Abstract state | Terrain presentation |
| --- | --- |
| `Unloaded` / `DataOnly` | no chunk scene node |
| `ProxyLoaded` | coarsest configured visual LOD, no collision |
| `VisualLoaded` | requested visual LOD, no collision |
| `PhysicsLoaded` / `GameplayActive` | requested visual LOD plus full-resolution collision |

Terrain LOD sampling uses powers-of-two over the authoritative vertex grid and always includes the exact final chunk edge. Adjacent chunks therefore read identical shared-border heights even at coarse LODs and on partial edge chunks. Coarse diagonals are chosen deterministically from the four sampled corner heights. LOD 0 continues to use the stored authoritative per-cell diagonal. Visual LOD never reduces physics collision fidelity and meshing never mutates terrain data.

The presentation adapter remains disposable. Demoting to `DataOnly` removes the terrain chunk node while leaving `FoundationTerrainData`, spatial records, and serialized chunk metadata intact.

## Debug, editor, and demo inspection

The shared debug registry contains a `streaming` provider with distinct colors for unloaded, data-only, proxy, near/far visual, physics, and gameplay states. Each chunk label exposes coordinate, runtime state, LOD, and transition serial. Disabled streaming debug performs no provider work.

The **Foundation Debug** editor dock can toggle this overlay and inspect runtime state, LOD, and transition serial for a selected chunk.

Run `res://demo/streaming_demo.tscn` in Godot 4.7 to inspect an 8×8 terrain:

- fly with RMB look, WASD, Q/E, Shift, and the mouse wheel;
- watch colored lifecycle/LOD bands follow the camera interest;
- pause automatic updates, apply one bounded step, or reset the lifecycle;
- inspect queued/applied transition counts and planner operation work.

## Explicit Phase 6 exclusions

- asynchronous/threaded jobs or background resource loading;
- disk/network persistence, chunk packages, cache eviction, or save migration;
- production building/road meshes, impostors, occlusion, HLOD atlases, or material streaming;
- navigation-region baking, gameplay entity spawning, multiplayer authority, or AI activation;
- terrain regeneration, grading, cuts, fills, pads, or collision decimation;
- predictive velocity corridors, portals, or platform-specific memory budgets.

The planner and transition contract are intended seams for those later systems, not substitutes for them.

## Validation

Run Phase 0 through Phase 6 with Godot 4.7, followed by the runtime demos and editor/plugin smoke test. The Phase 6 suite covers profile and interest serialization, signed distance bands, multi-interest order independence, non-mutating planning, hysteresis, bounded convergence, stale requests, release priority, runtime manifest state, record/authorship preservation, terrain LOD reduction and shared borders, full-resolution collision, data-only terrain generation, disposable presentation, debug disablement, demo inspection, and explicit scope exclusions.
