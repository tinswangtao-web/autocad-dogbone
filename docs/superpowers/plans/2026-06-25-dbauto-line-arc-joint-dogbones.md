# DBAUTO Line-Arc Joint Dogbones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `DBAUTO` automatically recognize non-tangent line-arc and arc-line fitting corners that can affect CNC assembly.

**Architecture:** Keep the existing LWPOLYLINE rebuild pipeline. Allow bulged source polylines into DBAUTO, preserve original bulges on untouched segments, and add an explicit line-arc kink predicate so tangent fillets are not treated as dogbone candidates.

**Tech Stack:** AutoLISP for AutoCAD for Mac; Node.js source-level regression checks.

---

### Task 1: Source-Level Regression

**Files:**
- Create: `scripts/test-dbauto-line-arc-source.mjs`

- [ ] **Step 1: Write the failing source test**

```js
import fs from "node:fs";
import assert from "node:assert/strict";

const source = fs.readFileSync(new URL("../dogbone.lsp", import.meta.url), "utf8");

assert.match(source, /\(defun db:line-arc-kink-p\b/, "DBAUTO should detect non-tangent line-arc joints");
assert.match(source, /\(defun db:auto-corner-candidate-p\b/, "DBAUTO should centralize automatic corner eligibility");
assert.match(source, /\(defun db:item-circle-data\b/, "Circle metadata should stay explicit after storing original vertices");
assert.match(source, /\(setq circle-data \(if \(db:has-bulge verts\) nil \(db:segmented-circle-data pts\)\)\)/, "Bulged source polylines should be collected but not treated as segmented circles");
assert.doesNotMatch(source, /\(\(db:has-bulge verts\)[\s\S]{0,120}\(setq skipped-bulge/, "DBAUTO should not skip every bulged polyline before line-arc analysis");
assert.match(source, /\(db:auto-corner-candidate-p verts i p0 p1 p2 area is-hole\)/, "DBAUTO patch building should use the automatic corner predicate");
assert.match(source, /\(setq next-patch \(db:find-patch \(rem \(1\+ i\) n\) patches\)\)/, "Replacement vertices should preserve source bulges before patched corners");
assert.match(source, /\(list \(cdr \(assoc 'end patch\)\) \(db:patch-after-bulge patch\)\)/, "Replacement vertices should preserve source bulges after patched corners");

console.log("DBAUTO line-arc source checks passed");
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node scripts/test-dbauto-line-arc-source.mjs`

Expected: FAIL because the new helpers and collection behavior do not exist yet.

### Task 2: Implement Line-Arc Eligibility

**Files:**
- Modify: `dogbone.lsp`

- [ ] **Step 1: Add arc tangent and kink helpers**

Add helpers that compute arc endpoint tangents from bulge data and return true only when exactly one adjacent segment is an arc and the straight segment is not tangent to that arc.

- [ ] **Step 2: Allow bulged DBAUTO items**

Change `db:collect-entities` to collect bulged polylines as normal items, store original `verts` at item index 8, and store segmented-circle data at item index 9 only for non-bulged outlines.

- [ ] **Step 3: Preserve untouched bulges during rebuild**

Update `db:build-replacement-vertices` so ordinary vertices keep their original bulge, patched vertices carry the original outgoing bulge where appropriate, and the vertex before a patched corner can carry the original incoming bulge.

- [ ] **Step 4: Use the new automatic predicate**

Change `db:build-patches` to call `db:auto-corner-candidate-p`, which preserves existing concave-corner behavior and adds non-tangent line-arc joints.

### Task 3: Verify and Document

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run regression checks**

Run:

```bash
node scripts/test-dbauto-line-arc-source.mjs
node scripts/test-dbauto-block-source.mjs
node scripts/test-dbauto-circle-source.mjs
git diff --check
```

Expected: all commands pass.

- [ ] **Step 2: Update documentation**

Document that `DBAUTO` now accepts bulged polylines for automatic line-arc kink detection, while smooth tangent fillets are ignored.
