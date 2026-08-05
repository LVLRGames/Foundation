# Foundation

Foundation is LVLR Studios' deterministic, data-first world and city generation addon for Godot 4.7.

The current Phase 1 baseline combines the Phase 0 chunked terrain subsystem with a renderer-independent spatial world model: centralized coordinates, stable IDs, spatial records and layers, chunk-bucket indexing, abstract regions/chunks, versioned serialization seams, and a disposable layered debug view.

Procedural roads, blocks, parcels, buildings, and other city generators are intentionally not implemented yet.

## Run the Phase 1 demo

1. Open the repository in Godot 4.7 and confirm **Project > Project Settings > Plugins > Foundation** is enabled.
2. Run the project. The main scene is `demo/spatial_model_demo.tscn`.
3. Toggle world, region, chunk, 4 m terrain-grid, record, and relationship overlays.
4. Select synthetic stable record IDs to inspect parent/child relationships.

The demo covers positive and negative chunk coordinates, region labels, dirty-chunk coloring, and records that span one or several chunk buckets. Its records are synthetic Phase 1 fixtures—not roads.

The Phase 0 terrain demonstration remains available at `demo/terrain_demo.tscn`.

## Locked spatial defaults

- terrain cell: 4 m by 4 m
- elevation step: 1 m
- chunk: 32 by 32 terrain cells
- chunk world size: 128 m by 128 m
- terrain chunk vertex region: 33 by 33 shared vertices
- region size: configurable in whole chunks
- future building modules: 1 m or 2 m while aligned to the 4 m grammar

All coordinate conversion goes through `FoundationCoordinateSystem`. Negative positions use floor division, so -1 m is in chunk -1 and -128 m is the beginning of chunk -1.

## Install and create a world

Copy `addons/foundation/` into another project's `addons/` directory and enable **Foundation**. Add a `FoundationWorld` node and optionally a `FoundationDebugView` child.

Runtime data can also be created without scene-tree nodes:

```gdscript
var metadata := FoundationWorldMetadata.new()
metadata.seed = 12345
metadata.world_bounds = Rect2(-256, -256, 512, 512)

var coordinates := FoundationCoordinateSystem.new()
var world := FoundationWorldData.new(metadata, coordinates)
world.initialize_default_layers()
world.initialize_partitions()

var record_id := FoundationSpatialId.make(
    metadata.seed,
    metadata.generator_version,
    metadata.content_pack_version,
    &"site",
    &"",
    "civic-center"
)
var record := FoundationSpatialRecord.new(
    record_id,
    &"site",
    &"feature",
    Rect2(-24, -16, 48, 32)
)
world.register_record(record)
```

Queries return stable-ID order:

```gdscript
var record := world.get_record(record_id)
var nearby := world.query_bounds(Rect2(-64, -64, 128, 128), [&"feature"])
var chunk_records := world.get_records_in_chunk(Vector2i(-1, 0), &"feature")
var dirty_chunks := world.mark_layer_dirty(&"feature", record.world_bounds)
```

## Terrain integration

Phase 0 terrain remains authoritative in `FoundationTerrainData`. `FoundationWorld.register_terrain_extent()` adapts its spatial extent into the terrain layer without moving or rewriting terrain arrays. Terrain generation, sampling, modification, rendering, and collision remain documented in [docs/architecture.md](docs/architecture.md).

## Validation

Run both acceptance suites with the installed Godot 4.7 executable:

```powershell
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_0_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_1_tests.gd
```

Phase 1 assertions cover negative coordinate boundaries, stable IDs, multi-chunk indexing, deterministic queries, dirty bounds, serialization, non-mutating debug providers, and the zero-work disabled debug path.

See [docs/spatial_model.md](docs/spatial_model.md) for the complete Phase 1 contracts, provider API, and revised roadmap. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for Phase 0 visual-reference attribution.
