# Copy the release CRT beside the executable, so installation needs no global
# Visual C++ Redistributable or administrator privileges. Never use System32 or
# debug_nonredist: the redistributable files come from the build toolchain.
param(
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)]
    [ValidateSet("x86_64-pc-windows-msvc", "aarch64-pc-windows-msvc")]
    [string]$Target
)
$ErrorActionPreference = "Stop"

$Architecture = switch ($Target) {
    "x86_64-pc-windows-msvc" { "x64" }
    "aarch64-pc-windows-msvc" { "arm64" }
}

$redist = $env:VCToolsRedistDir
if (-not $redist) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio/Installer/vswhere.exe"
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $vs) { throw "Cannot locate the Visual C++ build tools." }
    $version = (Get-Content -LiteralPath "$vs/VC/Auxiliary/Build/Microsoft.VCRedistVersion.default.txt" -Raw).Trim()
    $redist = Join-Path $vs "VC/Redist/MSVC/$version"
}
$crt = @(Get-ChildItem -Path "$redist/$Architecture/Microsoft.VC*.CRT" -Directory)
if ($crt.Count -ne 1 -or -not (Test-Path -LiteralPath "$($crt[0].FullName)/vcruntime140.dll" -PathType Leaf)) {
    throw "Cannot locate the $Architecture release CRT in $redist."
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
# Keep the CRT set together (including vcruntime140_1 and the C++ runtime).
Copy-Item -Path "$($crt[0].FullName)/*.dll" -Destination $Destination
Write-Host "Bundled $Architecture Visual C++ runtime from $($crt[0].FullName)"
