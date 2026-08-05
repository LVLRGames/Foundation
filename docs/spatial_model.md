# Foundation Phase 1 spatial model

## Architectural rule

`FoundationWorldData` owns abstract world state. Renderers, debug overlays, editor UI, navigation, collision, and gameplay consume that data; none of them becomes authoritative.

The runtime `FoundationWorld` node is a scene-facing owner and manifest adapter. Every core model beneath it is `RefCounted` data with no editor-class or Node references.

```text
FoundationWorld
└── FoundationWorldData
    ├── FoundationWorldMetadata
    ├── FoundationCoordinateSystem
    ├── FoundationSpatialIndex
    ├── FoundationLayerRegistry
    │   ├── terrain
    │   ├── override
    │   └── future spatial layers
    ├── FoundationRegionData[]
    └── FoundationChunkData[]
```

Phase 1 deliberately contains no procedural road topology.

## Revised roadmap

1. Deterministic chunked terrain
2. Spatial world model, coordinates, stable IDs, layers/indexing, serialization seams, and debug visualization
3. Terrain-aware road graph topology and debug lines
4. Block extraction
5. Parcel subdivision
6. Primitive building massing
7. Expanded chunk streaming and LOD
8. Modular facade and building grammar
9. District generation
10. Terrain grading for roads, pads, and bridges
11. Parking and public features
12. Full authoring tools
13. Selective interiors
14. Advanced roads and traffic metadata

## Responsibilities

| Type | Responsibility |
| --- | --- |
| `FoundationWorldMetadata` | Seed/version context, content-pack version, world bounds, and generation metadata |
| `FoundationCoordinateSystem` | Every world, terrain cell/vertex, chunk, region, local-coordinate, bounds, and snapping conversion |
| `FoundationSpatialRecord` | Stable identity, XZ world bounds, ownership chunks, parent/children, tags, authorship state, and source pass |
| `FoundationSpatialLayer` | Register/unregister/query records, layer serialization, and layer/chunk dirty state |
| `FoundationSpatialIndex` | Direct stable-ID lookup and deterministic chunk-bucket bounds queries |
| `FoundationRegionData` | Large logical scheduling/manifest partition above chunks |
| `FoundationChunkData` | Abstract chunk bounds, layer references, dirty state, generation state, and future runtime-state seam |
| `FoundationLayerRegistry` | Stable layer registration independent of rendering |
| `FoundationDebugView` | Disposable rendering of provider output in editor or runtime |

The `terrain` and `override` layers are registered by default. Overrides remain separate from raw generator layers; the complete authored override editor is a later phase.

## Coordinate conventions

Foundation's planning plane uses `Vector2`/`Rect2` as world XZ: `Vector2.x` is world X and `Vector2.y` is world Z. Scene positions use `Vector3(x, elevation, z)`.

Defaults are 4 m cells, 1 m elevation steps, and 32-cell chunks. Chunk `(cx, cz)` starts at terrain cell `(cx * 32, cz * 32)` and spans 128 m on each horizontal axis.

Integer and world conversions always floor toward negative infinity. Important one-axis examples are:

| World meters | Chunk coordinate |
| ---: | ---: |
| -129 | -2 |
| -128 | -1 |
| -1 | -1 |
| 0 | 0 |
| 127 | 0 |
| 128 | 1 |

Cell -1 is local cell 31 of chunk -1. Shared vertex coordinates may be converted relative to either owning chunk by explicitly passing that chunk to `local_vertex_in_chunk()`.

`snap_1m()`, `snap_2m()`, and `snap_4m()` keep future interiors/building modules aligned with the locked world grammar.

World bounds and record bounds are half-open at their maximum edge for chunk ownership. A record ending exactly at 128 m does not spill into the next chunk unless its area extends past that edge.

## Stable ID strategy

`FoundationSpatialId.make()` hashes only explicit deterministic context:

- world seed
- generator version
- content-pack version
- entity type
- parent stable ID
- semantic key or deterministic local index supplied as a string

It never reads runtime instance IDs, node order, dictionary order, or thread completion order. Chunk and region helpers use readable signed-coordinate IDs such as `chunk_-3_5` and `region_0_-2`.

Callers must canonicalize complex semantic input before supplying the key. Passing an unordered Dictionary as identity is intentionally unsupported.

## Generated, locked, and overridden semantics

Every record stores one `AuthorshipState`:

- `GENERATED`: the owning pass may replace it during regeneration
- `LOCKED`: preserve the current generated result
- `OVERRIDDEN`: authored replacement or edit, normally stored in the separate override layer

`source_pass` and `source_version` identify the generator contract that produced a record. Phase 1 defines the state and storage seam but not the complete override-editing UI.

## Chunk-bucket spatial index

Registration computes all chunks intersected by a record's half-open XZ bounds. The index stores the stable ID in each bucket and keeps one direct ID-to-record map. A bounds query visits only intersected buckets, deduplicates IDs, filters exact bounds/layers, then sorts once by stable ID at the public boundary.

Internal dictionaries are not treated as ordered. No query scans all world records unless the caller explicitly requests `get_all_records()` for tooling/debugging.

`FoundationChunkData` mirrors per-layer stable-ID references for manifests and generation scheduling. It is not a rendered chunk node and already exposes the future Unloaded/DataOnly/ProxyLoaded/VisualLoaded/PhysicsLoaded/GameplayActive state seam.

## Serialization seam

`FoundationWorldData.to_dict()` produces a versioned, Resource/JSON-friendly manifest containing:

- metadata and world bounds
- coordinate settings
- sorted layer registrations and records
- stable record IDs and authorship state
- regions and chunks
- layer references and dirty state

`FoundationWorldData.from_dict()` restores the direct lookup and chunk buckets from record data. No Node references are serialized. The format version is explicit but Phase 1 does not freeze a final binary format or migration framework.

## Debug provider API

Debug visualization is non-authoritative. A `FoundationDebugProvider` reads world data and appends primitives to `FoundationDebugGeometryBuilder`:

```gdscript
class_name MyFutureProvider
extends FoundationDebugProvider

func _init() -> void:
    provider_id = &"future_layer"

func append_debug(world, builder, context) -> void:
    invocation_count += 1
    for record in world.get_layer(&"future_layer").get_records():
        builder.add_rect(record.world_bounds, 0.5, &"record_generated")
        builder.add_text(
            Vector3(record.world_bounds.get_center().x, 2.0, record.world_bounds.get_center().y),
            String(record.stable_id)
        )

debug_view.layer_registry.register_provider(MyFutureProvider.new())
```

The builder supports lines, polylines, polygon outlines/fills, XZ rectangles, AABB boxes, points, arrows, text labels, and heatmap cells. Lines and filled surfaces are converted into two batched meshes. Labels are disposable and rebuilt explicitly; they are never spatial records or gameplay nodes.

The centralized `FoundationDebugStyle` resource maps semantic purposes to colors. Providers should not scatter hard-coded palette values.

Global disablement returns before any provider invocation or geometry allocation. Individual disabled providers are skipped. The debug view does not process every frame; callers or the editor dock explicitly rebuild it.

Phase 1 default providers display world bounds, regions and IDs, chunk coordinates/dirty state, the 4 m terrain grid, selected grid coordinates, record bounds/IDs/layer membership, and selected parent/child relationships. Future generators register providers through the same registry.

## Editor workflow

Add or select a `FoundationWorld` with a `FoundationDebugView` child. The **Foundation Debug** dock can:

- enable/disable rendering globally
- toggle each default provider
- select the world, an abstract chunk, or a stable record
- show stable IDs, bounds, layers, and parent identity
- follow editor node selection
- rebuild debug presentation explicitly

Changing debug visibility never regenerates world or terrain data.

## Phase 1 limits

- No procedural roads, road graph, pathfinding, lanes, or intersections
- No final persistence backend or binary format
- No full streaming scheduler despite region/chunk state seams
- No complete override-authoring editor
- No quadtree; chunk buckets are the measured-default replacement seam
- Debug labels use a disposable pool of `Label3D` nodes, while line/fill geometry is batched
