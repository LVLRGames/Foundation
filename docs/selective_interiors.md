# Foundation Phase 12 selective interiors

Phase 12 adds deterministic, renderer-independent interior topology for explicitly selected buildings and floors. It is deliberately opt-in: an empty request performs no work, and the generator never expands a request into city-wide interiors.

## Authority and inputs

`FoundationInteriorGenerationRequest` names building IDs and either explicit floor indices or an explicit all-floors switch. The profile caps selected buildings, floors, rooms, portals, connectors, and generation operations. Invalid requests fail before world mutation; missing buildings or out-of-range floors produce stable diagnostics and are skipped.

Generation consumes authoritative Phase 5 building footprints/massing, the Phase 7 primary-facade entrance module when available, and Phase 8 district/use lineage. It does not mutate those layers. Regenerating a selected building replaces only generator-owned interiors for that building and preserves locked or overridden records.

## Data contract

Each `FoundationInteriorRecord` lives in the `interiors` layer and retains building, parcel, block, district, and use lineage plus a source-building fingerprint. A record owns:

- selected `FoundationInteriorFloor` values with elevation, clear height, and usable footprint components;
- complete non-overlapping `FoundationInteriorRoom` coverage, including explicit circulation and small service fragments;
- `FoundationInteriorPortal` relationships between adjacent rooms and one exterior entrance on a generated ground floor;
- `FoundationInteriorVerticalConnector` relationships between consecutive selected floors.

Room and portal geometry is two-dimensional world-space data nested beneath the record. Stable identities derive from the world seed, generator/content versions, parent identity, floor, and canonical geometry/topology keys. The world manifest, typed codec, translation workflow, chunk ownership, authoring policy, editor controls, and disposable debug renderer all understand the new record kind.

## Geometry and topology rules

Usable floor space is derived by insetting the actual building footprint, including rotated, concave, and signed polygon input. A frontage-oriented bounded grid is clipped to the usable components. Every retained fragment becomes a room so the stored room area covers the usable area; small fragments are marked as service rooms instead of silently discarded.

Interior portals are placed only on shared room boundaries. Standard rooms require the profile's full shared-wall clearance; explicit clipped service fragments may use a narrower, provenance-tagged service access so no retained area becomes unreachable. Each floor identifies a circulation room, and validation requires all rooms to be reachable through the portal graph. A generated ground floor has exactly one exterior portal, carrying facade and entrance-module provenance when available. Consecutive selected floors have one abstract stair connector between circulation rooms.

## Validation and diagnostics

`FoundationInteriorValidator` checks lineage and building drift, floor and operation caps, usable containment, room coverage/accounting, room and portal identity, ground-entry cardinality, per-floor connectivity, consecutive-floor connectors, and chunk ownership. Applying validation state is optional; validation itself does not repair geometry.

The `interiors` debug provider renders a selected floor's room plans, portal segments, entrances, vertical connectors, labels, and invalid state as disposable batched geometry. Disabling the registry remains a zero-provider, zero-primitive path.

## Explicit exclusions

Phase 12 does not create scene nodes, production meshes or materials, walls/ceilings, furniture, collision, navmeshes, runtime doors, elevators, utilities, addresses, occupants, traffic, or gameplay simulation. Portals and connectors are abstract topology records for later systems. Phase 13 remains the advanced-road and traffic-metadata contract.
