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
$InstallPath=[IO.Path]::GetFullPath($InstallPath)
if($InstallPath -eq [IO.Path]::GetFullPath($source)){throw 'Choose an installation folder outside the source runtime directory.'}
New-Item -ItemType Directory -Path $InstallPath -Force|Out-Null
$backup=Join-Path $InstallPath ('backups\'+(Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $backup -Force|Out-Null
foreach($file in (Get-ChildItem -LiteralPath $source -File)){
    $destination=Join-Path $InstallPath $file.Name
    if($file.Name -eq 'menu-settings.json' -and (Test-Path -LiteralPath $destination)){continue}
    if(Test-Path -LiteralPath $destination){Copy-Item -LiteralPath $destination -Destination (Join-Path $backup $file.Name) -Force}
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    Unblock-File -LiteralPath $destination -ErrorAction SilentlyContinue
}
$assets=Join-Path $InstallPath 'assets'
New-Item -ItemType Directory -Path $assets -Force|Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'assets\*') -Destination $assets -Recurse -Force
foreach($notice in @('LICENSE','THIRD-PARTY.md','FONT-CREDITS.md')){
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $notice) -Destination (Join-Path $InstallPath $notice) -Force
}
$global:ShellControlRoot=$InstallPath
if($TerminalSettingsPath){$global:ShellControlSettingsPath=$TerminalSettingsPath}
. (Join-Path $InstallPath 'common.ps1')
. (Join-Path $InstallPath 'install-core.ps1')
. (Join-Path $InstallPath 'shell-menu.ps1')
$interactive=-not $NoInteractive -and $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected
$esc=[char]27
if($interactive){[Console]::Write("$esc[?1049h");$script:ShellSetupProgress={param($p,$m) Show-ShellSetupProgress $p $m}}
try {
    if(-not $SkipDependencies){
        $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if($admin){Install-ShellDependencies}else{Invoke-ShellSetup -Component Dependencies}
    }
    if(-not $SkipFonts){Install-ShellFonts -Pack $FontPack}
    if(-not $NoProfiles){
        if((Get-ExecutionPolicy -Scope CurrentUser) -in @('Undefined','Restricted') -and (Get-ExecutionPolicy -Scope LocalMachine) -in @('Undefined','Restricted') -and (Get-ExecutionPolicy -Scope MachinePolicy) -eq 'Undefined' -and (Get-ExecutionPolicy -Scope UserPolicy) -eq 'Undefined'){
            # Only the current user's policy is adjusted; machine policy is never changed.
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        }
        Install-ShellProfiles -DocumentsPath $DocumentsPath -BackupRoot $backup
    }
    Install-ShellCmd
    if(-not $NoTerminal){Install-ShellTerminal -PreserveProfiles:$PreserveTerminalProfiles -SetDefault:(-not $PreserveTerminalProfiles)}
    [void](Update-ShellHardwareCache)
    Send-ShellSetupProgress 100 'Installation completed'
    $receipt=[pscustomobject]@{Version='0.1.1';Installed=(Get-Date -Format o);Root=$InstallPath;Documents=$DocumentsPath;Backup=$backup;FontPack=$FontPack}
    [IO.File]::WriteAllText((Join-Path $InstallPath 'installation.json'),($receipt|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
} finally {
    if($interactive){[Console]::Write("$esc[0m$esc[?25h$esc[?1049l")}
    Write-Progress -Activity 'Shell Control setup' -Completed
}
Write-Host ('Installed: '+$InstallPath)
Write-Host ('Backups:   '+$backup)
Write-Host 'Open a new Terminal tab and run: shell-menu'
