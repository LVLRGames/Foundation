# Foundation Phase 11 authoring and overrides

Phase 11 turns the authorship seam established in Phase 1 into an explicit, deterministic workflow for Phase 1–10 spatial records. It supports locking generator output, applying typed modifications, creating authored records, deleting records with tombstones, reverting overrides, reconciling overrides after regeneration, and bounded undo/redo. The authoritative model remains Node-free; the editor dock and runtime demo are adapters over the same API.

## Authority model

`FoundationAuthoringSession` is the mutation coordinator introduced by this phase. It operates on `FoundationWorldData`, a serializable `FoundationAuthoringPolicy`, and a bounded `FoundationAuthoringHistory`. Every successful command replaces complete typed records through the existing registration API, so direct lookup, layer membership, chunk/region buckets, and abstract chunk references remain consistent.

The supported states are:

- `GENERATED`: the owning generator may replace the record;
- `LOCKED`: regeneration must preserve the current record;
- `OVERRIDDEN`: an active Phase 11 instruction owns the live record.

Lock and unlock are explicit history commands. A target with an active override must be reverted before its lock state can change.

## Override records

Each active instruction is a `FoundationOverrideRecord` in the existing `override` spatial layer. It records:

- a deterministic override ID derived from world seed/version, target ID, and policy ID;
- target ID, original layer/entity/record kind, and parent lineage;
- one operation: `modify`, `create`, or `delete`;
- canonical base and/or authored typed snapshots;
- SHA-256 fingerprints and stable-sorted changed-field paths;
- monotonic target revision, summary, active state, conflict state, validation state, and spatial ownership.

Modify retains the first generated base while later edits advance the same override revision. Create retains an authored snapshot and no generated base. Delete removes a generated/modified live target but retains its base snapshot as a spatially indexed tombstone. Deleting a never-generated authored creation cancels that creation, with undo retaining the complete recovery path. Protected identity fields such as stable ID, record kind, entity type, layer, and parent cannot be changed by a modification.

`FoundationSpatialRecordCodec` is the single typed restoration path used by manifests and authoring. Canonical JSON recursively sorts dictionary keys before fingerprinting; runtime IDs, dictionary insertion order, frame timing, and global random state do not participate.

## Reapply, conflicts, and reversion

Generators continue to own their existing generated-record replacement policies. After regeneration, call `reapply_all()` to reconcile active overrides in stable-ID order:

- an unchanged base accepts its authored modify snapshot;
- a missing create is restored;
- a regenerated delete target is removed again;
- an already-applied instruction is recognized without another revision;
- base drift, missing targets, and target collisions are reported without changing the conflicting live record.

Forced reapply is an explicit caller policy and uses the retained authored snapshot or tombstone. It is never implicit under the default drift-rejection policy; callers may instead supply an explicit permissive policy. `revert_override()` restores the exact retained base for modify/delete or removes an authored creation. Under the default policy, a drifted live target is not overwritten unless the caller explicitly forces reversion.

## History and atomic rejection

Each successful user operation stores complete before/after target and override snapshots plus affected downstream layer names. Undo and redo restore both records as one command and reindex them through `FoundationWorldData`. Adding a command after undo truncates the redo branch. The policy defines finite active-override and history caps; reaching either cap has deterministic behavior.

Invalid JSON values, unsupported types/layers, protected-field edits, identity collisions, invalid policy, and preflight drift are rejected before target, index, metadata, or history mutation. Authoring reports potentially affected downstream layers but never silently reruns generators.

## Validation and debug presentation

`FoundationAuthoringValidator.validate()` is read-only. It checks policy/history bounds, stable identities, operation/snapshot shapes, revision and source metadata, fingerprints, changed fields, conflict state, live-target agreement, and chunk/region ownership. Diagnostics are typed `FoundationAuthoringValidationIssue` values.

The `overrides` debug provider batches modify/create/delete bounds, tombstones, conflict styling, labels, and selection emphasis into the shared debug geometry buffers. Disabling the layer skips provider invocation and primitive allocation.

The **Foundation Authoring** editor dock exposes record selection, typed JSON editing, translation, create/delete, lock/unlock, revert, reapply, undo/redo, validation, and affected-layer status. `demo/spatial_model_demo.tscn` exposes a smaller runtime exercise for nudge, revert, reapply, and undo/redo. Neither UI stores authoritative state.

## Explicit Phase 11 scope

The policy covers Phase 1–10 spatial record kinds: anchors, road patterns/topology, blocks, parcels, buildings, facades, districts, parking facilities, and public features. Phase 11 does not edit authoritative terrain arrays or Phase 9 grading-plan arrays.

It does not add interiors/rooms/portals (Phase 12), advanced roads, navigation, vehicles, or traffic simulation (Phase 13), production meshes/materials/collision, prefabs, utilities, vegetation, a final persistence backend, or automatic dependency regeneration.

## Validation

Run `res://tests/run_phase_11_tests.gd` with Godot 4.7 after the Phase 0–10 suites, followed by runtime and editor/plugin smoke checks. The focused suite covers canonical fingerprints, policy serialization, locking, modify/create/delete/revert, revision retention, deterministic identities, conflict-safe and forced reapply, atomic rejection, bounded undo/redo, typed manifest round trips, signed multi-chunk reindexing, queries, read-only validation, corruption diagnostics, debug disablement, editor/demo controls, and scope exclusions.
