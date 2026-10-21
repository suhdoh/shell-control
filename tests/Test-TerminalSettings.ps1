# Select the settings file for the current profile rather than always preferring stable.
& {
    $settingsFixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-settings-'+[guid]::NewGuid().ToString('N'))
    $savedLocalAppData=$env:LOCALAPPDATA
    $savedProfileId=$env:WT_PROFILE_ID
    $savedSettingsPath=$global:ShellControlSettingsPath
    $savedRoot=$global:ShellControlRoot
    $savedWindowsDirectory=$env:WINDIR
    try {
        $env:LOCALAPPDATA=$settingsFixture
        $global:ShellControlSettingsPath=$null
        $global:ShellControlRoot=Join-Path $settingsFixture 'runtime'
        $env:WINDIR=Join-Path $settingsFixture 'Windows'
        $stable=Join-Path $settingsFixture 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'
        $preview=Join-Path $settingsFixture 'Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json'
        New-Item -ItemType Directory -Path (Split-Path $stable),(Split-Path $preview) -Force|Out-Null
        $activeId='{00000000-0000-0000-0000-000000000002}'
        $otherId='{00000000-0000-0000-0000-000000000001}'
        $activeJson='{"profiles":{"list":[{"guid":"'+$activeId+'"}]}}'
        $otherJson='{"profiles":{"list":[{"guid":"'+$otherId+'"}]}}'
        $otherJson|Set-Content -LiteralPath $stable -Encoding UTF8
        $activeJson|Set-Content -LiteralPath $preview -Encoding UTF8
        $env:WT_PROFILE_ID=$null
        Assert ((Get-ShellTerminalSettingsPath) -eq $stable) 'Setup outside Terminal changed the settings preference order'
        $env:WT_PROFILE_ID=$activeId
        Assert ((Get-ShellTerminalSettingsPath) -eq $preview) 'Active Preview profile selected stable Terminal settings'
        $explicit=Join-Path $settingsFixture 'explicit.json'
        $global:ShellControlSettingsPath=$explicit
        Assert ((Get-ShellTerminalSettingsPath) -eq $explicit) 'Explicit settings override was ignored'
        $global:ShellControlSettingsPath=$null
        $otherJson|Set-Content -LiteralPath $preview -Encoding UTF8
        $failure=$null
        try {Get-ShellTerminalSettingsPath|Out-Null}catch{$failure=$_.Exception.Message}
        Assert ($failure -like '*not found*' -and $failure.Contains($stable) -and $failure.Contains($preview) -and $failure -like '*TerminalSettingsPath*') 'Missing active profile did not report settings override guidance'
        $activeJson|Set-Content -LiteralPath $stable -Encoding UTF8
        $activeJson|Set-Content -LiteralPath $preview -Encoding UTF8
        $failure=$null
        try {Get-ShellTerminalSettingsPath|Out-Null}catch{$failure=$_.Exception.Message}
        Assert ($failure -like '*multiple settings files*' -and $failure.Contains($stable) -and $failure.Contains($preview)) 'Ambiguous active profile silently selected the wrong Terminal'
        '{invalid'|Set-Content -LiteralPath $preview -Encoding UTF8
        $failure=$null
        try {Get-ShellTerminalSettingsPath|Out-Null}catch{$failure=$_.Exception.Message}
        Assert ($failure -like '*could not be read*' -and $failure.Contains($preview)) 'Unreadable candidate allowed unsafe settings selection'
        $workerRoot=$global:ShellControlRoot
        New-Item -ItemType Directory -Path (Join-Path $workerRoot 'assets'),(Join-Path $settingsFixture 'Michael & Team') -Force|Out-Null
        $workerSettings=Join-Path $settingsFixture 'Michael & Team/settings.json'
        $otherJson|Set-Content -LiteralPath $workerSettings -Encoding UTF8
        @{terminalSettingsPath=$workerSettings}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $workerRoot 'menu-settings.json') -Encoding UTF8
        Assert ((Get-ShellTerminalSettingsPath) -eq $workerSettings) 'Saved Terminal settings preference was ignored'
        $global:ShellControlSettingsPath=$explicit
        Assert ((Get-ShellTerminalSettingsPath) -eq $explicit) 'Saved settings preference overrode the explicit session path'
        $global:ShellControlSettingsPath=$workerSettings
        $launch=Get-ShellSetupLaunchParameters -Component Terminal -StatusPath (Join-Path $settingsFixture 'worker-status.json') -IsAdministrator $false
        $arguments=@($launch.ArgumentList)
        $index=[Array]::IndexOf($arguments,'-TerminalSettingsPath')
        Assert ($index -ge 0 -and $arguments[$index+1] -eq ('"'+$workerSettings+'"')) 'Worker launch lost or incorrectly quoted the session settings override'
        $explicitLaunch=Get-ShellSetupLaunchParameters -Component Terminal -StatusPath (Join-Path $settingsFixture 'unused-status.json') -IsAdministrator $false -TerminalSettingsPath $explicit
        $explicitArguments=@($explicitLaunch.ArgumentList)
        $index=[Array]::IndexOf($explicitArguments,'-TerminalSettingsPath')
        Assert ($index -ge 0 -and $explicitArguments[$index+1] -eq ('"'+$explicit+'"')) 'Explicit launch settings override was ignored'
        $projectRoot=Split-Path $PSScriptRoot
        foreach($name in @('common.ps1','safe-io.ps1','install-core.ps1','SetupWorker.ps1')){
            Copy-Item -LiteralPath (Join-Path $projectRoot ('runtime/'+$name)) -Destination (Join-Path $workerRoot $name)
        }
        Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/themes.json') -Destination (Join-Path $workerRoot 'assets/themes.json')
        # A conflicting saved preference proves the worker honors the passed session override.
        @{terminalSettingsPath=$preview}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $workerRoot 'menu-settings.json') -Encoding UTF8
        $workerHost=(Get-Process -Id $PID).Path
        $process=Microsoft.PowerShell.Management\Start-Process -FilePath $workerHost -ArgumentList $launch.ArgumentList -RedirectStandardOutput (Join-Path $settingsFixture 'worker.out.log') -RedirectStandardError (Join-Path $settingsFixture 'worker.err.log') -Wait -PassThru
        Assert ($process.ExitCode -eq 0) 'Terminal setup worker failed with an explicit path containing spaces and ampersand'
        $workerStatus=Get-Content -LiteralPath (Join-Path $settingsFixture 'worker-status.json') -Raw -Encoding UTF8|ConvertFrom-Json
        Assert ($workerStatus.Percent -eq 100 -and -not $workerStatus.Error) 'Terminal worker did not complete using the settings override'
        Assert (@((Read-ShellTerminalJson $workerSettings).schemes).Count -eq 18) 'Terminal worker changed a different settings file'
    } finally {
        $env:LOCALAPPDATA=$savedLocalAppData
        $env:WT_PROFILE_ID=$savedProfileId
        $global:ShellControlSettingsPath=$savedSettingsPath
        $global:ShellControlRoot=$savedRoot
        $env:WINDIR=$savedWindowsDirectory
        if(Test-Path -LiteralPath $settingsFixture){Remove-Item -LiteralPath $settingsFixture -Recurse -Force}
    }
}
Write-Host 'PASS Terminal settings: profile selection, saved/session overrides, safe ambiguity and worker propagation'
