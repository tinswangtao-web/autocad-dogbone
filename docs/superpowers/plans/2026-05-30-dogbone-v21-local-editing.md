# Dogbone V2.1 Local Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local dogbone editing commands `DBADD` and `DBRESTORE` while preserving the V2.0 `DBAUTO` workflow.

**Architecture:** Extend the existing single-file AutoLISP implementation with reusable vertex, selection, and rebuild helpers. `DBADD` inserts C-type patches into selected sharp corners; `DBRESTORE` recognizes selected 90-degree C-type dogbone arcs and replaces them with restored corner vertices.

**Tech Stack:** AutoLISP for AutoCAD for Mac, `entget`/`entmakex`, closed `LWPOLYLINE` entities.

---

## File Structure

- Modify `dogbone.lsp`: add V2.1 command logic and helper functions.
- Modify `README.md`: document `DBADD`, `DBRESTORE`, and the resize-by-restore workflow.
- Modify `CHANGELOG.md`: add V2.1 notes.

## Task 1: Add Selection Helpers

**Files:**
- Modify: `dogbone.lsp`

- [ ] Add helpers for rectangle selection:

```lisp
(defun db:rect-from-points (a b)
  (list
    (min (db:x a) (db:x b))
    (min (db:y a) (db:y b))
    (max (db:x a) (db:x b))
    (max (db:y a) (db:y b))
  )
)

(defun db:point-in-rect (pt rect)
  (and
    (>= (db:x pt) (nth 0 rect))
    (<= (db:x pt) (nth 2 rect))
    (>= (db:y pt) (nth 1 rect))
    (<= (db:y pt) (nth 3 rect))
  )
)
```

- [ ] Add helper for nearest point matching:

```lisp
(defun db:min-distance-to-points (pt pts / best p d)
  (setq best nil)
  (foreach p pts
    (setq d (db:distance pt p))
    (if (or (not best) (< d best))
      (setq best d)
    )
  )
  best
)
```

- [ ] Verify with static check:

Run:

```bash
node -e "const s=require('fs').readFileSync('dogbone.lsp','utf8'); if(!s.includes('db:rect-from-points')) process.exit(1); console.log('selection helpers present')"
```

Expected: `selection helpers present`

## Task 2: Read Bulged LWPOLYLINE for Editing

**Files:**
- Modify: `dogbone.lsp`

- [ ] Add a collection function for editing that accepts closed LWPOLYLINE with existing bulges:

```lisp
(defun db:collect-edit-selection (ss / i en ed data verts pts area items skipped-open layer color ltype lweight)
  (setq i 0)
  (setq items '())
  (setq skipped-open 0)
  (while (< i (sslength ss))
    (setq en (ssname ss i))
    (setq ed (entget en))
    (setq data (db:lwpoly-data en))
    (setq verts (cadr data))
    (if (and (car data) (>= (length verts) 3))
      (progn
        (setq pts (db:vertex-points verts))
        (setq area (db:poly-area pts))
        (if (> (abs area) *db-eps*)
          (progn
            (setq layer (cdr (assoc 8 ed)))
            (setq color (cdr (assoc 62 ed)))
            (setq ltype (cdr (assoc 6 ed)))
            (setq lweight (cdr (assoc 370 ed)))
            (setq items (cons (list en pts area nil layer color ltype lweight verts) items))
          )
          (setq skipped-open (1+ skipped-open))
        )
      )
      (setq skipped-open (1+ skipped-open))
    )
    (setq i (1+ i))
  )
  (list (reverse items) skipped-open)
)
```

- [ ] Verify that `DBAUTO` still uses `db:collect-selection`, while new commands use `db:collect-edit-selection`.

## Task 3: Implement DBADD Patch Selection

**Files:**
- Modify: `dogbone.lsp`

- [ ] Add selected-corner detection for point/window modes.
- [ ] Reuse `db:create-c-patch` for selected sharp material corners.
- [ ] Skip vertices whose previous or current outgoing segment already has non-zero bulge.
- [ ] Skip vertices that do not satisfy `db:needs-dogbone`.

Expected behavior:

- Point mode clicks select nearest eligible sharp corner.
- Window mode selects all eligible sharp corners whose corner point is inside the rectangle.

## Task 4: Implement DBADD Rebuild

**Files:**
- Modify: `dogbone.lsp`

- [ ] Add rebuild helper that preserves existing unrelated bulges:

```lisp
;; Concept:
;; ordinary vertex -> (point original-bulge-after)
;; selected corner -> (start dogbone-bulge), (end 0.0)
```

- [ ] Add command `c:DBADD`.
- [ ] Wrap command in UNDO begin/end.
- [ ] Delete original only after replacement succeeds.
- [ ] Print counts: selected polylines, matching corners, dogbones added, rebuilt polylines.

## Task 5: Implement Dogbone Arc Recognition

**Files:**
- Modify: `dogbone.lsp`

- [ ] Add function to detect V2.0 C-type 90-degree dogbone segments:

```lisp
(defun db:dogbone-bulge-p (bulge)
  (<= (abs (- (abs bulge) 1.0)) 0.05)
)
```

- [ ] Add arc midpoint/corner approximation for selected dogbone:

```lisp
;; For abs(bulge) ~= 1.0, the restored corner is the midpoint of the selected half-circle arc.
;; This point is also used for point/window selection matching.
```

## Task 6: Implement DBRESTORE

**Files:**
- Modify: `dogbone.lsp`

- [ ] Add point/window matching for dogbone arc candidates.
- [ ] Add rebuild helper:

```lisp
;; selected dogbone arc start vertex + next end vertex -> restored corner vertex.
;; restored corner gets bulge 0.0.
```

- [ ] Add command `c:DBRESTORE`.
- [ ] Wrap command in UNDO begin/end.
- [ ] Delete original only after replacement succeeds.
- [ ] Print counts: selected polylines, matched dogbones, restored dogbones, rebuilt polylines.

## Task 7: Docs and Version

**Files:**
- Modify: `dogbone.lsp`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] Update `*db-version*` to `V2.1`.
- [ ] Update load message with `DBADD` and `DBRESTORE`.
- [ ] Document the resize workflow:

```text
DBRESTORE -> DBSET -> DBADD/DBAUTO
```

## Task 8: Verification

**Files:**
- Verify: `dogbone.lsp`

- [ ] Run parenthesis check:

```bash
node - <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('dogbone.lsp','utf8');
let depth=0, line=1, inStr=false, comment=false, min=0;
for (const ch of s) {
  if (ch === '\n') { line++; comment=false; continue; }
  if (comment) continue;
  if (inStr) { if (ch === '"') inStr=false; continue; }
  if (ch === ';') { comment=true; continue; }
  if (ch === '"') { inStr=true; continue; }
  if (ch === '(') depth++;
  if (ch === ')') { depth--; min=Math.min(min, depth); }
}
if (depth !== 0 || min < 0 || inStr) throw new Error(JSON.stringify({depth,min,inStr,line}));
console.log('paren-check ok; lines=' + line);
NODE
```

Expected: `paren-check ok`.

- [ ] Check commands exist:

```bash
rg -n "defun c:DBADD|defun c:DBRESTORE|defun c:DBAUTO|defun c:DBSET" dogbone.lsp
```

Expected: all four commands listed.

- [ ] Manual AutoCAD acceptance test:

```text
1. Load dogbone.lsp.
2. Run DBSET and confirm tool diameter.
3. Run DBAUTO on a sample shape.
4. Manually undo one dogbone by restoring or test on a copy.
5. Run DBADD in point mode on one sharp corner.
6. Run DBADD in window mode on multiple sharp corners.
7. Run DBRESTORE in point mode on one dogbone.
8. Run DBRESTORE in window mode on multiple dogbones.
9. Confirm replacement polylines are closed and old polylines are deleted only after replacements exist.
```

