$ErrorActionPreference = "Stop"
$pluginRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot "build.ps1")
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pluginRoot "tests\build-reproducibility.ps1")
if ($LASTEXITCODE -ne 0) { throw "Build reproducibility test failed" }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pluginRoot "tests\registration-node-preflight.ps1")
if ($LASTEXITCODE -ne 0) { throw "Registration Node preflight test failed" }

Push-Location $pluginRoot
try {
    & node --test "./tests/*.test.mjs"
    if ($LASTEXITCODE -ne 0) { throw "Node tests failed" }

    & powershell -NoProfile -ExecutionPolicy Bypass -File "./tests/native-e2e.ps1"
    if ($LASTEXITCODE -ne 0) { throw "Native E2E failed" }
}
finally {
    Pop-Location
}

Write-Output "All Windows AppShots verification passed."
