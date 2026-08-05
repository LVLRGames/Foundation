# Foundation Phase 3 block-extraction contract

Phase 3 derives deterministic abstract city blocks from Phase 2 road centerline polylines. A block is a canonical bounded planar face with source-road provenance, metrics, spatial ownership, serialization, and disposable debug presentation. It is not a parcel, road reservation, district, building site, or rendered mesh.

## Data model

`FoundationWorldData` registers a default `blocks` layer containing `FoundationBlockRecord` values. Each record is Node-free `RefCounted` data with:

- a stable deterministic ID;
- a canonical counter-clockwise XZ outer boundary with one deterministic starting vertex;
- typed `FoundationBlockBoundaryReference` values that identify the source road edge, source polyline segment, parametric span, block-side index, and frontage length;
- sorted unique boundary-road IDs and frontage totals by road edge;
- area, perimeter, XZ bounds, polygon centroid, and a stable interior label point;
- inherited generated/locked/overridden state, source pass/version, tags, metadata, chunks, and regions;
- an explicit validation state and diagnostic messages seam.

Boundaries follow abstract road centerlines. Physical widths, curbs, setbacks, and parcel-ready insets belong to later phases.

## Extraction pipeline

`FoundationBlockExtractor.generate(world, profile)` performs six deterministic stages:

1. collect non-degenerate XZ segments from stable-ID-sorted road edges;
2. place segment bounds in deterministic uniform spatial buckets and compare only unique local candidate pairs;
3. split segments at at-grade crossings, shared points, and collinear overlap endpoints;
4. merge identical undirected fragments while retaining every source span as provenance;
5. prune degree-one open chains and walk directed half-edges with stable angular ordering;
6. retain positive bounded faces, reject invalid/small faces, normalize them, and register typed block records.

The exterior walk of each disconnected component has negative winding and is excluded. Open chains, dead ends, cul-de-sac spurs, duplicate fragments, degenerate rings, and self-intersecting or below-minimum faces do not become blocks.

```gdscript
var profile := FoundationBlockGenerationProfile.new()
profile.point_quantization = 0.01
profile.intersection_bucket_size = 128.0
profile.minimum_block_area = 16.0

var result := FoundationBlockExtractor.generate(world_data, profile)
assert(result.success)

var blocks: Array[FoundationBlockRecord] = world_data.get_blocks()
```

## Determinism and planar rules

The profile explicitly controls point quantization, intersection and collinearity tolerances, bucket size, minimum area, face-walk guard, generator version, and debug lift. Stable block identity hashes the canonical quantized boundary plus world seed/version context.

Every public block collection is stable-ID sorted. Candidate pairs, vertices, angular neighbors, half-edge starts, provenance, faces, boundary roads, diagnostics, chunk ownership, and region ownership have explicit stable ordering. Dictionary iteration, scene/node order, frame timing, runtime instance IDs, and thread completion order never define output.

XZ crossings are planar junctions by default. Road metadata may set `grade_separated = true` or a distinct `grade_level` to prevent an interior crossing from being split; exact shared endpoints remain connected. This is only a data-extraction rule and creates no physical intersection or traffic behavior.

The bucket diagnostics record input/planar/pruned segment counts, local candidate comparisons, unrestricted-pair reference count, bucket count, split crossings, exterior faces, and rejected faces. Timing is intentionally absent from deterministic identity and serialization.

## Concavity, metrics, and provenance

The extractor never assumes rectangles or a uniform grid. Consecutive duplicate and forward-collinear points are removed after face walking, while concave turns remain. The canonical polygon uses positive winding and rotates to the lexicographically smallest XZ vertex.

Area and centroid use the polygon shoelace formulas rather than bounds. If the centroid is outside a concave polygon, the stable label point comes from the largest deterministic triangulation triangle. Debug fill triangulation uses Godot's polygon triangulator, so L-shaped fills do not fan across their missing corner.

When adjacent source roads duplicate a shared centerline fragment, the working graph stores one geometric segment with all source spans. Each adjacent block receives consistent shared-boundary references and per-road frontage totals.

## Spatial ownership, regeneration, and serialization

Block bounds register through the existing chunk/region spatial index, including negative coordinates and boundaries spanning zero. World queries and abstract chunk references work through the same direct buckets as every earlier spatial record.

Regeneration removes only `GENERATED` Phase 3 records. `LOCKED` and `OVERRIDDEN` blocks are re-registered as the same objects so edited bounds refresh chunks, regions, and abstract chunk references. If an authored record occupies the stable ID of a newly extracted but different face, a deterministic repair ID preserves both records.

World manifests restore typed boundaries, boundary references, source spans, frontage, metrics, validation, authorship, ownership, generation profile, counts, and deterministic diagnostics. The format is versioned and Resource/JSON-friendly, but it is not a final persistence backend.

## Debug visualization

`FoundationBlockDebugProvider` emits canonical outlines, concave-safe translucent fills, and labels with stable ID, area, boundary-road count, and validation state. Generated, locked, overridden, selected, and invalid blocks have distinct semantic purposes. Diagnostics with locations use the invalid purpose.

All outlines share the existing batched line mesh and all fills share the existing batched triangle mesh. Labels are disposable `Label3D` objects. Disabling the block provider skips its invocation and creates no primitives. Debug elevation is applied only to copied presentation points.

## Explicit Phase 3 exclusions

- parcel subdivision or use assignment
- buildings, massing, facades, interiors, or prefabs
- district generation
- road meshes, curbs, sidewalks, lanes, markings, or production rendering
- physical intersection geometry, control, signs, signals, traffic rules, or simulation
- gameplay navigation or route-query APIs
- terrain grading, bridges, retaining structures, or building pads
- parking, public-space, or vegetation placement

The boundary and provenance contracts are extension seams for Phase 4 parcel subdivision and later physical road-width/setback processing.

## Validation

```powershell
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_0_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_1_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_2_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_3_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --quit-after 5 --verbose
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --editor --path . --quit-after 5 --verbose
```

The Phase 3 suite covers deterministic IDs/polygons/provenance/metrics/diagnostics, rectangular and concave loops, adjacent shared faces, crossing planarization, spurs/open chains, exterior and minimum-area rejection, disconnected components, signed boundaries, authored regeneration/reindexing/collisions, typed serialization, input non-mutation, concave-safe batched debug output, bounded large-graph candidate work, demo fixtures, and scope exclusions.
