# Removes Heartmark.
#
#   .\uninstall.ps1                 unregister and delete the program
#   .\uninstall.ps1 -RemoveAllTags  also strip the heartmark stream from every file
#                                   still listed as a favourite, before removing
#   .\uninstall.ps1 -PurgeData      also delete the index and favourites list
#
# By default the tags on your files are left exactly where they are. Reinstalling
# and running a rescan brings every heart back.

[CmdletBinding()]
param(
    [switch]$RemoveAllTags,
    [switch]$PurgeData,
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Removing the overlay handler needs administrator rights. Re-launching." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($RemoveAllTags) { $argList += '-RemoveAllTags' }
    if ($PurgeData)     { $argList += '-PurgeData' }
    if ($NoRestart)     { $argList += '-NoRestart' }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    return
}

$target = Join-Path $env:ProgramFiles 'Heartmark'
$dataDir = Join-Path $env:LOCALAPPDATA 'Heartmark'

# ------------------------------------------------------------------- the tags --

# Do this first, while the favourites list still exists to tell us which files to
# visit. The stream is invisible, so leaving strays behind is untidy in a way the
# user would have no way to see.
if ($RemoveAllTags) {
    $list = Join-Path $dataDir 'favorites.tsv'
    if (Test-Path $list) {
        $removed = 0
        foreach ($line in Get-Content $list) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $path = ($line -split "`t")[0]
            try {
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath "$path`:heartmark" -Force -ErrorAction Stop
                    $removed++
                }
            } catch {
                # A file that moved, or one we can't write to. Nothing to do about it.
            }
        }
        Write-Host "Removed the tag from $removed file(s)." -ForegroundColor Cyan
    } else {
        Write-Host "No favourites list found, so there was nothing to untag." -ForegroundColor Yellow
    }
}

# --------------------------------------------------------------------- the app --

Get-Process -Name 'Heartmark' -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 400
    if (-not $_.HasExited) { $_ | Stop-Process -Force }
}
Write-Host "Stopped the tray app."

# Start-with-Windows lives under the current user, not the elevated one, so clear
# it from both to be sure.
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
Remove-ItemProperty -Path $runKey -Name 'Heartmark' -ErrorAction SilentlyContinue

# ------------------------------------------------------------- the registration --

$dll = Join-Path $target 'HeartOverlay.dll'
if (Test-Path $dll) {
    Start-Process regsvr32.exe -ArgumentList '/u', '/s', "`"$dll`"" -Wait | Out-Null
    Write-Host "Unregistered the overlay handler."
} else {
    # Clean up the keys anyway; the DLL may already have been deleted by hand.
    Remove-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers\   Heartmark' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item 'HKLM:\SOFTWARE\Classes\CLSID\{BD9E3B04-A934-433C-ADE7-AFF2FD43FBDB}' -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed the registry entries."
}

# ------------------------------------------------------------------- explorer --

if (-not $NoRestart) {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Write-Host "Restarted Explorer so it lets go of the handler."
}

# --------------------------------------------------------------------- files --

if (Test-Path $target) {
    try {
        Remove-Item $target -Recurse -Force
        Write-Host "Deleted $target"
    } catch {
        Write-Host "Couldn't delete $target - it will be free after a reboot." -ForegroundColor Yellow
    }
}

if ($PurgeData -and (Test-Path $dataDir)) {
    Remove-Item $dataDir -Recurse -Force
    Write-Host "Deleted $dataDir"
} elseif (Test-Path $dataDir) {
    Write-Host "`nLeft your favourites list at $dataDir" -ForegroundColor Cyan
    if (-not $RemoveAllTags) {
        Write-Host "The hearts are still on your files. Reinstalling and running a rescan brings them all back."
    }
}

Write-Host "`nHeartmark removed." -ForegroundColor Green
