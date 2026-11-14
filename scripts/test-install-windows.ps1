# File replacement/rollback checks; CI also supplies its real compiled executable.
param([string]$BuiltBinary, [string]$BuildTarget = "x86_64-pc-windows-msvc")

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\install-windows.ps1"

function Assert($Condition, $Message) {
    if (-not $Condition) { throw $Message }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) "herdr-install-test-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmp | Out-Null
$previousHome = $env:HERDR_APP_HOME
try {
    $binary = Join-Path $tmp "build.exe"
    $icon = Join-Path $tmp "icon.svg"
    $destination = Join-Path $tmp "Programs\herdr-app"
    $runtime = Join-Path $tmp "runtime"
    New-Item -ItemType Directory -Path $runtime | Out-Null
    Set-Content -LiteralPath "$runtime/support.dll" -Value "first support file"
    Set-Content -LiteralPath $binary -Value "first build"
    Set-Content -LiteralPath $icon -Value "icon"
    Install-HerdrAppFiles $binary $icon $destination $runtime
    Assert ((Get-Content "$destination\herdr-app.exe") -eq "first build") "First install lost the binary"
    Assert ((Get-Content "$destination\herdr-app.svg") -eq "icon") "First install lost the icon"

    Assert ((Get-Content "$destination/support.dll") -eq "first support file") "First install lost a support file"
    Set-Content -LiteralPath "$runtime/support.dll" -Value "new support file"
    Set-Content -LiteralPath $binary -Value "new build"
    Install-HerdrAppFiles $binary $icon $destination $runtime
    Assert ((Get-Content "$destination\herdr-app.exe") -eq "new build") "Replacement kept the old binary"
    Assert ((Get-Content "$destination/support.dll") -eq "new support file") "Replacement kept the old support file"
    Assert ((Get-ChildItem (Split-Path $destination)).Count -eq 1) "Replacement left temporary files"

    # Fail the promotion, then the rollback too, using real moves otherwise.
    function Rename-Item {
        param($LiteralPath, $NewName)
        $script:moves++
        if ($script:failMoves -contains $script:moves) { throw "injected move failure $script:moves" }
        Microsoft.PowerShell.Management\Rename-Item -LiteralPath $LiteralPath -NewName $NewName
    }
    foreach ($failures in @(@(2), @(2, 3))) {
        $script:moves = 0
        $script:failMoves = $failures
        $errorText = $null
        try { Install-HerdrAppFiles $binary $icon $destination $runtime }
        catch { $errorText = $_.ToString() }
        Assert ($null -ne $errorText) "Failed installation reported success"
        if ($failures.Count -eq 1) {
            Assert ((Get-Content "$destination\herdr-app.exe") -eq "new build") "Rollback lost the previous build"
        } else {
            $backup = Get-ChildItem (Split-Path $destination) -Directory -Filter "herdr-app.old-*"
            Assert ($backup.Count -eq 1) "Failed rollback lost the backup"
            Assert ($errorText.Contains($backup.FullName)) "Failed rollback did not report the backup path"
            Assert ((Get-Content "$($backup.FullName)\herdr-app.exe") -eq "new build") "Failed rollback damaged the backup"
        }
        Assert (-not (Get-ChildItem (Split-Path $destination) -Directory -Filter "herdr-app.install-*")) "Failed install left staging files"
    }
    Remove-Item Function:Rename-Item
    if ($BuiltBinary) {
        $runtime = Join-Path $tmp "real-runtime"
        & "$PSScriptRoot/windows-runtime.ps1" -Destination $runtime -Target $BuildTarget
        $installed = Join-Path $tmp "real-app"
        Install-HerdrAppFiles $BuiltBinary $icon $installed $runtime
        Assert (Test-Path -LiteralPath "$installed/vcruntime140.dll") "Installed payload is missing the CRT"
        $env:HERDR_APP_HOME = Join-Path $tmp "home"
        $process = Start-Process -FilePath "$installed/herdr-app.exe" -ArgumentList '--version' -NoNewWindow -Wait -PassThru
        Assert ($process.ExitCode -eq 0) "Installed executable failed to start (exit $($process.ExitCode))"
    }
    Write-Host "Installer file replacement and rollback checks passed."
} finally {
    $env:HERDR_APP_HOME = $previousHome
    Remove-Item Function:Rename-Item -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force
}
