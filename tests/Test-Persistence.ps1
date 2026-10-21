# Preferences and Terminal changes must survive a completely fresh shell process.
& {
    $persistenceFixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-persistence-'+[guid]::NewGuid().ToString('N'))
    $persistenceRuntime=Join-Path $persistenceFixture "runtime's settings"
    $persistenceTerminal=Join-Path $persistenceFixture 'Terminal & custom/settings.json'
    $savedRoot=$global:ShellControlRoot
    $savedSettingsPath=$global:ShellControlSettingsPath
    $savedProfileId=$env:WT_PROFILE_ID
    $savedGreeting=$env:SHELL_NO_GREETING
    $savedLanguage=$script:ShellMenuLanguage
    try {
        $project=Split-Path $PSScriptRoot
        New-Item -ItemType Directory -Path $persistenceRuntime,(Split-Path $persistenceTerminal) -Force|Out-Null
        Copy-Item -Path (Join-Path $project 'runtime/*') -Destination $persistenceRuntime -Recurse
        Copy-Item -LiteralPath (Join-Path $project 'assets') -Destination (Join-Path $persistenceRuntime 'assets') -Recurse
        @'
{
 "defaultProfile":"{00000000-0000-0000-0000-000000000001}",
 "profiles":{"defaults":{"font":{"face":"Consolas","size":12}},"list":[
  {"guid":"{00000000-0000-0000-0000-000000000001}","name":"Persistence fixture","custom":"kept"},
  {"guid":"{00000000-0000-0000-0000-000000000002}","name":"Other","custom":"other kept"}
 ]},
 "exampleUrl":"https://example.test/kept"
}
'@|Set-Content -LiteralPath $persistenceTerminal -Encoding UTF8
        $env:SHELL_NO_GREETING='1'
        $env:WT_PROFILE_ID='{00000000-0000-0000-0000-000000000001}'
        $global:ShellControlSettingsPath=$null
        . (Join-Path $persistenceRuntime 'Initialize.ps1')
        # Mock only installed-family discovery; all setters and persistence are real.
        function Get-ShellFontChoices {
            [pscustomobject]@{Shortcut='fixture-first';Family='Fixture Mono First'}
            [pscustomobject]@{Shortcut='fixture-second';Family='Fixture Mono Second'}
        }
        Set-ShellControlPreference terminalSettingsPath $persistenceTerminal
        Set-ShellMenuLanguage de
        Set-ShellPromptEngine native
        Set-ShellControlPreference fastfetch $false
        Set-TerminalTheme rose 6>$null
        Set-TerminalFont fixture-first 6>$null
        Set-TerminalFontSize 17 6>$null
        Set-TerminalCrt on 6>$null

        function Read-FreshPersistenceState {
            param([string]$Name)
            $entry=(Join-Path $persistenceRuntime 'Initialize.ps1').Replace("'","''")
            $command=@"
`$ErrorActionPreference='Stop'
. '$entry'
`$path=Get-ShellTerminalSettingsPath
`$settings=Read-ShellTerminalJson `$path
`$current=`$settings.profiles.list|Where-Object guid -eq `$env:WT_PROFILE_ID|Select-Object -First 1
[pscustomobject]@{
 Preferences=(Get-ShellControlPreferences)
 Language=(Get-ShellMenuLanguage)
 SettingsPath=`$path
 Appearance=(Get-ShellTerminalAppearance)
 Theme=`$current.colorScheme
 NativePrompt=((Get-Command prompt).Definition.Contains('`$promptLocation'))
 OtherPreference=`$settings.exampleUrl
 OtherProfile=`$settings.profiles.list[1].custom
}|ConvertTo-Json -Depth 20 -Compress
"@
            $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
            $stdout=Join-Path $persistenceFixture ($Name+'.out.log')
            $stderr=Join-Path $persistenceFixture ($Name+'.err.log')
            $child=Microsoft.PowerShell.Management\Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoLogo','-NoProfile','-EncodedCommand',$encoded) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
            $output=[IO.File]::ReadAllText($stdout)
            $errors=[IO.File]::ReadAllText($stderr)
            if($child.ExitCode -ne 0){throw ('Fresh-shell persistence check failed ('+$child.ExitCode+'): '+$output+[Environment]::NewLine+$errors)}
            try {return ($output|ConvertFrom-Json -ErrorAction Stop)} catch {throw ('Invalid fresh-shell state: '+$output+[Environment]::NewLine+$errors)}
        }
        $first=Read-FreshPersistenceState 'first'
        Assert ($first.Language -eq 'de' -and $first.Preferences.language -eq 'de') 'Language did not persist into a new shell'
        Assert ($first.Preferences.promptEngine -eq 'native' -and $first.NativePrompt) 'Native prompt preference did not persist into a new shell'
        Assert ($first.Preferences.fastfetch -eq $false) 'Disabled startup greeting did not persist into a new shell'
        Assert ($first.SettingsPath -eq $persistenceTerminal -and $first.Preferences.terminalSettingsPath -eq $persistenceTerminal) 'Terminal settings path did not persist into a new shell'
        Assert ($first.Theme -eq 'rose-pine' -and $first.Appearance.Font -eq 'Fixture Mono First' -and $first.Appearance.Size -eq 17 -and $first.Appearance.CRT) 'Theme, font, size or CRT did not persist into a new shell'
        Assert ($first.OtherPreference -eq 'https://example.test/kept' -and $first.OtherProfile -eq 'other kept') 'Appearance changes lost unrelated settings'

        Set-ShellMenuLanguage en
        Set-ShellControlPreference fastfetch $true
        Set-TerminalTheme amber 6>$null
        Set-TerminalFont fixture-second 6>$null
        Set-TerminalFontSize 14 6>$null
        Set-TerminalCrt off 6>$null
        $second=Read-FreshPersistenceState 'second'
        Assert ($second.Language -eq 'en' -and $second.Preferences.language -eq 'en' -and $second.Preferences.fastfetch -eq $true) 'Changed language or greeting did not persist into a second new shell'
        Assert ($second.Preferences.promptEngine -eq 'native' -and $second.NativePrompt -and $second.SettingsPath -eq $persistenceTerminal) 'Updating preferences discarded the prompt or Terminal settings path'
        Assert ($second.Theme -eq 'Amber 340' -and $second.Appearance.Font -eq 'Fixture Mono Second' -and $second.Appearance.Size -eq 14 -and -not $second.Appearance.CRT) 'Updated appearance values did not persist into a second new shell'
    } finally {
        $global:ShellControlRoot=$savedRoot
        $global:ShellControlSettingsPath=$savedSettingsPath
        $env:WT_PROFILE_ID=$savedProfileId
        $env:SHELL_NO_GREETING=$savedGreeting
        $script:ShellMenuLanguage=$savedLanguage
        if(Test-Path -LiteralPath $persistenceFixture){Remove-Item -LiteralPath $persistenceFixture -Recurse -Force}
    }
}
Write-Host 'PASS persistence: fresh-shell language, prompt, greeting, Terminal path, theme, font, size and CRT'
