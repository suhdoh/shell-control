param([string]$Root,[ValidateSet('Dependencies','Fonts','Profiles','Terminal')][string]$Component,[ValidateSet('Recommended','All')][string]$Pack='Recommended',[string]$StatusPath,[string]$TerminalSettingsPath)
$ErrorActionPreference='Stop'
$global:ShellControlRoot=$Root
$global:ShellControlSettingsPath=$TerminalSettingsPath
. (Join-Path $Root 'common.ps1')
. (Join-Path $Root 'install-core.ps1')
$script:ShellSetupProgress={param($p,$m) Write-ShellAtomicText -Path $StatusPath -Text ([pscustomobject]@{Percent=$p;Message=$m;Error=$null}|ConvertTo-Json) -Json -SkipBackup}
try {
    if($Component -eq 'Dependencies'){Install-ShellDependencies}
    if($Component -eq 'Fonts'){Install-ShellFonts -Pack $Pack}
    if($Component -eq 'Profiles'){Install-ShellProfiles;Install-ShellCmd}
    if($Component -in @('Terminal')){Install-ShellTerminal}
    Send-ShellSetupProgress 100 'Setup completed'
} catch {
    Write-ShellAtomicText -Path $StatusPath -Text ([pscustomobject]@{Percent=0;Message='Setup failed';Error=$_.Exception.Message}|ConvertTo-Json) -Json -SkipBackup
    exit 1
}
