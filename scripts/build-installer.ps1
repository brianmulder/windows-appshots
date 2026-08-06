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
& (Join-Path $PSScriptRoot "build.ps1")

$candidates = @(
    (Join-Path $pluginRoot ".tools\nsis\makensis.exe"),
    (Get-Command makensis.exe -ErrorAction SilentlyContinue).Source,
    (Join-Path ${env:ProgramFiles(x86)} "NSIS\makensis.exe"),
    (Join-Path $env:ProgramFiles "NSIS\makensis.exe")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

$compiler = $candidates | Select-Object -First 1
if (-not $compiler) {
    throw "NSIS 3.12 is required. Install NSIS.NSIS or place its toolchain under .tools\nsis."
}
$nsisVersion = (& $compiler /VERSION).Trim().TrimStart('v')
if ($nsisVersion -ne "3.12") {
    throw "NSIS 3.12 is required for reproducible installer builds; found '$nsisVersion'."
}

New-Item -ItemType Directory -Force -Path (Join-Path $pluginRoot "dist") | Out-Null
& $compiler /WX /V2 (Join-Path $pluginRoot "installer\WindowsAppShots.nsi")
if ($LASTEXITCODE -ne 0) { throw "Installer build failed with exit code $LASTEXITCODE" }

$installer = Join-Path $pluginRoot "dist\WindowsAppShots-Setup-0.1.0.exe"
if (-not (Test-Path -LiteralPath $installer)) { throw "Installer output is missing: $installer" }
$native = Join-Path $pluginRoot "bin\AppshotCapture.exe"
$installerHash = Get-Sha256 $installer
$nativeHash = Get-Sha256 $native
$sourceCommit = (& git -C $pluginRoot rev-parse HEAD).Trim()
$sourceTree = (& git -C $pluginRoot rev-parse 'HEAD^{tree}').Trim()
$sourceDirty = [bool](& git -C $pluginRoot status --porcelain --untracked-files=no)
$dotnet = Join-Path $pluginRoot ".tools\dotnet\dotnet.exe"
if (-not (Test-Path $dotnet)) { $dotnet = (Get-Command dotnet).Source }
$receipt = [ordered]@{
    schema = "windows-appshots/release-build-v1"
    version = "0.1.0"
    sourceCommit = $sourceCommit
    sourceTree = $sourceTree
    sourceDirty = $sourceDirty
    tools = [ordered]@{
        dotnetSdk = (& $dotnet --version).Trim()
        nsis = $nsisVersion
    }
    artifacts = [ordered]@{
        nativeHelper = [ordered]@{ file = "AppshotCapture.exe"; sha256 = $nativeHash; bytes = (Get-Item $native).Length }
        installer = [ordered]@{ file = "WindowsAppShots-Setup-0.1.0.exe"; sha256 = $installerHash; bytes = (Get-Item $installer).Length; signing = "unsigned" }
    }
}
$receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $pluginRoot "dist\BUILD-RECEIPT.json") -Encoding UTF8
@(
    "$nativeHash  AppshotCapture.exe",
    "$installerHash  WindowsAppShots-Setup-0.1.0.exe"
) | Set-Content -LiteralPath (Join-Path $pluginRoot "dist\SHA256SUMS.txt") -Encoding ASCII
Write-Output "Built $installer"
Write-Output "SHA256 $installerHash"
