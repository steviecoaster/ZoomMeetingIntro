function Install-ZoomIntroPreReqs {
    <#
.SYNOPSIS
    Installs ZoomMeetingIntro prerequisites with Chocolatey.

.DESCRIPTION
    Installs the requested Chocolatey packages. Run this command from an elevated PowerShell session;
    administrator privileges and Chocolatey must be available.

.PARAMETER PackageList
    Chocolatey package IDs to install. Defaults to Python and FFmpeg.

.EXAMPLE
    $installParams = @{
        PackageList = @('python', 'ffmpeg')
    }
    Install-ZoomIntroPrereqs @installParams

    Installs Python and FFmpeg using Chocolatey.
#>
    [CmdletBinding()]
    Param(
        [Parameter()]
        [String[]]
        $PackageList = @('ffmpeg')
    )

    begin {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
        if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Administrator privileges are required. Run PowerShell as Administrator and try again.'
        }

        if(-not (Get-Command choco)) {
            throw 'Chocolatey is required to install prerequisites'
        }
    }

    process {

        $chocoArgs = @('install',$($PackageList -join ';'),'--confirm')

        & choco @chocoArgs
    }
}