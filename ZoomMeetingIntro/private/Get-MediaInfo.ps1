function Get-MediaInfo {
    param([Parameter(Mandatory)][string]$Path)

    $probeArgs = @(
        '-v', 'error'
        '-show_entries', 'stream=codec_type,width,height,avg_frame_rate,r_frame_rate,sample_rate,duration:format=duration'
        '-of', 'json'
        $Path
    )
    $json = & ffprobe @probeArgs | Out-String
    if ($LASTEXITCODE -ne 0) { throw "ffprobe could not read '$Path'." }
    $data = $json | ConvertFrom-Json

    $video = $data.streams | Where-Object -Property codec_type -EQ -Value 'video' | Select-Object -First 1
    $audio = $data.streams | Where-Object -Property codec_type -EQ -Value 'audio' | Select-Object -First 1

    $fps = 30
    foreach ($rate in @($video.avg_frame_rate, $video.r_frame_rate)) {
        if ($rate -and $rate -match '^(\d+)/(\d+)$' -and [double]$Matches[2] -gt 0) {
            $candidate = [double]$Matches[1] / [double]$Matches[2]
            if ($candidate -ge 5 -and $candidate -le 120) { $fps = [math]::Round($candidate, 3); break }
        }
    }

    [pscustomobject]@{
        Width      = [int]$video.width
        Height     = [int]$video.height
        Fps        = $fps
        HasAudio   = [bool]$audio
        AudioDuration = if ($audio.duration -and $audio.duration -ne 'N/A') {
            [double]::Parse($audio.duration, [System.Globalization.CultureInfo]::InvariantCulture)
        } else { $null }
        SampleRate = if ($audio.sample_rate) { [int]$audio.sample_rate } else { 48000 }
        Duration   = [double]::Parse($data.format.duration, $inv)
    }
}