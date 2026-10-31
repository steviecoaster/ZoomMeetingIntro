
function Add-IntroToRecording {
    <#
.SYNOPSIS
    Stitches an intro video into a Zoom recording at a given timestamp.

.DESCRIPTION
    Inserts the intro clip into a recording at -Timestamp. By default everything in the recording is kept:
    the part before the timestamp, then the intro, then the rest of the recording. Use -TrimBefore to throw
    away everything before the timestamp (handy for cutting the "waiting for people to join" chatter), and
    -EndTimestamp to cut the tail of the recording.

    The intro is automatically scaled/padded, frame-rate matched and audio-resampled to match the recording,
    so it works with 720p, 1080p, or odd Zoom resolutions. Requires ffmpeg and ffprobe on PATH
    (choco install ffmpeg).

.PARAMETER RecordingPath
    Path to the Zoom recording (mp4/m4a/mov/mkv).

.PARAMETER Timestamp
    Where in the recording the intro should be inserted. Accepts hh:mm:ss, mm:ss, hh:mm:ss.fff, or plain seconds.

.PARAMETER IntroPath
    Path to the intro video. Defaults to psoh_intro.mp4 in the module root.

.PARAMETER OutputPath
    Where to write the result. Defaults to <yyyy-MM-dd>_with_intro.mp4 using the meeting date, next to the recording.

.PARAMETER TrimBefore
    Discard the part of the recording before -Timestamp so the video opens with the intro.

.PARAMETER EndTimestamp
    Optional. Cut the recording at this point (measured in the original recording's time).

.PARAMETER MeetingDate
    The meeting date stamped under "psoh.io" in the intro. If omitted, it is read from a Zoom-style file name
    (GMTyyyyMMdd-HHmmss..., converted from UTC to local time); otherwise the recording's last-modified date is used.

.PARAMETER DateFormat
    A .NET format string for the date. Default 'MMMM d, yyyy' (e.g. October 30, 2026).
    Anything in single quotes is literal, e.g. "'Recorded' MMMM d, yyyy".

.PARAMETER NoDate
    Don't stamp a date on the intro.

.PARAMETER FontPath
    Font used for the date. Defaults to Poppins Light if installed (matches the intro), then Segoe UI Light, then Arial.

.PARAMETER FadeSeconds
    Length of the fade between the recording and the intro. Default 0.5. Use 0 for hard cuts.

.EXAMPLE
    Add-IntroToRecording -RecordingPath .\GMT20261030.mp4 -Timestamp 00:04:12 -TrimBefore

    Drops the first 4m12s of pre-meeting chatter, opens with the intro, then plays the meeting.

.EXAMPLE
    $stitchParams = @{
        RecordingPath = '.\meeting.mp4'
        Timestamp     = '3:05'
        MeetingDate   = '2026-11-12'
        TrimBefore    = $true
    }
    Add-IntroToRecording @stitchParams

    Stamps "November 12, 2026" on the intro.

.EXAMPLE
    Add-IntroToRecording -RecordingPath .\meeting.mp4 -Timestamp 12:30 -EndTimestamp 1:31:05

    Keeps the welcome/announcements, plays the intro at 12:30 (e.g. right before the main talk), and cuts after 1:31:05.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]
    $RecordingPath,

    [Parameter(Mandatory, Position = 1)]
    [string]
    $Timestamp,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]
    $IntroPath,

    [Parameter()]
    [string]
    $OutputPath,

    [Parameter()]
    [switch]
    $TrimBefore,

    [Parameter()]
    [string]
    $EndTimestamp,

    [Parameter()]
    [datetime]
    $MeetingDate,

    [Parameter()]
    [string]
    $DateFormat = 'MMMM d, yyyy',

    [Parameter()]
    [switch]
    $NoDate,

    [Parameter()]
    [string]
    $FontPath,

    [Parameter()]
    [ValidateRange(0, 5)]
    [double]
    $FadeSeconds = 0.5,

    [Parameter()]
    [ValidateRange(0, 51)]
    [int]
    $Crf = 20,

    [Parameter()]
    [ValidateSet('ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow')]
    [string]
    $Preset = 'medium'
)

$ErrorActionPreference = 'Stop'
$inv = [System.Globalization.CultureInfo]::InvariantCulture

# --- Pre-flight --------------------------------------------------------------------------------
foreach ($tool in 'ffmpeg', 'ffprobe') {
    if (-not (Get-Command -Name $tool -ErrorAction SilentlyContinue)) {
        throw "$tool was not found on PATH. Install it with: Install-ZoomIntroPrereqs"
    }
}

$RecordingPath = (Resolve-Path -LiteralPath $RecordingPath).ProviderPath
$IntroPath = (Resolve-Path -LiteralPath $IntroPath).ProviderPath

if (-not $PSBoundParameters.ContainsKey('MeetingDate')) {
    $MeetingDate = Get-MeetingDate -Path $RecordingPath
    Write-Verbose -Message ("MeetingDate not supplied, using {0:yyyy-MM-dd} from the recording" -f $MeetingDate)
}

if (-not $OutputPath) {
    $outSplat = @{
        Path      = Split-Path -Path $RecordingPath -Parent
        ChildPath = '{0}_with_intro.mp4' -f $MeetingDate.ToString('yyyy-MM-dd', $inv)
    }
    $OutputPath = Join-Path @outSplat
}
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

$rec = Get-MediaInfo -Path $RecordingPath
$intro = Get-MediaInfo -Path $IntroPath

$start = ConvertTo-Seconds -Value $Timestamp
$end = if ($EndTimestamp) { ConvertTo-Seconds -Value $EndTimestamp } else { $rec.Duration }

if ($start -lt 0 -or $start -ge $rec.Duration) {
    throw ("Timestamp {0}s is outside the recording (length {1}s)." -f (Format-Seconds -Seconds $start), (Format-Seconds -Seconds $rec.Duration))
}
if ($end -le $start) { throw 'EndTimestamp must be after Timestamp.' }
$end = [math]::Min($end, $rec.Duration)

# Even dimensions are required for yuv420p / H.264
$w = $rec.Width - ($rec.Width % 2)
$h = $rec.Height - ($rec.Height % 2)
$fps = Format-Seconds -Seconds $rec.Fps
$sr = $rec.SampleRate
$fade = Format-Seconds -Seconds $FadeSeconds
$keepBefore = (-not $TrimBefore) -and ($start -gt 0.05)

# --- Meeting date overlay ----------------------------------------------------------------------
$dateText = $null
$workSplat = @{
    Path = [System.IO.Path]::GetTempPath()
    ChildPath = 'meeting_intro_' + [guid]::NewGuid().ToString('N')
}
$dirSplat = @{
    ItemType = 'Directory'
    Path = Join-Path @workSplat
    WhatIf = $false
}
$workDir = (New-Item @dirSplat).FullName
$audioPath = Join-Path -Path $workDir -ChildPath 'audio.m4a'
$cleanupSplat = @{
    LiteralPath = $workDir
    Recurse = $true
    WhatIf = $false
    ErrorAction = 'SilentlyContinue'
}
$dateFilter = ''
if (-not $NoDate) {
    $dateText = $MeetingDate.ToString($DateFormat)
    if (-not $FontPath) { $FontPath = Find-DateFont }
    $FontPath = (Resolve-Path -LiteralPath $FontPath).ProviderPath

    # ffmpeg filter options choke on drive-letter colons, commas and apostrophes, so the font and the
    # date text are placed in a temp folder under plain names and ffmpeg is run from that folder.
    # (WhatIf = $false so these temp-file steps still run under -WhatIf)
    $copySplat = @{
        LiteralPath = $FontPath
        Destination = Join-Path -Path $workDir -ChildPath ('datefont' + [System.IO.Path]::GetExtension($FontPath))
        WhatIf      = $false
    }
    Copy-Item @copySplat
    $fontName = Split-Path -Path $copySplat.Destination -Leaf
    $dateFile = Join-Path -Path $workDir -ChildPath 'date.txt'
    $writeSplat = @{
        LiteralPath = $dateFile
        Value       = $dateText
        Encoding    = 'utf8NoBOM'
        NoNewline   = $true
        WhatIf      = $false
    }
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        [System.IO.File]::WriteAllText($dateFile, $dateText, [System.Text.UTF8Encoding]::new($false))
    }
    else {
        Set-Content @writeSplat
    }

    # Timing matches the intro's built-in animation: fades in at 5.8s, out with the fade to black at 8.2s
    $alpha = "'if(lt(t,5.8),0,min(1,min((t-5.8)/0.7,(9-t)/0.8)))'"
    $dateFilter = "drawtext=fontfile=${fontName}:textfile=date.txt:fontsize=34:fontcolor=0xBEC8DC:x=(w-text_w)/2:y=970-th/2:alpha=${alpha},"
}

Write-Verbose -Message ("Recording: {0}x{1} @ {2}fps, audio {3}Hz, {4}s" -f $rec.Width, $rec.Height, $fps, $sr, (Format-Seconds -Seconds $rec.Duration))
Write-Verbose -Message ("Intro at {0}s, recording kept {1} -> {2}s" -f (Format-Seconds -Seconds $start), $(if ($keepBefore) { '0' } else { Format-Seconds -Seconds $start }), (Format-Seconds -Seconds $end))

# --- Build the ffmpeg command ------------------------------------------------------------------
$norm = "scale=${w}:${h}:force_original_aspect_ratio=decrease,pad=${w}:${h}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,fps=${fps},format=yuv420p"
$anorm = "aresample=${sr},aformat=sample_fmts=fltp:channel_layouts=stereo"

$ffArgs = [System.Collections.Generic.List[string]]::new()
$ffArgs.AddRange([string[]]@('-hide_banner', '-y', '-loglevel', 'error', '-stats'))

# Input 0: recording. When trimming the front we seek on input, which is much faster on long recordings.
$offset = 0
if (-not $keepBefore -and $start -gt 0) {
    $ffArgs.AddRange([string[]]@('-ss', (Format-Seconds -Seconds $start)))
    $offset = $start
}
$ffArgs.AddRange([string[]]@('-i', $RecordingPath, '-i', $IntroPath))

# Render audio in its own process. A shared video/audio graph can prematurely end the recording's
# audio on FFmpeg 9 even when the source audio is complete. Separate concat filters alone do not help.
$audioArgs = [System.Collections.Generic.List[string]]::new()
$audioArgs.AddRange($ffArgs)
# Input 2: silence, only if the recording has no audio track
if (-not $rec.HasAudio) {
    $audioArgs.AddRange([string[]]@('-f', 'lavfi', '-i', "anullsrc=r=${sr}:cl=stereo"))
}
$recAudio = if ($rec.HasAudio) { '0:a' } else { '2:a' }

$filters = [System.Collections.Generic.List[string]]::new()
$audioFilters = [System.Collections.Generic.List[string]]::new()
$segments = [System.Collections.Generic.List[string]]::new()
$audioSegments = [System.Collections.Generic.List[string]]::new()

# Intro (normalised to match the recording)
$introLen = Format-Seconds -Seconds $intro.Duration
$introAudio = if ($intro.HasAudio) { "[1:a]$anorm" } else { "anullsrc=r=${sr}:cl=stereo,$anorm" }
$filters.Add("[1:v]$dateFilter$norm,setpts=PTS-STARTPTS[iv]")
$audioFilters.Add("$introAudio,asetpts=PTS-STARTPTS,apad,atrim=duration=${introLen}[ia]")

$afterStart = Format-Seconds -Seconds ($start - $offset)
$afterEnd = Format-Seconds -Seconds ($end - $offset)
$afterLen = Format-Seconds -Seconds ($end - $start)
$fadeOutAt = Format-Seconds -Seconds ([math]::Max(0, $start - $FadeSeconds))
$recAudioNorm = "$anorm,apad,atrim=duration=$(Format-Seconds -Seconds ($rec.Duration - $offset))"

if ($keepBefore) {
    $filters.Add("[0:v]$norm,split=2[v0][v1]")
    $audioFilters.Add("[${recAudio}]$recAudioNorm,asplit=2[a0][a1]")
    $beforeV = "[v0]trim=0:$(Format-Seconds -Seconds $start),setpts=PTS-STARTPTS"
    $beforeA = "[a0]atrim=0:$(Format-Seconds -Seconds $start),asetpts=PTS-STARTPTS,apad,atrim=duration=$(Format-Seconds -Seconds $start)"
    if ($FadeSeconds -gt 0) {
        $beforeV += ",fade=t=out:st=${fadeOutAt}:d=${fade}"
        $beforeA += ",afade=t=out:st=${fadeOutAt}:d=${fade}"
    }
    $filters.Add("$beforeV[bv]")
    $audioFilters.Add("$beforeA[ba]")
    $segments.Add('[bv]')
    $audioSegments.Add('[ba]')
    $srcV = '[v1]'
    $srcA = '[a1]'
}
else {
    $srcV = "[0:v]$norm,"
    $srcA = "[${recAudio}]$recAudioNorm,"
}
$afterV = "${srcV}trim=${afterStart}:${afterEnd},setpts=PTS-STARTPTS"
$afterA = "${srcA}atrim=${afterStart}:${afterEnd},asetpts=PTS-STARTPTS,apad,atrim=duration=${afterLen}"
if ($FadeSeconds -gt 0) {
    $afterV += ",fade=t=in:st=0:d=${fade}"
    $afterA += ",afade=t=in:st=0:d=${fade}"
}
$filters.Add("$afterV[av]")
$audioFilters.Add("$afterA[aa]")

$segments.Add('[iv]')
$segments.Add('[av]')
$audioSegments.Add('[ia]')
$audioSegments.Add('[aa]')
$filters.Add(('{0}concat=n={1}:v=1:a=0[outv]' -f ($segments -join ''), $segments.Count))
$audioFilters.Add(('{0}concat=n={1}:v=0:a=1[outa]' -f ($audioSegments -join ''), $audioSegments.Count))

$audioArgs.AddRange([string[]]@(
    '-filter_complex', ($audioFilters -join ';')
    '-map', '[outa]', '-vn'
    '-c:a', 'aac', '-b:a', '160k', '-ar', "$sr"
    $audioPath
))

$ffArgs.AddRange([string[]]@(
    '-i', $audioPath
    '-filter_complex', ($filters -join ';')
    '-map', '[outv]', '-map', '2:a:0'
    '-c:v', 'libx264', '-preset', $Preset, '-crf', "$Crf", '-pix_fmt', 'yuv420p'
    '-c:a', 'copy'
    '-movflags', '+faststart'
    $OutputPath
))

Write-Verbose -Message ("ffmpeg (audio pass) " + ($audioArgs -join ' '))
Write-Verbose -Message ("ffmpeg " + ($ffArgs -join ' '))

if (-not $PSCmdlet.ShouldProcess($OutputPath, "Insert intro dated '$dateText' at $Timestamp")) {
    if ($workDir) { Remove-Item @cleanupSplat }
}
else {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    if ($workDir) { Push-Location -LiteralPath $workDir }
    try {
        & ffmpeg @audioArgs
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg audio pass failed with exit code $LASTEXITCODE." }
        $renderedAudio = Get-MediaInfo -Path $audioPath
        $expectedAudioDuration = $intro.Duration + ($end - $start) + $(if ($keepBefore) { $start } else { 0 })
        if (-not $renderedAudio.HasAudio -or $null -eq $renderedAudio.AudioDuration -or
            $renderedAudio.AudioDuration -lt ($expectedAudioDuration - 0.1)) {
            throw 'The rendered audio ended early. Video encoding was canceled to avoid an incomplete soundtrack.'
        }
        & ffmpeg @ffArgs
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed with exit code $LASTEXITCODE." }
    }
    finally {
        if ($workDir) {
            Pop-Location
            Remove-Item @cleanupSplat
        }
    }
    $sw.Stop()

    $final = Get-MediaInfo -Path $OutputPath
    if (-not $final.HasAudio -or $null -eq $final.AudioDuration -or
        $final.AudioDuration -lt ($expectedAudioDuration - 0.1)) {
        throw "The output audio ended early. The incomplete output is at '$OutputPath'."
    }
    [pscustomobject]@{
        OutputPath    = $OutputPath
        Duration      = [TimeSpan]::FromSeconds($final.Duration).ToString('hh\:mm\:ss')
        Resolution    = '{0}x{1}' -f $final.Width, $final.Height
        MeetingDate   = $dateText
        IntroStartsAt = [TimeSpan]::FromSeconds($(if ($keepBefore) { $start } else { 0 })).ToString('hh\:mm\:ss')
        Elapsed       = $sw.Elapsed.ToString('hh\:mm\:ss')
    }
}
}
