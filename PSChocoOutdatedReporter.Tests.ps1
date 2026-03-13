BeforeAll {
    Import-Module "$PSScriptRoot/PSChocoOutdatedReporter.psd1" -Force
}

Describe "New-CommandRunner" {
    It "Returns a CommandRunner instance" {
        $runner = New-CommandRunner
        $runner.GetType().Name | Should -Be "CommandRunner"
    }
}

Describe "CommandRunner.Run" {
    It "Runs a command and returns its output" {
        $runner = New-CommandRunner
        $result = $runner.Run("pwsh", @("-NoProfile", "-Command", "Write-Output 'hello'"))
        $result | Should -Contain "hello"
    }

    It "Passes multiple arguments to the command correctly" {
        $runner = New-CommandRunner
        $result = $runner.Run("pwsh", @("-NoProfile", "-Command", "Write-Output 'foo'; Write-Output 'bar'"))
        $result | Should -Contain "foo"
        $result | Should -Contain "bar"
    }
}
