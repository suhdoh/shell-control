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
        $env:WT_PROFILE_ID=$null
        $failure=$null
        try {Get-ShellTerminalAppearance|Out-Null}catch{$failure=$_.Exception.Message}
        Assert ($failure -like '*Windows-Terminal*') 'A plain console reported a configured Terminal profile as its actual appearance'
        if($env:OS -eq 'Windows_NT'){
            $installRoot=Join-Path $startupFixture 'installed shell'
            $installSettings=Join-Path $startupFixture 'install-settings.json'
            '{"profiles":{"defaults":{},"list":[]},"schemes":[]}'|Set-Content -LiteralPath $installSettings -Encoding UTF8
            $projectRoot=Split-Path $PSScriptRoot
            $installer=Join-Path $projectRoot 'Install.ps1'
            $hostPath=(Get-Process -Id $PID).Path
            $output=Join-Path $startupFixture 'install.out.log'
            $errorLog=Join-Path $startupFixture 'install.err.log'
            # NoProfiles avoids altering execution policy or real user startup files.
            $arguments=@('-NoLogo','-NoProfile','-File',('"'+$installer+'"'),'-InstallPath',('"'+$installRoot+'"'),'-TerminalSettingsPath',('"'+$installSettings+'"'),'-SkipDependencies','-SkipFonts','-NoProfiles','-NoInteractive')
            $process=Microsoft.PowerShell.Management\Start-Process -FilePath $hostPath -ArgumentList $arguments -RedirectStandardOutput $output -RedirectStandardError $errorLog -Wait -PassThru
            if($process.ExitCode -ne 0){throw ('Configuration installer failed: '+(Get-Content $output,$errorLog -Raw|Out-String))}
            $installed=Read-ShellTerminalJson $installSettings
            $managed=$installed.profiles.list|Where-Object guid -eq '{2947bb6d-5661-4ace-9b6d-842eab823451}'|Select-Object -First 1
            Assert ($managed.commandline -eq ('pwsh.exe -NoLogo -NoProfile -NoExit -File "'+(Join-Path $installRoot 'Initialize.ps1')+'"')) 'Real installation generated an incorrect clean startup command'
            Assert (Test-Path -LiteralPath (Join-Path $installRoot 'terminal-controls.ps1')) 'Real installation omitted menu controls'
            $preferences=Get-Content -LiteralPath (Join-Path $installRoot 'menu-settings.json') -Raw -Encoding UTF8|ConvertFrom-Json
            Assert ($preferences.terminalSettingsPath -eq $installSettings) 'Real installation did not retain its settings file'
        }
    } finally {
        $global:ShellControlSettingsPath=$savedSettings
        $env:WT_PROFILE_ID=$savedProfile
        Remove-Item -LiteralPath $startupFixture -Recurse -Force
    }
}
Write-Host 'PASS startup checks: clean launchers, legacy migration, preserved customizations and accurate console status'
