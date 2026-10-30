function Format-Seconds {
    param([Parameter(Mandatory)][double]$Seconds)
    return $Seconds.ToString('0.###', $inv)
}