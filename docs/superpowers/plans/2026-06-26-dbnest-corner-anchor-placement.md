# DBNEST Corner Anchor Placement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve `DBNEST` packing by trying four corner-anchored positions and 0/90-degree orientation candidates for each free rectangle.

**Architecture:** Keep the existing AABB MaxRects packer. Add a small candidate helper in `dogbone.lsp`, update `db:maxrect-find-placement` to iterate anchors and orientations, and extend the source regression test to lock the behavior.

**Tech Stack:** AutoLISP in `dogbone.lsp`; Node.js source-contract tests in `scripts/test-nesting-source.mjs`.

---

### Task 1: Corner-Anchored MaxRects Placement

**Files:**
- Modify: `scripts/test-nesting-source.mjs`
- Modify: `dogbone.lsp`

- [ ] **Step 1: Write the failing test**

Add assertions that require a `db:maxrect-anchor-candidate` helper, four anchor labels, and nested iteration over anchors inside `db:maxrect-find-placement`.

- [ ] **Step 2: Run test to verify it fails**

Run: `node scripts/test-nesting-source.mjs`

Expected: FAIL because `db:maxrect-anchor-candidate` and `db:maxrect-anchors` are not present.

- [ ] **Step 3: Write minimal implementation**

Add `db:maxrect-anchors`, add `db:maxrect-anchor-candidate`, and update `db:maxrect-find-placement` so every free rectangle tries all anchors and all orientations.

- [ ] **Step 4: Run test to verify it passes**

Run: `node scripts/test-nesting-source.mjs`

Expected: PASS with `nesting source checks passed`.

- [ ] **Step 5: Verify Lisp structure and whitespace**

Run:

```bash
node - <<'NODE'
const fs = require('fs');
const text = fs.readFileSync('dogbone.lsp', 'utf8');
let depth = 0, min = 0, minLine = 1, line = 1;
for (const ch of text) {
  if (ch === '\n') line++;
  if (ch === '(') depth++;
  if (ch === ')') depth--;
  if (depth < min) { min = depth; minLine = line; }
}
console.log(JSON.stringify({ depth, min, minLine }));
if (depth !== 0 || min !== 0) process.exit(1);
NODE
git diff --check
```

Expected: JSON shows `{"depth":0,"min":0,"minLine":1}` and `git diff --check` exits 0.
