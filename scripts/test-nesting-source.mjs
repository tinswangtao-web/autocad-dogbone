import fs from "node:fs";
import assert from "node:assert/strict";

const source = fs.readFileSync(new URL("../dogbone.lsp", import.meta.url), "utf8");

assert.match(
  source,
  /\(setq \*db-version\* "V2\.1-Nest-Compact-500"\)/,
  "The plugin should expose a unique compact-packing version so AutoCAD reloads are visible",
);

assert.match(
  source,
  /\(setq \*db-nest-gap\* 6\.0\)/,
  "Default component-to-component nesting gap should be 6 mm",
);

assert.match(
  source,
  /\(setq \*db-nest-edge-margin\* 2\.0\)/,
  "Default component-to-sheet-edge nesting margin should be 2 mm",
);

assert.match(
  source,
  /\(setq \*db-nest-sheet-gap\* 500\.0\)/,
  "Default copied sheet-to-sheet spacing should be 500 mm",
);

assert.match(
  source,
  /\(defun c:DBVER\b/,
  "The plugin should provide DBVER to confirm which dogbone.lsp is loaded",
);

assert.match(
  source,
  /\(defun db:collect-sheet-obstacles\b/,
  "DBNEST should collect existing sheet objects as placement obstacles",
);

assert.match(
  source,
  /\(defun db:circle-bbox\b/,
  "Nesting should support CIRCLE geometry so holes can move with their containing part",
);

assert.match(
  source,
  /\(\(= etype "CIRCLE"\)\s+\(db:circle-bbox ename\)\)/,
  "Unified AABB dispatch should include CIRCLE entities",
);

assert.match(
  source,
  /\(defun db:group-nest-items\b/,
  "Nesting should group contained outlines and holes into one movable part",
);

assert.match(
  source,
  /\(ssget '\(\(0 \. "LWPOLYLINE,INSERT,CIRCLE"\)\)\)/,
  "Nesting selection should include circles used as holes inside a component",
);

assert.match(
  source,
  /\(ssget "_C" minpt maxpt '\(\(0 \. "LWPOLYLINE,INSERT,CIRCLE"\)\)\)/,
  "Sheet obstacle collection should include circles",
);

assert.match(
  source,
  /\(defun db:bottom-left-pack\b/,
  "DBNEST should use an obstacle-aware bottom-left packer",
);

assert.match(
  source,
  /\(defun db:find-placement\b/,
  "Nesting should keep the older bottom-left single-part placement helper available",
);

assert.match(
  source,
  /\(defun db:maxrect-find-placement\b/,
  "DBNEST should use a MaxRects-style placement search for tighter packing",
);

assert.match(
  source,
  /\(defun db:maxrect-anchors\b/,
  "MaxRects placement should enumerate multiple anchor positions inside each free rectangle",
);

assert.match(
  source,
  /"LB"[\s\S]*"RB"[\s\S]*"LT"[\s\S]*"RT"/,
  "MaxRects anchor positions should include lower-left, lower-right, upper-left, and upper-right",
);

assert.match(
  source,
  /\(defun db:maxrect-anchor-candidate\b/,
  "MaxRects placement should build candidates for each anchor position",
);

assert.match(
  source,
  /\(defun db:maxrect-init-free-rects\b/,
  "DBNEST should initialize free rectangles from the usable sheet area and existing obstacles",
);

assert.match(
  source,
  /\(defun db:maxrect-split-free-rect\b/,
  "DBNEST should split remaining free rectangles after each placement",
);

assert.match(
  source,
  /\(defun db:maxrect-prune-free-rects\b/,
  "DBNEST should prune contained free rectangles to keep the search space compact",
);

assert.match(
  source,
  /\(defun db:maxrect-update-free-rects\b/,
  "DBNEST should update each board's free rectangles after placing a part",
);

const maxrectFindPlacementMatch = source.match(/\(defun db:maxrect-find-placement\b[\s\S]*?\n\)\n\n;;; ---------------------------------------------------------------------------\n;;; db:bottom-left-pack/);
assert.ok(maxrectFindPlacementMatch, "MaxRects placement helper should be present before bottom-left packer");

assert.match(
  maxrectFindPlacementMatch[0],
  /\(setq anchors \(db:maxrect-anchors\)\)/,
  "MaxRects placement should load the four anchor positions before candidate search",
);

assert.match(
  maxrectFindPlacementMatch[0],
  /\(foreach anchor anchors[\s\S]*\(foreach orient orientations/,
  "MaxRects placement should try every orientation for every anchor position",
);

assert.match(
  maxrectFindPlacementMatch[0],
  /\(setq candidate \(db:maxrect-anchor-candidate free pw ph anchor\)\)/,
  "MaxRects placement should create each candidate from the current free rectangle, orientation, and anchor",
);

assert.match(
  source,
  /\(defun db:lwpoly-bbox-points\b/,
  "Nesting AABBs should include bulge arc extrema, not only polyline vertices",
);

assert.match(
  source,
  /\(db:lwpoly-bbox-points closed verts\)/,
  "LWPOLYLINE nesting bboxes should use arc-aware bbox points",
);

assert.match(
  source,
  /\(db:lwpoly-bbox-points \(car data\) \(cadr data\)\)/,
  "INSERT nesting bboxes should include arc-aware points from nested LWPOLYLINE entities",
);

assert.match(
  source,
  /\(defun db:part-orientations\b/,
  "DBNEST should evaluate 0 and 90 degree orientations for each part",
);

assert.match(
  source,
  /\(defun db:rotate-entity-90\b/,
  "DBNEST should rotate entities when the selected orientation is 90 degrees",
);

assert.match(
  source,
  /\(setq obstacles \(db:collect-sheet-obstacles\b/,
  "DBNEST should pass collected obstacles into packing",
);

assert.match(
  source,
  /\(db:rotate-entity-90 en bbox\)/,
  "DBNEST should rotate placed parts before the final move when needed",
);

assert.match(
  source,
  /\(command "_.MOVE" ename "" "_non" from-pt "_non" to-pt\)/,
  "Automated MOVE should use _non point input so object snaps do not distort nesting placement",
);

assert.match(
  source,
  /\(command "_.ROTATE" ename "" "_non" base "90"\)/,
  "Single-entity ROTATE should use _non base point so intersection snap cannot change rotation origin",
);

assert.match(
  source,
  /\(command "_.ROTATE" en "" "_non" base "90"\)/,
  "Grouped ROTATE should use _non base point so intersection snap cannot change rotation origin",
);

assert.match(
  source,
  /\(command "_.COPY" sheet-en "" "_non" from-pt "_non" to-pt\)/,
  "Automated sheet COPY should use _non point input so copied boards keep the requested gap",
);

assert.match(
  source,
  /\(defun db:place-nested-part\b/,
  "Nesting should move every entity in a grouped component together",
);

assert.match(
  source,
  /\(foreach en entities[\s\S]*?\(db:move-entity-to en from-pt to-pt\)/,
  "Grouped component placement should move all child entities, not only the outer outline",
);

assert.match(
  source,
  /\(defun db:copy-sheet-frame\b/,
  "Multi-sheet nesting should copy the selected sheet frame as needed",
);

assert.match(
  source,
  /\(defun db:find-empty-sheet-bbox\b/,
  "Multi-sheet nesting should find an empty target region before copying a sheet frame",
);

assert.match(
  source,
  /\(db:find-empty-sheet-bbox template-bbox sheet-gap occupied-sheet-bboxes\b/,
  "Multi-sheet nesting should skip copied sheet positions that already contain drawing objects",
);

assert.match(
  source,
  /\(defun c:DBNESTM\b/,
  "Multi-sheet nesting should provide a DBNESTM command",
);

const dbnestMatch = source.match(/\(defun c:DBNEST\b[\s\S]*?\n\)\n\n;;; ---------------------------------------------------------------------------\n;;; c:DBNESTM/);
assert.ok(dbnestMatch, "DBNEST command body should be present before DBNESTM");

assert.match(
  dbnestMatch[0],
  /\(db:run-multi-sheet-nest "DBNEST"\)/,
  "DBNEST should auto-create additional sheet frames when one sheet cannot fit selected parts",
);

const multiSheetRunnerMatch = source.match(/\(defun db:run-multi-sheet-nest\b[\s\S]*?\n\)\n\n;;; ---------------------------------------------------------------------------\n;;; c:DBNEST/);
assert.ok(multiSheetRunnerMatch, "Shared multi-sheet nesting runner should be present before DBNEST");

assert.match(
  multiSheetRunnerMatch[0],
  /DBNEST-DIAG/,
  "DBNEST should print runtime diagnostic data so stale loads and wrong grouping are visible",
);

assert.match(
  source,
  /\(setq \*db-last-nest-raw-count\* n\)/,
  "Nesting collection should remember raw selected entity count for diagnostics",
);

assert.match(
  source,
  /\(setq \*db-last-nest-group-count\* \(length parts\)\)/,
  "Nesting collection should remember grouped component count for diagnostics",
);

assert.match(
  source,
  /\(setq \*db-last-tail-compact-status\* "SKIPPED"\)/,
  "Tail-board compaction diagnostics should start with a visible skipped state",
);

assert.match(
  source,
  /\(setq \*db-last-tail-compact-before\* \(length boards\)\)/,
  "Tail-board compaction should record the board count before refill attempts",
);

assert.match(
  source,
  /\(setq \*db-last-tail-compact-after\* \(length \(cadr compacted\)\)\)/,
  "Tail-board compaction should record the board count after refill attempts",
);

assert.match(
  multiSheetRunnerMatch[0],
  /tail-compact=/,
  "DBNEST diagnostics should print tail-board compaction status",
);

assert.match(
  source,
  /\(defun db:nest-sort-variants\b/,
  "Nesting should try multiple part ordering strategies instead of only area-desc",
);

assert.match(
  source,
  /"AREA"[\s\S]*"WIDTH"[\s\S]*"HEIGHT"[\s\S]*"LONG"/,
  "Nesting strategy variants should include area, width, height, and long-side ordering",
);

assert.match(
  source,
  /\(defun db:pack-score\b/,
  "Nesting should score packed results so it can choose the tighter attempt",
);

assert.match(
  source,
  /\(defun db:multi-sheet-pack-best\b/,
  "Nesting should run multiple pack attempts and keep the best result",
);

assert.match(
  source,
  /\(defun db:tail-board-results\b/,
  "Nesting should be able to identify parts placed on the last board for refill compaction",
);

assert.match(
  source,
  /\(defun db:compact-tail-board\b/,
  "Nesting should try to refill earlier boards with the final board's parts before accepting an extra sheet",
);

assert.match(
  source,
  /\(defun db:try-place-result-on-earlier-board\b/,
  "Tail-board compaction should try moving a tail-board part back onto an earlier board",
);

assert.match(
  source,
  /\(db:compact-tail-board packed gap\)/,
  "Best-pack selection should compact the chosen result before scoring and returning it",
);

assert.match(
  source,
  /\(db:multi-sheet-pack sorted template-bbox gap edge-margin sheet-gap initial-obstacles\)/,
  "Best-pack selection should still use the shared multi-sheet packer with separate edge margin",
);

assert.match(
  multiSheetRunnerMatch[0],
  /\(db:multi-sheet-pack-best parts sheet-bbox \*db-nest-gap\* \*db-nest-edge-margin\* sheet-gap obstacles\)/,
  "Shared nesting runner should pick the best multi-strategy packing result with separate edge margin",
);

assert.match(
  multiSheetRunnerMatch[0],
  /\(db:copy-sheet-frame sheet-en sheet-bbox \(car board\)\)/,
  "Shared nesting runner should copy additional sheet frames produced by multi-sheet packing",
);

assert.match(
  multiSheetRunnerMatch[0],
  /\(setq \*db-nest-sheet-gap\* \(db:normalize-sheet-gap \*db-nest-sheet-gap\*\)\)/,
  "Shared nesting runner should reset stale zero sheet spacing before prompting",
);

assert.match(
  multiSheetRunnerMatch[0],
  /\(if \(and gap-input \(> gap-input 0\.0\)\)/,
  "Shared nesting runner should ignore zero sheet spacing input instead of making copied sheets touch",
);

assert.match(
  source,
  /\(defun db:sheet-placement-bbox\b/,
  "Nesting should inset the usable sheet area so parts do not touch or overflow the frame",
);

assert.match(
  source,
  /\(db:maxrect-init-free-rects \(db:sheet-placement-bbox template-bbox edge-margin\) initial-obstacles gap\)/,
  "Multi-sheet packing should initialize first-board free rectangles with edge margin and component gap",
);

assert.match(
  source,
  /\(db:maxrect-find-placement part \(nth 2 board\) gap\)/,
  "Multi-sheet packing should place parts by searching each board's current free rectangles",
);

assert.match(
  source,
  /\(db:maxrect-find-placement part \(db:maxrect-init-free-rects \(db:sheet-placement-bbox new-bbox edge-margin\) '\(\) gap\) gap\)/,
  "New sheet packing should also use edge margin when creating its initial free rectangle",
);

assert.match(
  source,
  /\(setq packed \(db:multi-sheet-pack-best parts sheet-bbox \*db-nest-gap\* \*db-nest-edge-margin\* sheet-gap obstacles\)\)/,
  "DBNEST should pass separate component gap and edge margin into best-of multi-sheet packing",
);

assert.match(
  source,
  /边缘留边/,
  "DBNSET and diagnostics should expose editable edge margin text",
);

assert.match(
  source,
  /\(defun db:normalize-sheet-gap\b/,
  "Copied sheet spacing should normalize zero or invalid sheet gaps to a positive default",
);

assert.match(
  source,
  /\(defun db:normalize-sheet-gap\b[\s\S]*?500\.0/,
  "Invalid copied sheet spacing should fall back to the 500 mm default",
);

assert.match(
  source,
  /DBNESTM/,
  "The load prompt should advertise DBNESTM",
);

console.log("nesting source checks passed");
