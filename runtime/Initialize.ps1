# Shared entry point for Windows PowerShell 5.1, ISE and PowerShell 7.
if($Host.Name -eq 'ConsoleHost'){[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)}
$global:ShellControlRoot=$PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
foreach($shellControlFile in @('prompt.ps1','listing.ps1','file-commands.ps1','terminal-controls.ps1','system-info.ps1','shell-menu.ps1','install-core.ps1')){
    . (Join-Path $PSScriptRoot $shellControlFile)
}
$shellControlPreferences=Get-ShellControlPreferences
if($Host.Name -eq 'ConsoleHost' -and $shellControlPreferences.promptEngine -eq 'omp' -and (Find-ShellExecutable oh-my-posh.exe)){
    Set-ShellPromptEngine omp
}
if($shellControlPreferences.fastfetch -ne $false){. (Join-Path $PSScriptRoot 'greeting.ps1')}
