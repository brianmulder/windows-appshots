# Privacy

## Capture is explicit

Windows AppShots captures application pixels and accessibility content only when you invoke `capture_appshot` or press the configured hotkey.

Enabling the plugin starts a local watcher unless an installed watcher is already running. The watcher remembers the last eligible foreground window. It does not continuously capture pixels or accessibility content.

## What can be captured

A bundle can contain visible pixels, Microsoft UI Automation controls, and provider-exposed text outside the visible viewport.

When screen fallback is needed, overlapping windows or notifications inside the target rectangle can also appear in `visual.png`.

Captured text is untrusted data, not instructions for Codex to follow.

## Storage and deletion

Bundles are stored under `%LOCALAPPDATA%\WindowsAppshots` until you delete them. There is no automatic expiry, and uninstalling Windows AppShots does not delete captures.

The watcher stores one `last-foreground.json` record. It contains the window handle, process identity, title, and observation time. A later eligible window overwrites it.

The README explains how to stop the watcher, inspect stored bundles, and delete the capture directory.

## What leaves the machine

Invoking the MCP capture tool returns the selected pixels and semantic context to the Codex client you chose.

Windows AppShots has no independent telemetry or network service.

OpenAI-operated Codex services follow the [OpenAI Privacy Policy](https://openai.com/policies/privacy-policy/). Another compatible client or service follows its operator's policy.

## Redaction limits

Controls marked as passwords keep basic metadata, but Windows AppShots suppresses their UI Automation Value and Text.

A bounded credential policy also redacts recognised secrets from semantic artifacts. Redaction failure stops publication and leaves the previous latest capture unchanged.

Redaction is best effort, not a safety guarantee. It does not remove ordinary confidential prose, personal details, identifiers, file paths, or every unusual credential format.

`visual.png` is not redacted.

## Questions and reports

Brian Mulder maintains this project.

Open a GitHub issue for general privacy questions, but do not attach private capture data. Use the private route in [SECURITY.md](SECURITY.md) when the report itself is sensitive.
