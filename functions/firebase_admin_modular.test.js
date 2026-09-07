const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {spawnSync} = require("node:child_process");
const test = require("node:test");

const functionsDirectory = __dirname;
const entrypointPath = path.join(functionsDirectory, "index.js");

test("functions entrypoint loads with the modular Firebase Admin SDK", () => {
  const result = spawnSync(process.execPath, [
    "-e",
    "const functions = require('./index.js'); " +
      "if (typeof functions.verifySubscriptionPurchase !== 'function') " +
      "process.exit(1);",
  ], {
    cwd: functionsDirectory,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
});

test("functions entrypoint does not use removed Admin namespace APIs", () => {
  const source = fs.readFileSync(entrypointPath, "utf8");

  assert.doesNotMatch(
      source,
      /\badmin\.(firestore|auth|storage|messaging|initializeApp)\b/,
  );
});
