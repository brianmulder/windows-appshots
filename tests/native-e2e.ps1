$ErrorActionPreference = "Stop"
$pluginRoot = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$fixtureExe = Join-Path $PSScriptRoot "FixtureWindow.exe"
$nativeExe = Join-Path $pluginRoot "bin\AppshotCapture.exe"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("windows-appshots-e2e-" + [Guid]::NewGuid().ToString("N"))
$bundle = Join-Path $testRoot "captures\bundle"
$selectionBundle = Join-Path $testRoot "captures\selection-bundle"
$fixture = $null
$hangingFixture = $null
$watcher = $null

New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

function Invoke-Native([string[]] $Arguments) {
    $stdoutPath = Join-Path $testRoot ("native-stdout-" + [Guid]::NewGuid().ToString("N") + ".txt")
    $stderrPath = Join-Path $testRoot ("native-stderr-" + [Guid]::NewGuid().ToString("N") + ".txt")
    try {
        $process = Start-Process -FilePath $nativeExe -ArgumentList $Arguments `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath `
            -WindowStyle Hidden -Wait -PassThru
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -Raw $stdoutPath } else { "" }
            Stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -Raw $stderrPath } else { "" }
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

& $compiler /nologo /target:winexe /platform:x64 `
    "/out:$fixtureExe" `
    /reference:System.dll `
    /reference:System.Drawing.dll `
    /reference:System.Windows.Forms.dll `
    (Join-Path $PSScriptRoot "FixtureWindow.cs")
if ($LASTEXITCODE -ne 0) { throw "Fixture compilation failed" }

$fixture = Start-Process -FilePath $fixtureExe -ArgumentList "Primary" -PassThru
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    $hwnd = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        $fixture.Refresh()
        if ($fixture.MainWindowHandle -ne [IntPtr]::Zero) {
            $hwnd = $fixture.MainWindowHandle
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if ($hwnd -eq [IntPtr]::Zero) { throw "Fixture window did not become available" }
    if (-not $fixture.WaitForInputIdle(5000)) { throw "Fixture window did not become ready" }

    $capture = Invoke-Native @(
        "capture-bounded", "--hwnd", $hwnd.ToInt64().ToString(), "--output", $bundle,
        "--state-root", $testRoot, "--tree-view", "raw"
    )
    if ($capture.ExitCode -ne 0) { throw "Native capture failed: $($capture.Stderr)" }

    $required = @(
        "manifest.json",
        "visual.png",
        "accessibility-tree.json",
        "accessible-text.txt",
        "model-context.md"
    )
    foreach ($name in $required) {
        $path = Join-Path $bundle $name
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing artifact: $name" }
        if ((Get-Item -LiteralPath $path).Length -eq 0) { throw "Empty artifact: $name" }
    }

    $manifest = Get-Content -Raw (Join-Path $bundle "manifest.json") | ConvertFrom-Json
    if ($manifest.Schema -ne "windows-appshot/v1") { throw "Unexpected manifest schema" }
    if ($manifest.TreeView -ne "raw") { throw "Raw UI Automation tree mode was not used" }
    if ($manifest.Window.Title -ne "Windows AppShots Acceptance Fixture - Primary - client_secret=[REDACTED:LABELLED_SECRET]") {
        throw "Wrong window captured: $($manifest.Window.Title)"
    }
    if ($manifest.NodeCount -lt 5) { throw "Too few UIA nodes: $($manifest.NodeCount)" }
    if ($manifest.Limits.MaxNodes -ne 5000 -or
        $manifest.Limits.MaxText -ne 200000 -or
        $manifest.Limits.MaxDepth -ne 40 -or
        $manifest.Limits.TimeoutMs -ne 15000) {
        throw "Capture manifest did not report the applied limits"
    }

    $tree = Get-Content -Raw (Join-Path $bundle "accessibility-tree.json")
    if ($tree -notmatch "Send synthetic action") { throw "Accessible button was not captured" }
    if ($tree -notmatch "Synthetic sample action is ready") { throw "Text value was not captured" }
    if ($tree -match "PASSWORD_VALUE_MUST_NOT_APPEAR") { throw "Password value leaked into accessibility output" }

    $semanticFiles = @(
        "manifest.json", "accessibility-tree.json", "accessible-text.txt", "model-context.md"
    )
    $semantic = ($semanticFiles | ForEach-Object {
        Get-Content -Raw (Join-Path $bundle $_)
    }) -join "`n"
    $secretSentinels = @(
        "APPSHOTS_TITLE_SECRET_SENTINEL",
        "APPSHOTS_AUTHORIZATION_SECRET_SENTINEL",
        "APPSHOTS_SESSION_COOKIE_SECRET_SENTINEL",
        "APPSHOTS_CONNECTION_SECRET_SENTINEL",
        "APPSHOTS_PROVIDER_TOKEN_SECRET_SENTINEL",
        "APPSHOTS_LABELLED_SECRET_SENTINEL",
        "APPSHOTS_PASSWORD_SECRET_SENTINEL",
        "APPSHOTS_PRIVATE_KEY_SECRET_SENTINEL"
    )
    foreach ($sentinel in $secretSentinels) {
        if ($semantic -match [regex]::Escape($sentinel)) {
            throw "Credential sentinel leaked into semantic artifacts: $sentinel"
        }
    }
    foreach ($placeholder in @(
        "[REDACTED:PRIVATE_KEY]", "[REDACTED:AUTHORIZATION]",
        "[REDACTED:SESSION_COOKIE]", "[REDACTED:CONNECTION_SECRET]",
        "[REDACTED:PROVIDER_TOKEN]", "[REDACTED:LABELLED_SECRET]",
        "[REDACTED:PASSWORD]"
    )) {
        if ($semantic -notmatch [regex]::Escape($placeholder)) {
            throw "Expected credential placeholder is missing: $placeholder"
        }
    }
    foreach ($nearMiss in @(
        "APPSHOTS_PUBLIC_KEY_NEARMISS", "APPSHOTS_APPLICATION_ID_NEARMISS",
        "APPSHOTS_HASH_NEARMISS", "contact@example.test",
        "C:\synthetic\fixture.txt", "123e4567-e89b-12d3-a456-426614174000",
        "APPSHOTS_CERTIFICATE_NEARMISS", "Synthetic Person", "+61 400 000 000",
        "4111111111111111", "APPSHOTS_GOV_ID_NEARMISS",
        "APPSHOTS_CUSTOMER_NEARMISS", "ordinary confidential prose",
        "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo"
    )) {
        if ($semantic -notmatch [regex]::Escape($nearMiss)) {
            throw "Out-of-scope near-miss was removed: $nearMiss"
        }
    }
    if ($manifest.CredentialRedaction.Policy -ne "credentials-v1" -or
        -not $manifest.CredentialRedaction.Succeeded -or
        -not $manifest.CredentialRedaction.SemanticArtifactsSanitized -or
        $manifest.CredentialRedaction.RawMatchesPersisted -or
        $manifest.CredentialRedaction.VisualRedacted) {
        throw "Credential redaction manifest receipt is missing or incorrect"
    }
    foreach ($credentialClass in @(
        "PRIVATE_KEY", "AUTHORIZATION", "SESSION_COOKIE", "CONNECTION_SECRET",
        "PROVIDER_TOKEN", "LABELLED_SECRET", "PASSWORD"
    )) {
        if ($manifest.CredentialRedaction.ReplacementCounts.$credentialClass -lt 1) {
            throw "Credential redaction receipt did not count class: $credentialClass"
        }
    }
    if ($tree -notmatch '"Password":true' -or $tree -notmatch '"Name":"Password"') {
        throw "Password control metadata was not preserved"
    }

    $staleIdentity = @{
        Hwnd = ("0x" + $hwnd.ToInt64().ToString("X"))
        ProcessId = ($fixture.Id + 1)
        ProcessName = "FixtureWindow"
        ProcessStartedAt = [DateTime]::UtcNow.ToString("o")
        Title = "Stale fixture identity"
        ObservedAt = [DateTime]::UtcNow.ToString("o")
    } | ConvertTo-Json -Compress
    Set-Content -LiteralPath (Join-Path $testRoot "last-foreground.json") -Value $staleIdentity -Encoding UTF8

    $staleCapture = Invoke-Native @(
        "capture", "--output", $selectionBundle, "--state-root", $testRoot,
        "--tree-view", "control"
    )
    if ($staleCapture.ExitCode -eq 0) { throw "A stale remembered HWND was accepted" }
    if (($staleCapture.Stderr + $staleCapture.Stdout) -notmatch "no longer matches its recorded process identity") {
        throw "Stale remembered-window rejection returned an unexpected diagnostic"
    }
    if (Test-Path -LiteralPath $selectionBundle) {
        throw "Stale remembered-window rejection wrote a capture bundle"
    }

    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile((Join-Path $bundle "visual.png"))
    try {
        if ($image.Width -lt 500 -or $image.Height -lt 300) {
            throw "Visual capture dimensions are implausible: $($image.Width)x$($image.Height)"
        }
    }
    finally {
        $image.Dispose()
    }

    $env:WINDOWS_APPSHOTS_STATE_ROOT = $testRoot
    $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $request = '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_latest_appshot","arguments":{}}}'
    $mcpOutput = $request | node (Join-Path $pluginRoot "mcp\server.mjs")
    $mcpOutput | node (Join-Path $PSScriptRoot "verify-mcp-output.mjs")
    if ($LASTEXITCODE -ne 0) { throw "MCP response verification failed" }
    foreach ($sentinel in $secretSentinels) {
        if (("$mcpOutput") -match [regex]::Escape($sentinel)) {
            throw "Credential sentinel leaked through get_latest_appshot: $sentinel"
        }
    }
    $listRequest = '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_appshots","arguments":{}}}'
    $listOutput = $listRequest | node (Join-Path $pluginRoot "mcp\server.mjs")
    foreach ($sentinel in $secretSentinels) {
        if (("$listOutput") -match [regex]::Escape($sentinel)) {
            throw "Credential sentinel leaked through list_appshots: $sentinel"
        }
    }

    $latestBeforeFailure = Get-Content -Raw (Join-Path $testRoot "latest-capture.json")
    $failedBundle = Join-Path $testRoot "captures\redaction-failure"
    $env:WINDOWS_APPSHOTS_TEST_REDACTION_FAILURE = "1"
    try {
        $failedCapture = Invoke-Native @(
            "capture-bounded", "--hwnd", $hwnd.ToInt64().ToString(), "--output", $failedBundle,
            "--state-root", $testRoot, "--tree-view", "raw"
        )
    }
    finally {
        Remove-Item Env:WINDOWS_APPSHOTS_TEST_REDACTION_FAILURE -ErrorAction SilentlyContinue
    }
    if ($failedCapture.ExitCode -eq 0) { throw "Injected redaction failure did not fail capture" }
    if (Test-Path -LiteralPath $failedBundle) { throw "Redaction failure published a bundle" }
    if ((Get-Content -Raw (Join-Path $testRoot "latest-capture.json")) -ne $latestBeforeFailure) {
        throw "Redaction failure changed the latest capture pointer"
    }
    foreach ($sentinel in $secretSentinels) {
        if (($failedCapture.Stdout + $failedCapture.Stderr) -match [regex]::Escape($sentinel)) {
            throw "Credential sentinel leaked through redaction failure diagnostics: $sentinel"
        }
    }

    $programType = [Reflection.Assembly]::LoadFile($nativeExe).GetType("WindowsAppshots.Program", $true)
    $redactorType = $programType.Assembly.GetType("WindowsAppshots.CredentialRedactor", $true)
    $redactor = [Activator]::CreateInstance($redactorType, $true)
    $redactMethod = $redactorType.GetMethod(
        "Redact", [Reflection.BindingFlags] "NonPublic,Instance")
    $truncatedPrivateKey = $redactMethod.Invoke($redactor, @(
        "prefix -----BEGIN ENCRYPTED PRIVATE KEY-----`nTRUNCATED_PRIVATE_KEY_SENTINEL", $false
    ))
    if ($truncatedPrivateKey -match "TRUNCATED_PRIVATE_KEY_SENTINEL" -or
        $truncatedPrivateKey -notmatch [regex]::Escape("[REDACTED:PRIVATE_KEY]")) {
        throw "Truncated private-key block was not safely replaced"
    }
    $spacedPassword = $redactMethod.Invoke($redactor, @(
        "password=multi word password sentinel", $false
    ))
    if ($spacedPassword -match "multi word password sentinel" -or
        $spacedPassword -notmatch [regex]::Escape("[REDACTED:PASSWORD]")) {
        throw "Spaced labelled password was only partially replaced"
    }
    $entropyNearMiss = "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo"
    if ($redactMethod.Invoke($redactor, @($entropyNearMiss, $false)) -ne $entropyNearMiss) {
        throw "Generic entropy near-miss was redacted"
    }
    $scanMethod = $programType.GetMethod("FindPrintedContent", [Reflection.BindingFlags] "NonPublic,Static")
    $scanBitmap = New-Object System.Drawing.Bitmap 3840,2160
    try {
        $scanBitmap.SetPixel(3800, 2100, [System.Drawing.Color]::White)
        $scanTimer = [Diagnostics.Stopwatch]::StartNew()
        $scanBounds = $scanMethod.Invoke($null, @($scanBitmap.PSObject.BaseObject))
        $scanTimer.Stop()
        if ($scanBounds.Width -ne 3801 -or $scanBounds.Height -ne 2101) {
            throw "Locked-bitmap scan returned wrong bounds: $scanBounds"
        }
        if ($scanTimer.ElapsedMilliseconds -gt 1000) {
            throw "Locked-bitmap scan exceeded 1 second: $($scanTimer.ElapsedMilliseconds) ms"
        }
    }
    finally {
        $scanBitmap.Dispose()
    }

    $hangingFixture = Start-Process -FilePath $fixtureExe -ArgumentList "Hanging" -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    $hangingHwnd = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        $hangingFixture.Refresh()
        if ($hangingFixture.MainWindowHandle -ne [IntPtr]::Zero) {
            $hangingHwnd = $hangingFixture.MainWindowHandle
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if ($hangingHwnd -eq [IntPtr]::Zero) { throw "Hanging fixture window did not become available" }
    $hangTimer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $hangOutput = Invoke-Native @(
            "capture-bounded", "--hwnd", $hangingHwnd.ToInt64().ToString(),
            "--output", (Join-Path $testRoot "captures\hang"), "--state-root", $testRoot,
            "--tree-view", "raw", "--timeout-ms", "500"
        )
    }
    finally {
        $hangTimer.Stop()
    }
    if ($hangOutput.ExitCode -eq 0) { throw "A deliberately hung UI Automation provider was not bounded" }
    if (($hangOutput.Stderr + $hangOutput.Stdout) -notmatch "isolated worker process was stopped") {
        throw "Hung provider returned an unexpected diagnostic"
    }
    if ($hangTimer.ElapsedMilliseconds -gt 5000) {
        throw "Hung provider was not stopped promptly: $($hangTimer.ElapsedMilliseconds) ms"
    }

    $watcher = Start-Process -FilePath $nativeExe -ArgumentList @(
        "watch", "--state-root", ('"' + $testRoot + '"'), "--no-hotkey", "true", "--tray", "true"
    ) -PassThru
    $watcherStatePath = Join-Path $testRoot "watcher.json"
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $watcherStatePath)) {
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $watcherStatePath)) { throw "Tray watcher did not publish state" }
    $watcherState = Get-Content -Raw $watcherStatePath | ConvertFrom-Json
    if (-not $watcherState.Tray) { throw "Watcher did not start in optional tray mode" }
    $consoleHost = Get-CimInstance Win32_Process -Filter (
        "ParentProcessId = $($watcher.Id) AND Name = 'conhost.exe'"
    )
    if ($consoleHost) { throw "Tray watcher opened a console host" }

    $stopRequest = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"stop_watcher","arguments":{}}}'
    $stopOutput = $stopRequest | node (Join-Path $pluginRoot "mcp\server.mjs") | ConvertFrom-Json
    if ($stopOutput.result.isError -or -not $stopOutput.result.structuredContent.stopped) {
        throw "MCP stop_watcher did not stop the verified tray watcher"
    }
    if (-not $watcher.WaitForExit(5000)) { throw "Stopped tray watcher process remained alive" }
    if (Test-Path -LiteralPath $watcherStatePath) { throw "Watcher state remained after stop" }

    Write-Output "Native E2E passed."
    Write-Output "Bundle: $bundle"
    Write-Output "Window: $($manifest.Window.Title)"
    Write-Output "UIA nodes: $($manifest.NodeCount)"
    Write-Output "PNG bytes: $((Get-Item (Join-Path $bundle 'visual.png')).Length)"
    Write-Output "Remembered-window identity validation: passed"
    Write-Output "Credentials-v1 semantic redaction and fail-closed publication: passed"
    Write-Output "Locked-bitmap scan: $($scanTimer.ElapsedMilliseconds) ms at 3840x2160"
    Write-Output "Hung UIA isolation: stopped in $($hangTimer.ElapsedMilliseconds) ms"
    Write-Output "Optional tray watcher + MCP stop: passed"
}
finally {
    foreach ($process in @($fixture, $hangingFixture, $watcher)) {
        if ($null -eq $process) { continue }
        if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null }
        if (-not $process.WaitForExit(3000)) { Stop-Process -Id $process.Id -Force }
    }
    Remove-Item -LiteralPath $fixtureExe -Force -ErrorAction SilentlyContinue
    if ($env:WINDOWS_APPSHOTS_KEEP_TEST_ARTIFACTS -ne "1") {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
