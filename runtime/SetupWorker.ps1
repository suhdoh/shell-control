param([string]$Root,[ValidateSet('Dependencies','Fonts','Profiles','Terminal','All')][string]$Component,[ValidateSet('Recommended','All')][string]$Pack='Recommended',[string]$StatusPath)
$ErrorActionPreference='Stop'
$global:ShellControlRoot=$Root
. (Join-Path $Root 'common.ps1')
. (Join-Path $Root 'install-core.ps1')
$script:ShellSetupProgress={param($p,$m) [IO.File]::WriteAllText($StatusPath,([pscustomobject]@{Percent=$p;Message=$m;Error=$null}|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))}
try {
    if($Component -in @('Dependencies','All')){Install-ShellDependencies}
    if($Component -in @('Fonts','All')){Install-ShellFonts -Pack $Pack}
    if($Component -in @('Profiles','All')){Install-ShellProfiles;Install-ShellCmd}
    if($Component -in @('Terminal','All')){Install-ShellTerminal}
    Send-ShellSetupProgress 100 'Setup completed'
} catch {
    [IO.File]::WriteAllText($StatusPath,([pscustomobject]@{Percent=0;Message='Setup failed';Error=$_.Exception.Message}|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    exit 1
}
