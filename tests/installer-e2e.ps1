$ErrorActionPreference = "Stop"
$pluginRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $pluginRoot "dist\WindowsAppShots-Setup-0.1.0.exe"
$sourceExe = Join-Path $pluginRoot "bin\AppshotCapture.exe"
$compiler = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$nodeExe = (Get-Command node.exe -ErrorAction Stop).Source
$testRoot = Join-Path (Join-Path $pluginRoot ".test-tmp") ("installer-" + [Guid]::NewGuid().ToString("N"))
$installRoot = Join-Path $testRoot "installed"
$stateRoot = Join-Path $testRoot "state"
$codexHome = Join-Path $testRoot "codex-home"
$nodeShimRoot = Join-Path $testRoot "node-24"
$fixtureExe = Join-Path $testRoot "FixtureWindow.exe"
$originalPath = $env:PATH
$fixture = $null
$watcher = $null

function Get-Sha256([string] $Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "") }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

if (-not (Test-Path -LiteralPath $installer)) { throw "Installer is missing: $installer" }
New-Item -ItemType Directory -Force -Path $testRoot, $codexHome, $nodeShimRoot | Out-Null

@"
@echo off
if "%~1"=="--version" (
  echo v24.0.0
  exit /b 0
)
"$nodeExe" %*
"@ | Set-Content -LiteralPath (Join-Path $nodeShimRoot "node.cmd") -Encoding ASCII
$env:PATH = $nodeShimRoot + ";" + $originalPath

try {
    $setupArgs = @(
        "/S", "/NOCODEX", ("/D=" + $installRoot)
    )
    $setup = Start-Process -FilePath $installer -ArgumentList $setupArgs -PassThru -Wait
    if ($setup.ExitCode -ne 0) { throw "Installer exited with $($setup.ExitCode)" }

    $installedExe = Join-Path $installRoot "bin\AppshotCapture.exe"
    if (-not (Test-Path -LiteralPath $installedExe)) { throw "Installed helper is missing" }
    foreach ($document in @("README.md", "CONTRIBUTING.md", "SECURITY.md", "PRIVACY.md", "CODE_SIGNING.md")) {
        if (-not (Test-Path -LiteralPath (Join-Path $installRoot $document))) {
            throw "Installed policy document is missing: $document"
        }
    }
    if ((Get-Sha256 $installedExe) -ne (Get-Sha256 $sourceExe)) {
        throw "Installed helper does not match the exact built helper"
    }

    $supportedPath = $env:PATH
    try {
        $env:PATH = ""
        & $installedExe stop --state-root $stateRoot | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Installed native helper failed without Node on PATH" }
    }
    finally {
        $env:PATH = $supportedPath
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installRoot "scripts\register-codex.ps1") -AppRoot $installRoot -CodexHome $codexHome | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Isolated Codex registration failed" }
    $env:CODEX_HOME = $codexHome
    $marketplaces = (codex plugin marketplace list --json | ConvertFrom-Json).marketplaces
    if (-not ($marketplaces | Where-Object { $_.name -eq "windows-appshots" })) {
        throw "Installer registration did not add its isolated marketplace"
    }
    $cachedPluginRoot = Join-Path $codexHome "plugins\cache\windows-appshots\windows-appshots\0.1.0"
    $cachedPluginManifest = Get-Content -LiteralPath (Join-Path $cachedPluginRoot ".codex-plugin\plugin.json") -Raw | ConvertFrom-Json
    if ($null -ne $cachedPluginManifest.skills -or
        -not $cachedPluginManifest.mcpServers -or
        (Test-Path -LiteralPath (Join-Path $cachedPluginRoot "skills"))) {
        throw "Registered plugin must be MCP-only"
    }
    $cachedMcp = Join-Path $cachedPluginRoot "mcp\server-lib.mjs"
    $cacheLock = [System.IO.File]::Open(
        $cachedMcp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installRoot "scripts\register-codex.ps1") -AppRoot $installRoot -CodexHome $codexHome | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Isolated Codex registration refresh failed while its MCP cache was open" }
    }
    finally {
        $cacheLock.Dispose()
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installRoot "scripts\unregister-codex.ps1") -AppRoot $installRoot -CodexHome $codexHome | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Isolated Codex unregistration failed" }
    if ((codex plugin marketplace list --json | ConvertFrom-Json).marketplaces | Where-Object { $_.name -eq "windows-appshots" }) {
        throw "Installer unregistration left its isolated marketplace behind"
    }
    Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue

    & $compiler /nologo /target:winexe /platform:x64 "/out:$fixtureExe" `
        /reference:System.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll `
        (Join-Path $PSScriptRoot "FixtureWindow.cs")
    if ($LASTEXITCODE -ne 0) { throw "Installer fixture compilation failed" }
    $fixture = Start-Process -FilePath $fixtureExe -ArgumentList "Installed" -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    $hwnd = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        $fixture.Refresh()
        if ($fixture.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $fixture.MainWindowHandle; break }
        Start-Sleep -Milliseconds 100
    }
    if ($hwnd -eq [IntPtr]::Zero) { throw "Installed-path fixture did not become available" }

    $env:WINDOWS_APPSHOTS_STATE_ROOT = $stateRoot
    $request = '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"capture_appshot","arguments":{"hwnd":"' + $hwnd.ToInt64() + '","treeView":"raw"}}}'
    $mcpOutput = $request | node (Join-Path $installRoot "mcp\server.mjs")
    $mcpOutput | node (Join-Path $PSScriptRoot "verify-mcp-output.mjs")
    if ($LASTEXITCODE -ne 0) { throw "Installed MCP capture failed" }

    $watcher = Start-Process -FilePath $installedExe -ArgumentList @(
        "watch", "--state-root", ('"' + $stateRoot + '"'), "--no-hotkey", "true", "--tray", "true"
    ) -WindowStyle Hidden -PassThru
    $watcherStatePath = Join-Path $stateRoot "watcher.json"
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path $watcherStatePath)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path $watcherStatePath)) { throw "Installed tray watcher did not start" }

    $upgrade = Start-Process -FilePath $installer -ArgumentList $setupArgs -PassThru
    if (-not $upgrade.WaitForExit(15000)) {
        Stop-Process -Id $upgrade.Id -Force
        throw "Installer upgrade hung while the installed watcher held AppshotCapture.exe open"
    }
    if ($upgrade.ExitCode -ne 0) {
        throw "Installer upgrade could not replace a running watcher; exit code $($upgrade.ExitCode)"
    }
    if (-not $watcher.WaitForExit(5000)) { throw "Installer upgrade did not stop the running watcher" }
    if (Test-Path $watcherStatePath) { throw "Installer upgrade left watcher state behind" }
    if ((Get-Sha256 $installedExe) -ne (Get-Sha256 $sourceExe)) {
        throw "Upgraded helper does not match the exact built helper"
    }

    $watcher = Start-Process -FilePath $installedExe -ArgumentList @(
        "watch", "--state-root", ('"' + $stateRoot + '"'), "--no-hotkey", "true", "--tray", "true"
    ) -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path $watcherStatePath)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path $watcherStatePath)) { throw "Upgraded tray watcher did not restart" }
    $stopRequest = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"stop_watcher","arguments":{}}}'
    $stopOutput = $stopRequest | node (Join-Path $installRoot "mcp\server.mjs") | ConvertFrom-Json
    if (-not $stopOutput.result.structuredContent.stopped) { throw "Installed MCP did not stop its watcher" }

    Set-Content -LiteralPath (Join-Path $stateRoot "retention-marker.txt") -Value "retain"
    $uninstaller = Join-Path $installRoot "uninstall.exe"
    $uninstall = Start-Process -FilePath $uninstaller -ArgumentList "/S" -PassThru -Wait
    if ($uninstall.ExitCode -ne 0) { throw "Uninstaller exited with $($uninstall.ExitCode)" }
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline -and (Test-Path $installRoot)) { Start-Sleep -Milliseconds 100 }
    if (Test-Path $installRoot) { throw "Uninstaller left the application directory behind" }
    if (-not (Test-Path (Join-Path $stateRoot "retention-marker.txt"))) { throw "Uninstaller deleted retained capture state" }

    Write-Output "Installer E2E passed."
    Write-Output "Installer SHA256: $(Get-Sha256 $installer)"
    Write-Output "Installed helper SHA256: $(Get-Sha256 $sourceExe)"
    Write-Output "Installed native helper without Node, MCP capture, watcher-safe upgrade, optional tray, verified stop, Codex registration, and uninstall retention: passed"
}
finally {
    $env:PATH = $originalPath
    Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:WINDOWS_APPSHOTS_STATE_ROOT -ErrorAction SilentlyContinue
    foreach ($process in @($fixture, $watcher)) {
        if ($null -eq $process) { continue }
        if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null }
        if (-not $process.WaitForExit(3000)) { Stop-Process -Id $process.Id -Force }
    }
    if (Test-Path (Join-Path $installRoot "uninstall.exe")) {
        Start-Process -FilePath (Join-Path $installRoot "uninstall.exe") -ArgumentList "/S" -Wait | Out-Null
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
