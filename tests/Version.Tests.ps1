using module ..\Version.psm1

Describe "Version" {
    It "returns the original version string" {
        $version = [Version]::new("1.2.3")

        $version.ToString() | Should -Be "1.2.3"
    }

    It "compares equal versions as zero" {
        $left = [Version]::new("2.10.5")
        $right = [Version]::new("2.10.5")

        $left.CompareTo($right) | Should -Be 0
    }

    It "treats larger numeric part as greater" {
        $left = [Version]::new("1.10.0")
        $right = [Version]::new("1.2.0")

        $left.CompareTo($right) | Should -Be 1
    }

    It "treats smaller numeric part as less" {
        $left = [Version]::new("3.0.9")
        $right = [Version]::new("3.1.0")

        $left.CompareTo($right) | Should -Be -1
    }

    It "treats missing parts as zero" {
        $left = [Version]::new("1.2")
        $right = [Version]::new("1.2.0")

        $left.CompareTo($right) | Should -Be 0
    }

    It "treats a missing part as less than a non-zero part" {
        $left = [Version]::new("1.2")
        $right = [Version]::new("1.2.1")

        $left.CompareTo($right) | Should -Be -1
        $right.CompareTo($left) | Should -Be 1
    }
}
