#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const ELK = require("elkjs/lib/elk.bundled.js");

const HERE = __dirname;
const INPUT_DIR = path.join(HERE, "..", "..", "fixtures", "golden", "inputs");
const PINNED_ELKJS_VERSION = "0.11.0";
// The only case elkjs is expected to reject. Any other case rejecting is
// treated as an authoring/regression bug, not a golden to record.
const EXPECTED_ERROR_CASES = new Set(["hyperedge"]);
// The pinned rejection message itself (verified live against elkjs
// 0.11.0), not just "it threw something" -- a rejection for an unrelated
// reason (a real elkjs/graph-shape bug) must not be recorded as if it
// were the documented hyperedge rejection.
const HYPEREDGE_ERROR_PATTERN = /Passed edge is not 'simple'/;

function strip(value) {
  if (Array.isArray(value)) return value.map(strip);
  if (value && typeof value === "object") {
    const out = {};
    for (const [key, val] of Object.entries(value)) {
      if (key === "$H" || key === "container") continue;
      out[key] = strip(val);
    }
    return out;
  }
  if (typeof value === "number") {
    // A NaN/Infinity from elkjs itself would otherwise pass through
    // unchanged and `JSON.stringify` silently turns it into `null` --
    // which the Ruby side's `numeric_or_zero` then reads as 0.0, a false
    // parity match instead of the loud failure a genuinely broken elkjs
    // value deserves.
    if (!Number.isFinite(value)) {
      throw new Error(`non-finite number in elkjs result: ${value}`);
    }
    const rounded = Math.round(value * 1e6) / 1e6;
    // The multiply-then-divide above can itself overflow to Infinity for
    // a value near the double-precision max, even though `value` alone
    // passed the check above -- re-validated rather than assumed.
    if (!Number.isFinite(rounded)) {
      throw new Error(`rounding produced a non-finite number from ${value}`);
    }
    return rounded;
  }
  return value;
}

async function main() {
  const outDir = process.argv[2];
  if (!outDir) {
    console.error("usage: generate.js <output_dir>");
    process.exit(1);
  }

  const installedVersion = require("elkjs/package.json").version;
  if (installedVersion !== PINNED_ELKJS_VERSION) {
    console.error(
      `elkjs ${installedVersion} installed, expected exactly ${PINNED_ELKJS_VERSION} — ` +
        `run: npm ci --prefix spec/support/elkjs_golden`,
    );
    process.exit(1);
  }

  fs.mkdirSync(outDir, { recursive: true });

  const elk = new ELK();
  const files = fs.readdirSync(INPUT_DIR).filter((f) => f.endsWith(".json")).sort();
  const cases = [];

  for (const file of files) {
    const name = path.basename(file, ".json");
    const input = JSON.parse(fs.readFileSync(path.join(INPUT_DIR, file), "utf8"));

    // layoutResult/layoutError from elk.layout() are captured separately
    // from strip()'s own execution below -- a bug in strip() (our code,
    // not elkjs's) must never be recorded as if it were an elkjs
    // rejection.
    let layoutResult;
    let layoutError = null;
    try {
      layoutResult = await elk.layout(input.graph, { layoutOptions: input.options || {} });
    } catch (err) {
      layoutError = err;
    }

    let expected;
    if (EXPECTED_ERROR_CASES.has(name)) {
      if (!layoutError) {
        console.error(`${name}: expected elkjs to reject this case, but it succeeded`);
        process.exit(1);
      }
      if (!HYPEREDGE_ERROR_PATTERN.test(layoutError.message)) {
        console.error(`${name}: rejected, but not with the expected message: ${layoutError.message}`);
        process.exit(1);
      }
      expected = { error: layoutError.message };
    } else {
      if (layoutError) {
        console.error(`${name}: unexpected elkjs rejection: ${layoutError.message}`);
        process.exit(1);
      }
      expected = strip(layoutResult);
    }

    fs.writeFileSync(
      path.join(outDir, `${name}.json`),
      `${JSON.stringify(expected, null, 2)}\n`,
    );
    cases.push(name);
  }

  const missingErrorCases = [...EXPECTED_ERROR_CASES].filter((name) => !cases.includes(name));
  if (missingErrorCases.length > 0) {
    console.error(`expected-error case(s) never exercised: ${missingErrorCases.join(", ")}`);
    process.exit(1);
  }

  const manifest = {
    elkjs: require("elkjs/package.json").version,
    node: process.version,
    generated: new Date().toISOString(),
    cases,
  };
  fs.writeFileSync(
    path.join(outDir, "MANIFEST.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
