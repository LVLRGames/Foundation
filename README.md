# Foundation

Foundation is LVLR Studios' deterministic, data-first world and city generation addon for Godot 4.7.

The current Phase 3 baseline combines chunked terrain, the renderer-independent spatial model and city anchors, deterministic terrain-aware road planning, and deterministic city-block extraction. Roads include functional hierarchy, district-style pattern inputs, logical-road identity, abstract intersections, desired elevation and grading reports, and validation. Blocks are canonical bounded planar faces with source-road provenance, irregular/concave polygon support, metrics, signed spatial ownership, versioned serialization, authored regeneration states, and batched debug presentation.

Parcels, buildings, full districts, physical road geometry/intersections, traffic/navigation, terrain deformation, parking, and vegetation are intentionally not implemented.

## Run the Phase 3 demo

1. Open the repository in Godot 4.7 and confirm **Project > Project Settings > Plugins > Foundation** is enabled.
2. Run the project. The main scene is `demo/spatial_model_demo.tscn`.
3. Select a seed/profile and enable any combination of downtown-grid, suburban-loop, and rural terrain-following pattern areas.
4. Toggle topology, routing-cost, candidate, validation, and block overlays.
5. Inspect stable pattern, node, edge, logical-road, intersection, or block records.

The demo generates a signed-origin terrain, connects five anchors plus three pattern areas with the expanded Phase 2 graph, and adds a concave L-shaped Phase 3 fixture that produces a block plus an open component that correctly produces none. It covers negative coordinates, hierarchy colors, logical continuity, intersections, terrain costs, grading warnings, block metrics, and chunk/region ownership. The original terrain-only scene remains at `demo/terrain_demo.tscn`.

## Locked spatial defaults

- terrain cell: 4 m by 4 m
- elevation step: 1 m
- chunk: 32 by 32 terrain cells (128 m square)
- terrain chunk vertex region: 33 by 33 shared vertices
- region size: configurable in whole chunks
- future building modules: 1 m or 2 m aligned to the 4 m grammar

All coordinate conversion goes through `FoundationCoordinateSystem`. Negative positions use floor division, so -1 m is in chunk -1 and -128 m begins chunk -1.

## Generate blocks from roads

Copy `addons/foundation/` into another project's `addons/` directory and enable **Foundation**. After creating Phase 0 terrain, Phase 1 anchors, and Phase 2 road topology:

```gdscript
var metadata := FoundationWorldMetadata.new()
metadata.seed = 12345
metadata.world_bounds = Rect2(-256, -256, 512, 512)

var coordinates := FoundationCoordinateSystem.new()
var world_data := FoundationWorldData.new(metadata, coordinates)
world_data.initialize_default_layers()
world_data.initialize_partitions()

var anchor := FoundationCityAnchor.create(
    metadata,
    FoundationCityAnchor.CATEGORY_CIVIC_CENTER,
    Vector3(32, 0, -16),
    "primary-civic-center",
    24.0,
    0.9
)
world_data.register_record(anchor)

var downtown := FoundationRoadPatternArea.create(
    metadata,
    "downtown-core",
    Rect2(-96, -96, 128, 128),
    FoundationRoadPatternArea.DOWNTOWN_GRID
)
world_data.register_record(downtown)

var terrain_profile := FoundationTerrainProfile.new()
terrain_profile.seed = metadata.seed
terrain_profile.grid_cells = Vector2i(128, 128)
var terrain := FoundationTerrainGenerator.generate(terrain_profile)
var terrain_origin_cell := Vector2i(-64, -64)

var road_profile := FoundationRoadGenerationProfile.new()
var road_result := FoundationRoadTopologyGenerator.generate(
    world_data,
    terrain,
    terrain_origin_cell,
    road_profile
)
assert(road_result.success)

var block_profile := FoundationBlockGenerationProfile.new()
block_profile.minimum_block_area = 16.0
var block_result := FoundationBlockExtractor.generate(world_data, block_profile)
assert(block_result.success)

var blocks: Array[FoundationBlockRecord] = world_data.get_blocks()
var signed_chunk_blocks := world_data.get_records_in_chunk(Vector2i(-1, 0), &"blocks")
```

When using a scene-facing `FoundationWorld` node, call its `register_terrain_extent()` helper to expose the terrain footprint through the spatial index. The topology generator itself consumes the authoritative terrain arrays directly.

Queries return stable-ID order:

```gdscript
var nearby := world_data.query_bounds(Rect2(-64, -64, 128, 128))
var road_nodes := world_data.get_road_nodes()
var road_edges := world_data.get_road_edges()
var logical_roads := world_data.get_logical_roads()
var intersections := world_data.get_road_intersections()
var blocks := world_data.get_blocks()
```

Terrain, anchors, road nodes, and road edges remain authoritative inputs and are not mutated. Phase 3 polygons follow abstract road centerlines; road widths, setbacks, and parcel-ready insets are later contracts.

## Validation

```powershell
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_0_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_1_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_2_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_3_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --quit-after 5 --verbose
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --editor --path . --quit-after 5 --verbose
```

See [docs/block_extraction.md](docs/block_extraction.md) for the Phase 3 planarization, canonical face, provenance, regeneration, performance, and debug contracts. Earlier contracts remain in [docs/road_topology.md](docs/road_topology.md), [docs/spatial_model.md](docs/spatial_model.md), and [docs/architecture.md](docs/architecture.md). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for visual-reference attribution.
