import fs from "node:fs";
import assert from "node:assert/strict";

const source = fs.readFileSync(new URL("../dogbone.lsp", import.meta.url), "utf8");

assert.match(
  source,
  /\(defun db:collect-sheet-obstacles\b/,
  "DBNEST should collect existing sheet objects as placement obstacles",
);

assert.match(
  source,
  /\(defun db:bottom-left-pack\b/,
  "DBNEST should use an obstacle-aware bottom-left packer",
);

assert.match(
  source,
  /\(defun db:find-placement\b/,
  "Nesting should expose single-part placement for multi-sheet packing",
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

assert.match(
  source,
  /DBNESTM/,
  "The load prompt should advertise DBNESTM",
);

console.log("nesting source checks passed");
