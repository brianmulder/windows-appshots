param(
    [Parameter(Mandatory = $true)]
    [string] $AppRoot,
    [string] $CodexHome
)

$ErrorActionPreference = "Stop"
if ($CodexHome) { $env:CODEX_HOME = $CodexHome }

function Get-Sha256([string] $Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "") }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Assert-SupportedNode {
    $node = Get-Command node -ErrorAction SilentlyContinue
    $guidance = "Node.js 22 or 24 LTS is required for the Windows AppShots MCP server (24 recommended). No Codex registration was changed. Install Node.js 24 LTS from https://nodejs.org/, then run this script again. The native AppShots helper does not need Node."
    if (-not $node) {
        throw "Node was not found on PATH. $guidance"
    }

    try {
        $version = (& $node.Source --version 2>&1 | Out-String).Trim()
        $exitCode = $LASTEXITCODE
    }
    catch {
        throw "Node at '$($node.Source)' could not report its version. $guidance"
    }
    if ($exitCode -ne 0 -or $version -notmatch '^v?(\d+)\.') {
        throw "Node at '$($node.Source)' did not report a valid version. $guidance"
    }
    if ([int] $Matches[1] -notin @(22, 24)) {
        throw "Found unsupported Node $version at '$($node.Source)'. $guidance"
    }
}

function Test-CurrentPluginCache([string] $SourceRoot, [string] $CacheRoot) {
    $runtimeFiles = @(
        ".codex-plugin\plugin.json",
        ".mcp.json",
        "assets\branding\app-icon-256.png",
        "bin\AppshotCapture.exe",
        "mcp\server-lib.mjs",
        "mcp\server.mjs"
    )
    foreach ($relative in $runtimeFiles) {
        $source = Join-Path $SourceRoot $relative
        $cached = Join-Path $CacheRoot $relative
        if (-not (Test-Path -LiteralPath $source) -or
            -not (Test-Path -LiteralPath $cached) -or
            (Get-Sha256 $source) -ne (Get-Sha256 $cached)) {
            return $false
        }
    }
    if (Test-Path -LiteralPath (Join-Path $CacheRoot "skills")) {
        return $false
    }
    return $true
}

Assert-SupportedNode

$codex = (Get-Command codex -ErrorAction SilentlyContinue).Source
if (-not $codex) { throw "Codex CLI was not found on PATH." }

$resolvedRoot = [System.IO.Path]::GetFullPath($AppRoot).TrimEnd('\')
$marketplaces = (& $codex plugin marketplace list --json | ConvertFrom-Json).marketplaces
$existing = $marketplaces | Where-Object { $_.name -eq "windows-appshots" }
if ($existing) {
    $existingRoot = [System.IO.Path]::GetFullPath($existing.root).TrimEnd('\')
    if (-not $existingRoot.Equals($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "A different windows-appshots marketplace is already configured at $existingRoot. Remove it explicitly before registering this installation."
    }
} else {
    & $codex plugin marketplace add $resolvedRoot --json
    if ($LASTEXITCODE -ne 0) { throw "Codex marketplace registration failed." }
}

$plugins = (& $codex plugin list --json | ConvertFrom-Json).installed
$installed = $plugins | Where-Object { $_.pluginId -eq "windows-appshots@windows-appshots" } | Select-Object -First 1
if ($installed) {
    $effectiveCodexHome = if ($env:CODEX_HOME) {
        [System.IO.Path]::GetFullPath($env:CODEX_HOME)
    } else {
        Join-Path $env:USERPROFILE ".codex"
    }
    $cacheRoot = Join-Path $effectiveCodexHome (
        "plugins\cache\windows-appshots\windows-appshots\" + $installed.version)
    if (Test-CurrentPluginCache $resolvedRoot $cacheRoot) {
        Write-Output "Windows AppShots is already registered with the current plugin files. Restart Codex before first use."
        exit 0
    }
    if (Get-Process -Name Codex -ErrorAction SilentlyContinue) {
        throw "Codex is running and the installed plugin cache needs to be refreshed. Fully quit Codex, then run this script or the installer again."
    }
    & $codex plugin remove windows-appshots@windows-appshots --json | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "The previous Codex plugin installation could not be refreshed." }
}
& $codex plugin add windows-appshots@windows-appshots --json
if ($LASTEXITCODE -ne 0) { throw "Codex plugin installation failed." }

Write-Output "Windows AppShots is registered with Codex. Restart Codex before first use."
