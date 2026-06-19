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
        $partCount = [Math]::Max($thisParts.Length, $otherParts.Length)

        $index = 0
        while ($index -lt $partCount) {
            $thisPart = 0
            if ($index -lt $thisParts.Length) {
                $thisPart = [int]$thisParts[$index]
            }

            $otherPart = 0
            if ($index -lt $otherParts.Length) {
                $otherPart = [int]$otherParts[$index]
            }

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
