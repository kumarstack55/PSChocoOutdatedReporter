class CommandRunner {
    [string[]] Run([string]$FilePath, [string[]]$ArgumentList) {
        return (& $FilePath @ArgumentList)
    }
}

function New-CommandRunner {
    [CmdletBinding()]
    [OutputType([CommandRunner])]
    param()
    return [CommandRunner]::new()
}

Export-ModuleMember -Function New-CommandRunner
