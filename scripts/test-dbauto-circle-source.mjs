import fs from "node:fs";
import assert from "node:assert/strict";

const source = fs.readFileSync(new URL("../dogbone.lsp", import.meta.url), "utf8");

assert.match(
  source,
  /\(setq \*db-circle-min-vertices\* 24\)/,
  "Segmented circles should require at least 24 vertices",
);

assert.match(
  source,
  /\(setq \*db-circle-radius-tol\* 0\.001\)/,
  "Segmented-circle radial tolerance should be 0.1 percent",
);

assert.match(
  source,
  /\(defun db:segmented-circle-data\b/,
  "DBAUTO should expose isolated segmented-circle recognition",
);

assert.doesNotMatch(
  source,
  /\(defun db:circumcircle-3pt\b/,
  "Even symmetric circles should not depend on a three-point circumcircle",
);

assert.match(
  source,
  /\(= 1 \(rem n 2\)\)/,
  "Segmented circles should require an even vertex count",
);

assert.match(
  source,
  /\(setq half \(fix \(\/ n 2\)\)\)/,
  "Circle recognition should pair each vertex with its opposite vertex",
);

assert.match(
  source,
  /\(setq center \(db:mul \(db:add \(nth 0 pts\) \(nth half pts\)\) 0\.5\)\)/,
  "The circle center should be the midpoint of an opposite vertex pair",
);

assert.match(
  source,
  /\(> center-error \(\* radius \*db-circle-radius-tol\*\)\)/,
  "Every opposite pair midpoint should agree within the circle tolerance",
);

assert.match(
  source,
  /\(defun db:circle-ordered-p\b/,
  "Circle recognition should reject duplicate, reversing, or multi-turn vertex paths",
);

assert.match(
  source,
  /\(db:circle-ordered-p pts center\)/,
  "Circle fitting should validate that vertices traverse exactly one ordered circle",
);

assert.match(
  source,
  /\(< \(length pts\) \*db-circle-min-vertices\*\)/,
  "Circle recognition should reject outlines below the vertex threshold",
);

assert.match(
  source,
  /\(> max-error \(\* radius \*db-circle-radius-tol\*\)\)/,
  "Circle recognition should reject radial error above the relative tolerance",
);

assert.match(
  source,
  /\(defun db:make-circle-from-item\b/,
  "Direct segmented circles should be replaced by CIRCLE entities",
);

assert.match(
  source,
  /\(defun db:circle-polyline-vertices\b/,
  "Block segmented circles should have an exact two-bulge representation",
);

assert.match(
  source,
  /\(list \(list start bulge\) \(list end bulge\)\)/,
  "The block representation should contain two semicircular bulges",
);

assert.match(
  source,
  /\(if \(> area 0\.0\) 1\.0 -1\.0\)/,
  "Exact block circles should preserve source winding",
);

assert.match(
  source,
  /\(setq circle-data \(if \(db:has-bulge verts\) nil \(db:segmented-circle-data pts\)\)\)/,
  "Entity collection should tag non-bulged segmented circles before dogbone processing",
);

assert.match(
  source,
  /\(if circle-data[\s\S]*?\(db:make-circle-from-item item circle-data\)/,
  "Recognized direct circles should use the CIRCLE persistence path",
);

assert.match(
  source,
  /\(if circle-data[\s\S]*?\(db:update-lwpolyline-in-place[\s\S]*?\(db:circle-polyline-vertices/,
  "Recognized block circles should use exact in-place circular polylines",
);

assert.match(
  source,
  /\(cons 'circles-detected circle-detected-count\)/,
  "Per-group results should count detected segmented circles",
);

assert.match(
  source,
  /segmented circles detected=/,
  "DBAUTO output should report detected segmented circles",
);

assert.match(
  source,
  /circle conversions failed=/,
  "DBAUTO output should report failed circle conversions",
);

console.log("DBAUTO segmented-circle source checks passed");
