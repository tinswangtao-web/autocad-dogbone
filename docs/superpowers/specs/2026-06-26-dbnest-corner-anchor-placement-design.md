# DBNEST Corner Anchor Placement Design

## Goal

Improve `DBNEST` packing density for cases where the same rectangular component can save sheet area by using a different position inside an available free rectangle, including 90-degree rotation.

## Scope

This is a conservative upgrade to the existing AABB MaxRects packer in `dogbone.lsp`.

In scope:
- For each free rectangle, try four anchor positions: lower-left, lower-right, upper-left, and upper-right.
- For each anchor position, try every allowed part orientation from `db:part-orientations`, including 90 degrees when width and height differ.
- Keep the existing AABB safety model, component gap, edge margin, multi-sheet behavior, grouping, and diagnostics.
- Add source regression checks in `scripts/test-nesting-source.mjs`.

Out of scope:
- Exact polygon nesting.
- Non-90-degree rotation.
- Changing component grouping or sheet-copy behavior.

## Design

Add a helper that derives candidate AABBs from a free rectangle, part width/height, and anchor label. `db:maxrect-find-placement` will iterate free rectangles, orientations, and anchors. Each valid candidate will update free rectangles through the existing `db:maxrect-update-free-rects`, then be scored.

The scoring stays deterministic and conservative. It should prefer placements that keep overall board usage compact while still honoring the existing best-short-side and best-area-fit behavior. The selected placement remains a single `(x y angle candidate updated-free-rects)` tuple, so downstream board and move logic does not change.

## Verification

Use the existing source-contract test:

```bash
node scripts/test-nesting-source.mjs
```

Then run a Lisp balance check and whitespace check:

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
