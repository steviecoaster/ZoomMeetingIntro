function New-MeetingIntro {
    <#
.SYNOPSIS
    Creates a standalone copy of the Ohio PowerShell User Group intro with optional text stamped on it.

.DESCRIPTION
    Takes psoh_intro.mp4 and writes a new video with an optional meeting date and/or message shown under "psoh.io",
    using the same date styling and timing as Add-IntroToRecording.ps1. Nothing is stitched: the output is
    just the 9-second intro, ready to drop into any video editor.

    Requires ffmpeg on PATH (choco install ffmpeg).

.PARAMETER MeetingDate
    The date to stamp. Defaults to today.

.PARAMETER DateFormat
    .NET format string for the date. Default 'MMMM d, yyyy' (e.g. November 12, 2026).
    Anything in single quotes is literal, e.g. "'Recorded' MMMM d, yyyy".

.PARAMETER NoDate
    Don't stamp a date. Use -Message to show a message instead, or alongside the date when this switch is omitted.

.PARAMETER Message
    Optional message to show under "psoh.io". When combined with the date, it appears above the date.

.PARAMETER FontPath
    Font used for the date/message. Defaults to Poppins Light if installed (matches the intro), then Segoe UI Light, then Arial.

.PARAMETER IntroPath
    The base intro video. Defaults to psoh_intro.mp4 next to this script.

.PARAMETER OutputPath
    Where to write the result. Defaults to psoh_intro_<yyyy-MM-dd>.mp4 in the current folder.

.EXAMPLE
    .\New-PsohIntro.ps1 -MeetingDate 2026-11-12

    Writes psoh_intro_2026-11-12.mp4 showing "November 12, 2026".

.EXAMPLE
    $introParams = @{
        MeetingDate = '2026-11-12'
        DateFormat  = 'dddd, MMMM d, yyyy'
        OutputPath  = 'C:\Videos\November intro.mp4'
    }
    .\New-PsohIntro.ps1 @introParams

.EXAMPLE
    New-MeetingIntro -Message 'Welcome, everyone!' -MeetingDate '2026-11-12'

    Shows the message above the meeting date.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [datetime]$MeetingDate = (Get-Date),

        [Parameter()]
        [string]
        $DateFormat = 'MMMM d, yyyy',

        [Parameter()]
        [switch]
        $NoDate,

        [Parameter()]
        [string]
        $Message,

        [Parameter()]
        [string]
        $FontPath,

        [Parameter()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]
        $IntroPath = (Join-Path -Path $PSScriptRoot -ChildPath 'psoh_intro.mp4'),

        [Parameter()]
        [string]
        $OutputPath
    )

    $ErrorActionPreference = 'Stop'

    if (-not (Get-Command -Name ffmpeg -ErrorAction SilentlyContinue)) {
        throw 'ffmpeg was not found on PATH. Install it with: choco install ffmpeg'
    }

    $IntroPath = (Resolve-Path -LiteralPath $IntroPath).ProviderPath
    if (-not $OutputPath) {
        $OutputPath = 'psoh_intro_{0:yyyy-MM-dd}.mp4' -f $MeetingDate
    }
    $OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    if ($OutputPath -eq $IntroPath) {
        throw 'OutputPath must be different from IntroPath.'
    }

    $dateText = if ($NoDate) { $null } else { $MeetingDate.ToString($DateFormat) }
    $messageText = if ([string]::IsNullOrWhiteSpace($Message)) { $null } else { $Message }
    $overlayLines = @()
    if ($messageText) { $overlayLines += $messageText }
    if ($dateText) { $overlayLines += $dateText }
    $actionText = $overlayLines -join ' / '
    $action = if ($actionText) { "Create intro with '$actionText'" } else { 'Create intro without overlay text' }

    if (-not $PSCmdlet.ShouldProcess($OutputPath, $action)) {
        return
    }

    $ffArgs = [System.Collections.Generic.List[string]]::new()
    $ffArgs.AddRange([string[]]@('-hide_banner', '-y', '-loglevel', 'error', '-i', $IntroPath))

    $workDir = $null
    $pushed = $false
    try {
        if ($overlayLines.Count -gt 0) {
            if (-not $FontPath) { $FontPath = Find-DateFont }
            $FontPath = (Resolve-Path -LiteralPath $FontPath).ProviderPath

            # ffmpeg filter options choke on drive-letter colons, commas and apostrophes, so the font and the
            # date text are placed in a temp folder under plain names and ffmpeg is run from that folder.
            $workSplat = @{
                Path      = [System.IO.Path]::GetTempPath()
                ChildPath = 'psoh_intro_' + [guid]::NewGuid().ToString('N')
            }
            $dirSplat = @{
                ItemType = 'Directory'
                Path     = Join-Path @workSplat
            }
            $workDir = (New-Item @dirSplat).FullName

            $copySplat = @{
                LiteralPath = $FontPath
                Destination = Join-Path -Path $workDir -ChildPath ('datefont' + [System.IO.Path]::GetExtension($FontPath))
            }
            Copy-Item @copySplat
            $fontName = Split-Path -Path $copySplat.Destination -Leaf

            # Same timing as the intro's animation: fades in at 5.8s, out with the fade to black at 8.2s
            $alpha = "'if(lt(t,5.8),0,min(1,min((t-5.8)/0.7,(9-t)/0.8)))'"
            $textFilters = [System.Collections.Generic.List[string]]::new()
            if ($messageText) {
                $messageFile = Join-Path -Path $workDir -ChildPath 'message.txt'
                [System.IO.File]::WriteAllText($messageFile, $messageText, [System.Text.UTF8Encoding]::new($false))
                $messageY = if ($dateText) { 'h*0.88' } else { 'h*0.95' }
                $textFilters.Add("drawtext=fontfile=${fontName}:textfile=message.txt:fontsize=34:fontcolor=0xBEC8DC:x=(w-text_w)/2:y=${messageY}-th/2:alpha=${alpha}")
            }
            if ($dateText) {
                $dateFile = Join-Path -Path $workDir -ChildPath 'date.txt'
                [System.IO.File]::WriteAllText($dateFile, $dateText, [System.Text.UTF8Encoding]::new($false))
                $dateY = 'h*0.95'
                $textFilters.Add("drawtext=fontfile=${fontName}:textfile=date.txt:fontsize=34:fontcolor=0xBEC8DC:x=(w-text_w)/2:y=${dateY}-th/2:alpha=${alpha}")
            }
            $ffArgs.AddRange([string[]]@('-vf', ($textFilters -join ',')))
            Push-Location -LiteralPath $workDir
            $pushed = $true
        }

        $ffArgs.AddRange([string[]]@(
                '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p'
                '-c:a', 'copy'
                '-movflags', '+faststart'
                $OutputPath
            ))

        & ffmpeg @ffArgs
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed with exit code $LASTEXITCODE." }
    }
    finally {
        if ($pushed) { Pop-Location }
        if ($workDir) {
            Remove-Item -LiteralPath $workDir -Recurse -ErrorAction SilentlyContinue
        }
    }

    [pscustomobject]@{
        OutputPath  = $OutputPath
        MeetingDate = $dateText
        Message     = $messageText
    }
}