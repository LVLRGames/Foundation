# Foundation

Foundation is LVLR Studios' reusable, deterministic world and city generation addon for Godot 4.7. Phase 0 supplies the production-oriented terrain foundation only: authoritative data, deterministic generation, query APIs, chunk rendering, matching collision, explicit surface IDs, semantic terrain edits, editor controls, and a development demo.

Roads, districts, blocks, parcels, buildings, interiors, traffic, vegetation, and the full streaming/LOD state machine are intentionally outside Phase 0.

## Run the Phase 0 demo

1. Open this repository as a Godot 4.7 project.
2. Confirm **Project > Project Settings > Plugins > Foundation** is enabled. It is enabled in this development project by default.
3. Run the project. `demo/terrain_demo.tscn` generates four 32×32-cell chunks from the visible seed.
4. Use **Same seed** to demonstrate reproducibility, **Next seed** to generate a different height grid, and WASD plus Q/E to inspect the terrain.

The default profile uses 4 m cells, 1 m height quantization, 32×32-cell chunks, and a 64×64-cell demo world. A full default chunk therefore covers 128×128 m and reads a 33×33 vertex region from shared authoritative data. The demo selects flat normals for a blockier retro appearance; `FoundationTerrain.smooth_normals` switches to an indexed shared-vertex mesh with globally consistent border normals.

## Install in another project

Copy `addons/foundation/` into the target project's `addons/` directory and enable **Foundation** in the Plugins tab. Add a `FoundationTerrain` node, assign or edit its `FoundationTerrainProfile`, then use the **Foundation Terrain** dock's explicit **Generate Terrain** action.

The dock exposes seed, terrain dimensions, cell size, height step, and noise controls. Editing values does not automatically rebuild terrain, which prevents accidental editor stalls on large profiles. **Rebuild Dirty Chunks** only refreshes chunks marked by data edits.

At runtime, the same path is available without editor classes:

```gdscript
var terrain := FoundationTerrain.new()
terrain.profile.seed = 12345
terrain.profile.grid_cells = Vector2i(64, 64)
add_child(terrain)
terrain.generate_terrain()
```

## Query and modify terrain

Consumers use `FoundationTerrainSampler`, not mesh nodes:

```gdscript
var sampler := terrain.get_sampler()
var height := sampler.get_height_at_world(Vector2(40.0, 72.0))
var slope := sampler.get_slope_degrees_at_world(Vector2(40.0, 72.0))
var surface_id := sampler.get_surface_at_world(Vector2(40.0, 72.0))
var buildable := sampler.is_buildable_at_world(Vector2(40.0, 72.0), 15.0)
```

Semantic edits write to `FoundationTerrainData` and mark only affected chunks. A vertex on a chunk border dirties every neighboring chunk that uses it:

```gdscript
var modifier := terrain.get_modifier()
modifier.add_height(Vector2i(32, 10), 1.0, FoundationTerrainData.ModificationSource.ROAD_FILL)
modifier.flatten(Rect2i(8, 8, 5, 5), 3.0, FoundationTerrainData.ModificationSource.BUILDING_PAD)
modifier.set_surface(Vector2i(9, 9), FoundationTerrainSurface.Type.CONCRETE)
terrain.rebuild_dirty_chunks()
```

Phase 0 records the last semantic modification source per vertex. A future layered grading stack can expand that seam without moving ownership into rendering nodes.

## Determinism contract

Foundation derives stable named sub-seeds instead of using uncontrolled `rand*()` calls or a single sequential RNG. Phase 0 uses independent `terrain_height` and `terrain_surface` streams; future systems can add roads, rivers, parcels, and buildings without perturbing existing output.

The reproducibility inputs stored by terrain data are:

- world seed
- Foundation generator version
- content-pack version
- complete terrain profile

Height generation explicitly applies `round(raw_height / height_step) * height_step`. The chosen diagonal for every cell is also stored in data so the sampler, visual mesh, and collision agree.

## Development assertions

Run the Phase 0 assertions with a Godot 4.7 executable:

```text
godot --headless --path . --script res://tests/run_phase_0_tests.gd
```

The suite checks same-seed reproduction, different-seed variation, exact quantization, shared chunk borders, boundary dirty propagation, read-only meshing, sampler queries, chunk creation, and collision geometry.

See [docs/architecture.md](docs/architecture.md) for data flow, coordinate conventions, chunk lifetime seams, and current limitations. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the visual reference attribution.
