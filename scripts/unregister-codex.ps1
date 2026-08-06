param(
    [Parameter(Mandatory = $true)]
    [string] $AppRoot,
    [string] $CodexHome
)

$ErrorActionPreference = "Stop"
if ($CodexHome) { $env:CODEX_HOME = $CodexHome }

$codex = (Get-Command codex -ErrorAction SilentlyContinue).Source
if (-not $codex) { exit 0 }

$resolvedRoot = [System.IO.Path]::GetFullPath($AppRoot).TrimEnd('\')
$marketplaces = (& $codex plugin marketplace list --json | ConvertFrom-Json).marketplaces
$existing = $marketplaces | Where-Object { $_.name -eq "windows-appshots" }
if (-not $existing) { exit 0 }

$existingRoot = [System.IO.Path]::GetFullPath($existing.root).TrimEnd('\')
if (-not $existingRoot.Equals($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Warning "A different windows-appshots marketplace is configured; leaving it untouched."
    exit 0
}

$plugins = (& $codex plugin list --json | ConvertFrom-Json).installed
if ($plugins | Where-Object { $_.pluginId -eq "windows-appshots@windows-appshots" }) {
    & $codex plugin remove windows-appshots@windows-appshots --json | Out-Null
}
& $codex plugin marketplace remove windows-appshots | Out-Null
Write-Output "Windows AppShots was removed from Codex."
