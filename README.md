# PSChocoOutdatedReporter

PSChocoOutdatedReporter is a small PowerShell script for checking outdated Chocolatey packages on Windows.
It runs `choco outdated`, shows the current and available versions in a readable format, and prints the commands and package pages you can use to review and upgrade each package.

## Requirements

- Windows 11+
- PowerShell 5.1+
- Chocolatey 2.6+

## Usage

```powershell
# powershell
git clone https://...
Set-Location .\PSChocoOutdatedReporter
.\Invoke-ReportChocolateyOutdated.ps1
```

If you want to run this script in startup, you can create a shortcut and add it to the startup folder.

```powershell
# powershell
Set-Location .\PSChocoOutdatedReporter

$location = Get-Location
$path = $location.Path
$scriptPath = Join-Path $path "Invoke-ReportChocolateyOutdated.ps1"

$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "ReportChocolateyOutdated.lnk"

$wshShell = New-Object -ComObject WScript.Shell
$shortcut = $wshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`""
$shortcut.Save()
```

## License

MIT
