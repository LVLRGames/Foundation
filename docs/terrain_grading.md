# Foundation Phase 9 terrain grading

Phase 9 converts existing road elevation intent and building footprints into a deterministic, Node-free terrain-grading plan. Planning is read-only. Applying or reverting a plan is always explicit and changes only `FoundationTerrainData`; road, block, parcel, building, facade, and district records remain untouched.

## Data contract

`FoundationTerrainGradingProfile` serializes all grading policy: per-road-class half-width/priority, blend widths, pad apron, bridge clearance/approach length, cut/fill limits, protected/water policy, work cap, tolerance, and debug elevation. No grading behavior depends on editor state or hidden constants.

`FoundationTerrainGradingPlan` captures the world/terrain seeds, terrain origin/shape/quantization, source revision, profile, canonical operations, resolved row-major vertex edits, diagnostics, work counts, and lifecycle state (`planned`, `applied`, or `reverted`). `FoundationTerrainGradingOperation` records stable source lineage plus a canonical source-record fingerprint, kind, priority, bounds, elevation range, owned edit keys, and kind-specific metadata. `FoundationTerrainGradingEdit` records one unique local terrain vertex, original/target height, original/target provenance, owner operation, and blend weight.

The operation kinds are road corridor, building pad, bridge span, and bridge approach. Bridge spans are deck intent and deliberately own no terrain edits.

## Deterministic planning and overlap resolution

Road segments rasterize only their expanded cell-space envelopes. Centerline elevation interpolates canonical desired elevation samples (or route elevations when samples are absent). Full corridor width receives the desired elevation; shoulders blend to the existing terrain. Cut and fill are clamped to explicit profile limits and quantized by `FoundationTerrainData`.

Building pads rasterize the footprint plus apron/blend envelope. The interior is flat. When a valid primary road exists, the pad elevation is sampled deterministically from that road's desired elevation; otherwise the footprint terrain median (or a clipped centroid fallback) is used.

Every candidate contribution has an explicit priority. Building pads win over bridge approaches, bridge approaches win over road corridors, and road classes have serialized hierarchy. Equal-priority conflicts resolve by blend weight and stable operation/segment identity. The final plan owns no duplicate vertex edits and is sorted row-major. Candidate work stops at the serialized cap.

## Bridges and protected terrain

Contiguous bridge-marked road samples become bridge spans with source-road/segment lineage, start/end deck positions, elevation range, and clearance. Terrain beneath the span is never flattened or filled. Adjacent non-span segments within the configured approach distance use `BRIDGE_APPROACH` provenance.

By default, any vertex touching protected or water cells is excluded from terrain edits. Profiles may explicitly allow those categories, but the choice is serialized and validated. Bridge spans preserve water regardless because they contain no edits.

## Apply, validate, and revert

`FoundationTerrainGrader.create_plan()` performs no terrain or world-record writes. `apply_plan()` first validates the complete plan, source lineage/fingerprints, terrain identity, source revision, and every original height/provenance value. Any terrain or upstream-source mismatch rejects the entire plan before the first write. A valid application uses `FoundationTerrainData.set_vertex_height()`, so height quantization, modification provenance, cell-diagonal refresh, revision increments, and shared-border dirty-chunk propagation remain authoritative.

`revert_plan()` similarly verifies that every affected vertex still matches the applied target height and provenance before restoring anything. Later terrain edits therefore cannot be silently overwritten. A safe revert restores original heights and modification sources in reverse canonical order.

`FoundationTerrainGradingValidator` is read-only. It recomputes plan identity/shape policy, operation order and uniqueness, source types, edit ownership/accounting/order/uniqueness, bounds, quantization, blend range, cut/fill limits, protected/water policy, provenance, and—when requested—applied height/source agreement.

`FoundationTerrainData.to_dict()` and `from_dict()` round-trip authoritative height, flag, provenance, surface, diagonal, revision, and dirty-chunk arrays. World manifests round-trip the typed current grading plan.

## Debug, editor, and demo

The `terrain_grading` debug provider shows road corridors, pads, bridge spans/approaches, cut/fill deltas, labels, and located diagnostics. Disabling it skips invocation and primitive allocation.

The Foundation Debug dock provides explicit **Plan / Apply Terrain Grading** and **Revert Terrain Grading** actions when the selected `FoundationWorld` has registered terrain data. `demo/spatial_model_demo.tscn` generates and applies a Phase 9 plan after districts, exposes the grading overlay, and adds a grading-only regeneration stage.

## Explicit Phase 9 exclusions

Phase 9 does not implement:

- production road, curb, sidewalk, driveway, foundation, retaining-wall, tunnel, or bridge meshes, materials, or collision;
- bridge supports, structural engineering, or final clearance certification;
- production parking/public-space geometry; abstract parking and public-feature placement is implemented in Phase 10;
- addresses, traffic/lane simulation, navigation, vegetation, utilities, interiors, or production building rendering;
- background jobs, a persistence backend, migration framework, or non-destructive terrain-layer compositing.

## Validation

Run `res://tests/run_phase_9_tests.gd` after the Phase 0–8 suites, then run the runtime demo and editor/plugin smoke checks. The focused suite covers deterministic plans and terrain snapshots, planning immutability, priority resolution, cut/fill/pad/approach provenance, flat frontage-aligned pads, span preservation, protected/water safeguards, chunk-border dirtying, typed round trips, read-only validation, stale/corrupt/unsafe-revert rejection, work caps, disabled-debug zero work, editor/demo controls, and scope exclusions.
