# Builds both halves of Heartmark into dist\.
#
#   dist\HeartOverlay.dll   the native badge handler that loads into explorer.exe
#   dist\Heartmark.exe      the tray app that owns the shortcut and the tagging
#
# Needs: MSVC C++ toolset, Windows SDK, CMake, .NET 7 SDK. Nothing else.

[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Config = 'Release',
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$root  = $PSScriptRoot
$dist  = Join-Path $root 'dist'
$build = Join-Path $root 'build'

function Step($msg) { Write-Host "`n=== $msg" -ForegroundColor Cyan }

if ($Clean) {
    Step "Cleaning"
    foreach ($d in @($build, $dist)) {
        if (Test-Path $d) { Remove-Item $d -Recurse -Force }
    }
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null

Step "Icons"
& (Join-Path $root 'tools\make-icons.ps1')

Step "Overlay handler (C++)"
& cmake -S (Join-Path $root 'src\overlay') -B (Join-Path $build 'overlay') -A x64 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }

& cmake --build (Join-Path $build 'overlay') --config $Config | ForEach-Object {
    if ($_ -match 'error|warning') { Write-Host "  $_" -ForegroundColor Yellow }
}
if ($LASTEXITCODE -ne 0) { throw "CMake build failed" }

$dll = Join-Path $build "overlay\$Config\HeartOverlay.dll"
if (-not (Test-Path $dll)) { throw "HeartOverlay.dll was not produced" }
Copy-Item $dll $dist -Force
Write-Host ("  HeartOverlay.dll  {0:N0} bytes" -f (Get-Item $dll).Length)

Step "Tray app (C#)"
$trayOut = Join-Path $build 'tray'
& dotnet publish (Join-Path $root 'src\tray\Heartmark.csproj') `
    -c $Config -r win-x64 --self-contained true `
    -o $trayOut --nologo -v q
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

# The publish folder carries pdbs and the .NET host's bookkeeping; the installer
# only needs what actually runs.
Get-ChildItem $trayOut -File |
    Where-Object { $_.Extension -in '.exe', '.dll', '.json' } |
    ForEach-Object { Copy-Item $_.FullName $dist -Force }

Copy-Item (Join-Path $root 'assets\app.ico') $dist -Force

Step "Installer scripts"
Copy-Item (Join-Path $root 'install.ps1')   $dist -Force
Copy-Item (Join-Path $root 'uninstall.ps1') $dist -Force

Step "Done"
Get-ChildItem $dist -File | Sort-Object Name |
    Format-Table @{L='Name';E={$_.Name}}, @{L='Size';E={'{0,10:N0}' -f $_.Length}} -AutoSize

Write-Host "`nNext: run dist\install.ps1 as administrator." -ForegroundColor Green
