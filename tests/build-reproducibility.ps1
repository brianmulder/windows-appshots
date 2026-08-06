$ErrorActionPreference = "Stop"
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = "false"
$env:DOTNET_NOLOGO = "1"
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1"
$pluginRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $pluginRoot "native\AppshotCapture.csproj"
$localDotnet = Join-Path $pluginRoot ".tools\dotnet\dotnet.exe"
$dotnet = if (Test-Path -LiteralPath $localDotnet) { $localDotnet } else { (Get-Command dotnet).Source }
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("windows-appshots-build-" + [Guid]::NewGuid().ToString("N"))
$first = Join-Path $testRoot "first"
$second = Join-Path $testRoot "second"

function Get-Sha256([string] $Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "") }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-PeSubsystem([string] $Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 256 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw "Native helper is not a valid PE executable"
    }
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($peOffset -lt 0 -or $peOffset + 94 -gt $bytes.Length -or
        $bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45) {
        throw "Native helper has an invalid PE header"
    }
    return [BitConverter]::ToUInt16($bytes, $peOffset + 24 + 68)
}

try {
    & $dotnet build $project -c Release -o $first --nologo -v:minimal
    if ($LASTEXITCODE -ne 0) { throw "First reproducibility build failed" }
    & $dotnet build $project -c Release -o $second --nologo -v:minimal
    if ($LASTEXITCODE -ne 0) { throw "Second reproducibility build failed" }

    $firstExe = Join-Path $first "AppshotCapture.exe"
    $secondExe = Join-Path $second "AppshotCapture.exe"
    $firstHash = Get-Sha256 $firstExe
    $secondHash = Get-Sha256 $secondExe
    if ($firstHash -ne $secondHash) {
        throw "Native build is not byte-reproducible: $firstHash != $secondHash"
    }

    $version = (Get-Item -LiteralPath $firstExe).VersionInfo
    if ($version.FileVersion -ne "0.1.1.0" -or $version.ProductName -ne "Windows AppShots") {
        throw "Native helper version metadata is missing or incorrect"
    }
    $subsystem = Get-PeSubsystem $firstExe
    if ($subsystem -ne 2) {
        throw "Native helper must use the Windows GUI subsystem so tray and startup modes do not open a console; found PE subsystem $subsystem"
    }
    $assembly = [Reflection.Assembly]::Load([System.IO.File]::ReadAllBytes($firstExe))
    $resources = $assembly.GetManifestResourceNames()
    foreach ($state in @("idle", "capturing", "success", "error")) {
        foreach ($theme in @("light", "dark")) {
            $resource = "WindowsAppshots.Assets.tray-$state-on-$theme.ico"
            if ($resources -notcontains $resource) {
                throw "Native helper is missing embedded tray resource: $resource"
            }
        }
    }
    Add-Type -AssemblyName System.Drawing
    $applicationIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($firstExe)
    try {
        if ($null -eq $applicationIcon -or $applicationIcon.Width -lt 16 -or $applicationIcon.Height -lt 16) {
            throw "Native helper application icon is missing or invalid"
        }
    }
    finally {
        if ($null -ne $applicationIcon) { $applicationIcon.Dispose() }
    }
    Write-Output "Deterministic native build passed: SHA256 $firstHash"
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
