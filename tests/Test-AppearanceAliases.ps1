# Ordinary and managed launch routes for the same PowerShell must retain one appearance.
& {
    $aliasFixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-aliases-'+[guid]::NewGuid().ToString('N'))
    $aliasRuntime=Join-Path $aliasFixture "runtime's files"
    $aliasSettings=Join-Path $aliasFixture 'settings.json'
    $savedRoot=$global:ShellControlRoot
    $savedSettings=$global:ShellControlSettingsPath
    $savedProfile=$env:WT_PROFILE_ID
    $savedGreeting=$env:SHELL_NO_GREETING
    try {
        $project=Split-Path $PSScriptRoot
        New-Item -ItemType Directory -Path $aliasRuntime -Force|Out-Null
        Copy-Item -Path (Join-Path $project 'runtime/*') -Destination $aliasRuntime -Recurse
        Copy-Item -LiteralPath (Join-Path $project 'assets') -Destination (Join-Path $aliasRuntime 'assets') -Recurse
        @'
{
 "profiles":{"defaults":{"font":{"face":"Consolas","size":12}},"list":[
  {"guid":"{574e775e-4f2a-5b96-ac1e-a2962a402336}","name":"PowerShell 7 (x64)","font":{"face":"Old 7","size":14,"features":{"ss01":1}},"startingDirectory":"~","colorScheme":"Old 7"},
  {"guid":"{2947bb6d-5661-4ace-9b6d-842eab823451}","name":"Shell Control 7","font":{"face":"Other 7","size":16,"axes":{"wght":450}},"tabTitle":"custom 7","colorScheme":"Other 7"},
  {"guid":"{61c54bbd-c2c6-5271-96e7-009a87ff44bf}","name":"Windows PowerShell","font":{"face":"Old 5","size":13},"colorScheme":"Old 5"},
  {"guid":"{2947bb6d-5661-4ace-9b6d-842eab823452}","name":"Shell Control 5","font":{"face":"Other 5","size":15},"colorScheme":"Other 5"},
  {"guid":"{00000000-0000-0000-0000-000000000009}","name":"Personal task","font":{"face":"Personal Mono","size":11},"colorScheme":"Personal"}
 ]},"exampleUrl":"https://example.test/kept"
}
'@|Set-Content -LiteralPath $aliasSettings -Encoding UTF8
        $env:SHELL_NO_GREETING='1'
        $env:WT_PROFILE_ID='{574e775e-4f2a-5b96-ac1e-a2962a402336}'
        $global:ShellControlSettingsPath=$aliasSettings
        . (Join-Path $aliasRuntime 'Initialize.ps1')
        Set-ShellControlPreference terminalSettingsPath $aliasSettings
        # Installed-font discovery alone is mocked; all writes use the real settings functions.
        function Get-ShellFontChoices {
            [pscustomobject]@{Shortcut='alias-first';Family='Alias Mono First';cellWidth='0.6';cellHeight='1'}
            [pscustomobject]@{Shortcut='alias-second';Family='Alias Mono Second'}
        }
        $original=Read-ShellTerminalJson $aliasSettings
        $original5=ConvertTo-Json -InputObject @($original.profiles.list[2],$original.profiles.list[3]) -Depth 20 -Compress
        $originalOther=ConvertTo-Json -InputObject $original.profiles.list[4] -Depth 20 -Compress
        Set-TerminalTheme rose 6>$null
        Set-TerminalFont alias-first 6>$null
        Set-TerminalFontSize 18 6>$null
        Set-TerminalCrt on 6>$null
        $updated=Read-ShellTerminalJson $aliasSettings
        foreach($profile in @($updated.profiles.list[0],$updated.profiles.list[1])){
            Assert ($profile.colorScheme -eq 'rose-pine' -and $profile.font.face -eq 'Alias Mono First' -and $profile.font.size -eq 18 -and $profile.'experimental.retroTerminalEffect') 'Changing the ordinary PS7 tab did not update its managed launch route'
        }
        Assert ((ConvertTo-Json -InputObject @($updated.profiles.list[2],$updated.profiles.list[3]) -Depth 20 -Compress) -eq $original5) 'PS7 appearance changes modified PS5 profiles'
        Assert ((ConvertTo-Json -InputObject $updated.profiles.list[4] -Depth 20 -Compress) -eq $originalOther) 'Paired appearance changes modified a personal task profile'
        Assert ($updated.profiles.list[0].font.features.ss01 -eq 1 -and $updated.profiles.list[1].font.axes.wght -eq 450 -and $updated.profiles.list[0].startingDirectory -eq '~' -and $updated.profiles.list[1].tabTitle -eq 'custom 7') 'Appearance synchronization replaced unrelated profile or font properties'

        # Reverse direction and the second PS version must follow the same persisted choices.
        $env:WT_PROFILE_ID='{2947bb6d-5661-4ace-9b6d-842eab823451}'
        Set-TerminalFontSize 19 6>$null
        $env:WT_PROFILE_ID='{2947bb6d-5661-4ace-9b6d-842eab823452}'
        Set-TerminalTheme amber 6>$null
        Set-TerminalFont alias-second -Size 17 6>$null
        Set-TerminalCrt off 6>$null
        $env:WT_PROFILE_ID='{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
        Set-TerminalFontSize 20 6>$null
        $entry=(Join-Path $aliasRuntime 'Initialize.ps1').Replace("'","''")
        $command=@"
`$ErrorActionPreference='Stop'
. '$entry'
`$results=@(foreach(`$id in @('{574e775e-4f2a-5b96-ac1e-a2962a402336}','{2947bb6d-5661-4ace-9b6d-842eab823451}','{61c54bbd-c2c6-5271-96e7-009a87ff44bf}','{2947bb6d-5661-4ace-9b6d-842eab823452}')){
    `$env:WT_PROFILE_ID=`$id
    Get-ShellTerminalAppearance
})
ConvertTo-Json -InputObject `$results -Depth 10 -Compress
"@
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $stdout=Join-Path $aliasFixture 'fresh.out.log'
        $stderr=Join-Path $aliasFixture 'fresh.err.log'
        $child=Microsoft.PowerShell.Management\Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoLogo','-NoProfile','-EncodedCommand',$encoded) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
        if($child.ExitCode -ne 0){throw ('Fresh appearance alias check failed: '+[IO.File]::ReadAllText($stdout)+[IO.File]::ReadAllText($stderr))}
        $fresh=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($stdout))
        foreach($index in @(0,1)){
            Assert ($fresh[$index].Theme -eq 'rose-pine' -and $fresh[$index].Font -eq 'Alias Mono First' -and $fresh[$index].Size -eq 19 -and $fresh[$index].CRT) 'PS7 launch routes did not retain the same appearance in a fresh process'
        }
        foreach($index in @(2,3)){
            Assert ($fresh[$index].Theme -eq 'Amber 340' -and $fresh[$index].Font -eq 'Alias Mono Second' -and $fresh[$index].Size -eq 20 -and -not $fresh[$index].CRT) 'PS5 launch routes did not retain the same appearance in a fresh process'
        }

        $env:WT_PROFILE_ID='{00000000-0000-0000-0000-000000000009}'
        $before=Read-ShellTerminalJson $aliasSettings
        $pairedBefore=ConvertTo-Json -InputObject @($before.profiles.list|Select-Object -First 4) -Depth 20 -Compress
        Set-TerminalFontSize 22 6>$null
        $after=Read-ShellTerminalJson $aliasSettings
        Assert ($after.profiles.list[4].font.size -eq 22 -and (ConvertTo-Json -InputObject @($after.profiles.list|Select-Object -First 4) -Depth 20 -Compress) -eq $pairedBefore) 'An arbitrary task profile changed the known PowerShell appearance pairs'

        # A shader on either launch route must block CRT before either route is written.
        $env:WT_PROFILE_ID='{574e775e-4f2a-5b96-ac1e-a2962a402336}'
        Set-TerminalCrt off 6>$null
        $shaderSettings=Read-ShellTerminalJson $aliasSettings
        $shaderSettings.profiles.list[1]|Add-Member -NotePropertyName 'experimental.pixelShaderPath' -NotePropertyValue 'personal.hlsl'
        [IO.File]::WriteAllText($aliasSettings,($shaderSettings|ConvertTo-Json -Depth 30))
        $before=(Read-ShellTextSnapshot $aliasSettings).Hash
        $failure=$null
        try {Set-TerminalCrt on 6>$null}catch{$failure=$_.Exception.Message}
        Assert ($failure -like '*Pixelshader*' -and (Read-ShellTextSnapshot $aliasSettings).Hash -eq $before) 'A shader conflict on the alternate launch route partially saved CRT'

        # Existing aliases are synchronized; missing ones are not created by an appearance setter.
        $missing=Read-ShellTerminalJson $aliasSettings
        $missing.profiles.list=@($missing.profiles.list|Where-Object guid -ne '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}')
        [IO.File]::WriteAllText($aliasSettings,($missing|ConvertTo-Json -Depth 30))
        $env:WT_PROFILE_ID='{2947bb6d-5661-4ace-9b6d-842eab823452}'
        Set-TerminalFontSize 21 6>$null
        $afterMissing=Read-ShellTerminalJson $aliasSettings
        Assert (@($afterMissing.profiles.list).Count -eq 4 -and @($afterMissing.profiles.list|Where-Object guid -eq '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}').Count -eq 0) 'An appearance change created a missing standard profile'
    } finally {
        $global:ShellControlRoot=$savedRoot
        $global:ShellControlSettingsPath=$savedSettings
        $env:WT_PROFILE_ID=$savedProfile
        $env:SHELL_NO_GREETING=$savedGreeting
        if(Test-Path -LiteralPath $aliasFixture){Remove-Item -LiteralPath $aliasFixture -Recurse -Force}
    }
}
Write-Host 'PASS appearance aliases: ordinary and managed PS5/PS7 launch routes retain selections across fresh processes'
