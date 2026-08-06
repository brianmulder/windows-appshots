import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { handleRequest, toolDefinitions } from "../mcp/server-lib.mjs";

test("advertises the complete appshot tool surface", () => {
  assert.deepEqual(
    toolDefinitions.map((tool) => tool.name),
    ["capture_appshot", "get_latest_appshot", "list_appshots", "stop_watcher"],
  );
  assert.match(toolDefinitions[0].description, /accessible text can be off-screen/i);
  assert.match(toolDefinitions[0].description, /ObservedAt\/CapturedAt/);
  assert.match(toolDefinitions[0].description, /5,000 nodes/);
  assert.match(toolDefinitions[1].description, /without recapturing/i);
  assert.deepEqual(toolDefinitions[0].inputSchema.properties.treeView.enum, [
    "control",
    "content",
    "raw",
  ]);
});

test("reports a clean stop when no verified watcher is running", (t) => {
  const root = mkdtempSync(join(tmpdir(), "windows-appshots-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const response = handleRequest({
    jsonrpc: "2.0",
    id: 4,
    method: "tools/call",
    params: { name: "stop_watcher", arguments: {} },
  }, root);

  assert.equal(response.result.isError, false);
  assert.equal(response.result.structuredContent.stopped, false);
  assert.match(response.result.content[0].text, /no verified/i);
});

test("does not stop a reused or mismatched watcher PID", (t) => {
  const root = mkdtempSync(join(tmpdir(), "windows-appshots-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  writeFileSync(join(root, "watcher.json"), JSON.stringify({
    Pid: process.pid,
    ProcessStartedAt: "2000-01-01T00:00:00.0000000Z",
    Executable: process.execPath,
    Tray: false,
  }));

  const response = handleRequest({
    jsonrpc: "2.0",
    id: 5,
    method: "tools/call",
    params: { name: "stop_watcher", arguments: {} },
  }, root);

  assert.equal(response.result.isError, false);
  assert.equal(response.result.structuredContent.stopped, false);
  assert.match(response.result.structuredContent.reason, /different process identity/i);
});

test("initializes with MCP tool capabilities", (t) => {
  const root = mkdtempSync(join(tmpdir(), "windows-appshots-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const response = handleRequest(
    {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: { protocolVersion: "2025-06-18" },
    },
    root,
    { startWatcher: false },
  );
  assert.equal(response.result.protocolVersion, "2025-06-18");
  assert.equal(response.result.serverInfo.name, "windows-appshots");
  assert.deepEqual(response.result.capabilities, {
    tools: { listChanged: false },
  });
});

test("returns a saved bundle as text plus image", (t) => {
  const root = mkdtempSync(join(tmpdir(), "windows-appshots-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const bundle = join(root, "captures", "fixture");
  mkdirSync(bundle, { recursive: true });
  writeFileSync(
    join(bundle, "manifest.json"),
    JSON.stringify({
      CapturedAt: "2026-07-27T00:00:00Z",
      Window: {
        Hwnd: "0x1234",
        ProcessId: 42,
        ProcessName: "fixture",
        Title: "Fixture",
        ObservedAt: "2026-07-26T23:59:59Z",
      },
      AccessibilityTree: "accessibility-tree.json",
      Limits: { MaxNodes: 5000, MaxText: 200000, MaxDepth: 40, TimeoutMs: 15000 },
      Truncated: false,
      CredentialRedaction: {
        Policy: "credentials-v1",
        Succeeded: true,
        SemanticArtifactsSanitized: true,
        RawMatchesPersisted: false,
        VisualRedacted: false,
      },
    }),
  );
  writeFileSync(join(bundle, "model-context.md"), "# Fixture AppShot");
  writeFileSync(
    join(bundle, "visual.png"),
    Buffer.from("iVBORw0KGgo=", "base64"),
  );
  writeFileSync(
    join(root, "latest-capture.json"),
    JSON.stringify({ bundle }),
  );

  const response = handleRequest({
    jsonrpc: "2.0",
    id: 2,
    method: "tools/call",
    params: { name: "get_latest_appshot", arguments: {} },
  }, root);

  assert.equal(response.result.isError, false);
  assert.equal(response.result.content[0].type, "text");
  assert.match(response.result.content[0].text, /Fixture AppShot/);
  assert.equal(response.result.content[1].type, "image");
  assert.equal(response.result.content[1].mimeType, "image/png");
  assert.equal(response.result.structuredContent.target.processName, "fixture");
  assert.equal(response.result.structuredContent.target.observedAt, "2026-07-26T23:59:59Z");
  assert.equal(response.result.structuredContent.captureLimits.MaxDepth, 40);
  assert.equal(response.result.structuredContent.truncated, false);
});

test("refuses semantic retrieval from a legacy unverified bundle", (t) => {
  const root = mkdtempSync(join(tmpdir(), "windows-appshots-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const bundle = join(root, "captures", "legacy");
  mkdirSync(bundle, { recursive: true });
  writeFileSync(join(bundle, "manifest.json"), JSON.stringify({
    CapturedAt: "2026-07-27T00:00:00Z",
    Window: { ProcessName: "fixture", Title: "client_secret=LEGACY_SECRET_SENTINEL" },
    AccessibilityTree: "accessibility-tree.json",
  }));
  writeFileSync(join(bundle, "model-context.md"), "LEGACY_SECRET_SENTINEL");
  writeFileSync(join(root, "latest-capture.json"), JSON.stringify({ bundle }));

  const response = handleRequest({
    jsonrpc: "2.0",
    id: 6,
    method: "tools/call",
    params: { name: "get_latest_appshot", arguments: {} },
  }, root);

  assert.equal(response.result.isError, true);
  assert.match(response.result.content[0].text, /legacy|unverified/i);
  assert.doesNotMatch(response.result.content[0].text, /LEGACY_SECRET_SENTINEL/);
});

test("lists legacy bundles without unchecked semantic metadata", (t) => {
  const root = mkdtempSync(join(tmpdir(), "windows-appshots-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const bundle = join(root, "captures", "legacy");
  mkdirSync(bundle, { recursive: true });
  writeFileSync(join(bundle, "manifest.json"), JSON.stringify({
    CapturedAt: "2026-07-27T00:00:00Z",
    Window: { ProcessName: "fixture", Title: "token=LEGACY_LIST_SECRET_SENTINEL" },
  }));

  const response = handleRequest({
    jsonrpc: "2.0",
    id: 7,
    method: "tools/call",
    params: { name: "list_appshots", arguments: {} },
  }, root);

  assert.equal(response.result.isError, false);
  assert.equal(response.result.structuredContent.appshots[0].redactionVerified, false);
  assert.equal(response.result.structuredContent.appshots[0].legacy, true);
  assert.doesNotMatch(response.result.content[0].text, /LEGACY_LIST_SECRET_SENTINEL/);
});

test("rejects a latest-capture pointer outside the capture store", (t) => {
  const root = mkdtempSync(join(tmpdir(), "windows-appshots-test-"));
  const outside = mkdtempSync(join(tmpdir(), "windows-appshots-outside-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  t.after(() => rmSync(outside, { recursive: true, force: true }));
  writeFileSync(join(outside, "manifest.json"), "{}");
  writeFileSync(join(outside, "model-context.md"), "# Outside");
  writeFileSync(
    join(root, "latest-capture.json"),
    JSON.stringify({ bundle: outside }),
  );

  const response = handleRequest({
    jsonrpc: "2.0",
    id: 3,
    method: "tools/call",
    params: { name: "get_latest_appshot", arguments: {} },
  }, root);

  assert.equal(response.result.isError, true);
  assert.match(response.result.content[0].text, /outside the capture store/i);
});
