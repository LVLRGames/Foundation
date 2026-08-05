# Phase 4 parcel subdivision

Phase 4 turns canonical Phase 3 block polygons into compact, renderer-independent `FoundationParcelRecord` data. It subdivides land only: districts, land use, buildings, parking, addresses, physical streets, grading, navigation, and traffic remain outside this phase.

## Data and frontage contracts

Every parcel stores a canonical counter-clockwise XZ boundary, stable parent-block identity, area/perimeter/centroid/label metrics, approximate frontage width and depth, signed chunk/region ownership, authorship state, and validation state. `FoundationParcelFrontageReference` maps parcel boundary segments back to the contributing block side, Phase 2 road edge, and logical road. A deterministic primary frontage is selected with local-access roads preferred over higher-control road classes.

Parcel kinds are `standard`, `corner`, `flag_access`, and `remainder`. Standard and corner parcels are buildable only when the configured area, frontage, and depth limits pass. Landlocked or otherwise ineligible pieces are never silently presented as ordinary buildable lots: larger pieces become explicit access-required records and small leftovers become explicit remainders.

## Deterministic subdivision and coverage

`FoundationParcelSubdivider` validates and canonicalizes each parent block, selects a stable split axis, and partitions its bounds into deterministic seeded strips. Each strip is intersected with the actual block polygon through `Geometry2D`, so concave and L-shaped blocks may yield multiple valid polygon components without rectangular assumptions.

The strips partition the full parent extent. Their clipped components therefore cover the parent polygon, including explicit remainder/access-required pieces. `FoundationParcelValidator` checks outside-parent geometry, overlap, area coverage, degeneracy, self-intersection, frontage/access rules, and road/logical-road provenance. Coverage tolerance is derived only from the serialized geometry profile.

The named seed streams are:

- `parcel_split_orientation`
- `parcel_split_spacing`
- `parcel_frontage_priority`
- `parcel_remainder_resolution`

No global RNG, dictionary order, node order, frame order, or timing affects identity.

## Regeneration, indexing, and serialization

Generated parcels are replaced on regeneration. Locked and overridden parcels remain the same objects and are reindexed from their current authored bounds. Stable-ID collisions use deterministic repair identities. The generator never mutates blocks, roads, logical roads, anchors, or terrain.

The `parcels` spatial layer serializes its typed records, profile, deterministic counts, coverage totals, and diagnostics through `FoundationWorldData`. Parcel queries use the existing chunk/region index and return stable-ID order.

## Debug and controls

The parcel debug provider batches outlines, concave-safe fills, primary and secondary frontage, corner/access/remainder colors, labels, selection, and located validation diagnostics. Disabling the provider performs no provider work. The runtime demo and editor debug dock can regenerate or clear generated parcels, toggle the parcel overlay, inspect records, and exercise locked/overridden states without coupling the records to scene nodes.

## Non-goals

Phase 4 does not implement district allocation, zoning/use assignment, addresses, buildings, parking, road/curb/sidewalk/driveway meshes, terrain cuts or fills, bridges, lanes, traffic, signals, navigation, vegetation, utilities, or public-space placement.
