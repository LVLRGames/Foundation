# Foundation

Foundation is LVLR Studios' deterministic, data-first world and city generation addon for Godot 4.7.

The current Phase 2 baseline combines chunked terrain, the renderer-independent Phase 1 spatial model and city anchors, and deterministic terrain-aware abstract road topology. Roads exist as stable node and edge records with terrain-routed polylines, spatial ownership, versioned serialization, authorship states, and batched debug presentation.

Road meshes, lane geometry, gameplay navigation, traffic, intersections, and terrain grading are intentionally not implemented.

## Run the Phase 2 demo

1. Open the repository in Godot 4.7 and confirm **Project > Project Settings > Plugins > Foundation** is enabled.
2. Run the project. The main scene is `demo/spatial_model_demo.tscn`.
3. Toggle world, region, chunk, terrain-grid, anchor, relationship, and road-topology overlays.
4. Select stable anchor, road-node, or road-edge IDs to inspect abstract data and routing metadata.

The demo generates a signed-origin Phase 0 terrain, registers it with the Phase 1 world, and connects three anchors with Phase 2 topology. It covers negative coordinates, chunk/region labels, state-colored road records, route costs and slope metadata. The original terrain-only scene remains at `demo/terrain_demo.tscn`.

## Locked spatial defaults

- terrain cell: 4 m by 4 m
- elevation step: 1 m
- chunk: 32 by 32 terrain cells
- chunk world size: 128 m by 128 m
- terrain chunk vertex region: 33 by 33 shared vertices
- region size: configurable in whole chunks
- future building modules: 1 m or 2 m while aligned to the 4 m grammar

All coordinate conversion goes through `FoundationCoordinateSystem`. Negative positions use floor division, so -1 m is in chunk -1 and -128 m is the beginning of chunk -1.

## Create terrain, anchors, and topology

Copy `addons/foundation/` into another project's `addons/` directory and enable **Foundation**. Runtime data can be created without scene-tree nodes:

```gdscript
var metadata := FoundationWorldMetadata.new()
metadata.seed = 12345
metadata.world_bounds = Rect2(-256, -256, 512, 512)

var coordinates := FoundationCoordinateSystem.new()
var world := FoundationWorldData.new(metadata, coordinates)
world.initialize_default_layers()
world.initialize_partitions()

var anchor := FoundationCityAnchor.create(
    metadata,
    FoundationCityAnchor.CATEGORY_CIVIC_CENTER,
    Vector3(32, 0, -16),
    "primary-civic-center",
    24.0,
    0.9
)
world.register_record(anchor)

var terrain_profile := FoundationTerrainProfile.new()
terrain_profile.seed = metadata.seed
terrain_profile.grid_cells = Vector2i(128, 128)
var terrain := FoundationTerrainGenerator.generate(terrain_profile)
var terrain_origin_cell := Vector2i(-64, -64)

var road_profile := FoundationRoadGenerationProfile.new()
var result := FoundationRoadTopologyGenerator.generate(
    world,
    terrain,
    terrain_origin_cell,
    road_profile
)
assert(result.success)
```

When using a scene-facing `FoundationWorld` node, call its `register_terrain_extent()` helper to expose the terrain footprint through the spatial index. The topology generator itself consumes the authoritative terrain arrays directly.

Queries return stable-ID order:

```gdscript
var nearby := world.query_bounds(Rect2(-64, -64, 128, 128))
var road_nodes := world.get_road_nodes()
var road_edges := world.get_road_edges()
var chunk_edges := world.get_records_in_chunk(Vector2i(-1, 0), &"road_edges")
```

Phase 0 terrain remains authoritative in `FoundationTerrainData`. Topology generation reads its heights, slopes, flags, and surfaces without moving, grading, or rewriting its arrays.

## Validation

Run the complete acceptance and smoke set with Godot 4.7:

```powershell
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_0_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_1_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_2_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --quit-after 5 --verbose
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --editor --path . --quit-after 5 --verbose
```

See [docs/road_topology.md](docs/road_topology.md) for the Phase 2 contract, deterministic cost model, regeneration semantics, serialization, and exclusions. Phase 1 spatial contracts are in [docs/spatial_model.md](docs/spatial_model.md), and Phase 0 terrain architecture is in [docs/architecture.md](docs/architecture.md). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for visual-reference attribution.
