import fs from "node:fs";
import assert from "node:assert/strict";

const source = fs.readFileSync(new URL("../dogbone.lsp", import.meta.url), "utf8");

assert.match(
  source,
  /\(ssget '\(\(0 \. "LWPOLYLINE,INSERT"\)\)\)/,
  "DBAUTO should accept direct polylines and block references",
);

assert.match(
  source,
  /\(defun db:unit-scale-insert-p\b/,
  "DBAUTO should validate block reference scale",
);

assert.match(
  source,
  /\(defun db:collect-block-polylines\b/,
  "DBAUTO should collect direct LWPOLYLINE children from a block definition",
);

assert.match(
  source,
  /\(defun db:collect-dbauto-groups\b/,
  "DBAUTO should expand and deduplicate the mixed selection into processing groups",
);

assert.match(
  source,
  /\(defun db:process-dbauto-group\b/,
  "DBAUTO should process each containment group independently",
);

assert.doesNotMatch(
  source,
  /\(defun db:collect-block-polylines[\s\S]*?\(db:collect-block-polylines\s+sub-/,
  "Block polyline collection should not recurse into nested INSERT definitions",
);

console.log("DBAUTO block source checks passed");
