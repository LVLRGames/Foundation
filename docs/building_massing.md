# Phase 5 parcel-aware building footprints and primitive massing

Phase 5 turns eligible Phase 4 parcels into compact, renderer-independent `FoundationBuildingRecord` data. It establishes footprint, setback, frontage-orientation, coverage, floor-count, height, and gross-floor-area contracts only. It does not assign land use or architectural content and does not create production scene nodes, meshes, collision, navigation, or terrain modifications.

## Data contract

`FoundationWorldData` registers a dedicated `buildings` layer. Each building is Node-free `RefCounted` data with:

- a stable deterministic ID and parent parcel/block identity;
- a canonical counter-clockwise XZ footprint, bounds, area, perimeter, centroid, and stable interior label point;
- actual and seeded target parcel-coverage ratios;
- front, side, rear, and corner-side setback inputs;
- the primary parcel-frontage segment plus source road-edge and logical-road identity;
- an outward frontage direction and stable orientation angle;
- base elevation, floor count, floor height, total height, gross floor area, flat-roof kind, and `extruded_footprint` massing kind;
- signed chunk/region ownership, generation source/version, tags, metadata, authorship state, and validation state/messages.

The base elevation is an explicit profile value. Phase 5 does not sample or grade terrain, create pads, or resolve stepped foundations.

## Footprint generation

`FoundationBuildingGenerator.generate(world, profile)` processes parcels in stable-ID order and creates at most one primary massing record for each eligible parcel. A parcel must be valid, buildable, directly accessible, geometrically usable, and have a valid primary frontage reference.

Generation proceeds deterministically:

1. inset the parcel by the configured side setback with `Geometry2D`;
2. clip against a frontage-oriented strip that enforces primary-front and rear depths;
3. clip corner parcels behind each secondary road-frontage setback;
4. retain the largest valid component using area and canonical-boundary tie-breaks;
5. apply a bounded offset search until the seeded target coverage is met;
6. quantize, canonicalize, and validate the footprint;
7. derive floor count from its independent named seed stream and store a flat-roof extrusion envelope.

This works with concave parcels and never substitutes a parcel bounding rectangle for the actual parcel polygon. If offsets or coverage constraints leave less than the minimum footprint area, generation records a located `setbacks_exhaust_parcel` diagnostic and creates no false building. Non-buildable, access-required, and remainder parcels receive explicit skip diagnostics.

The named seed streams are:

- `building_footprint_coverage`
- `building_floor_count`

No global RNG, dictionary order, node order, frame order, timing, or rendered geometry affects output identity.

## Stable identity, authorship, and serialization

The primary building ID derives from world seed/version context, parent parcel stable ID, and the semantic key `primary_massing`. It does not depend on runtime node identity. Same seed, content version, profile, and parcels reproduce IDs, footprint geometry, ordering, coverage, and height.

Regeneration removes generated buildings and preserves locked or overridden buildings as the same objects. Preserved records are re-registered so authored bounds refresh chunk and region ownership. If an authored record occupies a generated identity with different geometry, a deterministic repair identity preserves both.

World manifests restore typed building records and layer metadata, including the versioned profile, deterministic counts, area totals, diagnostics, footprint/frontage provenance, massing metrics, authored states, and spatial ownership.

## Validation

`FoundationBuildingValidator` reports deterministic issues for:

- missing parent parcels or mismatched parent blocks;
- buildings attached to non-buildable/access-required parcels;
- degenerate or self-intersecting footprints;
- footprints outside their parent parcel;
- below-minimum area or excessive coverage;
- invalid, inconsistent, or excessive height/floor massing;
- missing or inconsistent primary-frontage road/logical-road provenance.

Read-only validation does not mutate records. Applied validation updates generated building state/messages only; locked and overridden records remain authored authority.

## Debug and inspection

`FoundationBuildingDebugProvider` copies authoritative footprint/massing data into the shared batched debug buffers. It emits base/top outlines, vertical extrusion edges, concave-safe roof fills, labels, selection emphasis, authorship colors, and located diagnostics. It does not create one node per building or mutate world data. Disabling the provider skips its invocation and performs no provider work.

The runtime demo and editor debug dock can:

- generate/regenerate or clear generated buildings independently;
- toggle parcel and building overlays independently;
- inspect stable parcel/block/frontage provenance, footprint area, coverage, floors, height, ownership, and validation;
- exercise generated, locked, and overridden states;
- confirm same-seed regeneration and downstream clearing behavior.

## Explicit Phase 5 exclusions

- district, zoning, or land-use assignment
- addresses, final names, entrances, driveways, or service access geometry
- facade grammar, windows, doors, roofs beyond the flat envelope, interiors, or prefabs
- production meshes, materials, collision, occlusion, or LOD
- terrain sampling, cuts, fills, pads, retaining walls, foundations, or bridges
- parking, loading, utilities, public space, street furniture, or vegetation
- pedestrian/vehicle navigation, lanes, traffic, signs, or signals

## Validation commands

From the repository root with Godot 4.7:

```powershell
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_0_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_1_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_2_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_3_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_4_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --script res://tests/run_phase_5_tests.gd
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --path . --quit-after 5 --verbose
& 'D:\Program Files\Godot\v4.7\Godot_v4.7-stable_win64.exe' --headless --editor --path . --quit-after 5 --verbose
```

The Phase 5 suite covers same-seed identity, eligible seed variation, frontage-oriented setbacks, coverage and massing metrics, concave/corner parcels, explicit skip/exhaustion diagnostics, signed coordinates, authored regeneration/reindexing, typed serialization, input non-mutation, read-only validation, zero-work debug disabling, bounded larger fixtures, runtime demo controls, and Phase 6+ scope exclusions.
