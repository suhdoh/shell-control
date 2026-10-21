# Appearance controls must work before the full Terminal setup has imported themes.
& {
    $appearanceFixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-appearance-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $appearanceFixture|Out-Null
    $savedSettings=$global:ShellControlSettingsPath
    $savedProfile=$env:WT_PROFILE_ID
    try {
        $global:ShellControlSettingsPath=Join-Path $appearanceFixture 'settings.json'
        $env:WT_PROFILE_ID='{00000000-0000-0000-0000-000000000001}'
        @'
{
 "defaultProfile":"{00000000-0000-0000-0000-000000000001}",
 "profiles":{"defaults":{"font":{"face":"Consolas","size":12}},"list":[
  {"guid":"{00000000-0000-0000-0000-000000000001}","name":"Current","custom":"kept"},
  {"guid":"{00000000-0000-0000-0000-000000000002}","name":"Other","colorScheme":"Existing"}
 ]},
 "exampleUrl":"https://example.test/kept"
}
'@|Set-Content -LiteralPath $global:ShellControlSettingsPath -Encoding UTF8
        $before=Read-ShellTextSnapshot $global:ShellControlSettingsPath
        $families=@(Get-ShellThemeFamilies)
        Assert (@($families|ForEach-Object Variants).Count -eq 18) 'Bundled themes are unavailable before setup'
        Assert ((Read-ShellTextSnapshot $global:ShellControlSettingsPath).Hash -eq $before.Hash) 'Listing themes changed settings'
        Set-TerminalTheme rose 6>$null
        $settings=Read-ShellTerminalJson $global:ShellControlSettingsPath
        Assert ($settings.profiles.list[0].colorScheme -eq 'rose-pine') 'Theme was not applied to the current profile'
        Assert (@($settings.schemes).Count -eq 1 -and $settings.schemes[0].name -eq 'rose-pine') 'Selected bundled theme was not imported'
        Assert ($settings.profiles.list[0].custom -eq 'kept' -and $settings.profiles.list[1].colorScheme -eq 'Existing' -and $settings.exampleUrl -eq 'https://example.test/kept') 'Theme change lost unrelated settings'
        Set-TerminalTheme rose 6>$null
        Assert (@((Read-ShellTerminalJson $global:ShellControlSettingsPath).schemes).Count -eq 1) 'Theme selection duplicated a scheme'
        $settings=Read-ShellTerminalJson $global:ShellControlSettingsPath
        $settings.schemes[0].background='#123456'
        [IO.File]::WriteAllText($global:ShellControlSettingsPath,($settings|ConvertTo-Json -Depth 30))
        Set-TerminalTheme rose 6>$null
        Assert ((Read-ShellTerminalJson $global:ShellControlSettingsPath).schemes[0].background -eq '#123456') 'Theme selection overwrote a customized scheme'
        Set-TerminalCrt on 6>$null
        Assert ((Get-ShellTerminalAppearance).CRT) 'CRT on was not saved'
        Set-TerminalCrt toggle 6>$null
        Assert (-not (Get-ShellTerminalAppearance).CRT) 'CRT toggle was not saved'
        $settings=Read-ShellTerminalJson $global:ShellControlSettingsPath
        $settings.profiles.defaults|Add-Member -NotePropertyName 'experimental.pixelShaderPath' -NotePropertyValue 'custom.hlsl'
        $settings.profiles.list[0]|Add-Member -NotePropertyName 'experimental.retroTerminalEffect' -NotePropertyValue $true -Force
        [IO.File]::WriteAllText($global:ShellControlSettingsPath,($settings|ConvertTo-Json -Depth 30))
        $appearance=Get-ShellTerminalAppearance
        Assert ($appearance.CRTConfigured -and -not $appearance.CRT) 'CRT was reported active despite an overriding shader'
        $before=Read-ShellTextSnapshot $global:ShellControlSettingsPath
        $failure=$null
        try {Set-TerminalCrt on 6>$null}catch{$failure=$_.Exception.Message}
        Assert ($failure -like '*Pixelshader*') 'Shader conflict was not explained'
        Assert ((Read-ShellTextSnapshot $global:ShellControlSettingsPath).Hash -eq $before.Hash) 'CRT conflict changed shader settings'
        $settings.profiles.list[0]|Add-Member -NotePropertyName 'experimental.pixelShaderPath' -NotePropertyValue ''
        [IO.File]::WriteAllText($global:ShellControlSettingsPath,($settings|ConvertTo-Json -Depth 30))
        Set-TerminalCrt on 6>$null
        Assert ((Get-ShellTerminalAppearance).CRT) 'An explicit empty shader override did not allow CRT'
        # Terminal's built-in font size can be absent from the settings file.
        $settings=Read-ShellTerminalJson $global:ShellControlSettingsPath
        $settings.profiles.defaults.PSObject.Properties.Remove('font')
        [IO.File]::WriteAllText($global:ShellControlSettingsPath,($settings|ConvertTo-Json -Depth 30))
        function Get-ShellFontChoices {[pscustomobject]@{Shortcut='fixture';Family='Fixture Mono'}}
        Set-TerminalFont fixture 6>$null
        $settings=Read-ShellTerminalJson $global:ShellControlSettingsPath
        Assert ($settings.profiles.list[0].font.face -eq 'Fixture Mono' -and $null -eq $settings.profiles.list[0].font.PSObject.Properties['size']) 'Font selection wrote an invalid null size instead of inheriting Terminal defaults'
        Set-TerminalFont fixture -Size 17 6>$null
        Assert ((Read-ShellTerminalJson $global:ShellControlSettingsPath).profiles.list[0].font.size -eq 17) 'Explicit font size was not saved'

    } finally {
        $global:ShellControlSettingsPath=$savedSettings
        $env:WT_PROFILE_ID=$savedProfile
        Remove-Item -LiteralPath $appearanceFixture -Recurse -Force
    }
}
Write-Host 'PASS appearance checks: bundled themes, targeted imports, CRT persistence and shader conflicts'
