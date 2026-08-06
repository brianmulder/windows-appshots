$ErrorActionPreference = "Stop"

$pluginRoot = Split-Path -Parent $PSScriptRoot
$registerScript = Join-Path $pluginRoot "scripts\register-codex.ps1"
$powershell = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
$testRoot = Join-Path (Join-Path $pluginRoot ".test-tmp") ("node-preflight-" + [Guid]::NewGuid().ToString("N"))

function Invoke-PreflightCase([string] $Name, [string] $NodeVersion, [bool] $ShouldSucceed) {
    $caseRoot = Join-Path $testRoot $Name
    $fakeBin = Join-Path $caseRoot "bin"
    $codexHome = Join-Path $caseRoot "codex-home"
    $codexMarker = Join-Path $caseRoot "codex-invoked.txt"
    New-Item -ItemType Directory -Force -Path $fakeBin, $codexHome | Out-Null

    @'
@echo off
echo invoked>>"%CODEX_FAKE_MARKER%"
if "%1 %2 %3"=="plugin marketplace list" echo {"marketplaces":[]}
if "%1 %2"=="plugin list" echo {"installed":[]}
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $fakeBin "codex.cmd") -Encoding ASCII

    if ($NodeVersion) {
        @"
@echo off
echo $NodeVersion
"@ | Set-Content -LiteralPath (Join-Path $fakeBin "node.cmd") -Encoding ASCII
    }

    $originalPath = $env:PATH
    $originalMarker = $env:CODEX_FAKE_MARKER
    $originalErrorAction = $ErrorActionPreference
    try {
        $env:PATH = $fakeBin
        $env:CODEX_FAKE_MARKER = $codexMarker
        $ErrorActionPreference = "Continue"
        $output = (& $powershell -NoProfile -ExecutionPolicy Bypass -File $registerScript `
            -AppRoot $pluginRoot -CodexHome $codexHome 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $env:PATH = $originalPath
        $env:CODEX_FAKE_MARKER = $originalMarker
        $ErrorActionPreference = $originalErrorAction
    }

    if ($ShouldSucceed) {
        if ($exitCode -ne 0) { throw "$Name registration rejected supported Node $NodeVersion" }
        if (-not (Test-Path -LiteralPath $codexMarker)) { throw "$Name registration did not reach Codex" }
        return
    }

    if ($exitCode -eq 0) { throw "$Name registration unexpectedly succeeded without modern Node" }
    if (Test-Path -LiteralPath $codexMarker) { throw "$Name registration invoked Codex before rejecting Node" }
    if ($output -notmatch "Node.js 22 or newer" -or
        $output -notmatch "current Node.js release" -or
        $output -notmatch "No Codex registration was changed") {
        throw "$Name registration did not return actionable Node guidance: $output"
    }
    if (Get-ChildItem -LiteralPath $codexHome -Force) {
        throw "$Name registration left partial Codex state"
    }
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    Invoke-PreflightCase -Name "missing" -NodeVersion "" -ShouldSucceed $false
    Invoke-PreflightCase -Name "ancient" -NodeVersion "v20.19.0" -ShouldSucceed $false
    Invoke-PreflightCase -Name "modern" -NodeVersion "v25.8.0" -ShouldSucceed $true
    Write-Output "Node registration preflight accepts modern Node and rejects missing or ancient Node without partial Codex state."
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
