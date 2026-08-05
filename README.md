# Foundation

Foundation is LVLR Studios' deterministic, data-first world and city generation addon for Godot 4.7.

The current Phase 3 baseline combines chunked terrain, the renderer-independent spatial model and city anchors, terrain-aware abstract road topology, and deterministic city-block extraction. Blocks are canonical bounded planar faces with source-road provenance, irregular/concave polygon support, metrics, signed spatial ownership, versioned serialization, authored regeneration states, and batched debug presentation.

Parcels, buildings, districts, physical road geometry, traffic/navigation, intersection systems, terrain grading, parking, and vegetation are intentionally not implemented.

## Run the Phase 3 demo

1. Open the repository in Godot 4.7 and enable **Project > Project Settings > Plugins > Foundation**.
2. Run `demo/spatial_model_demo.tscn`.
3. Toggle terrain/spatial, anchor, road-topology, and block overlays.
4. Select stable road or block IDs to inspect abstract metrics and ownership.

The demo includes terrain-aware Phase 2 roads, a concave L-shaped Phase 3 loop that produces a block, and an open road component that correctly produces none. Block outlines and concave fills share the disposable debug batches. The original terrain-only scene remains at `demo/terrain_demo.tscn`.

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
var road_result := FoundationRoadTopologyGenerator.generate(
    world_data,
    terrain_data,
    terrain_origin_cell,
    FoundationRoadGenerationProfile.new()
)
assert(road_result.success)

var block_profile := FoundationBlockGenerationProfile.new()
block_profile.minimum_block_area = 16.0
var block_result := FoundationBlockExtractor.generate(world_data, block_profile)
assert(block_result.success)

var blocks: Array[FoundationBlockRecord] = world_data.get_blocks()
var signed_chunk_blocks := world_data.get_records_in_chunk(Vector2i(-1, 0), &"blocks")
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
