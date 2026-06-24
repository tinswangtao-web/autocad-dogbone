# DBAUTO In-Place Block Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make DBAUTO update polylines inside selected block definitions in place so the result remains a block and no standalone replacement polyline is created.

**Architecture:** Reuse the existing patch geometry and group collection. Extract vertex construction from entity persistence, then choose persistence by group type: direct polylines keep create/delete replacement semantics, while block-definition polylines reconstruct their DXF vertex data and call `entmod` on the existing entity.

**Tech Stack:** AutoLISP for AutoCAD for Mac; Node.js source-level regression checks; DXF entity lists through `entget` and `entmod`.

---

## File Structure

- Modify `dogbone.lsp`: add vertex-building and in-place DXF update helpers; make DBAUTO mutation group-aware.
- Modify `scripts/test-dbauto-block-source.mjs`: require `entmod` block persistence and prohibit the block branch from create/delete replacement behavior.
- Modify `README.md`: clarify that block geometry is updated in place and no standalone polyline is emitted.
- Modify `CHANGELOG.md`: record correction of the first block persistence implementation.

### Task 1: Add a Failing In-Place Persistence Contract

**Files:**
- Modify: `scripts/test-dbauto-block-source.mjs`

- [ ] **Step 1: Add failing assertions**

Extract the `db:process-dbauto-group` source body and assert that production code defines an in-place update helper, calls `entmod`, passes the group kind into processing, and branches to in-place update for `block` groups:

```js
assert.match(source, /\(defun db:update-lwpolyline-in-place\b/,
  "Block geometry should have a dedicated in-place update helper");
assert.match(source, /\(entmod modified\)/,
  "Block geometry should be persisted with entmod");
assert.match(dbauto, /\(db:process-dbauto-group \(car group\) \(nth 2 group\)\)/,
  "DBAUTO should pass group kind into persistence processing");
assert.match(source,
  /\(if \(= group-kind 'block\)[\s\S]*?\(db:update-lwpolyline-in-place/,
  "Block groups should update existing polylines in place");
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `node scripts/test-dbauto-block-source.mjs`

Expected: FAIL with `Block geometry should have a dedicated in-place update helper`.

- [ ] **Step 3: Commit the failing regression test**

```bash
git add scripts/test-dbauto-block-source.mjs
git commit -m "test: require in-place block dogbone updates"
```

### Task 2: Build Replacement Vertices Independently

**Files:**
- Modify: `dogbone.lsp:1186-1219`
- Test: `scripts/test-dbauto-block-source.mjs`

- [ ] **Step 1: Extract vertex construction**

Move the current vertex loop from `db:rebuild-polyline` into:

```lisp
(defun db:build-replacement-vertices (item patches / pts n i patch vertices)
  ;; Existing loop returns ((point bulge) ...) without creating an entity.
)
```

Change `db:rebuild-polyline` to call this helper and retain its current owned `entmakex` behavior for directly selected polylines only.

- [ ] **Step 2: Run both source checks**

```bash
node scripts/test-dbauto-block-source.mjs
node scripts/test-nesting-source.mjs
```

Expected: the focused test remains RED only because in-place persistence is not implemented; nesting passes.

### Task 3: Update Block Polylines With entmod

**Files:**
- Modify: `dogbone.lsp:1186-1230`
- Test: `scripts/test-dbauto-block-source.mjs`

- [ ] **Step 1: Add DXF classification helpers**

Add helpers with these exact responsibilities:

```lisp
(defun db:lwpoly-vertex-code-p (code)
  (or (= code 10) (= code 40) (= code 41) (= code 42) (= code 91))
)

(defun db:lwpoly-trailing-code-p (code)
  (= code 210)
)
```

- [ ] **Step 2: Implement in-place update**

Implement `db:update-lwpolyline-in-place`:

```lisp
(defun db:update-lwpolyline-in-place (ename vertices / ed header trailing d modified v)
  (setq ed (entget ename))
  (setq header '())
  (setq trailing '())
  (foreach d ed
    (cond
      ((= (car d) 90) (setq header (append header (list (cons 90 (length vertices))))))
      ((db:lwpoly-vertex-code-p (car d)))
      ((db:lwpoly-trailing-code-p (car d)) (setq trailing (append trailing (list d))))
      (T (setq header (append header (list d))))
    )
  )
  (setq modified header)
  (foreach v vertices
    (setq modified
      (append modified (list (cons 10 (db:pt2d (car v))) (cons 42 (cadr v)))))
  )
  (setq modified (append modified trailing))
  (entmod modified)
)
```

During implementation, avoid duplicating group `210`: trailing groups must be excluded from `header` before they are appended after the new vertices.

- [ ] **Step 3: Make group persistence explicit**

Change the signature to `(db:process-dbauto-group group-kind items)`. For each patched item:

```lisp
(setq vertices (db:build-replacement-vertices item patches))
(if (= group-kind 'block)
  (setq newent (db:update-lwpolyline-in-place (car item) vertices))
  (progn
    (setq newent (db:rebuild-polyline-from-vertices item vertices))
    (if newent (entdel (car item)))
  )
)
```

The block branch must contain no `entmakex` or `entdel` call. Increment rebuilt statistics for either successful return value.

- [ ] **Step 4: Pass group kind from DBAUTO**

Replace:

```lisp
(db:process-dbauto-group (nth 2 group))
```

with:

```lisp
(db:process-dbauto-group (car group) (nth 2 group))
```

- [ ] **Step 5: Run focused test and verify GREEN**

Run: `node scripts/test-dbauto-block-source.mjs`

Expected: `DBAUTO block source checks passed`.

- [ ] **Step 6: Run nesting regression and whitespace checks**

```bash
node scripts/test-nesting-source.mjs
git diff --check
```

Expected: nesting passes and whitespace check exits 0.

- [ ] **Step 7: Commit implementation**

```bash
git add dogbone.lsp scripts/test-dbauto-block-source.mjs
git commit -m "fix: update dogbones inside blocks in place"
```

### Task 4: Correct User Documentation

**Files:**
- Modify: `README.md:69-80`
- Modify: `CHANGELOG.md:3-9`

- [ ] **Step 1: Document in-place behavior**

State that block processing uses `entmod` to update the existing block-definition polyline, keeps every reference as `INSERT`, and does not create standalone model-space dogbone polylines.

- [ ] **Step 2: Record the persistence correction**

Add a changelog bullet explaining that the initial owner-based replacement path was corrected to in-place block-definition updates.

- [ ] **Step 3: Verify and commit documentation**

```bash
rg -n "entmod|独立多段线|INSERT" README.md CHANGELOG.md
git diff --check
git add README.md CHANGELOG.md
git commit -m "docs: clarify in-place block dogbone updates"
```

### Task 5: Final Verification

**Files:**
- Verify: `dogbone.lsp`
- Verify: `scripts/test-dbauto-block-source.mjs`
- Verify: `scripts/test-nesting-source.mjs`

- [ ] **Step 1: Verify RED against the pre-fix commit**

Run the updated regression script against commit `27662a3` using its `--git-ref` option.

Expected: non-zero exit because the old implementation has no in-place helper.

- [ ] **Step 2: Verify GREEN and all repository checks**

```bash
node scripts/test-dbauto-block-source.mjs
node scripts/test-nesting-source.mjs
git diff --check 27662a3..HEAD
git status --short
```

Expected: both tests pass; whitespace check exits 0; status shows only the user's pre-existing deletions of `dogbone-v2.0-stable.lsp` and `dogbone-v2.1-dev.lsp`.

- [ ] **Step 3: Report the manual runtime boundary**

Do not claim AutoCAD runtime success until the user reloads `dogbone.lsp` and verifies that selected objects remain `INSERT` references with no standalone model-space output.
