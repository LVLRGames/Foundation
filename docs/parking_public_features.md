# Foundation Phase 10 parking and public features

Phase 10 turns Phase 4–9 parcel, building, district/use, road-frontage, anchor, and elevation intent into deterministic parking facilities and public-site placements. Both outputs are renderer-independent spatial records. They contain planning geometry and policy evidence, not scene nodes, production art, traffic, or navigation.

## Data layers and records

`FoundationWorldData` registers `parking_facilities` and `public_features` by default. Stable-order getters and lineage helpers resolve records by parcel, block, building, district, and source anchor.

`FoundationParkingFacilityRecord` stores a canonical site footprint, parcel/block/building/district lineage, road/frontage access provenance, orientation/elevation, demand, supply, accessible/bicycle counts, unmet demand, compact `FoundationParkingSpace` values, and abstract `FoundationParkingAccessPath` aisle/access polylines. Parking spaces are ordered by row, column, then stable ID. Paths and spaces are values beneath one spatial facility record; they are not separate indexed nodes.

`FoundationPublicFeatureRecord` stores a canonical site footprint and position, parcel/block/district lineage, optional source anchor, feature kind, orientation/elevation, access provenance, capacity, service radius, and suitability evidence. Built-in kinds are park, plaza, playground, transit stop, civic marker, and landmark site. The vocabulary is intentionally extensible.

All records retain the shared generated/locked/overridden state, source pass/version, tags, metadata, validation state, and signed chunk/region ownership.

## Deterministic policy and bounded work

`FoundationSiteFeatureGenerationProfile` is the complete versioned policy input. It serializes parking-demand ratios by land use, stall/accessibility/aisle dimensions, site clearances, default and per-use public-site area fractions, anchor influence and service radii, geometry tolerances, record limits, per-parcel candidate limits, a global operation cap, and debug elevation.

Independent named seed streams isolate eligible variation:

- `parking_facility_priority`
- `parking_layout`
- `public_feature_priority`
- `public_feature_variation`

Generation never uses the global random-number state, scene order, runtime IDs, frame timing, or dictionary iteration as an output-order authority. Stable IDs include the world seed, generator/content versions, record kind, parent identity, semantic kind, and canonical footprint key.

Public sites are reserved first. Civic, institutional, and open-space assignments are eligible without an anchor; public-square, transit-node, landmark, and civic-center anchors provide explicit kind/lineage preference. Candidate rectangles are tested in a deterministic seeded order against their parcel and all existing building/authored/generated site reservations. Layer metadata reconciles public target count, generated coverage, and unserved targets with located diagnostics.

Parking demand derives from the member land use plus building gross floor area, or a bounded parcel-area fallback when a building does not exist. Direct frontage is required. A valid residual site is filled with compact row/column spaces up to the configured demand/facility cap, with deterministic accessible-space assignment and abstract aisle paths. Demand that cannot be supplied remains explicit as unmet demand and a stable diagnostic.

Candidate evaluation is bounded per parcel and by a global operation cap. Exceeding the global cap removes partial generated Phase 10 output, preserves authored records, and reports a deterministic error.

## Authorship and regeneration

Regeneration removes generated parking/public records and retains locked or overridden records as the same objects. Retained geometry is remeasured and reindexed, then reserved before new placement. A parent parcel with an authored Phase 10 record is not given a duplicate generated record of the same layer. Stable-ID conflicts use deterministic repair identities. `clear_generated()` removes both generated layers and reports per-layer counts without deleting authored records.

Editor/demo pipelines clear generated Phase 10 data before replacing an upstream parcel, building, facade, district, or grading result. Regenerating Phase 10 itself can consume the currently applied Phase 9 state without reverting that terrain plan.

## Validation and serialization

`FoundationSiteFeatureValidator` is read-only. It checks:

- typed parent, building, district, anchor, and access lineage;
- canonical footprint bounds/area/centroid and containment in the parent parcel;
- building/public/parking reservation overlap;
- supported facility/feature kinds and policy ranges;
- parking-space identity, dimensions, placement, ordering, and accessible counts;
- demand/supply/unmet-demand accounting;
- signed chunk ownership and stored profile/work-cap metadata.

World manifests restore typed parking/public records and compact space/path values. Geometry, counts, evidence, authorship, diagnostics, metadata, and ownership survive the round trip with no Node references.

## Debug, editor, and demo

The `parking_facilities` debug provider batches site fills/outlines, stall rectangles, accessible spaces, aisle/access paths, demand labels, and located diagnostics. The `public_features` provider batches site fills/outlines, markers, service-radius rings, anchor links, and labels. Generated, locked, overridden, invalid, warning, and selected states use centralized semantic colors. A disabled layer does not invoke its provider or allocate primitives.

The Foundation Debug dock exposes parking/public toggles plus explicit **Generate / Regenerate Parking + Public Features** and **Clear Generated Parking + Public Features** actions. `demo/spatial_model_demo.tscn` runs Phase 10 after districts and terrain grading, includes a Phase 10-only regeneration stage, supports record inspection/authorship states, and shows parking and public-feature overlays independently.

## Explicit Phase 10 exclusions

Phase 10 does not implement:

- the full override/authoring workflow planned for Phase 11;
- selective interiors planned for Phase 12;
- advanced lanes, traffic control, or simulation planned for Phase 13;
- production parking/public-space meshes, markings, materials, collision, furniture, vegetation, or prefabs;
- driveable road connections, vehicle/pedestrian navigation, or occupancy simulation;
- addresses, utilities/services, economy, or population simulation;
- new terrain edits or grading ownership.

## Validation

Run `res://tests/run_phase_10_tests.gd` with Godot 4.7 after the Phase 0–9 suites, followed by runtime and editor/plugin smoke checks. The focused suite covers reproducibility and seed variation, demand accounting, residual placement, access lineage, ordered/accessible stalls, anchor/use selection, overlap avoidance, signed/multi-chunk ownership, authorship preservation, typed round trips, lineage queries, upstream immutability, corruption diagnostics, debug batching/disablement, work caps, editor/demo controls, and explicit exclusions.
