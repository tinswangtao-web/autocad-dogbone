# Dogbone V2.1 Local Editing Design

## Goal

Add local editing tools on top of the V2.0 stable baseline without changing the proven `DBAUTO` production workflow.

V2.1 adds:

- `DBADD`: add dogbones to missing corners inside a selected window area.
- `DBRESTORE`: restore existing dogbone arcs inside a selected window area back to sharp corners.
- `DBRESTOREALL`: restore all recognized dogbones in selected polylines.

V2.1 explicitly does not add direct dogbone resize. Resize workflow is:

1. Run `DBRESTORE` on the affected dogbones.
2. Run `DBSET` to change tool diameter.
3. Run `DBADD` or `DBAUTO` to regenerate dogbones.

## Current Baseline

V2.0 supports:

- Closed `LWPOLYLINE` only.
- Straight source edges for `DBAUTO`.
- Confirmed `C 45 Degree Dogbone`.
- New closed `LWPOLYLINE` output.
- Delete original polyline only after replacement succeeds.
- `DBDEBUG` and `DB1` for separate diagnostics.

## Commands

### DBADD

Purpose: add dogbones to corners that were missed or intentionally skipped.

Workflow:

1. User selects one or more closed `LWPOLYLINE` objects.
2. User picks two opposite corners of a rectangular area.
3. Program finds eligible sharp material corners.
4. Program inserts C-type dogbone patches only at matched corners.
5. Program rebuilds each affected polyline.
6. Program deletes each original polyline only after its replacement is created.

DBADD must be able to read polylines that already contain dogbone bulges. Unlike `DBAUTO`, it must not reject a polyline just because it has non-zero bulge segments.

### DBRESTORE

Purpose: restore existing C-type dogbone arcs to sharp corners.

Workflow:

1. User selects one or more closed `LWPOLYLINE` objects.
2. User picks two opposite corners of a rectangular area.
3. Program finds dogbone arc segments matching the selection.
4. Program replaces each selected dogbone arc with its reconstructed original corner point.
5. Program rebuilds each affected polyline.
6. Program deletes each original polyline only after its replacement is created.

### DBRESTOREALL

Purpose: batch restore all dogbones in selected polylines.

Workflow:

1. User selects one or more closed `LWPOLYLINE` objects.
2. Program finds every recognized V2.0/V2.1 C-type dogbone arc.
3. Program restores all matched arcs back to sharp corners.
4. Program rebuilds each affected polyline.
5. Program deletes each original polyline only after its replacement is created.

## Selection Rules

### Window Mode

Window mode uses a rectangular selection area.

For `DBADD`, a corner is selected when the corner point is inside the rectangle.

For `DBRESTORE`, a dogbone is selected when any of these is inside the rectangle:

- Reconstructed original corner point.
- Arc center.
- Arc midpoint.

## Geometry

### Add Dogbone

Use the existing V2.0 C-type patch calculation:

- `P0`: previous sharp vertex.
- `P1`: selected corner.
- `P2`: next sharp vertex.
- `R = toolDiameter / 2`.
- `dir = normalize(normalize(P0 - P1) + normalize(P2 - P1))`.
- `center = P1 + dir * R`.
- `trim = 2 * R * cos(theta / 2)`, with 90 degree special case `trim = R * sqrt(2)`.
- `start = P1 + normalize(P0 - P1) * trim`.
- `end = P1 + normalize(P2 - P1) * trim`.
- Bulge uses the near-corner half of the C-type circle.

DBADD skips a corner when either adjacent straight segment is too short for the trim distance.

### Restore Dogbone

For a C-type dogbone arc segment from `A` to `B` with bulge near `abs(1.0)`:

1. Recover the arc center and radius from endpoints and bulge.
2. Find the original corner as the point on the arc closest to the C-type near-corner side.
3. For 90 degree dogbones, this original corner is the midpoint of the selected half-circle arc.
4. Replace the arc segment with a single sharp vertex at that corner.

Because V2.0 C-type dogbones produce a half-circle at 90 degrees, V2.1 initially restores dogbones whose `abs(bulge)` is within tolerance of `1.0`. Other dogbone angles can be supported later after real CAD examples validate the geometry.

## Data Handling

The rebuild logic should operate on `(point bulge-after)` vertex records.

DBADD:

- For ordinary vertices, preserve existing point and bulge.
- For selected sharp corners, replace `P1` with `start` and `end`.
- Set `start` bulge to the dogbone patch bulge.
- Set `end` bulge to `0.0`.

DBRESTORE:

- For selected dogbone arc segment, replace its start/end arc pair with one restored corner vertex.
- Preserve all unrelated vertices and bulges.

## Safety

- Wrap each command in one AutoCAD UNDO group.
- Do not delete the original entity until replacement entity creation succeeds.
- If a selected polyline has no matching corners/arcs, leave it unchanged.
- Keep V2.0 `DBAUTO` behavior unchanged unless a shared helper must be extracted.

## Out of Scope

- Direct dogbone resize command.
- Automatic candidate marker UI.
- SPLINE, ARC, CIRCLE, old POLYLINE support.
- Complex nested hole logic.
- Full general-angle restore beyond validated 90 degree C-type dogbones.
