# Foundation Phase 8 district generation and land-use policy

Phase 8 groups eligible Phase 3 blocks into deterministic, contiguous planning districts. Each district records character, primary and allowed land uses, density/height/intensity targets, upstream intent, member suitability evidence, authorship, spatial ownership, and validation. The output is Node-free planning data, not rendered city content.

## Data and lineage contract

`FoundationWorldData` registers a `districts` spatial layer and exposes stable-order `get_districts()` results. `FoundationDistrictRecord` stores sorted member block IDs, complete member-block boundary components, total area, bounds, centroid/label point, character, use policy, source anchor/pattern IDs, road exposure, access score, style/content policy keys, normalized targets, and ordered `FoundationDistrictMemberAssignment` values.

Each member assignment stores district/block identity, one primary use, sorted allowed uses, suitability, density/intensity targets, optional authored parcel/building-use overrides, and deterministic evidence. Assignments are compact values owned by the district record; they are not spatial records or scene nodes.

Lineage remains query-only. Use `get_district_for_block()`, `get_district_for_parcel()`, `get_district_for_building()`, or `get_district_for_facade()` without writing district identity back into upstream records.

## Bounded allocation

The generator builds block adjacency from chunk-bucket candidates and exact shared canonical boundary spans. Each unique candidate pair is tested once. Diagnostics record candidate comparisons, the unrestricted pair reference, accepted adjacency edges, expansion work, skipped blocks, and caps.

Explicit city-anchor and road-pattern intent raises deterministic seed priority. District growth uses stable frontier ordering, shared-boundary length, and road-crossing penalties: compatible local/collector boundaries are preferred while arterials and highways resist cross-boundary grouping. Target/max block counts, maximum district area, neighbor-expansion work, and total operation work are explicit profile inputs.

Disconnected generated components form separate districts. Authored records may explicitly opt into multi-component membership; otherwise validation requires boundary contiguity. Every valid eligible block is assigned exactly once; invalid blocks are skipped with located diagnostics. Member polygons are deterministically unioned into canonical exterior components, so irregular and concave coverage remains lossless while internal member seams do not masquerade as district boundaries. Validation derives the same union from membership and recomputes metrics directly.

## Character and land use

Built-in characters are downtown core, mixed-use center, residential neighborhood, industrial employment, civic/institutional, suburban neighborhood, and rural edge. Built-in uses are residential, commercial, mixed use, industrial, civic, institutional, open space, agricultural, and undeveloped. Both vocabularies are explicit serialized policy seams for later content packs.

Character selection combines source-anchor category, containing road-pattern family, building-floor evidence, and the named `district_character` stream. Anchor/category preferences and all numeric character targets are explicit versioned profile data. Policy targets use the independent `district_policy_variation` stream. Member uses use `district_member_use`; seed tie variation uses `district_seed_priority`. No result depends on global RNG, dictionary iteration, node order, frame timing, editor state, or thread completion order.

District records expose style/content policy keys for later adapters, but Phase 8 does not instantiate meshes, materials, prefabs, or occupancy.

## Stable identity, authorship, and regeneration

District IDs hash world/version context, policy identity, canonical seed identity, and sorted member block IDs. Assignment IDs hash district identity plus block identity.

Regeneration removes generated districts and preserves locked/overridden records as the same objects. Valid authored membership reserves claimed blocks before generated allocation. Preserved records refresh their metrics and spatial ownership. Duplicate/missing authored claims are diagnosed, and generated stable-ID collisions receive repeatable repair identities. `clear_generated()` never removes authored records.

Replacing upstream generated blocks, parcels, buildings, or facades clears generated district policy first in the editor/demo pipeline. Authored districts remain available for validation and repair.

## Validation and serialization

`FoundationDistrictValidator` checks missing/duplicate/overlapping/unassigned blocks, stable member order, contiguity, complete boundary coverage, recomputed area/bounds/centroid, block/area caps, supported character/use policy, normalized target ranges, source references, complete ordered assignments, assignment identities, lineage, and allowed-use consistency. Read-only validation does not mutate records.

World manifests restore typed districts and assignments, policies, boundaries, evidence, diagnostics, authored state, and signed chunk/region ownership. Layer metadata preserves the versioned profile, policy ID, deterministic counts, bounded-work statistics, and diagnostics.

## Debug, editor, and runtime demo

The `districts` debug provider batches translucent character fills, component/inter-district outlines, seed influence arrows, labels, selection/authorship states, and located diagnostics. Disabling the provider bypasses invocation and primitive allocation.

The editor dock and `demo/spatial_model_demo.tscn` expose district visibility, selection details, explicit generation/clearing, authored-state inspection, and same-seed regeneration. Presentation is disposable and never becomes authoritative district state.

## Explicit Phase 8 exclusions

Phase 8 does not implement:

- terrain grading, road cuts/fills, pads, and bridge approaches (implemented in Phase 9; see [terrain_grading.md](terrain_grading.md)); retaining structures remain excluded;
- parking and public-feature placement (implemented in Phase 10; see [parking_public_features.md](parking_public_features.md));
- full override-authoring tools (Phase 11);
- interiors, rooms, portals, or vertical circulation (Phase 12);
- advanced lanes, traffic control, or traffic simulation (Phase 13);
- addresses or final names;
- production meshes, materials, collision, prefabs, or architectural content packs;
- gameplay navigation, vegetation, utilities, services, economy, population, or occupancy simulation.

## Validation

Run `res://tests/run_phase_8_tests.gd` with Godot 4.7 after the Phase 0–7 suites, then run the runtime and editor/plugin smoke checks. The Phase 8 suite covers determinism and variation, exactly-once coverage, bounded adjacency, disconnected components, road barriers, anchor/pattern character influence, policy consistency, signed ownership, authored preservation/reindexing/repair, typed round trips, lineage queries, upstream non-mutation, read-only validation, batched/disabled debug behavior, operation caps, demo/editor controls, and scope exclusions.
