$ErrorActionPreference = "Stop"

function Get-Sha256([string] $Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "") }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

$pluginRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $pluginRoot "scripts\build-installer.ps1"
$installer = Join-Path $pluginRoot "dist\WindowsAppShots-Setup-0.1.1.exe"
$timestampProbe = Join-Path $pluginRoot "README.md"

if (-not (Test-Path -LiteralPath $installer)) { throw "Installer is missing: $installer" }

$originalTime = (Get-Item -LiteralPath $timestampProbe).LastWriteTimeUtc
$firstHash = Get-Sha256 $installer
try {
    (Get-Item -LiteralPath $timestampProbe).LastWriteTimeUtc = $originalTime.AddSeconds(17)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Timestamp-variance installer build failed" }
    $secondHash = Get-Sha256 $installer
}
finally {
    (Get-Item -LiteralPath $timestampProbe).LastWriteTimeUtc = $originalTime
}

if ($firstHash -ne $secondHash) {
    throw "Installer embeds source file timestamps: $firstHash != $secondHash"
}

Write-Output "Timestamp-independent installer build passed: SHA256 $secondHash"
