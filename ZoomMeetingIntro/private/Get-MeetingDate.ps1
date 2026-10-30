function Get-MeetingDate {
    param([Parameter(Mandatory)][string]$Path)

    $name = [System.IO.Path]::GetFileName($Path)
    if ($name -match 'GMT(\d{8})-(\d{6})') {
        $utc = [datetime]::ParseExact("$($Matches[1])$($Matches[2])", 'yyyyMMddHHmmss', $inv, [System.Globalization.DateTimeStyles]::AssumeUniversal)
        return $utc.ToLocalTime()
    }
    if ($name -match '(\d{4})-(\d{2})-(\d{2})') {
        return [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
    }
    return (Get-Item -LiteralPath $Path).LastWriteTime
}