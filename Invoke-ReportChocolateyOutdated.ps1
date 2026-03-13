class CommandRunner {
    [string[]] Run([string]$FilePath, [string[]]$ArgumentList) {
        return (& $FilePath @ArgumentList)
    }
}

class PackageRecord {
    [string]$Id
    [string]$Version
    [string]$AvailableVersion
    [string]$Pinned

    PackageRecord([string]$id, [string]$version, [string]$availableVersion, [string]$pinned) {
        $this.Id = $id
        $this.Version = $version
        $this.AvailableVersion = $availableVersion
        $this.Pinned = $pinned
    }
}

function New-CommandRunner {
    [CmdletBinding()]
    [OutputType([CommandRunner])]
    param()
    return [CommandRunner]::new()
}

function Get-OutdatedPackages {
    [CmdletBinding()]
    [OutputType([PackageRecord[]])]
    param()
    $runner = New-CommandRunner
    $text = $runner.Run("choco", @("outdated", "--no-color", "--limit-output"))
    $lines = $text -split "`r?`n"
    $packages = foreach ($line in $lines) {
        $parts = $line -split "\|"
        if ($parts.Length -eq 4) {
            [PackageRecord]::new($parts[0], $parts[1], $parts[2], $parts[3])
        }
    }
    return $packages
}

function Invoke-ReportChocolateyOutdated {
    [CmdletBinding()]
    [OutputType([void])]
    param()
    $packages = @(Get-OutdatedPackages)

    if ($packages.Count -eq 0) {
        Write-Host "All packages are up to date."
        return
    }

    Write-Host "Outdated packages:"
    $packages | Format-Table -Property Id, Version, AvailableVersion, Pinned -AutoSize

    foreach ($package in $packages) {
        $id = $package.Id
        $version = $package.Version
        $availableVersion = $package.AvailableVersion
        $versionHistroyUrl = "https://community.chocolatey.org/packages/${id}/#versionhistory"
        $upgradeCommand = "choco upgrade ${id}"

        Write-Host "## $id"

        Write-Host -NoNewLine "To check Downloads, Last updated, Status, visit: "
        Write-Host -ForegroundColor Yellow "$versionHistroyUrl"

        Write-Host -NoNewLine "To upgrade from "
        Write-Host -NoNewLine -ForegroundColor Red ${version}
        Write-Host -NoNewLine " to "
        Write-Host -NoNewLine -ForegroundColor Green ${availableVersion}
        Write-Host -NoNewLine ", type: ``"
        Write-Host -NoNewLine -ForegroundColor Yellow ${upgradeCommand}
        Write-Host "``, or run the following command:"

        Write-Host -ForegroundColor Yellow "sudo powershell.exe -NoProfile -NoExit -Command `"$upgradeCommand`""
        Write-Host ""

    }
    Read-Host "Press Enter to exit..."
}

Invoke-ReportChocolateyOutdated
