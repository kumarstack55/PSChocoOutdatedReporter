param([switch]$WriteSudoCommand = $false)

class CommandRunner {
    [string[]] Run([string]$FilePath, [string[]]$ArgumentList) {
        return (& $FilePath @ArgumentList)
    }
}

class Version : System.IComparable {
    hidden [string]$VersionString

    Version([string]$versionString) {
        $this.VersionString = $versionString
    }

    [string] ToString() {
        return $this.VersionString
    }

    [int] CompareTo($other) {
        $thisParts = $this.VersionString.Split('.')
        $otherParts = $other.ToString().Split('.')
        if ($thisParts.Length -ne $otherParts.Length) {
            throw [System.ArgumentException] "Version strings must have the same number of parts"
        }

        $index = 0
        while ($index -lt $thisParts.Length) {
            $thisPart = [int]$thisParts[$index]
            $otherPart = [int]$otherParts[$index]
            if ($thisPart -gt $otherPart) {
                return 1
            } elseif ($thisPart -lt $otherPart) {
                return -1
            }

            $index++
        }
        return 0
    }
}

class SoftwarePackage {
    [Version]$Version
    [datetime]$PublishedDate

    SoftwarePackage([Version]$Version, [datetime]$PublishedDate) {
        $this.Version = $Version
        $this.PublishedDate = $PublishedDate
    }

    [string] GetAgoString() {
        [datetime]$now = (Get-Date)
        $date = $this.PublishedDate
        $timeSpan = $now - $date
        $days = $timeSpan.TotalDays
        $daysInt = [math]::Floor($days)
        if ($daysInt -ge 365) {
            $yearsInt = [math]::Floor($daysInt / 365)
            return "${yearsInt}y ago"
        }

        if ($daysInt -ge 1) {
            return "${daysInt}d ago"
        }

        $hoursInt = [math]::Floor($timeSpan.TotalHours)
        $minutesInt = [math]::Floor($timeSpan.TotalMinutes % 60)
        return "${hoursInt}h ${minutesInt}m ago"
    }

    [string] GetVersion() {
        return $this.Version.ToString()
    }

    [string] ToString() {
        return $this.Version.ToString() + " (" + $this.GetAgoString() + ")"
    }
}

class SoftwarePackageFactory {
    [DateTime] GetPublishedDate([string]$PackageId, [string]$Version) {
        $savedProgressPreference = $global:ProgressPreference
        try {
            $global:ProgressPreference = "SilentlyContinue"
            $url = "https://community.chocolatey.org/api/v2/Packages(Id='{0}',Version='{1}')" -f $PackageId, $Version
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing
            $xmlContent = $response.Content
            $xml = [xml]$xmlContent
            $namespace = [System.Xml.XmlNamespaceManager]::new($xml.NameTable)
            $namespace.AddNamespace('m', 'http://schemas.microsoft.com/ado/2007/08/dataservices/metadata')
            $namespace.AddNamespace('d', 'http://schemas.microsoft.com/ado/2007/08/dataservices')
            $node = $xml.SelectSingleNode('//m:properties/d:Published', $namespace)
            $publishedText = $node.InnerText
            return [DateTime]$publishedText
        } catch {
            Write-Host "Failed to retrieve published date for package '$PackageId' version '$Version': $_"
            return $null
        } finally {
            $global:ProgressPreference = $savedProgressPreference
        }
    }

    [SoftwarePackage[]] CreateList([string]$Id, [int]$MaxCount, [SoftwarePackage]$InstalledVersion) {
        $outputText = choco search ${Id} --exact --all-versions --limit-output --order-by=LastPublished

        $lines = $outputText -split "`r?`n"
        $recordLines = $lines | Where-Object { $_.StartsWith($Id + "|") }

        $versions = [System.Collections.Generic.List[object]]::new()
        foreach ($line in $recordLines) {
            $parts = $line -split "\|"
            if ($parts.Length -ge 2) {
                $versionString = $parts[1]
                $version = [Version]::new($versionString)
                if ($version -eq $InstalledVersion.GetVersion()) {
                    continue
                }

                $packageVersion = $this.Create($Id, $versionString)

                if ($null -ne $InstalledVersion) {
                    if ($packageVersion.PublishedDate -lt $InstalledVersion.PublishedDate) {
                        break
                    }
                }

                $versions.Add($packageVersion)

                if ($versions.Count -ge $MaxCount) {
                    break
                }

            }
        }

        return $versions.ToArray()
    }

    [SoftwarePackage] Create([string]$Id, [string]$versionString) {
        $publishedDate = $this.GetPublishedDate($Id, $versionString)
        $version = [Version]::new($versionString)
        return [SoftwarePackage]::new($version, $publishedDate)
    }
}

class PackageRecord {
    [string]$Id
    [SoftwarePackage]$InstalledVersion
    [SoftwarePackage]$AvailableVersion
    [string]$Pinned

    PackageRecord([string]$id, [SoftwarePackage]$installedVersion, [SoftwarePackage]$availableVersion, [string]$pinned) {
        $this.Id = $id
        $this.InstalledVersion = $installedVersion
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
    param([SoftwarePackageFactory]$packageVersionFactory)
    $runner = New-CommandRunner
    $text = $runner.Run("choco", @("outdated", "--no-color", "--limit-output"))
    $lines = $text -split "`r?`n"
    $packages = foreach ($line in $lines) {
        $parts = $line -split "\|"
        if ($parts.Length -eq 4) {
            $id = $parts[0]
            $installedVersion = $packageVersionFactory.Create($id, $parts[1])
            $availableVersion = $packageVersionFactory.Create($id, $parts[2])
            [PackageRecord]::new($id, $installedVersion, $availableVersion, $parts[3])
        }
    }
    return $packages
}

function Write-HostToUpgradeMessage {
    param(
        [SoftwarePackage]$installedVersion,
        [SoftwarePackage]$availableVersion,
        [string]$upgradeCommandBase,
        [bool]$hasSudo,
        [switch]$WriteSudoCommand,
        [int]$ExcludeNewerDays = 7
    )

    $version = $availableVersion.GetVersion()
    $upgradeCommand = "${upgradeCommandBase} --version=${version}"

    Write-Host -NoNewLine "To upgrade from "
    Write-Host -NoNewLine -ForegroundColor Red "${installedVersion}"
    Write-Host -NoNewLine " to "

    $now = Get-Date
    $coolDownDate = $now.AddDays(-$ExcludeNewerDays)
    if ($availableVersion.PublishedDate -gt $coolDownDate) {
        Write-Host -NoNewLine -ForegroundColor DarkGray "${availableVersion} [🧊 cool down]"
    } elseif ($availableVersion.GetVersion() -lt $installedVersion.GetVersion()) {
        Write-Host -NoNewLine -ForegroundColor DarkYellow "${availableVersion} [⚠️ older than installed]"
    } else {
        Write-Host -NoNewLine -ForegroundColor Yellow "${availableVersion}"
    }

    Write-Host -NoNewLine ", run: ``"
    Write-Host -NoNewLine -ForegroundColor Yellow ${upgradeCommand}
    Write-Host -NoNewLine "``"
    if ($hasSudo -and $WriteSudoCommand) {
        Write-Host ", or run the following command:"
        Write-Host -ForegroundColor Yellow "sudo powershell.exe -NoProfile -NoExit -Command `"${upgradeCommand}`""
    } else {
        Write-Host "."
    }
}

function Invoke-ReportChocolateyOutdated {
    [CmdletBinding()]
    [OutputType([void])]
    param([switch]$WriteSudoCommand = $false)

    $packageVersionFactory = [SoftwarePackageFactory]::new()
    $packages = @(Get-OutdatedPackages -packageVersionFactory $packageVersionFactory)

    if ($packages.Count -eq 0) {
        Write-Host -ForegroundColor Green "All packages are up to date."

        $sleepSeconds = 60
        Write-Host "No outdated packages found. Exiting in ${sleepSeconds} seconds..."
        Start-Sleep -Seconds $sleepSeconds

        return
    }

    Write-Host "Outdated packages:"
    $packages |
    Format-Table -Property Id, InstalledVersion, AvailableVersion, Pinned -AutoSize

    $sudoCommand = Get-Command "sudo" -ErrorAction SilentlyContinue
    $hasSudo = [bool]$sudoCommand

    foreach ($package in $packages) {
        $id = $package.Id
        $installedVersion = $package.InstalledVersion
        $versionHistroyUrl = "https://community.chocolatey.org/packages/${id}/#versionhistory"
        $upgradeCommand = "choco upgrade ${id}"

        Write-Host "## $id"

        Write-Host -NoNewLine "To check Downloads, Last updated, Status, visit: "
        Write-Host -ForegroundColor Yellow "$versionHistroyUrl"

        $maxCount = 20
        $packageVersionList = $packageVersionFactory.CreateList($id, $maxCount, $installedVersion)
        foreach ($packageVersion in $packageVersionList) {
            Write-HostToUpgradeMessage -InstalledVersion $installedVersion -AvailableVersion $packageVersion -UpgradeCommand $upgradeCommand -HasSudo $hasSudo -WriteSudoCommand:$WriteSudoCommand
        }

        Write-Host ""

    }
    Read-Host "Press Enter to exit..."
}

Invoke-ReportChocolateyOutdated -WriteSudoCommand:$WriteSudoCommand
