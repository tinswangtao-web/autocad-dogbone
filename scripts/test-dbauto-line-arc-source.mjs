import fs from "node:fs";
import assert from "node:assert/strict";

const source = fs.readFileSync(new URL("../dogbone.lsp", import.meta.url), "utf8");

assert.match(
  source,
  /\(defun db:end-undo \(\)\s+\(command-s "_.UNDO" "_End"\)/,
  "db:end-undo should use command-s because it is called from *error* handlers",
);

assert.match(
  source,
  /\(defun db:auto-corner-candidate-p\b/,
  "DBAUTO should centralize automatic corner eligibility",
);

assert.match(
  source,
  /\(and\s+\(db:sharp-corner-p verts idx\)\s+\(db:needs-dogbone p0 p1 p2 area is-hole\)/,
  "The current C dogbone patch should only be applied to sharp line-line dogbone candidates",
);

assert.doesNotMatch(
  source,
  /\(db:line-arc-kink-p verts idx\)/,
  "Line-arc joints should not be routed through the line-line C dogbone patch",
);

assert.doesNotMatch(
  source,
  /\(db:convex-fitting-corner-p verts idx p0 p1 p2 area is-hole\)/,
  "Convex tenon corners should not be routed through the concave C dogbone patch",
);

assert.match(
  source,
  /\(defun db:item-circle-data\b/,
  "Circle metadata should stay explicit after storing original vertices",
);

assert.match(
  source,
  /\(setq circle-data \(if \(db:has-bulge verts\) nil \(db:segmented-circle-data pts\)\)\)/,
  "Bulged source polylines should be collected but not treated as segmented circles",
);

assert.doesNotMatch(
  source,
  /\(\(db:has-bulge verts\)[\s\S]{0,120}\(setq skipped-bulge/,
  "DBAUTO should not skip every bulged polyline before preserving existing arc segments",
);

assert.match(
  source,
  /\(db:auto-corner-candidate-p verts i p0 p1 p2 area is-hole\)/,
  "DBAUTO patch building should use the automatic corner predicate",
);

assert.match(
  source,
  /\(setq failed \(1\+ failed\)\)/,
  "DBAUTO should count recognized corners whose dogbone geometry cannot fit",
);

assert.match(
  source,
  /\(cons 'failed failed-count\)/,
  "Per-group results should expose failed dogbone geometry count",
);

assert.match(
  source,
  /dogbone geometry failed=/,
  "DBAUTO output should report recognized corners that could not generate dogbones",
);

assert.match(
  source,
  /\(defun db:create-short-leg-c-patch\b/,
  "Short 90-degree fitting corners should have a dedicated fallback dogbone geometry",
);

assert.match(
  source,
  /\(defun db:create-c-or-short-leg-patch\b/,
  "Patch creation should use an explicit helper that preserves patch list return values",
);

assert.match(
  source,
  /\(if \(not patch\)[\s\S]*?\(setq patch \(db:create-short-leg-c-patch p0 p1 p2 radius source-index\)\)/,
  "Patch creation should fallback without using AutoLISP or, which only returns T",
);

assert.doesNotMatch(
  source,
  /\(or\s+\(db:create-c-patch p0 p1 p2 r index\)\s+\(db:create-short-leg-c-patch p0 p1 p2 r index\)/,
  "Patch creation should not use AutoLISP or because it converts a patch list to T",
);

assert.match(
  source,
  /\(setq next-patch \(db:find-patch \(rem \(1\+ i\) n\) patches\)\)/,
  "Replacement vertices should preserve source bulges before patched corners",
);

assert.match(
  source,
  /\(list \(cdr \(assoc 'end patch\)\) \(db:patch-after-bulge patch\)\)/,
  "Replacement vertices should preserve source bulges after patched corners",
);

console.log("DBAUTO bulged-polyline source checks passed");
