# Foundation Phase 13 advanced-road and traffic-metadata contract

Phase 13 deterministically derives lane cross-sections and intersection movement/control policy from the authoritative Phase 2 road graph. It is a renderer-independent, Node-free planning layer. It creates no road meshes, driveable navigation, runtime vehicles, traffic simulation, collision, signal props, signs, markings, or terrain edits.

## Data model

Two spatial records own Phase 13 output:

| Type | Responsibility |
| --- | --- |
| `FoundationRoadCrossSectionRecord` | One Phase 2 edge's logical-road/profile lineage, carriageway/median/shoulder/sidewalk widths, speed policy, source fingerprint, validation state, and ordered lanes |
| `FoundationIntersectionTrafficRecord` | One Phase 2 intersection's node lineage, control type, ordered approaches, permitted movements, optional signal phase groups, source fingerprint, and validation state |

Nested `FoundationRoadLane`, `FoundationTrafficApproach`, and `FoundationTurnMovement` values have versioned dictionary serialization and their own stable IDs. They remain compact values inside their owning spatial record rather than inflating the shared spatial index. The new `road_cross_sections` and `intersection_traffic` layers participate in chunk/region ownership, typed world serialization, authoring, and bounds queries.

## Cross-section policy

The default right-hand-traffic profile derives physical planning metadata from Phase 2 functional class without altering road centerlines:

| Class | Lanes per available direction | Lane width | Speed | Abstract hourly capacity per lane |
| --- | ---: | ---: | ---: | ---: |
| highway | 2 | 3.6 m | 100 km/h | 1900 |
| arterial | 2 | 3.2 m | 60 km/h | 1500 |
| collector | 1 | 3.2 m | 50 km/h | 1200 |
| local | 1 | 3.2 m | 35 km/h | 900 |
| alley/service | 1 | 2.8 m | 20 km/h | 300 |
| dirt | 1 | 3.2 m | 30 km/h | 450 |

`two_way` and `divided_concept` edges receive both directions. One-way edges receive only their declared direction. A divided concept reserves a configurable median; highways reserve shoulder intent, while urban non-highway/non-dirt profiles reserve sidewalk intent. These widths are planning inputs for later renderers, not generated surfaces.

Each lane centerline is a deterministic lateral offset of the complete terrain-aware route. Reverse lanes store points in their actual travel order. Two-lane directions assign left/through permission to the inner lane and through/right permission to the outer lane; a one-lane direction permits all three. Pedestrian permission remains an edge/right-of-way concern and is not copied into a motor/bicycle travel lane.

## Approaches, movements, and controls

Every degree-three-or-higher Phase 2 intersection receives one traffic record. Each connected edge becomes an approach with canonical outward bearing, hierarchy priority, and explicit inbound/outbound lane membership derived from edge directionality.

Permitted movements connect an inbound lane to one matching outbound lane on another approach. They classify the signed XZ change as `left`, `through`, or `right`, retain a stable lane-pair ID, hierarchy/turn priority, a conflict-group key, and a three-point visualization hint. The hint is not a splined drive path, a navigation edge, or a promise of vehicle clearance.

Control selection is deterministic:

- highway approaches or a two-class hierarchy gap use `priority` control;
- qualifying four-or-more-way arterial intersections use `signal_plan`;
- other generated intersections use `all_way_stop`.

Signal plans group permitted movement IDs by inbound approach. They express an abstract phasing seam only—no timing engine, amber interval, detector, controller cabinet, light object, or traffic-state machine exists.

## Identity, regeneration, and authorship

Spatial record IDs derive from world seed, Phase 13 generator version, content-pack version, entity type, Phase 2 parent ID, and policy key. Lane IDs derive from cross-section ID plus direction/index. Approach IDs derive from traffic-record ID plus road-edge ID. Movement IDs derive from traffic-record ID plus inbound lane, outbound lane, and turn class.

Canonical-ID collisions use deterministic ordinal repair keys. Output and nested values are stable-ID sorted before serialization. Source fingerprints cover only the Phase 2 fields consumed by the pass and let validation report stale derived metadata.

Regeneration removes only generated Phase 13 records. Locked and overridden cross-sections and intersection-traffic records are re-registered intact, including stable ID, nested values, metadata, tags, and authorship state. Phase 2 nodes, edges, logical roads, intersections, centerlines, adjacency, directionality, and terrain evidence are read-only inputs.

## Bounded generation and validation

`FoundationTrafficMetadataProfile` caps cross sections, intersection records, lanes per edge, movements per intersection, and total generation operations. Edge/intersection record caps fail before mutation. An operation-cap failure removes partial generator-owned Phase 13 output while retaining authored data.

`FoundationTrafficMetadataValidator` checks:

- Phase 2 parent, node, edge, logical-road, and lane lineage;
- globally unique nested IDs and canonical stable ordering;
- directionality, dimensions, speeds, capacity, modes, and turn permissions;
- complete finite lane centerlines and finite movement hints;
- movement approach/lane membership and absence of U-turn records;
- signal phase membership and control compatibility;
- generated canonical or collision-repaired identity;
- source-topology fingerprint drift;
- chunk ownership and stored cap accounting.

Diagnostics are stable-sorted and copied into both Phase 13 layer metadata dictionaries.

## Serialization, authoring, debug, demo, and editor

World manifests restore both typed records and all nested lane/approach/movement data. The Phase 11 codec translates lane centerlines and movement hints, and the authoring policy supports both new layers and record kinds. Translation changes spatial coordinates only; it does not silently regenerate downstream data.

The `traffic_metadata` debug provider batches lane polylines, movement hints, control points, and labels. Forward/reverse lanes, turn classes, control types, authored states, and validation severities use centralized semantic colors. Global debug disablement invokes no provider and allocates no primitives.

The main demo generates Phase 13 after the existing Phase 2–12 pipeline, offers an independent visibility toggle and regeneration stage, supports stable-record/authorship inspection, and keeps the existing fly camera plus hideable compact panel. The editor debug dock offers the same toggle, typed record details, generate/regenerate, and generated-only clearing actions.

## Explicit non-goals

- production roads, curbs, sidewalks, shoulders, medians, markings, signs, or signal meshes;
- vehicle, bicycle, or pedestrian navigation graphs;
- runtime vehicles, pedestrians, agents, path following, queues, demand assignment, or traffic simulation;
- physical signal timing, detection, coordination, pre-emption, or adaptive control;
- intersection swept-path/clearance engineering or legal traffic-code completeness;
- collision, physics, audio, materials, lighting, terrain grading, or scene nodes;
- addresses, parking-driveway routing, transit schedules, utilities, or vegetation.

## Validation commands

Run `tests/run_phase_13_tests.gd` with Godot 4.7, then the complete Phase 0–13 test sequence, main/terrain/streaming demo smokes, and an editor smoke before publishing.
