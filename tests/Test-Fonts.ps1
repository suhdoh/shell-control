# Exercise font bookkeeping and discovery without downloads or Windows font APIs.
& {
    $fontFixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-fonts-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fontFixture|Out-Null
    $savedRoot=$global:ShellControlRoot
    try {
        Copy-Item -LiteralPath (Join-Path $savedRoot 'font-catalog.json') -Destination $fontFixture
        $global:ShellControlRoot=$fontFixture
        $catalog=@(Get-Content (Join-Path $fontFixture 'font-catalog.json') -Raw -Encoding UTF8|ConvertFrom-Json)
        $first=Join-Path $fontFixture 'first.ttf'
        $second=Join-Path $fontFixture 'second.ttf'
        'fixture'|Set-Content -LiteralPath $first,$second -Encoding UTF8
        Save-ShellFontReceipt -Fonts @([pscustomobject]@{Family=$catalog[0].Family;Style='Regular';Path=$first})
        $receipt=Join-Path $fontFixture 'installed-fonts.json'
        Assert (@(Get-Content $receipt -Raw -Encoding UTF8|ConvertFrom-Json).Count -eq 1) 'The first registration was not persisted immediately'
        # A later pack must add to previous registrations rather than replace them.
        Save-ShellFontReceipt -Fonts @([pscustomobject]@{Family=$catalog[1].Family;Style='Regular';Path=$second})
        $registered=@(Get-Content $receipt -Raw -Encoding UTF8|ConvertFrom-Json)
        Assert ($registered.Count -eq 2) 'A later font pack discarded previous registrations'
        Save-ShellFontReceipt -Fonts @([pscustomobject]@{Family=$catalog[1].Family;Style='Bold';Path=$second})
        $registered=@(Get-Content $receipt -Raw -Encoding UTF8|ConvertFrom-Json)
        Assert ($registered.Count -eq 2 -and ($registered|Where-Object Path -eq $second).Style -eq 'Bold') 'Registering an existing path duplicated or failed to update its entry'
        # Optional WPF discovery must not hide valid entries from a completed registration.
        function Add-Type {param($AssemblyName,$ErrorAction) throw 'simulated unavailable font enumeration'}
        $choices=@(Get-ShellFontChoices)
        Assert ($choices.Count -eq 2 -and $catalog[0].Family -in $choices.Family -and $catalog[1].Family -in $choices.Family) 'WPF discovery failure hid registered font choices'
        Remove-Item -LiteralPath $second -Force
        $choices=@(Get-ShellFontChoices)
        Assert ($choices.Count -eq 1 -and $choices[0].Family -eq $catalog[0].Family) 'Missing font files were offered as installed choices'
    } finally {
        $global:ShellControlRoot=$savedRoot
        Remove-Item -LiteralPath $fontFixture -Recurse -Force
    }
}
Write-Host 'PASS font checks: merged registrations, durable progress, discovery fallback and missing-file filtering'
