function ConvertTo-Seconds {
    param([Parameter(Mandatory)][string]$Value)

    $parts = $Value.Trim().Split(':')
    if ($parts.Count -gt 3) {
        throw "Timestamp '$Value' is not valid. Use hh:mm:ss, mm:ss or seconds."
    }
    [double]$total = 0
    foreach ($part in $parts) {
        [double]$n = 0
        if (-not [double]::TryParse($part, [System.Globalization.NumberStyles]::Float, $inv, [ref]$n)) {
            throw "Timestamp '$Value' is not valid. Use hh:mm:ss, mm:ss or seconds."
        }
        $total = ($total * 60) + $n
    }
    return $total
}