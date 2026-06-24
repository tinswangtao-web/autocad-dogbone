# DBAUTO Block Definition Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `DBAUTO` so selecting a 1:1 block reference applies dogbones to eligible polylines in its shared block definition, updating every reference of that block.

**Architecture:** Keep the existing polyline geometry and replacement pipeline. Add a selection-expansion layer that separates direct polylines from block references, validates and deduplicates block definitions, collects direct child polylines from each definition, and processes each definition as an isolated containment group so hole detection and duplicate tracking do not leak across unrelated blocks.

**Tech Stack:** AutoLISP for AutoCAD for Mac; Node.js source-level regression checks; `entget`, `tblsearch`, `entnext`, `entdel`, and `entmakex`.

---

## File Structure

- Modify `dogbone.lsp`: add block validation/traversal helpers and refactor `DBAUTO` orchestration around processing groups.
- Create `scripts/test-dbauto-block-source.mjs`: source-level regression checks for the new selection, validation, deduplication, traversal, and mutation boundaries.
- Modify `README.md`: document the block-definition behavior and restrictions.
- Modify `CHANGELOG.md`: record the bug fix and supported scope.

### Task 1: Lock the Block Selection Contract With a Failing Test

**Files:**
- Create: `scripts/test-dbauto-block-source.mjs`
- Test: `scripts/test-dbauto-block-source.mjs`

- [ ] **Step 1: Write the failing source-level regression test**

Create a Node assertion script that reads `dogbone.lsp` and requires these concrete contracts:

```js
import fs from "node:fs";
import assert from "node:assert/strict";

const source = fs.readFileSync(new URL("../dogbone.lsp", import.meta.url), "utf8");

assert.match(source, /\(ssget '\(\(0 \. "LWPOLYLINE,INSERT"\)\)\)/,
  "DBAUTO should accept direct polylines and block references");
assert.match(source, /\(defun db:unit-scale-insert-p\b/,
  "DBAUTO should validate block reference scale");
assert.match(source, /\(defun db:collect-block-polylines\b/,
  "DBAUTO should collect direct LWPOLYLINE children from a block definition");
assert.match(source, /\(defun db:collect-dbauto-groups\b/,
  "DBAUTO should expand and deduplicate the mixed selection into processing groups");
assert.match(source, /\(defun db:process-dbauto-group\b/,
  "DBAUTO should process each containment group independently");
assert.doesNotMatch(source,
  /\(defun db:collect-block-polylines[\s\S]*?\(db:collect-block-polylines\s+sub-/,
  "Block polyline collection should not recurse into nested INSERT definitions");

console.log("DBAUTO block source checks passed");
```

- [ ] **Step 2: Run the test and verify RED**

Run: `node scripts/test-dbauto-block-source.mjs`

Expected: FAIL on the old `LWPOLYLINE`-only selection filter or the first missing block helper.

- [ ] **Step 3: Commit the failing test**

Run:

```bash
git add scripts/test-dbauto-block-source.mjs
git commit -m "test: cover DBAUTO block definition selection"
```

### Task 2: Add Block Validation, Traversal, and Group Collection

**Files:**
- Modify: `dogbone.lsp:791-829`
- Test: `scripts/test-dbauto-block-source.mjs`

- [ ] **Step 1: Add scale and list helpers**

Add helpers near `db:collect-selection`:

```lisp
(defun db:near-one-p (value)
  (<= (abs (- (float value) 1.0)) *db-eps*)
)

(defun db:unit-scale-insert-p (ed / sx sy sz)
  (setq sx (db:assoc-value 41 ed 1.0))
  (setq sy (db:assoc-value 42 ed 1.0))
  (setq sz (db:assoc-value 43 ed 1.0))
  (and (db:near-one-p sx) (db:near-one-p sy) (db:near-one-p sz))
)

(defun db:string-member-p (value values / found item)
  (setq found nil)
  (foreach item values
    (if (= value item) (setq found T))
  )
  found
)
```

- [ ] **Step 2: Add direct block-definition traversal**

Implement `db:collect-block-polylines` using `(tblsearch "BLOCK" blockname)`, its `-2` first-entity pointer, and `entnext`. Collect only entities whose DXF type is `LWPOLYLINE`; stop at `ENDBLK`; do not recurse when the type is `INSERT`.

```lisp
(defun db:collect-block-polylines (blockname / bdef en ed etype result)
  (setq bdef (tblsearch "BLOCK" blockname))
  (setq result '())
  (if bdef
    (progn
      (setq en (cdr (assoc -2 bdef)))
      (while en
        (setq ed (entget en))
        (setq etype (cdr (assoc 0 ed)))
        (cond
          ((= etype "ENDBLK") (setq en nil))
          ((= etype "LWPOLYLINE")
            (setq result (cons en result))
            (setq en (entnext en)))
          (T (setq en (entnext en)))
        )
      )
    )
  )
  (reverse result)
)
```

- [ ] **Step 3: Extract entity-list collection from selection-set collection**

Add `db:collect-entities`, taking a list of `LWPOLYLINE` enames and returning the existing `(items skipped-open skipped-bulge)` shape. Change `db:collect-selection` into a small adapter that converts its selection set into an entity list before calling `db:collect-entities`. Preserve the existing item format consumed by `db:tag-holes`, `db:build-patches`, and `db:rebuild-polyline`.

- [ ] **Step 4: Build deduplicated DBAUTO groups**

Implement `db:collect-dbauto-groups`. Return an association list containing groups and counters:

```lisp
((groups . ((direct items skipped-open skipped-bulge)
            (block block-name items skipped-open skipped-bulge) ...))
 (direct-count . N)
 (block-count . N)
 (skipped-blocks . N))
```

For each selected object:

- append direct `LWPOLYLINE` enames to one direct group;
- for `INSERT`, require `db:unit-scale-insert-p`;
- deduplicate valid blocks by DXF group `2` name;
- collect each unique block definition's direct polylines with `db:collect-block-polylines`;
- increment `skipped-blocks` for scaled, unresolved, or empty block definitions.

- [ ] **Step 5: Run the focused test and verify GREEN for helper contracts**

Run: `node scripts/test-dbauto-block-source.mjs`

Expected: it may still fail on `db:process-dbauto-group`, but all selection, validation, and traversal assertions introduced in Tasks 1-2 pass up to that point.

- [ ] **Step 6: Commit helper implementation**

Run:

```bash
git add dogbone.lsp scripts/test-dbauto-block-source.mjs
git commit -m "feat: collect DBAUTO block definition groups"
```

### Task 3: Process Groups and Update DBAUTO Reporting

**Files:**
- Modify: `dogbone.lsp:1587-1678`
- Test: `scripts/test-dbauto-block-source.mjs`

- [ ] **Step 1: Add one-group processing helper**

Extract the current `DBAUTO` item loop into `db:process-dbauto-group`. The helper receives one group of collected items, calls `db:tag-holes`, resets `all-patches` for that group, replaces only the polylines stored in those items, and returns counters in a stable association list:

```lisp
((valid . N) (holes . N) (corners . N) (dogbones . N)
 (duplicates . N) (rebuilt . N))
```

This group boundary ensures unrelated direct/model-space outlines and separate block definitions cannot classify each other as holes or suppress patches as duplicates.

- [ ] **Step 2: Refactor `c:DBAUTO` around mixed selection groups**

Change the prompt and selection filter to:

```lisp
(prompt "\nSelect closed LWPOLYLINE outlines or 1:1 block references. Editing a block updates all references.")
(setq ss (ssget '((0 . "LWPOLYLINE,INSERT"))))
```

Call `db:collect-dbauto-groups`, iterate through its groups, call `db:process-dbauto-group`, and sum the returned counters. Do not pass any selected `INSERT` ename to `db:lwpoly-data`, `db:rebuild-polyline`, or `entdel`.

- [ ] **Step 3: Add explicit summary counters**

Report selected objects, valid direct polylines, unique block definitions processed, skipped block references, invalid/bulged polylines, dogbones, and rebuilt polylines. Emit a separate warning when scaled or unsupported blocks were skipped.

- [ ] **Step 4: Strengthen the source test for mutation boundaries**

Add assertions that `c:DBAUTO` calls `db:collect-dbauto-groups`, iterates groups through `db:process-dbauto-group`, and uses the new user-facing warning. Add an assertion that `db:collect-block-polylines` contains no recursive self-call.

- [ ] **Step 5: Run the focused regression test and verify GREEN**

Run: `node scripts/test-dbauto-block-source.mjs`

Expected: `DBAUTO block source checks passed`.

- [ ] **Step 6: Run the pre-existing nesting regression test**

Run: `node scripts/test-nesting-source.mjs`

Expected: `nesting source checks passed`.

- [ ] **Step 7: Commit orchestration changes**

Run:

```bash
git add dogbone.lsp scripts/test-dbauto-block-source.mjs
git commit -m "fix: generate dogbones inside selected blocks"
```

### Task 4: Document the Supported Behavior

**Files:**
- Modify: `README.md:69-78`
- Modify: `README.md:203-208`
- Modify: `CHANGELOG.md:3`

- [ ] **Step 1: Update DBAUTO documentation**

State that `DBAUTO` accepts closed `LWPOLYLINE` and 1:1 `INSERT` references; selected blocks update their shared definition and therefore every same-name reference; direct child polylines are processed; nested block definitions and scaled references are skipped.

- [ ] **Step 2: Add changelog entry**

Add an `Unreleased` section describing block definition support, same-name reference updates, definition deduplication, and the 1:1/direct-child limitations.

- [ ] **Step 3: Run documentation and whitespace checks**

Run:

```bash
rg -n "1:1|block definition|块定义|嵌套块" README.md CHANGELOG.md
git diff --check
```

Expected: documentation mentions the supported boundaries and `git diff --check` exits successfully.

- [ ] **Step 4: Commit documentation**

Run:

```bash
git add README.md CHANGELOG.md
git commit -m "docs: describe DBAUTO block behavior"
```

### Task 5: Final Verification

**Files:**
- Verify: `dogbone.lsp`
- Verify: `scripts/test-dbauto-block-source.mjs`
- Verify: `scripts/test-nesting-source.mjs`
- Verify: `README.md`
- Verify: `CHANGELOG.md`

- [ ] **Step 1: Run all automated checks**

Run:

```bash
node scripts/test-dbauto-block-source.mjs
node scripts/test-nesting-source.mjs
git diff --check HEAD~3..HEAD
```

Expected: both scripts print their pass messages and the whitespace check exits with status 0.

- [ ] **Step 2: Inspect the final diff and repository state**

Run:

```bash
git diff HEAD~3..HEAD -- dogbone.lsp scripts/test-dbauto-block-source.mjs README.md CHANGELOG.md
git status --short
```

Confirm that only the intended files were committed and that the pre-existing deletions of `dogbone-v2.0-stable.lsp` and `dogbone-v2.1-dev.lsp` remain untouched.

- [ ] **Step 3: Record manual AutoCAD checks still required**

Because the repository has no AutoCAD runtime harness, report the six manual scenarios from the design document as pending real-application validation. Do not claim runtime verification from source-level tests alone.
