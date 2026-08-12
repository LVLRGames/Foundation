# Foundation Phase 7 modular facade and building grammar

Phase 7 projects deterministic architectural grammar onto Phase 5 building massing without turning presentation into authoritative data. Each eligible footprint edge produces one typed, Node-free `FoundationFacadeRecord`; its compact `FoundationFacadeModule` array describes a floor-by-bay grid of wall, window, and entrance modules.

The records are suitable inputs for a later mesh, prefab, material, or content-pack adapter. Phase 7 itself creates no production meshes, scene nodes, materials, collision, navigation, interiors, addresses, districts, uses, or terrain changes.

## Inputs and ownership

`FoundationFacadeGenerator.generate(world_data, profile)` consumes, but does not mutate:

- canonical `FoundationBuildingRecord.footprint` edges;
- building base elevation, height, floor count, and floor height;
- building-to-parcel/block lineage;
- the building primary-frontage direction and the parcel primary-frontage segment;
- world seed, generator version, and content-pack version.

Facade records live in the dedicated `facades` spatial layer. `parent_id` is the source building stable ID; parcel and block IDs are retained explicitly. The source footprint segment index, endpoints, outward normal, signed chunk/region ownership, source pass/version, authorship state, and validation state are serialized.

## Facade roles

Exactly one eligible footprint edge is selected as the primary facade. Selection first aligns edge outward normals with the building's primary frontage direction, then uses distance to the authoritative parcel frontage as a stable tie-break. Opposing edges are rear facades; remaining edges are sides. This supports irregular and concave footprints without assuming four sides or axis alignment.

The primary facade owns exactly one semantic ground-floor entrance module. This is grammar data, not a navigable doorway, address, curb cut, or instantiated door.

## Modular grid

The versioned `FoundationFacadeGenerationProfile` controls:

- grammar identity;
- preferred, minimum, and maximum bay width;
- maximum bays per edge and total operation cap;
- opening margins, window sill/height, and entrance dimensions;
- primary, side, and rear window probabilities;
- geometric tolerance and debug surface offset;
- the named `facade_module_pattern` and `facade_entrance_bay` seed streams.

Bay counts are chosen deterministically inside the configured width range. Every facade contains exactly one module per `(floor_index, bay_index)` cell. A wall module occupies the full cell; a window or entrance module stores its opening rectangle in physical horizontal/vertical facade coordinates. The record also stores the selected grammar ID, bay width/count, pattern phase, entrance module ID, and glazing ratio.

No global RNG, dictionary order, node order, frame timing, or thread completion order affects identity or layout. Stable facade IDs derive from world seed/version context, parent building ID, and source edge index. Module IDs derive from facade identity plus floor and bay indices.

## Regeneration and authored states

Regeneration replaces generated facade records and preserves locked or overridden records as the same objects. Preserved records are re-registered so authored segment edits refresh their spatial ownership. If an authored record occupies the expected generated ID with different geometry, the generated counterpart receives a deterministic repair ID.

`FoundationFacadeGenerator.clear_generated()` removes generated facade records only. Editor and demo pipeline actions clear generated facades before replacing upstream buildings or parcels; authored records remain available for validation and repair.

## Validation

`FoundationFacadeValidator` reports stable diagnostics for:

- missing building parents or mismatched parcel/block lineage;
- source segment geometry that no longer matches the parent footprint;
- degenerate facade planes or building-massing mismatches;
- invalid bay counts and widths;
- incomplete, duplicated, out-of-range, or unsupported module cells;
- module rectangles outside the facade plane;
- missing, duplicated, elevated, or non-primary entrances;
- invalid glazing ratios and per-building primary-facade counts.

Read-only validation does not mutate records. Applying validation state updates generated records only.

## Debug and editor presentation

The `facades` debug provider batches facade outlines, floor/bay grids, window rectangles, entrance rectangles, labels, and located diagnostics through the shared debug builder. It creates no node per facade or module. Disabling the layer bypasses provider work completely.

The runtime demo and editor dock can generate, clear, inspect, select, and toggle facade grammar independently. Visibility changes rebuild disposable debug presentation without regenerating world data.

## Explicit Phase 7 exclusions

Phase 7 does not implement:

- district, zoning, land-use, occupancy, or address assignment;
- production wall/window/door meshes, materials, textures, shaders, collision, or prefabs;
- architectural content packs or style selection from district/use data;
- roofs beyond the Phase 5 abstract flat-roof massing marker;
- interiors, rooms, vertical circulation, portals, or selective interior loading;
- terrain pads, grading, foundations, retaining structures, bridges, or road geometry;
- parking, service access, navigation, lanes, traffic, vegetation, props, or utilities;
- streaming-specific building HLOD or asynchronous facade jobs.

## Validation command

Run `res://tests/run_phase_7_tests.gd` with Godot 4.7 after the Phase 0–6 suites. The Phase 7 suite covers deterministic identity and seed variation, facade roles, complete floor/bay grids, primary entrances, signed spatial ownership, authorship preservation and repair IDs, typed manifest/profile round trips, non-mutation, read-only validation, disabled-debug zero work, bounded larger fixtures, demo controls, and scope exclusions.
