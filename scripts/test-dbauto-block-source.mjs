import fs from "node:fs";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";

const refIndex = process.argv.indexOf("--git-ref");
const source = refIndex >= 0
  ? execFileSync("git", ["show", `${process.argv[refIndex + 1]}:dogbone.lsp`], { encoding: "utf8" })
  : fs.readFileSync(new URL("../dogbone.lsp", import.meta.url), "utf8");
const dbautoStart = source.indexOf("(defun c:DBAUTO");
const dbautoEnd = source.indexOf(";;; =========================================================================", dbautoStart);

assert.notEqual(dbautoStart, -1, "dogbone.lsp should define c:DBAUTO");
assert.notEqual(dbautoEnd, -1, "c:DBAUTO should end before the nesting module");

const dbauto = source.slice(dbautoStart, dbautoEnd);

assert.match(
  dbauto,
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

assert.match(
  dbauto,
  /\(setq selection \(db:collect-dbauto-groups ss\)\)/,
  "DBAUTO should expand mixed selections before geometry processing",
);

assert.match(
  dbauto,
  /\(db:process-dbauto-group \(nth 2 group\)\)/,
  "DBAUTO should process each block definition as an independent group",
);

assert.match(
  source,
  /\(setq owner \(cdr \(assoc 330 \(entget \(car item\)\)\)\)\)/,
  "Replacement polylines should preserve their source owner",
);

function assertBalancedParens(text) {
  let depth = 0;
  let inString = false;
  let inComment = false;

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    if (inComment) {
      if (char === "\n") inComment = false;
      continue;
    }
    if (!inString && char === ";") {
      inComment = true;
      continue;
    }
    if (char === '"' && text[i - 1] !== "\\") {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (char === "(") depth += 1;
    if (char === ")") depth -= 1;
    assert.ok(depth >= 0, `dogbone.lsp has an unmatched closing parenthesis at offset ${i}`);
  }

  assert.equal(inString, false, "dogbone.lsp has an unterminated string");
  assert.equal(depth, 0, `dogbone.lsp has ${depth} unmatched opening parentheses`);
}

assertBalancedParens(source);

console.log("DBAUTO block source checks passed");
