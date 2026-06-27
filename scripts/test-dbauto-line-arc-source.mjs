import fs from "node:fs";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";

const refIndex = process.argv.indexOf("--git-ref");
const source = refIndex >= 0
  ? execFileSync("git", ["show", `${process.argv[refIndex + 1]}:dogbone.lsp`], { encoding: "utf8" })
  : fs.readFileSync(new URL("../dogbone.lsp", import.meta.url), "utf8");

function sliceBetween(start, end) {
  const startIndex = source.indexOf(start);
  assert.notEqual(startIndex, -1, `Expected to find ${start}`);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notEqual(endIndex, -1, `Expected to find ${end} after ${start}`);
  return source.slice(startIndex, endIndex);
}

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
  /\(defun db:find-polyarc-line-c-patch\b/,
  "DBAUTO should recognize real-DXF duplicate-corner line/polyarc joints through one dispatcher",
);

assert.match(
  source,
  /\(defun db:create-line-polyarc-c-patch\b/,
  "DBAUTO should keep the line -> duplicate corner -> polyarc dogbone path",
);

assert.match(
  source,
  /\(defun db:create-polyarc-line-c-patch\b/,
  "DBAUTO should add the reversed polyarc -> duplicate corner -> line dogbone path",
);

assert.match(
  source,
  /\(setq patch \(db:create-line-polyarc-c-patch verts idx area is-hole radius\)\)[\s\S]*?\(if \(not patch\)\s+\(setq patch \(db:create-polyarc-line-c-patch verts idx area is-hole radius\)\)/,
  "The line/polyarc dispatcher should try both real-DXF directions without AutoLISP or losing the patch list",
);

assert.match(
  source,
  /\(defun db:circle-segment-intersections\b/,
  "Line/polyarc dogbones should intersect the tool circle against finite source segments",
);

assert.match(
  source,
  /\(defun db:circle-line-noncorner-intersection\b/,
  "Line/polyarc dogbones should choose the non-corner intersection on the straight segment",
);

assert.match(
  source,
  /\(defun db:circle-polyarc-forward-intersection\b/,
  "line -> duplicate corner -> polyarc should trim at the first forward source-segment intersection",
);

assert.match(
  source,
  /\(defun db:circle-polyarc-backward-intersection\b/,
  "polyarc -> duplicate corner -> line should trim at the last backward source-segment intersection",
);

assert.match(
  source,
  /\(defun db:line-polyarc-bisector-center\b/,
  "Line/polyarc tool circle center should use the same one-radius angle-bisector model as C dogbones",
);

assert.doesNotMatch(
  source,
  /\(defun\s+db:point-on-segment-p\s+\([^)]*\/[^)]*\bt\b/i,
  "AutoLISP must not localize a variable named t because it tries to bind the protected T symbol at runtime",
);

assert.doesNotMatch(
  source,
  /\(setq\s+t\s+/i,
  "AutoLISP must not setq a variable named t because it aliases the protected T symbol",
);

assert.match(
  sliceBetween("(defun db:line-polyarc-bisector-center", "(defun db:circle-segment-intersections"),
  /\(setq bisector \(db:norm \(db:add u v\)\)\)/,
  "Line/polyarc center must normalize the direction sum before multiplying by the tool radius",
);

assert.doesNotMatch(
  sliceBetween("(defun db:line-polyarc-bisector-center", "(defun db:circle-segment-intersections"),
  /\(db:mul \(db:add u v\) radius\)/,
  "Line/polyarc center must not offset by one radius along each side of the reference square",
);

assert.match(
  source,
  /\(defun db:arc-bulge-with-start-tangent\b/,
  "Line/polyarc dogbones should choose arc direction by tangent continuity at the dogbone start",
);

assert.doesNotMatch(
  source,
  /near-arc\(start\|end\)|arc\(start\|end\)-near|near-source-end/i,
  "Source-circle tangency must not be hard-gated to a point near the polyarc endpoint",
);

assert.match(
  source,
  /\(cons 'skip-indices/,
  "Line/polyarc patches should carry trimmed duplicate-corner/source-arc vertex indices",
);

assert.match(
  source,
  /\(defun db:patch-skips-index-p\b/,
  "Polyline rebuilding should be able to skip vertices trimmed by a line/polyarc patch",
);

assert.match(
  source,
  /\(db:patch-skips-index-p i patches\)/,
  "Replacement vertices should omit duplicated corners and trimmed source arc vertices",
);

assert.match(
  source,
  /\(defun db:create-auto-patch\b/,
  "DBAUTO should choose specialized line/polyarc dogbones before falling back to line-line C dogbones",
);

assert.match(
  source,
  /\(setq patch \(db:create-auto-patch verts i p0 p1 p2 area is-hole\)\)/,
  "Automatic patch building should call the line/polyarc-aware patch factory",
);

const linePolyarcPatch = sliceBetween(
  "(defun db:create-line-polyarc-c-patch",
  "(defun db:create-polyarc-line-c-patch",
);

assert.match(
  linePolyarcPatch,
  /\(setq line-a \(nth \(db:wrap-index \(1- idx\) n\) pts\)\)/,
  "line -> duplicate corner -> polyarc should use the previous finite straight segment",
);

assert.match(
  linePolyarcPatch,
  /\(setq arc-run \(db:polyarc-run-forward pts dup-index\)\)/,
  "line -> duplicate corner -> polyarc should fit the source circle forward from the duplicate corner",
);

assert.match(
  linePolyarcPatch,
  /\(setq center \(db:line-polyarc-bisector-center corner line-back arc-tangent radius\)\)/,
  "line -> duplicate corner -> polyarc should place the tool circle one radius along the normalized bisector",
);

assert.doesNotMatch(
  linePolyarcPatch,
  /\(setq center \(cdr \(assoc 'center chosen\)\)\)/,
  "line -> duplicate corner -> polyarc should not drift the center to another tangent candidate",
);

assert.match(
  linePolyarcPatch,
  /\(setq start [\s\S]*?db:circle-line-noncorner-intersection center radius line-a line-b corner[\s\S]*?\(setq source-hit [\s\S]*?db:circle-polyarc-forward-intersection center radius pts arc-indices corner[\s\S]*?\(setq end \(cdr \(assoc 'point source-hit\)\)\)/,
  "line -> duplicate corner -> polyarc should output dogbone from the straight-line intersection to the source-segment intersection",
);

assert.match(
  linePolyarcPatch,
  /\(setq bulge \(db:arc-bulge-with-start-tangent center radius start end line-forward\)\)/,
  "line -> duplicate corner -> polyarc should follow the incoming straight-line tangent so the dogbone does not reverse outward",
);

assert.doesNotMatch(
  linePolyarcPatch,
  /db:fixed-center-line-circle-candidates|db:choose-polyarc-tangent-candidate|source-tangent chosen|db:arc-bulge-away-from-corner|db:arc-bulge-near-corner/,
  "line -> duplicate corner -> polyarc should not choose source endpoints from fitted-circle tangency or corner-distance direction",
);

assert.match(
  linePolyarcPatch,
  /\(setq skip \(cdr \(assoc 'skip-indices source-hit\)\)\)/,
  "line -> duplicate corner -> polyarc should trim duplicate and source arc vertices up to the source segment that contains the intersection",
);

const polyarcLinePatch = sliceBetween(
  "(defun db:create-polyarc-line-c-patch",
  "(defun db:find-polyarc-line-c-patch",
);

assert.match(
  polyarcLinePatch,
  /\(setq line-a corner\)[\s\S]*?\(setq line-b \(nth \(db:wrap-index \(\+ idx 2\) n\) pts\)\)/,
  "polyarc -> duplicate corner -> line should use the outgoing finite straight segment after the duplicate corner",
);

assert.match(
  polyarcLinePatch,
  /\(setq arc-run \(db:polyarc-run-ending-at pts idx\)\)/,
  "polyarc -> duplicate corner -> line should fit the source circle backward into the corner",
);

assert.match(
  polyarcLinePatch,
  /\(setq center \(db:line-polyarc-bisector-center corner \(db:mul arc-tangent -1\.0\) line-forward radius\)\)/,
  "polyarc -> duplicate corner -> line should place the tool circle one radius along the normalized bisector",
);

assert.doesNotMatch(
  polyarcLinePatch,
  /\(setq center \(cdr \(assoc 'center chosen\)\)\)/,
  "polyarc -> duplicate corner -> line should not drift the center to another tangent candidate",
);

assert.match(
  polyarcLinePatch,
  /\(setq source-hit [\s\S]*?db:circle-polyarc-backward-intersection center radius pts arc-indices corner[\s\S]*?\(setq start \(cdr \(assoc 'point source-hit\)\)\)/,
  "polyarc -> duplicate corner -> line should start the dogbone at the source-segment intersection",
);

assert.match(
  polyarcLinePatch,
  /\(setq end [\s\S]*?db:circle-line-noncorner-intersection center radius line-a line-b corner/,
  "polyarc -> duplicate corner -> line should end the dogbone at the straight-line intersection",
);

assert.match(
  polyarcLinePatch,
  /\(setq source-forward \(db:polyarc-tangent-forward fit start\)\)[\s\S]*?\(setq bulge \(db:arc-bulge-with-start-tangent center radius start end source-forward\)\)/,
  "polyarc -> duplicate corner -> line should follow the incoming source-arc tangent so the dogbone does not reverse outward",
);

assert.doesNotMatch(
  polyarcLinePatch,
  /db:fixed-center-line-circle-candidates|db:choose-polyarc-tangent-candidate|source-tangent chosen|db:arc-bulge-away-from-corner|db:arc-bulge-near-corner/,
  "polyarc -> duplicate corner -> line should not choose source endpoints from fitted-circle tangency or corner-distance direction",
);

assert.match(
  polyarcLinePatch,
  /\(setq skip \(append \(cdr \(assoc 'skip-indices source-hit\)\) \(list dup-index\)\)\)/,
  "polyarc -> duplicate corner -> line should trim source arc vertices after the source segment that contains the intersection and the duplicate corner",
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

console.log("DBAUTO line/polyarc source checks passed");
