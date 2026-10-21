# A package failure must not prevent independent profile and Terminal configuration.
& {
    $stageFixture=Join-Path $fixture 'setup-stages'
    $stageDocuments=Join-Path $stageFixture 'Documents'
    $stageTerminal=Join-Path $stageFixture 'terminal.json'
    $stageProfile=Join-Path $stageDocuments 'PowerShell/profile.ps1'
    New-Item -ItemType Directory -Path (Split-Path $stageProfile) -Force|Out-Null
    "function PersonalToolkit { 'kept' }"|Set-Content -LiteralPath $stageProfile -Encoding UTF8
    '{"profiles":{"defaults":{},"list":[]},"schemes":[]}'|Set-Content -LiteralPath $stageTerminal -Encoding UTF8
    $savedSettings=$global:ShellControlSettingsPath
    try {
        $global:ShellControlSettingsPath=$stageTerminal
        $calls=New-Object 'Collections.Generic.List[string]'
        $stageBackup=Join-Path $stageFixture 'backups'
        $stages=[ordered]@{
            Dependencies={[void]$calls.Add('Dependencies');throw 'simulated WinGet failure'}
            Fonts={[void]$calls.Add('Fonts');Write-Error 'simulated font failure'}
            Profiles={[void]$calls.Add('Profiles');Install-ShellProfiles -DocumentsPath $stageDocuments -BackupRoot $stageBackup}
            CMD={[void]$calls.Add('CMD');Install-ShellCmd}
            Terminal={[void]$calls.Add('Terminal');Install-ShellTerminal -SetDefault}
        }
        $failure=$null
        try {Invoke-ShellSetupStages -Stages $stages}catch{$failure=$_.Exception.Message}
        Assert (($calls -join ',') -eq 'Dependencies,Fonts,Profiles,CMD,Terminal') 'A failed stage prevented independent setup'
        Assert ($failure -like '*Dependencies: simulated WinGet failure*' -and $failure -like '*Fonts: simulated font failure*') 'Incomplete setup hid a failed stage'
        $profileText=Get-Content -LiteralPath $stageProfile -Raw -Encoding UTF8
        Assert ($profileText.Contains('function PersonalToolkit')) 'Partial setup lost existing toolkit code'
        Assert ($profileText.Contains(". '"+(Join-Path $global:ShellControlRoot 'Initialize.ps1').Replace("'","''")+"'")) 'Partial setup did not add the runtime import'
        $settings=Read-ShellTerminalJson $stageTerminal
        Assert (@($settings.schemes).Count -eq 18 -and @($settings.profiles.list).Count -eq 3) 'Partial setup did not configure Terminal'
        $originalBackup=Join-Path $stageBackup 'PowerShell-profile.ps1'
        $originalBackupHash=(Read-ShellTextSnapshot $originalBackup).Hash
        $stageBackup=Join-Path $stageFixture 'backups-retry'
        $stages.Dependencies={}
        $stages.Fonts={}
        Invoke-ShellSetupStages -Stages $stages
        $profileText=Get-Content -LiteralPath $stageProfile -Raw -Encoding UTF8
        Assert ((Read-ShellTextSnapshot $originalBackup).Hash -eq $originalBackupHash) 'Retry overwrote the original startup backup'
        Assert ([regex]::Matches($profileText,'# BEGIN SHELL CONTROL').Count -eq 1) 'Retry duplicated the startup import'
        $settings=Read-ShellTerminalJson $stageTerminal
        Assert (@($settings.schemes).Count -eq 18 -and @($settings.profiles.list).Count -eq 3) 'Retry duplicated Terminal configuration'
    } finally {$global:ShellControlSettingsPath=$savedSettings}
}
Write-Host 'PASS setup stages: independent configuration, preserved toolkit, reported failures and repeatable retry'
