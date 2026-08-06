# Contributing

Issues and focused pull requests are welcome.

Windows AppShots is a small, best-effort project maintained by Brian Mulder. Responses and merges may take time.

Build the native helper:

```powershell
npm run build
```

Before opening a pull request, run:

```powershell
npm run verify
```

If you change the installer or release packaging, run:

```powershell
npm run verify:release
```

Use synthetic test data. Do not commit captures, screenshots, logs, `bin`, or `dist`.
