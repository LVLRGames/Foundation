# Foundation

Foundation is LVLR Studios' deterministic, data-first world and city generation addon for Godot 4.7.

The current Phase 8 baseline combines chunked terrain, the renderer-independent spatial model and city anchors, deterministic terrain-aware road planning, city-block extraction, frontage-aware parcel subdivision, primitive building massing, modular facade grammar, deterministic district/land-use policy, and chunk streaming with terrain visual LOD. District data remains Node-free and records stable block coverage, character, use policy, suitability evidence, upstream lineage, and planning targets while keeping scene presentation disposable.

Addresses, interiors, prefabs, production building meshes/materials/collision, physical road geometry/intersections, traffic/navigation, terrain grading or pads, parking/public-feature placement, and vegetation are intentionally not implemented.

## Run the Phase 8 district-generation demo

1. Open `demo/spatial_model_demo.tscn` in Godot 4.7 and run the scene.
2. Enable **District coverage, character, and use policy** and optionally hide earlier overlays.
3. Inspect contiguous block membership, seed-influence links, character, primary/allowed uses, density, and validation labels.
4. Select **District generation + use policy** and regenerate to confirm same-seed stability.

District policies are abstract planning data. They do not grade terrain, assign addresses, place parking/public geometry, instantiate architecture, or create gameplay navigation and traffic.

## Run the Phase 7 facade grammar demo

1. Open `demo/spatial_model_demo.tscn` in Godot 4.7 and run the scene.
2. Enable **Facade bays, windows, and entrances** and optionally hide the earlier data layers.
3. Inspect primary, side, and rear edge roles plus deterministic floor/bay grids and the single semantic primary entrance.
4. Select **Modular facade grammar** in the stage control and regenerate to confirm same-seed stability.

Facade openings are renderer-independent grammar records. They are not final wall/window/door meshes, materials, collision, navigation portals, or interiors.

## Run the Phase 6 streaming demo

1. Open `demo/streaming_demo.tscn` in Godot 4.7 and run the scene.
2. Hold RMB and use WASD plus Q/E to fly across the 8×8 terrain.
3. Inspect the colored `Unloaded`/`Data`/`Proxy`/`Visual`/`Physics`/`Gameplay` chunk rings and LOD labels.
4. Pause, step one bounded streaming update, or reset the runtime lifecycle from the compact panel.

The camera is only a demo adapter. Core planning consumes Node-free `FoundationChunkInterest` data and is independent of rendering and frame timing.

## Run the Phase 5 demo

1. Open the repository in Godot 4.7 and confirm **Project > Project Settings > Plugins > Foundation** is enabled.
2. Run the project. The main scene is `demo/spatial_model_demo.tscn`.
3. Select a seed/profile and enable any combination of downtown-grid, suburban-loop, and rural terrain-following pattern areas.
4. Toggle topology, routing-cost, candidate, validation, block, parcel/frontage, and building-massing overlays.
5. Inspect stable pattern, node, edge, logical-road, intersection, block, parcel, or building records and exercise authorship states.
6. Hold the right mouse button to look around; use **WASD** to fly, **Q/E** to descend/ascend, **Shift** to boost, and the mouse wheel to adjust speed.
7. Press **H** or use the top-right button to hide/show the compact scrolling control panel while inspecting the city.

The demo generates a signed-origin terrain, Phase 2 roads, Phase 3 blocks, Phase 4 parcels, and Phase 5 footprints/massing. It keeps terrain and debug geometry upright in Godot's Y-up world, includes a concave L-shaped block, rectangular parcelized blocks, an open component that produces no false block, and a small access-required fixture that is explicitly skipped by building generation. It covers stable regeneration, frontage/corner setbacks, positive and negative ownership, validation, inspection, and authorship controls.

## Locked spatial defaults

- terrain cell: 4 m by 4 m
- elevation step: 1 m
- chunk: 32 by 32 terrain cells (128 m square)
- terrain chunk vertex region: 33 by 33 shared vertices
- region size: configurable in whole chunks
- building footprint quantization: configurable, with a default 0.01 m deterministic geometry grid

All coordinate conversion goes through `FoundationCoordinateSystem`. Negative positions use floor division, so -1 m is in chunk -1 and -128 m begins chunk -1.

## Generate parcel-aware building massing

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

var parcel_profile := FoundationParcelGenerationProfile.new()
var parcel_result := FoundationParcelSubdivider.generate(world_data, parcel_profile)
assert(parcel_result.success)

var building_profile := FoundationBuildingGenerationProfile.new()
building_profile.front_setback = 4.0
building_profile.side_setback = 2.0
building_profile.rear_setback = 4.0
var building_result := FoundationBuildingGenerator.generate(world_data, building_profile)
assert(building_result.success)

var facade_profile := FoundationFacadeGenerationProfile.new()
var facade_result := FoundationFacadeGenerator.generate(world_data, facade_profile)
assert(facade_result.success)

var district_profile := FoundationDistrictGenerationProfile.new()
var district_result := FoundationDistrictGenerator.generate(world_data, district_profile)
assert(district_result.success)

var blocks: Array[FoundationBlockRecord] = world_data.get_blocks()
var parcels: Array[FoundationParcelRecord] = world_data.get_parcels()
var buildings: Array[FoundationBuildingRecord] = world_data.get_buildings()
var facades: Array[FoundationFacadeRecord] = world_data.get_facades()
var districts: Array[FoundationDistrictRecord] = world_data.get_districts()
var signed_chunk_blocks := world_data.get_records_in_chunk(Vector2i(-1, 0), &"blocks")

var streaming_profile := FoundationChunkStreamingProfile.new()
var camera_interest := FoundationChunkInterest.new(&"primary_camera", Vector3.ZERO)
var streaming_plan := FoundationChunkStreamingScheduler.build_plan(
    world_data,
    [camera_interest],
    streaming_profile
)
var applied_transitions := FoundationChunkStreamingScheduler.apply_plan(
    world_data,
    streaming_plan
)
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
var parcels := world_data.get_parcels()
var buildings := world_data.get_buildings()
var facades := world_data.get_facades()
var districts := world_data.get_districts()
var parcel_district := world_data.get_district_for_parcel(parcels[0].stable_id)
```

Terrain, anchors, roads, blocks, parcels, buildings, and facades remain authoritative inputs and are not mutated. Phase 8 districts assign abstract character, allowed uses, and planning targets through lineage queries; terrain grading, addresses, production architecture, navigable entrances, parking/public geometry, and physical access remain later contracts.

## Validation

```powershell
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_0_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_1_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_2_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_3_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_4_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_5_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_6_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_7_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_8_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --quit-after 5 --verbose
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --editor --path . --quit-after 5 --verbose
```

See [docs/district_generation.md](docs/district_generation.md) for the Phase 8 district, membership, use-policy, regeneration, validation, and exclusion contract. Facades remain documented in [docs/facade_grammar.md](docs/facade_grammar.md), streaming in [docs/chunk_streaming.md](docs/chunk_streaming.md), and massing in [docs/building_massing.md](docs/building_massing.md). Earlier contracts remain in [docs/parcel_subdivision.md](docs/parcel_subdivision.md), [docs/block_extraction.md](docs/block_extraction.md), [docs/road_topology.md](docs/road_topology.md), [docs/spatial_model.md](docs/spatial_model.md), and [docs/architecture.md](docs/architecture.md). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for visual-reference attribution.
