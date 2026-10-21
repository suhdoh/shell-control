# Managed tabs skip foreign startup profiles and migrate only known Shell Control launchers.
& {
    $startupFixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-startup-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $startupFixture|Out-Null
    $savedSettings=$global:ShellControlSettingsPath
    $savedProfile=$env:WT_PROFILE_ID
    try {
        $global:ShellControlSettingsPath=Join-Path $startupFixture 'settings.json'
        @'
{
 "profiles":{"defaults":{},"list":[
  {"guid":"{2947bb6d-5661-4ace-9b6d-842eab823451}","name":"Shell Control 7","commandline":"pwsh.exe -NoLogo","opacity":42,"colorScheme":"rose-pine"},
  {"guid":"{2947bb6d-5661-4ace-9b6d-842eab823452}","name":"Shell Control 5","commandline":"powershell.exe -NoLogo"},
  {"guid":"{00000000-0000-0000-0000-000000000003}","name":"Personal tools","commandline":"pwsh.exe -File toolkit.ps1"}
 ]},
 "schemes":[]
}
'@|Set-Content -LiteralPath $global:ShellControlSettingsPath -Encoding UTF8
        Install-ShellTerminal -SetDefault
        $settings=Read-ShellTerminalJson $global:ShellControlSettingsPath
        $entry=Join-Path $global:ShellControlRoot 'Initialize.ps1'
        foreach($pair in @(@{Index=0;Exe='pwsh.exe'},@{Index=1;Exe='powershell.exe'})){
            $expected=$pair.Exe+' -NoLogo -NoProfile -NoExit -File "'+$entry+'"'
            Assert ($settings.profiles.list[$pair.Index].commandline -eq $expected) 'A managed tab still loads foreign startup profiles'
        }
        Assert ($settings.profiles.list[0].opacity -eq 42 -and $settings.profiles.list[0].colorScheme -eq 'rose-pine') 'Launcher migration reset a customized appearance'
        Assert ($settings.profiles.list[2].commandline -eq 'pwsh.exe -File toolkit.ps1') 'Launcher migration changed an unrelated profile'
        $custom='pwsh.exe -NoProfile -File personal-launcher.ps1'
        $settings.profiles.list[0].commandline=$custom
        [IO.File]::WriteAllText($global:ShellControlSettingsPath,($settings|ConvertTo-Json -Depth 30))
        Install-ShellTerminal -SetDefault
        Assert ((Read-ShellTerminalJson $global:ShellControlSettingsPath).profiles.list[0].commandline -eq $custom) 'Reinstall overwrote a customized managed command'
        Install-ShellTerminal -SetDefault -RepairStartup
        $repaired=Read-ShellTerminalJson $global:ShellControlSettingsPath
        Assert ($repaired.profiles.list[0].commandline -eq ('pwsh.exe -NoLogo -NoProfile -NoExit -File "'+$entry+'"')) 'Explicit startup repair did not replace a conflicting managed launcher'
        Assert ($repaired.profiles.list[0].opacity -eq 42 -and $repaired.profiles.list[0].colorScheme -eq 'rose-pine' -and $repaired.profiles.list[2].commandline -eq 'pwsh.exe -File toolkit.ps1') 'Explicit startup repair changed appearance or an unrelated profile'
        $env:WT_PROFILE_ID=$null
        $failure=$null
        try {Get-ShellTerminalAppearance|Out-Null}catch{$failure=$_.Exception.Message}
        Assert ($failure -like '*Windows-Terminal*') 'A plain console reported a configured Terminal profile as its actual appearance'
        if($env:OS -eq 'Windows_NT'){
            $installRoot=Join-Path $startupFixture 'installed shell'
            $installSettings=Join-Path $startupFixture 'install-settings.json'
            New-Item -ItemType Directory $installRoot|Out-Null
            'ShellControl'|Set-Content -LiteralPath (Join-Path $installRoot '.shell-control-root') -Encoding UTF8
            '{"language":"de","promptEngine":"omp","fastfetch":false}'|Set-Content -LiteralPath (Join-Path $installRoot 'menu-settings.json') -Encoding UTF8
            @'
{"profiles":{"defaults":{},"list":[
 {"guid":"{2947bb6d-5661-4ace-9b6d-842eab823451}","name":"Shell Control","commandline":"pwsh.exe -File old-startup.ps1","font":{"face":"Personal Mono","size":19},"colorScheme":"rose-pine"}
]},"schemes":[]}
'@|Set-Content -LiteralPath $installSettings -Encoding UTF8
            $projectRoot=Split-Path $PSScriptRoot
            $installer=Join-Path $projectRoot 'Install.ps1'
            $hostPath=(Get-Process -Id $PID).Path
            $output=Join-Path $startupFixture 'install.out.log'
            $errorLog=Join-Path $startupFixture 'install.err.log'
            # NoProfiles avoids altering execution policy or real user startup files.
            $arguments=@('-NoLogo','-NoProfile','-File',('"'+$installer+'"'),'-InstallPath',('"'+$installRoot+'"'),'-TerminalSettingsPath',('"'+$installSettings+'"'),'-SkipDependencies','-SkipFonts','-NoProfiles','-NoInteractive','-RepairStartup')
            $process=Microsoft.PowerShell.Management\Start-Process -FilePath $hostPath -ArgumentList $arguments -RedirectStandardOutput $output -RedirectStandardError $errorLog -Wait -PassThru
            if($process.ExitCode -ne 0){throw ('Configuration installer failed: '+(Get-Content $output,$errorLog -Raw|Out-String))}
            $installed=Read-ShellTerminalJson $installSettings
            $managed=$installed.profiles.list|Where-Object guid -eq '{2947bb6d-5661-4ace-9b6d-842eab823451}'|Select-Object -First 1
            Assert ($managed.commandline -eq ('pwsh.exe -NoLogo -NoProfile -NoExit -File "'+(Join-Path $installRoot 'Initialize.ps1')+'"')) 'Real installation generated an incorrect clean startup command'
            Assert (Test-Path -LiteralPath (Join-Path $installRoot 'terminal-controls.ps1')) 'Real installation omitted menu controls'
            $preferences=Get-Content -LiteralPath (Join-Path $installRoot 'menu-settings.json') -Raw -Encoding UTF8|ConvertFrom-Json
            Assert ($preferences.terminalSettingsPath -eq $installSettings) 'Real installation did not retain its settings file'
            Assert ($preferences.promptEngine -eq 'native' -and $preferences.fastfetch -eq $true -and $preferences.language -eq 'de') 'Startup repair did not select the native prompt and greeting while preserving other preferences'
            Assert ($managed.font.face -eq 'Personal Mono' -and $managed.font.size -eq 19 -and $managed.colorScheme -eq 'rose-pine') 'Startup repair discarded the selected font or theme'
            foreach($conflict in @('-NoTerminal','-PreserveTerminalProfiles')){
                $rejectedRoot=Join-Path $startupFixture ('rejected'+$conflict)
                $conflictArgs=@('-NoLogo','-NoProfile','-File',('"'+$installer+'"'),'-InstallPath',('"'+$rejectedRoot+'"'),'-RepairStartup',$conflict)
                $rejected=Microsoft.PowerShell.Management\Start-Process -FilePath $hostPath -ArgumentList $conflictArgs -RedirectStandardOutput (Join-Path $startupFixture ($conflict+'.out.log')) -RedirectStandardError (Join-Path $startupFixture ($conflict+'.err.log')) -Wait -PassThru
                Assert ($rejected.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $rejectedRoot)) 'Conflicting startup options modified the installation before failing'
            }
        }
    } finally {
        $global:ShellControlSettingsPath=$savedSettings
        $env:WT_PROFILE_ID=$savedProfile
        Remove-Item -LiteralPath $startupFixture -Recurse -Force
    }
}
Write-Host 'PASS startup checks: clean launchers, legacy migration, preserved customizations and accurate console status'
