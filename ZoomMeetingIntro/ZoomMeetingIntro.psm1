# Load private helpers before public commands.
foreach ($folder in 'private', 'public') {
    $folderPath = Join-Path -Path $PSScriptRoot -ChildPath $folder
    foreach ($file in Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File | Sort-Object -Property Name) {
        . $file.FullName
    }
}