$ErrorActionPreference = "Stop"
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = "false"
$env:DOTNET_NOLOGO = "1"
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1"

$pluginRoot = Split-Path -Parent $PSScriptRoot
$outputRoot = Join-Path $pluginRoot "bin"
$project = Join-Path $pluginRoot "native\AppshotCapture.csproj"
$localDotnet = Join-Path $pluginRoot ".tools\dotnet\dotnet.exe"
$requiredSdk = "10.0.302"
$dotnet = if (Test-Path -LiteralPath $localDotnet) {
    $localDotnet
} else {
    (Get-Command dotnet -ErrorAction SilentlyContinue).Source
}

if (-not $dotnet) {
    throw "The .NET $requiredSdk SDK is required to build from source. Install it or place it under .tools\dotnet. End users should use the Windows installer instead."
}

$actualSdk = (& $dotnet --version).Trim()
if ($LASTEXITCODE -ne 0 -or $actualSdk -ne $requiredSdk) {
    throw "The .NET $requiredSdk SDK is required to build from source; found '$actualSdk'."
}

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

& $dotnet build $project `
    --configuration Release `
    --output $outputRoot `
    --nologo `
    --verbosity minimal

if ($LASTEXITCODE -ne 0) {
    throw "Native helper build failed with exit code $LASTEXITCODE"
}

Write-Output "Built $outputRoot\AppshotCapture.exe"
