import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const manifest = JSON.parse(
  readFileSync(join(root, ".codex-plugin", "plugin.json"), "utf8"),
);

test("plugin advertises persisted AppShots instead of live computer use", () => {
  assert.equal(manifest.skills, undefined);
  assert.match(manifest.interface.shortDescription, /Save a semantic AppShot/);
  assert.match(manifest.interface.longDescription, /persisted Windows AppShot/);
  assert.match(manifest.interface.longDescription, /not live computer-use/);
  assert.ok(
    manifest.interface.defaultPrompt.every((prompt) =>
      /AppShot/.test(prompt),
    ),
  );
});
