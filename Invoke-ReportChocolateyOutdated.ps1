class CommandRunner {
    [string[]] Run([string]$FilePath, [string[]]$ArgumentList) {
        return (& $FilePath @ArgumentList)
    }
}

class PackageVersion {
    [string]$Version
    [datetime]$PublishedDate

    PackageVersion([string]$version, [datetime]$publishedDate) {
        $this.Version = $version
        $this.PublishedDate = $publishedDate
    }

    [string] GetAgoString() {
        [datetime]$now = (Get-Date)
        $date = $this.PublishedDate
        $timeSpan = $now - $date
        $days = $timeSpan.TotalDays
        $daysInt = [math]::Floor($days)
        return "${daysInt}d ago"
    }

    [string] ToString() {
        return $this.Version + " (" + $this.GetAgoString() + ")"
    }
}

class PackageVersionFactory {
    [string] $CacheJsonFolder
    [string] $CacheJsonPath

     PackageVersionFactory() {
        $this.CacheJsonFolder = "$env:LOCALAPPDATA\ReportChocolateyOutdated"
        $this.CacheJsonPath = Join-Path $this.CacheJsonFolder "cache.json"
        Write-Host "Cache file path: $($this.CacheJsonPath)"
    }

    [DateTime] FetchPublishedDate([string]$PackageId, [string]$Version) {
        try {
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
            Write-Error "Failed to retrieve published date for package '$PackageId' version '$Version': $_"
            return $null
        }
    }

    [hashtable] GetCache() {
        if (Test-Path -LiteralPath $this.CacheJsonPath) {
            try {
                $rawCache = Get-Content -LiteralPath $this.CacheJsonPath -Raw | ConvertFrom-Json -AsHashtable
                if ($rawCache -is [hashtable]) {
                    return $rawCache
                }
            } catch {
            }
        }
        return @{}
    }

    [hashtable] GetPackageCache([string]$Id, [hashtable]$cache) {
        if ($cache.ContainsKey($Id) -and $cache[$Id] -is [hashtable]) {
            return $cache[$Id]
        }

        $cache[$Id] = @{}
        return $cache[$Id]
    }

    [datetime] GetPublishedDate([string]$Id, [string]$versionString, [hashtable]$cache) {
        $keyPublishedDate = "PublishedDate"

        # Get from cache if available
        $packageCache = $this.GetPackageCache($Id, $cache)
        if ($packageCache.ContainsKey($versionString) -and $packageCache[$versionString]) {
            $versionCache = $packageCache[$versionString]
            if ($versionCache -is [hashtable] -and $versionCache.ContainsKey($keyPublishedDate)) {
                return [DateTime]$versionCache[$keyPublishedDate]
            }
        }

        # Not in cache, retrieve from web and update cache
        $publishedDate = $this.FetchPublishedDate($Id, $versionString)

        # Update cache
        if (-not $packageCache.ContainsKey($versionString)) {
            $packageCache[$versionString] = @{}
        }
        $versionCache2 = $packageCache[$versionString]
        $versionCache2[$keyPublishedDate] = $publishedDate

        return $publishedDate
    }

    [PackageVersion] Create([string]$Id, [string]$versionString) {
        $cache = $this.GetCache()
        $packageCache = $this.GetPackageCache($Id, $cache)

        $publishedDate = $null
        if ($packageCache.ContainsKey($versionString) -and $packageCache[$versionString]) {
            $versionCache = $packageCache[$versionString]

            $keyPublishedDate = "PublishedDate"

            if ($versionCache -is [hashtable] -and $versionCache.ContainsKey($keyPublishedDate)) {
                $publishedDate = [DateTime]$versionCache[$keyPublishedDate]
            }
        }

        $publishedDate = $this.GetPublishedDate($Id, $versionString, $cache)

        $packageCache[$versionString] = @{
            PublishedDate = $publishedDate
        }

        if (-not (Test-Path -LiteralPath $this.CacheJsonFolder)) {
            $null = New-Item -ItemType Directory -Path $this.CacheJsonFolder -Force
        }

        Write-Host "Caching version information for package '$Id' version '$versionString'."
        $cache | ConvertTo-Json -Depth 4 -Compress | Set-Content -LiteralPath $this.CacheJsonPath

        return [PackageVersion]::new($versionString, $publishedDate)
    }
}

class PackageRecord {
    [string]$Id
    [PackageVersion]$InstalledVersion
    [PackageVersion]$AvailableVersion
    [string]$Pinned

    PackageRecord([string]$id, [PackageVersion]$installedVersion, [PackageVersion]$availableVersion, [string]$pinned) {
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
    param([PackageVersionFactory]$versionFactory = [PackageVersionFactory]::new())
    $runner = New-CommandRunner
    $text = $runner.Run("choco", @("outdated", "--no-color", "--limit-output"))
    $lines = $text -split "`r?`n"
    $packages = foreach ($line in $lines) {
        $parts = $line -split "\|"
        if ($parts.Length -eq 4) {
            $id = $parts[0]
            $installedVersion = $versionFactory.Create($id, $parts[1])
            $availableVersion = $versionFactory.Create($id, $parts[2])
            [PackageRecord]::new($id, $installedVersion, $availableVersion, $parts[3])
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

    foreach ($package in $packages) {
        $id = $package.Id
        $installedVersion = $package.InstalledVersion
        $availableVersion = $package.AvailableVersion
        $versionHistroyUrl = "https://community.chocolatey.org/packages/${id}/#versionhistory"
        $upgradeCommand = "choco upgrade ${id}"

        Write-Host "## $id"

        Write-Host -NoNewLine "To check Downloads, Last updated, Status, visit: "
        Write-Host -ForegroundColor Yellow "$versionHistroyUrl"

        # TODO: get some previeous releases using `choco search chocolatey --exact --all-versions --limit-output --order-by=LastPublished`

        Write-Host -NoNewLine "To upgrade from "
        Write-Host -NoNewLine -ForegroundColor Red ${installedVersion}
        Write-Host -NoNewLine " to "
        Write-Host -NoNewLine -ForegroundColor Green ${availableVersion}
        Write-Host -NoNewLine ", run: ``"
        Write-Host -NoNewLine -ForegroundColor Yellow ${upgradeCommand}
        Write-Host -NoNewLine "``"

        if ($sudoCommand) {
            Write-Host ", or run the following command:"
            Write-Host -ForegroundColor Yellow "sudo powershell.exe -NoProfile -NoExit -Command `"${upgradeCommand}`""
        } else {
            Write-Host "."
        }
        Write-Host ""

    }
    Read-Host "Press Enter to exit..."
}

Invoke-ReportChocolateyOutdated
