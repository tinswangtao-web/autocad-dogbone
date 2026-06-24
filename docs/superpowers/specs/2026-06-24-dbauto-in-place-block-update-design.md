# DBAUTO In-Place Block Update Design

## Problem

The first block-support implementation sends block-definition polylines through the same replacement path as directly selected model-space polylines. That path calls `entmakex` to create a new `LWPOLYLINE`, then deletes the source only if creation succeeds.

In real AutoCAD use, the supplied DXF `330` owner does not make the new entity replace the polyline inside the block definition. The result is a standalone dogboned polyline in model space while the original block reference remains unchanged.

## Goal

After `DBAUTO` processes a selected block reference, the selected object must still be a block reference. Its shared block definition must contain the dogboned geometry, and no standalone replacement polyline may be created in model space.

## Approach

Keep the existing mixed-selection and block-definition collection logic. Split mutation behavior by processing-group type:

- Direct `LWPOLYLINE` group: retain the existing create-replacement-then-delete-source behavior.
- Block-definition group: update each source `LWPOLYLINE` in place with `entmod`.

The block path must not call `entmakex` or `entdel`. Because the existing entity is modified rather than replaced, its entity name, handle, owner, layer, and membership in the block definition remain intact. All references of that shared definition update after `REGEN`.

## DXF Update

The in-place update helper will read the source entity with `entget` and construct a valid modified entity list:

1. Preserve the entity identity and non-vertex header data, including DXF groups `-1`, `0`, `5`, `330`, subclass markers, layer, color, linetype, lineweight, flags, elevation, thickness, and constant width when present.
2. Replace group `90` with the new vertex count.
3. Remove the old per-vertex groups `10`, `40`, `41`, `42`, and `91`.
4. Insert the new group `10` coordinates and group `42` bulges in vertex order.
5. Preserve trailing extrusion direction group `210` when present.
6. Call `entmod` with the reconstructed entity list and treat a non-nil return value as success.

The existing patch geometry remains unchanged; only persistence into the block definition changes.

## Processing Boundary

`db:process-dbauto-group` will receive the group type in addition to the items:

- For `direct`, call the existing replacement creator and delete the source after success.
- For `block`, build the same replacement vertex list, pass it to the in-place update helper, and never delete the source entity.

Statistics continue to count a successful in-place update as one rebuilt polyline. A failed `entmod` leaves the original block polyline unchanged and does not increment the rebuilt count.

## Verification

Automated source checks will require:

- a dedicated in-place `LWPOLYLINE` update helper using `entmod`;
- group-type-aware DBAUTO processing;
- the block branch to avoid the create/delete replacement path;
- balanced AutoLISP parentheses and the existing nesting checks to remain green.

Manual AutoCAD verification remains required:

1. Create two references of one 1:1 block containing a dogbone-eligible closed polyline.
2. Run `DBAUTO` and select one reference.
3. Confirm both references display dogbones.
4. Confirm the selected and unselected objects are still `INSERT` entities.
5. Confirm no standalone dogboned `LWPOLYLINE` appears in model space.
6. Confirm one `UNDO` restores the original shared block geometry.
