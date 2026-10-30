function Find-DateFont {
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($dir in @("$env:LOCALAPPDATA\Microsoft\Windows\Fonts", "$env:WINDIR\Fonts")) {
        foreach ($file in 'Poppins-Light.ttf', 'segoeuil.ttf', 'segoeui.ttf', 'arial.ttf') {
            $candidates.Add((Join-Path -Path $dir -ChildPath $file))
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    if (Get-Command -Name fc-match -ErrorAction SilentlyContinue) {
        foreach ($family in 'Poppins:light', 'Segoe UI:light', 'sans-serif') {
            $match = & fc-match -f '%{file}' $family
            if ($match -and (Test-Path -LiteralPath $match -PathType Leaf)) { return $match }
        }
    }
    throw 'No usable font found for the date. Pass one with -FontPath, or use -NoDate.'
}