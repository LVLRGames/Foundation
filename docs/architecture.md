# Foundation Phase 0 terrain architecture

Phase 1 spatial-world responsibilities are documented separately in [spatial_model.md](spatial_model.md). Terrain arrays remain authoritative and are adapted into the world model without being rewritten.

Phase 2 terrain-aware abstract road topology consumes these arrays without grading them; see [road_topology.md](road_topology.md).

Phase 3 block extraction consumes road centerlines without mutating terrain; see [block_extraction.md](block_extraction.md).

Phase 4 parcel subdivision consumes canonical blocks and road provenance without mutating any earlier layer. The Phase 11.1 corrective contract caps generation at four opposing street-facing rows and preserves unreached centers as explicit non-buildable land; see [parcel_subdivision.md](parcel_subdivision.md).

Phase 5 building generation consumes buildable parcels and their frontage provenance without mutating any earlier layer. Phase 11.1 adds default footprint span/depth/aspect caps and an explicit long-form exception seam; see [building_massing.md](building_massing.md).

Phase 6 plans bounded chunk lifecycle and terrain visual LOD transitions without mutating spatial records or terrain arrays; see [chunk_streaming.md](chunk_streaming.md).

Phase 7 projects deterministic modular facade grammar onto Phase 5 massing without creating production building meshes or mutating upstream records; see [facade_grammar.md](facade_grammar.md).

Phase 8 groups canonical blocks into Node-free district and land-use policy while leaving terrain and upstream city records unchanged; see [district_generation.md](district_generation.md).

Phase 9 creates a deterministic Node-free terrain-grading plan from canonical roads and buildings, then applies or safely reverts that plan through the authoritative terrain API; see [terrain_grading.md](terrain_grading.md).

Phase 10 consumes parcel/building/district/frontage/anchor intent to place deterministic Node-free parking facilities and public sites without mutating Phase 1–9 data; see [parking_public_features.md](parking_public_features.md).

Phase 11 applies explicit typed authoring instructions to Phase 1–10 spatial records, retains deterministic base/authored snapshots, and reconciles them after regeneration without silently running dependencies; see [authoring_overrides.md](authoring_overrides.md).

## Data first, rendering second

`FoundationTerrainGenerator` accepts a `FoundationTerrainProfile` and returns `FoundationTerrainData`. Generation performs no scene-tree mutations. The resulting packed arrays are the authority for heights, flags, surface IDs, per-cell diagonals, and dirty chunks.

`FoundationTerrainMesher` is a pure projection over one chunk rectangle. `FoundationTerrainChunk` owns disposable `MeshInstance3D` and collision nodes, while `FoundationTerrain` coordinates generation and dirty rebuilds. Visual and collision resources can be cleared independently, leaving the data queryable for later streaming states.

```text
FoundationTerrainProfile
        |
        v
FoundationTerrainGenerator --> FoundationTerrainData <-- FoundationTerrainModifier
                                      |
                     +----------------+----------------+
                     |                                 |
                     v                                 v
          FoundationTerrainSampler          FoundationTerrainMesher
                                                       |
                                            FoundationTerrainChunk
                                            (visual / collision)
```

No cell creates a node or material. One chunk creates one `ArrayMesh`, one `MeshInstance3D`, and—when collision is active—one concave collision shape. Smooth-normal mode uses the indexed 33×33 grid directly. Flat-normal mode duplicates triangle render vertices only where required for independent face normals. All chunks share one material unless a caller provides another shared material.

## Coordinates and chunk borders

Terrain grid coordinates use `Vector2i(x, z)`. Cell coordinates range from `(0, 0)` inclusive to `grid_cells` exclusive. Vertex coordinates include the final edge and therefore range through `grid_cells` inclusive.

World conversion is:

```text
world_x = grid_x * cell_size
world_z = grid_z * cell_size
```

Chunk `(cx, cz)` begins at cell `(cx * chunk_cells.x, cz * chunk_cells.y)`. A 32×32-cell chunk reads 33×33 vertices. Adjacent chunks read their common edge from the same `FoundationTerrainData` indices; neither chunk generates an independent border. Border normals also sample global authoritative neighbors.

Partial edge chunks are supported when world dimensions are not exact chunk multiples.

## Triangulation and collision agreement

Generation compares the height deltas of a cell's opposing corners and stores one of two deterministic diagonals. The visual mesh, concave collision faces, and `TerrainSampler`'s piecewise-linear world height interpolation all read that stored diagonal. Rebuilding a view does not recalculate the choice or mutate data.

## Surface and buildability data

Surface IDs are explicit cell data. Phase 0 generation renders grass, dirt, sand, and rock through shared material vertex colors, while the stable surface enum already reserves the categories named by the Phase 0 contract.

Cell flags currently include no-build, protected, and water. `TerrainSampler` combines those flags with a caller-selected maximum slope. Future roads, parcels, and buildings can query the same API without depending on `MeshInstance3D` nodes.

## Deterministic streams

`FoundationSeed.derive()` hashes the world seed with a named stream. Height and surface classification use separate `FastNoiseLite` instances. Adding or changing one subsystem cannot consume values from another subsystem's RNG sequence.

Terrain data records the generator and content-pack versions alongside the seed. Phase 0 does not implement save/load yet, but the reproducibility fields already have an authoritative home.

## Dirty rebuilds and Phase 6 streaming

A cell edit marks its containing chunk. A vertex edit examines the four adjacent cells, so vertices shared by chunk edges or corners dirty all affected chunks. `FoundationTerrain.rebuild_dirty_chunks()` consumes that set and independently rebuilds those chunk views.

`FoundationTerrainChunk.State` mirrors the abstract Unloaded, DataOnly, ProxyLoaded, VisualLoaded, PhysicsLoaded, and GameplayActive lifecycle. Phase 6 now supplies deterministic Node-free interest planning, hysteresis, bounded transitions, terrain proxy/visual LOD presentation, and separable full-resolution collision. Threaded jobs and persistence remain outside the current contract.

## Phase 0 limitations

- Noise generation is synchronous. Pure generation and meshing are separated so later work can move jobs off the main thread safely.
- Collision uses full-resolution concave triangle geometry. Lower-resolution collision proxies are a later streaming concern.
- The editor dock edits and generates a selected terrain node but does not persist generated runtime arrays into a scene or resource.
- Terrain modification records the last semantic source per vertex; non-destructive multi-layer composition and authored-data persistence remain future work.
- Surface rendering uses shared vertex colors rather than the final pixel-art texture/material library.
- Phase 6 supplies the first deterministic streaming state machine; asynchronous loading, persistence, and production city HLOD remain later work.
