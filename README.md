# ZoomMeetingIntro

Adds an intro video (with the meeting date) to Zoom recordings. The included sample intro is branded for the Ohio PowerShell User Group; use `-IntroPath` to supply your group's own intro video.

| File | What it is |
|---|---|
| [ZoomMeetingIntro.psd1](ZoomMeetingIntro.psd1) | Module manifest. Import this to use `Add-IntroToRecording`. |
| [ZoomMeetingIntro.psm1](ZoomMeetingIntro.psm1) | Loads private helpers and public commands. |
| [LICENSE](LICENSE) | MIT License. |
| [public/Add-IntroToRecording.ps1](public/Add-IntroToRecording.ps1) | Public command that inserts the intro and stamps the meeting date. |
| [public/Install-ZoomIntroPrereqs.ps1](public/Install-ZoomIntroPrereqs.ps1) | Installs FFmpeg through Chocolatey. |
| [private/.gitkeep](private/.gitkeep) | Placeholder for future private helpers. |

---

## 1. Install the module

Choose either the PowerShell Gallery or GitHub source.

### PowerShell Gallery

```powershell
$installParams = @{
    Name  = 'ZoomMeetingIntro'
    Scope = 'CurrentUser'
}
Install-Module @installParams
Import-Module ZoomMeetingIntro
```

### GitHub source

Clone the repository and import its manifest:

```powershell
git clone https://github.com/steviecoaster/ZoomMeetingIntro.git
$manifestPath = Join-Path -Path $PWD -ChildPath 'ZoomMeetingIntro\ZoomMeetingIntro.psd1'
Import-Module ZoomMeetingIntro
```

## 2. One-time prerequisites

The module's prerequisite command installs FFmpeg (which includes ffprobe). Chocolatey must already be installed. Open PowerShell **as Administrator**, import the module using the method above if needed, then run:

```powershell
$prereqParams = @{}
Install-ZoomIntroPrereqs @prereqParams
```

Open a new terminal afterwards and verify FFmpeg is on `PATH` with `ffmpeg -version`.

Make sure an intro MP4 is available. By default, the command looks for `psoh_intro.mp4` in the module root; use `-IntroPath` to point to a different intro video.

**Optional:** Install Poppins Light from [Google Fonts](https://fonts.google.com/specimen/Poppins) for the date overlay. Otherwise, the script uses Segoe UI Light or Arial.

Works in Windows PowerShell 5.1 and PowerShell 7+.

## 3. Choose your timestamp

Open the Zoom recording in any player and note when the meeting actually starts (for example `00:04:12`). That's the `-Timestamp`.

---

## 4. Run it

### Most common: cut the pre-meeting chatter and open with the intro

```powershell
$stitchParams = @{
    RecordingPath = 'C:\Zoom\GMT20261113-003015_Recording_1920x1080.mp4'
    Timestamp     = '00:04:12'
    TrimBefore    = $true
}
Add-IntroToRecording @stitchParams
```

Result: the intro, then the meeting from 4:12 onwards, saved next to the original as `<meeting-date>_with_intro.mp4` (for example, `2026-11-12_with_intro.mp4`).


### Trim both ends and set the date yourself

```powershell
$stitchParams = @{
    RecordingPath = '.\meeting.mp4'
    Timestamp     = '3:05'
    EndTimestamp  = '1:31:05'
    TrimBefore    = $true
    MeetingDate   = '2026-11-12'
    OutputPath    = '.\2026-11-12 Meeting.mp4'
}
Add-IntroToRecording @stitchParams
```

### Preview without encoding anything

Add `WhatIf = $true` to the splat. The script prints what it would do, including the date it picked, and doesn't encode anything.

When it finishes, the script prints a summary showing the output path, duration, resolution, the date used and how long the encode took.

---

## 5. Parameters

| Parameter | Default | Notes |
|---|---|---|
| `RecordingPath` | *(required)* | The Zoom `.mp4` (`.mov` and `.mkv` work too). |
| `Timestamp` | *(required)* | Where the intro goes. Accepts `hh:mm:ss`, `mm:ss`, `hh:mm:ss.fff` or plain seconds (`252`). |
| `TrimBefore` | off | Removes everything before `Timestamp`. |
| `EndTimestamp` | end of file | Cuts the recording at this point, measured in the original recording's time. |
| `MeetingDate` | auto | See "How the date is picked" below. |
| `DateFormat` | `MMMM d, yyyy` | .NET date format. `dddd, MMMM d, yyyy` gives "Thursday, November 12, 2026". |
| `NoDate` | off | Leaves the date line blank. |
| `FontPath` | auto | Font for the date. Tries Poppins Light, then Segoe UI Light, then Arial. |
| `OutputPath` | `<yyyy-MM-dd>_with_intro.mp4` | Uses the meeting date (explicit or detected) and saves next to the original by default. |
| `IntroPath` | *(required)* | The path to the intro video to splice onto the recording |
| `FadeSeconds` | `0.5` | Fade length between the recording and the intro. `0` gives hard cuts. |
| `Preset` | `medium` | x264 speed. `veryfast` encodes quicker with slightly larger files. |
| `Crf` | `20` | Quality: lower means better quality and bigger files. 18–23 is sensible. |

### How the date is picked (when `MeetingDate` isn't given)

1. **Zoom file name.** Zoom names files like `GMT20261113-003015_...`, which is in UTC. The script converts it to your local time, so a 7:30 pm Ohio meeting correctly shows as November 12, not 13.
2. **A `yyyy-MM-dd` date anywhere in the file name.**
3. **The file's last-modified date.**
