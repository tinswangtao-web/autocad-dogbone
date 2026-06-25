# DBAUTO Segmented Circle Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `DBAUTO` recognize SketchUp-exported closed polylines with at least 24 circle-fit vertices and convert them to exact circular geometry without adding dogbones.

**Architecture:** Add an isolated circle-fit helper that requires an even vertex count, derives the center from opposite-vertex midpoints, and validates opposite-pair centers and every source radius against a 0.1% tolerance. Keep recognized circles in containment analysis, but route them through separate persistence: direct selections become `CIRCLE` entities, while block-owned polylines are updated in place to two exact semicircular bulge segments.

**Tech Stack:** AutoLISP/DXF entity data, Node.js source-contract tests, AutoCAD for Mac manual verification.

---

### Task 1: Circle recognition contract

**Files:**
- Create: `scripts/test-dbauto-circle-source.mjs`
- Modify: `dogbone.lsp`

- [x] **Step 1: Write failing source tests**

Assert that the source defines 24-vertex and 0.001 relative tolerances, requires an even vertex count, derives the center from opposite vertices, and checks every opposite-pair center and radial error.

- [x] **Step 2: Run the new test and verify failure**

Run: `node scripts/test-dbauto-circle-source.mjs`

Expected: failure because circle recognition functions are absent.

- [x] **Step 3: Implement minimal recognition helpers**

Add `db:segmented-circle-data`. It returns `(center radius)` only for closed, straight polylines with at least 24 even-count vertices whose opposite-pair center deviation and maximum radial deviation are no greater than `radius * 0.001`.

- [x] **Step 4: Run tests**

Run: `node scripts/test-dbauto-circle-source.mjs && node scripts/test-dbauto-block-source.mjs`

Expected: both pass.

### Task 2: Persist exact circular geometry

**Files:**
- Modify: `scripts/test-dbauto-circle-source.mjs`
- Modify: `dogbone.lsp`

- [x] **Step 1: Extend failing source tests**

Require a direct `CIRCLE` creation helper that preserves entity properties and a block update path that writes exactly two vertices with semicircular bulges.

- [x] **Step 2: Run the test and verify failure**

Run: `node scripts/test-dbauto-circle-source.mjs`

Expected: failure because persistence helpers are absent.

- [x] **Step 3: Implement persistence helpers**

Create direct circles before deleting their sources. For block items, compute opposite endpoints around the fitted center and call `db:update-lwpolyline-in-place` with two same-sign bulges whose sign follows the source polygon winding.

- [x] **Step 4: Run tests**

Run: `node scripts/test-dbauto-circle-source.mjs && node scripts/test-dbauto-block-source.mjs`

Expected: both pass.

### Task 3: Integrate conversion into DBAUTO

**Files:**
- Modify: `scripts/test-dbauto-circle-source.mjs`
- Modify: `dogbone.lsp`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [x] **Step 1: Add failing integration assertions**

Require circle tagging during collection, exclusion from dogbone patch generation, detected/converted/failed counters, and `REGEN` after block conversion.

- [x] **Step 2: Run the test and verify failure**

Run: `node scripts/test-dbauto-circle-source.mjs`

Expected: integration assertions fail.

- [x] **Step 3: Route recognized circles through conversion**

Retain their polygon points for hole parity, skip patch generation, attempt the group-specific conversion, and preserve the source without dogboning it on failure. Add the three counters to `DBAUTO` output.

- [x] **Step 4: Document behavior**

Update `README.md` and `CHANGELOG.md` with the 24-vertex threshold, 0.1% tolerance, direct `CIRCLE` behavior, and exact block-polyline fallback.

- [x] **Step 5: Run full verification**

Run: `node scripts/test-dbauto-circle-source.mjs && node scripts/test-dbauto-block-source.mjs && node scripts/test-nesting-source.mjs && git diff --check`

Expected: all scripts pass and `git diff --check` is silent.

### Task 4: Manual AutoCAD acceptance

**Files:**
- No repository changes required.

- [ ] **Step 1: Load the updated plugin in AutoCAD for Mac**

Use `APPLOAD` to reload `dogbone.lsp`.

- [ ] **Step 2: Verify direct and block cases**

Run `DBAUTO` on a SketchUp-exported drawing containing a 24-segment circle, a 23-segment polygon, normal dogbone corners, and two references of one block. Confirm direct circles become `CIRCLE`, block circles become smooth exact circular polylines in every instance, the 23-segment polygon remains unchanged, normal corners receive dogbones, and one `UNDO` restores the drawing.
