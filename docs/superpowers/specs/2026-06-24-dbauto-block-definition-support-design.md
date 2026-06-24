# DBAUTO Block Definition Support Design

## Goal

Allow `DBAUTO` to accept block references (`INSERT`) and add dogbones to eligible polylines in the selected block definitions. Updating a block definition must update every reference of that block without exploding or replacing block references.

## Scope

- Extend `DBAUTO` only. `DBADD`, `DBRESTORE`, and `DBRESTOREALL` retain their current `LWPOLYLINE`-only behavior.
- Continue supporting directly selected closed `LWPOLYLINE` entities exactly as before.
- Support selected `INSERT` entities whose X, Y, and Z scale factors are all `1.0` within the existing numeric tolerance.
- Process closed, straight-segment `LWPOLYLINE` entities directly contained in the selected block definition.
- Do not recursively modify nested block definitions in this release.
- Do not support dynamic block-specific behavior, non-uniform scaling, or scaled block references in this release.

## Selection and Validation

`DBAUTO` will accept `LWPOLYLINE,INSERT` in its selection filter.

For each selected `INSERT`:

1. Read its block name and scale factors.
2. Skip it with a clear command-line message if any scale factor differs from `1.0` beyond tolerance.
3. Resolve its block table record.
4. Deduplicate by block definition name so that selecting multiple references of the same block processes that definition once.
5. Collect only directly contained `LWPOLYLINE` entities. Ignore other entity types and nested `INSERT` entities.

Anonymous, external-reference, layout, or otherwise non-editable definitions must be skipped safely if AutoCAD does not permit their entities to be replaced.

## Geometry Processing

Eligible block-definition polylines use the existing `DBAUTO` pipeline:

1. Validate that each polyline is closed, has at least three vertices, has non-zero area, and has no bulge segments.
2. Collect all eligible polylines from one block definition as one group so existing containment-based hole detection remains valid inside that block.
3. Detect material-side internal corners and construct C 45-degree dogbone patches using the configured tool diameter.
4. Create each replacement `LWPOLYLINE` in the block definition, preserving the source entity's layer and basic properties.
5. Delete the original block-definition polyline only after its replacement is created successfully.

Because supported references are restricted to 1:1 scale, the configured tool diameter has the same drawing-unit size in the block definition and in every supported reference. Rotation and translation do not affect the geometry size.

## Data and Mutation Boundaries

Directly selected model-space polylines remain independent processing items and retain current deletion semantics.

Block references themselves are never deleted, exploded, recreated, moved, or renamed. Only eligible polylines in their shared block definition are replaced. Therefore every reference of the same definition updates together, including references that were not selected.

One selected definition is processed at most once per `DBAUTO` run. A failure in one source polyline leaves that source entity intact and does not prevent other eligible polylines from being processed.

## User Feedback

The completion summary will distinguish direct polylines and block definitions. It will report at least:

- total selected objects;
- valid direct polylines;
- unique block definitions processed;
- skipped scaled or unsupported block references;
- skipped open, invalid, or bulged polylines;
- dogbones generated;
- replacement polylines created.

The selection prompt will state that `DBAUTO` accepts closed polylines or 1:1 block references and that editing a block updates all references of that definition.

## Verification

Automated source-level regression checks will verify that:

- `DBAUTO` accepts `LWPOLYLINE,INSERT`;
- block definitions are deduplicated before processing;
- scale validation rejects non-1:1 references;
- traversal stops at directly contained polylines and does not recursively modify nested definitions;
- block references are not passed to the existing polyline replacement/deletion path.

Manual AutoCAD verification will cover:

1. Two 1:1 references of the same block both update after selecting one reference.
2. Selecting both references processes the definition once and does not duplicate dogbones.
3. A rotated 1:1 reference produces the expected rotated result.
4. A scaled reference is skipped with a clear message and remains unchanged.
5. A block containing outer and hole polylines preserves containment-based corner handling.
6. Direct `LWPOLYLINE` selection still behaves as before.
