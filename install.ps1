$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinSrc = Join-Path $ScriptDir "claude.exe"
if (-not (Test-Path $BinSrc)) {
  throw "Cannot find claude.exe next to install.ps1"
}

$InstallDir = if ($env:PREFIX) { Join-Path $env:PREFIX "bin" } else { Join-Path $env:LOCALAPPDATA "Programs\ClaudeCode" }
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$Dest = Join-Path $InstallDir "claude.exe"
Copy-Item -Force $BinSrc $Dest

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = @()
if ($userPath) { $pathParts = $userPath -split ";" | Where-Object { $_ } }
if ($pathParts -notcontains $InstallDir) {
  $newPath = if ($userPath) { "$userPath;$InstallDir" } else { $InstallDir }
  [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
  Write-Host "Added to user PATH: $InstallDir"
  Write-Host "Open a new PowerShell window before running claude from PATH."
}

Write-Host "Installed: $Dest"
& $Dest --version
