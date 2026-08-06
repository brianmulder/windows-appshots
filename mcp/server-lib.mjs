import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const moduleRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const nativeExe = join(moduleRoot, "bin", "AppshotCapture.exe");
const defaultStateRoot = join(
  process.env.LOCALAPPDATA || join(homedir(), "AppData", "Local"),
  "WindowsAppshots",
);

export const toolDefinitions = [
  {
    name: "capture_appshot",
    description:
      "Explicitly capture a Windows app as pixels plus bounded Microsoft UI Automation semantics. With hwnd, capture that exact validated window identity; otherwise capture the last non-Codex foreground identity remembered by the watcher. Confirm the returned process/title and ObservedAt/CapturedAt are the intended fresh target. Defaults: 5,000 nodes, 200,000 text characters, depth 40, and a 15-second UIA deadline; the result reports applied limits and truncation. High-confidence credentials are removed from semantic content, pixels are not redacted, and accessible text can be off-screen. Call only when the user asks to share or inspect that application context.",
    inputSchema: {
      type: "object",
      properties: {
        hwnd: {
          type: "string",
          description:
            "Optional explicit HWND in decimal or 0x hexadecimal form. Its live PID and process-start identity are validated before capture. Omit to use the watcher's last remembered non-Codex foreground identity.",
        },
        maxNodes: {
          type: "integer",
          minimum: 100,
          maximum: 20000,
          default: 5000,
          description: "Maximum UI Automation nodes. Hitting this bound sets Truncated in the result manifest.",
        },
        maxText: {
          type: "integer",
          minimum: 1000,
          maximum: 1000000,
          default: 200000,
          description: "Maximum characters of provider-exposed accessible text across the capture.",
        },
        treeView: {
          type: "string",
          enum: ["control", "content", "raw"],
          default: "control",
          description:
            "UI Automation view to export. raw is the fullest provider-exposed tree but can be very large and noisy.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "get_latest_appshot",
    description:
      "Return the most recently saved Windows AppShot without recapturing. It may be stale: verify CapturedAt and the returned target process/title before using it. The result includes the applied capture limits, truncation state, image, and semantic summary.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "list_appshots",
    description:
      "List recent local Windows AppShot bundles and capture times without reading their captured content. Use CapturedAt to select a sufficiently fresh bundle; verified bundles also include redacted target process/title metadata.",
    inputSchema: {
      type: "object",
      properties: {
        limit: { type: "integer", minimum: 1, maximum: 100, default: 20 },
      },
      additionalProperties: false,
    },
  },
  {
    name: "stop_watcher",
    description:
      "Stop the verified local Windows AppShots foreground watcher. Existing captures remain on disk, and capture_appshot can still capture an explicit HWND.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
];

export function stateRoot(env = process.env) {
  return env.WINDOWS_APPSHOTS_STATE_ROOT || defaultStateRoot;
}

export function ensureNativeBuilt() {
  if (existsSync(nativeExe)) return;
  const script = join(moduleRoot, "scripts", "build.ps1");
  const result = spawnSync(
    "powershell.exe",
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script],
    { cwd: moduleRoot, encoding: "utf8" },
  );
  if (result.status !== 0 || !existsSync(nativeExe)) {
    throw new Error(
      `Windows AppShots native helper is unavailable.\n${result.stderr || result.stdout}`,
    );
  }
}

export function startWatcher(root = stateRoot()) {
  ensureNativeBuilt();
  mkdirSync(root, { recursive: true });
  const status = invokeNative(["watcher-status"], root);
  if (status.running) return { started: false, pid: status.pid, tray: status.tray };

  const child = spawn(nativeExe, ["watch", "--state-root", root], {
    detached: true,
    stdio: "ignore",
    windowsHide: true,
  });
  child.unref();
  return { started: true, pid: child.pid };
}

function invokeNative(args, root = stateRoot()) {
  ensureNativeBuilt();
  const result = spawnSync(nativeExe, [...args, "--state-root", root], {
    encoding: "utf8",
    windowsHide: true,
    timeout: 45_000,
    maxBuffer: 10 * 1024 * 1024,
  });
  if (result.status !== 0) {
    let message = result.stderr || result.stdout || `exit ${result.status}`;
    try {
      message = JSON.parse(message.trim()).error;
    } catch {
      // Keep the native diagnostic.
    }
    throw new Error(message);
  }
  return JSON.parse(result.stdout.trim());
}

function latestBundle(root = stateRoot()) {
  const pointer = join(root, "latest-capture.json");
  if (!existsSync(pointer)) {
    throw new Error(
      "No Windows AppShot has been captured yet. Focus a target window and call capture_appshot.",
    );
  }
  const data = JSON.parse(readFileSync(pointer, "utf8"));
  if (!data.bundle || !existsSync(data.bundle)) {
    throw new Error("The latest Windows AppShot bundle no longer exists.");
  }
  const captureRoot = resolve(root, "captures");
  const bundle = resolve(data.bundle);
  const fromCaptureRoot = relative(captureRoot, bundle);
  if (
    !fromCaptureRoot ||
    fromCaptureRoot.startsWith("..") ||
    resolve(captureRoot, fromCaptureRoot) !== bundle
  ) {
    throw new Error("The latest Windows AppShot pointer is outside the capture store.");
  }
  return bundle;
}

function isRedactionVerified(manifest) {
  const receipt = manifest?.CredentialRedaction;
  return receipt?.Policy === "credentials-v1" &&
    receipt?.Succeeded === true &&
    receipt?.SemanticArtifactsSanitized === true &&
    receipt?.RawMatchesPersisted === false &&
    receipt?.VisualRedacted === false;
}

function requireRedactionVerified(manifest) {
  if (!isRedactionVerified(manifest)) {
    throw new Error(
      "This AppShot is legacy or unverified and its semantic content will not be returned. Capture the application again.",
    );
  }
}

function bundleContent(bundle) {
  const manifestPath = join(bundle, "manifest.json");
  const contextPath = join(bundle, "model-context.md");
  const visualPath = join(bundle, "visual.png");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  requireRedactionVerified(manifest);
  const summary = readFileSync(contextPath, "utf8");
  const target = {
    capturedAt: manifest.CapturedAt,
    observedAt: manifest.Window?.ObservedAt,
    hwnd: manifest.Window?.Hwnd,
    processId: manifest.Window?.ProcessId,
    processName: manifest.Window?.ProcessName,
    title: manifest.Window?.Title,
  };
  const verification =
    `Target verification: ${JSON.stringify(target)}\n` +
    `Capture limits: ${JSON.stringify(manifest.Limits || {})}\n` +
    `Truncated: ${manifest.Truncated === true}`;
  const content = [
    {
      type: "text",
      text:
        `${summary}\n\n${verification}\nBundle: ${bundle}\n` +
        `Manifest: ${manifestPath}\nAccessibility tree: ${join(bundle, manifest.AccessibilityTree)}`,
    },
  ];
  if (existsSync(visualPath)) {
    content.push({
      type: "image",
      data: readFileSync(visualPath).toString("base64"),
      mimeType: "image/png",
    });
  }
  return {
    content,
    structuredContent: {
      bundle,
      target,
      captureLimits: manifest.Limits || null,
      truncated: manifest.Truncated === true,
      manifest,
    },
    isError: false,
  };
}

export function callTool(name, args = {}, root = stateRoot()) {
  if (name === "capture_appshot") {
    const nativeArgs = ["capture-bounded"];
    if (args.hwnd) nativeArgs.push("--hwnd", String(args.hwnd));
    if (args.maxNodes) nativeArgs.push("--max-nodes", String(args.maxNodes));
    if (args.maxText) nativeArgs.push("--max-text", String(args.maxText));
    if (args.treeView) nativeArgs.push("--tree-view", String(args.treeView));
    const result = invokeNative(nativeArgs, root);
    return bundleContent(result.bundle);
  }

  if (name === "get_latest_appshot") {
    return bundleContent(latestBundle(root));
  }

  if (name === "list_appshots") {
    const captureRoot = join(root, "captures");
    const limit = Math.max(1, Math.min(100, args.limit || 20));
    const bundles = existsSync(captureRoot)
      ? readdirSync(captureRoot)
          .map((name) => join(captureRoot, name))
          .filter((path) => statSync(path).isDirectory())
          .sort()
          .reverse()
          .slice(0, limit)
          .map((path) => {
            const manifestPath = join(path, "manifest.json");
            if (!existsSync(manifestPath)) {
              return { bundle: path, redactionVerified: false, legacy: true };
            }
            const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
            if (!isRedactionVerified(manifest)) {
              return {
                bundle: path,
                capturedAt: manifest.CapturedAt,
                redactionVerified: false,
                legacy: true,
              };
            }
            return {
              bundle: path,
              capturedAt: manifest.CapturedAt,
              application: manifest.Window?.ProcessName,
              title: manifest.Window?.Title,
              redactionVerified: true,
              legacy: false,
            };
          })
      : [];
    return {
      content: [{ type: "text", text: JSON.stringify(bundles, null, 2) }],
      structuredContent: { appshots: bundles },
      isError: false,
    };
  }

  if (name === "stop_watcher") {
    const result = invokeNative(["stop"], root);
    return {
      content: [{ type: "text", text: result.stopped
        ? `Windows AppShots watcher ${result.pid} stopped. Captures were retained.`
        : `No verified Windows AppShots watcher was running. ${result.reason || ""}`.trim() }],
      structuredContent: result,
      isError: false,
    };
  }

  throw new Error(`Unknown tool: ${name}`);
}

export function handleRequest(message, root = stateRoot(), options = {}) {
  const id = message.id;
  if (message.method === "initialize") {
    if (options.startWatcher !== false) {
      try {
        startWatcher(root);
      } catch (error) {
        process.stderr.write(`Windows AppShots watcher did not start: ${error.message}\n`);
        // Tool calls still work with an explicit HWND or currently foreground app.
      }
    }
    return {
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: message.params?.protocolVersion || "2025-06-18",
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "windows-appshots", version: "0.1.0" },
      },
    };
  }
  if (message.method === "ping") {
    return { jsonrpc: "2.0", id, result: {} };
  }
  if (message.method === "tools/list") {
    return { jsonrpc: "2.0", id, result: { tools: toolDefinitions } };
  }
  if (message.method === "tools/call") {
    try {
      return {
        jsonrpc: "2.0",
        id,
        result: callTool(message.params?.name, message.params?.arguments || {}, root),
      };
    } catch (error) {
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: error.message }],
          isError: true,
        },
      };
    }
  }
  if (message.method?.startsWith("notifications/")) return null;
  return {
    jsonrpc: "2.0",
    id,
    error: { code: -32601, message: `Method not found: ${message.method}` },
  };
}

export const paths = { moduleRoot, nativeExe };
