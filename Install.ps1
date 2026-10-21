[CmdletBinding()]
param(
    [string]$InstallPath=(Join-Path $env:LOCALAPPDATA 'ShellControl'),
    [ValidateSet('Recommended','All')][string]$FontPack='Recommended',
    [switch]$SkipDependencies,[switch]$SkipFonts,[switch]$NoProfiles,[switch]$NoTerminal,
    [switch]$PreserveTerminalProfiles,[switch]$NoInteractive,
    [string]$DocumentsPath=([Environment]::GetFolderPath('MyDocuments')),
    [string]$TerminalSettingsPath
)
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Shell Control requires Windows 10/11.'}
$source=Join-Path $PSScriptRoot 'runtime'
if(-not(Test-Path -LiteralPath (Join-Path $source 'Initialize.ps1'))){throw 'Extract the complete repository ZIP before running Install.ps1.'}
. (Join-Path $source 'safe-io.ps1')
$InstallPath=Assert-ShellInstallTarget -Path $InstallPath -SourceRoot $PSScriptRoot
New-Item -ItemType Directory -Path $InstallPath -Force|Out-Null
Write-ShellAtomicText -Path (Join-Path $InstallPath '.shell-control-root') -Text 'ShellControl' -SkipBackup
$backup=Join-Path $InstallPath ('backups\'+(Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $backup -Force|Out-Null
foreach($file in (Get-ChildItem -LiteralPath $source -File)){
    $destination=Join-Path $InstallPath $file.Name
    if($file.Name -eq 'menu-settings.json' -and (Test-Path -LiteralPath $destination)){continue}
    if(Test-Path -LiteralPath $destination){Copy-Item -LiteralPath $destination -Destination (Join-Path $backup $file.Name) -Force}
    $snapshot=Read-ShellTextSnapshot $destination
    $sourceBytes=[IO.File]::ReadAllBytes($file.FullName)
    $withBom=($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 239 -and $sourceBytes[1] -eq 187 -and $sourceBytes[2] -eq 191)
    Write-ShellAtomicText -Path $destination -Text ([IO.File]::ReadAllText($file.FullName)) -ExpectedHash $snapshot.Hash -Bom:$withBom
    Unblock-File -LiteralPath $destination -ErrorAction SilentlyContinue
}
$assets=Join-Path $InstallPath 'assets'
New-Item -ItemType Directory -Path $assets -Force|Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'assets\*') -Destination $assets -Recurse -Force
foreach($notice in @('LICENSE','THIRD-PARTY.md','FONT-CREDITS.md','SECURITY.md')){
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $notice) -Destination (Join-Path $InstallPath $notice) -Force
}
$global:ShellControlRoot=$InstallPath
if($TerminalSettingsPath){$global:ShellControlSettingsPath=[IO.Path]::GetFullPath($TerminalSettingsPath)}
. (Join-Path $InstallPath 'Initialize.ps1')
if($TerminalSettingsPath){Set-ShellControlPreference terminalSettingsPath $global:ShellControlSettingsPath}
$interactive=-not $NoInteractive -and $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected
$esc=[char]27
if($interactive){[Console]::Write("$esc[?1049h");$script:ShellSetupProgress={param($p,$m) Show-ShellSetupProgress $p $m}}
try {
    $stages=[ordered]@{}
    if(-not $SkipDependencies){
        $stages.Dependencies={
            $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if($admin){Install-ShellDependencies}else{Invoke-ShellSetup -Component Dependencies}
        }
    }
    if(-not $SkipFonts){$stages.Fonts={Install-ShellFonts -Pack $FontPack}}
    if(-not $NoProfiles){
        $stages.Profiles={
            if((Get-ExecutionPolicy -Scope CurrentUser) -in @('Undefined','Restricted') -and (Get-ExecutionPolicy -Scope LocalMachine) -in @('Undefined','Restricted') -and (Get-ExecutionPolicy -Scope MachinePolicy) -eq 'Undefined' -and (Get-ExecutionPolicy -Scope UserPolicy) -eq 'Undefined'){
                # Only the current user's policy is adjusted; machine policy is never changed.
                Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
            }
            Install-ShellProfiles -DocumentsPath $DocumentsPath -BackupRoot $backup
        }
    }
    $stages.CMD={Install-ShellCmd}
    if(-not $NoTerminal){$stages.Terminal={Install-ShellTerminal -PreserveProfiles:$PreserveTerminalProfiles -SetDefault:(-not $PreserveTerminalProfiles)}}
    Invoke-ShellSetupStages -Stages $stages
    [void](Update-ShellHardwareCache)
    Send-ShellSetupProgress 100 'Installation completed'
    $receipt=[pscustomobject]@{Version='0.1.2';Installed=(Get-Date -Format o);Root=$InstallPath;Documents=$DocumentsPath;Backup=$backup;FontPack=$FontPack}
    Write-ShellAtomicText -Path (Join-Path $InstallPath 'installation.json') -Text ($receipt|ConvertTo-Json) -Json
} finally {
    if($interactive){[Console]::Write("$esc[0m$esc[?25h$esc[?1049l")}
    Write-Progress -Activity 'Shell Control setup' -Completed
}
Write-Host ('Installed: '+$InstallPath)
Write-Host ('Backups:   '+$backup)
Write-Host 'Open a new Terminal tab and run: shell-menu'
