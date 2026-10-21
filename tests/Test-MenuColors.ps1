# Menu colors must read Windows Terminal's JSONC settings on both PowerShell versions.
& {
    $colorFixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-menu-colors-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $colorFixture|Out-Null
    $savedSettingsPath=$global:ShellControlSettingsPath
    $savedProfileId=$env:WT_PROFILE_ID
    try {
        $global:ShellControlSettingsPath=Join-Path $colorFixture 'settings.json'
        @'
{
  // Terminal settings support comments and trailing commas.
  "defaultProfile":"{00000000-0000-0000-0000-000000000001}",
  "profiles":{"defaults":{},"list":[
    {"guid":"{00000000-0000-0000-0000-000000000001}","colorScheme":"Default"},
    {"guid":"{00000000-0000-0000-0000-000000000002}","colorScheme":"Current"},
  ]},
  "schemes":[
    {"name":"Default","cyan":"#ABCDEF"},
    {"name":"Current","cyan":"#123456"},
  ],
}
'@ | Set-Content -LiteralPath $global:ShellControlSettingsPath -Encoding UTF8
        $env:WT_PROFILE_ID='{00000000-0000-0000-0000-000000000002}'
        $colors=Get-ShellMenuPickerColors
        Assert ($colors.Selection -eq ([string][char]27+'[48;2;18;52;86;38;2;250;250;250m')) 'Menu colors did not use the active profile from JSONC settings'
        $env:WT_PROFILE_ID=$null
        $colors=Get-ShellMenuPickerColors
        Assert ($colors.Selection -eq ([string][char]27+'[48;2;171;205;239;38;2;16;16;16m')) 'Menu colors did not use the default profile when outside Windows Terminal'
        '{invalid'|Set-Content -LiteralPath $global:ShellControlSettingsPath -Encoding UTF8
        $colors=Get-ShellMenuPickerColors
        Assert ($colors.Selection -eq ([string][char]27+'[48;2;103;183;186;38;2;16;16;16m')) 'Invalid Terminal settings prevented setup menu navigation'
    } finally {
        $global:ShellControlSettingsPath=$savedSettingsPath
        $env:WT_PROFILE_ID=$savedProfileId
        Remove-Item -LiteralPath $colorFixture -Recurse -Force
    }
}
Write-Host 'PASS menu color checks: JSONC, active profile and default profile'
