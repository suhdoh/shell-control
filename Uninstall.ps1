[CmdletBinding(SupportsShouldProcess)]
param([string]$InstallPath=(Join-Path $env:LOCALAPPDATA 'ShellControl'),[string]$DocumentsPath=([Environment]::GetFolderPath('MyDocuments')))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'runtime\safe-io.ps1')
$expectedEntry=(Join-Path ([IO.Path]::GetFullPath($InstallPath)) 'Initialize.ps1').Replace("'","''")
foreach($version in @('PowerShell','WindowsPowerShell')){
    $path=Join-Path $DocumentsPath ($version+'\profile.ps1')
    if(-not(Test-Path -LiteralPath $path)){continue}
    $snapshot=Read-ShellTextSnapshot $path
    $text=$snapshot.Text
    $pattern='(?m)^# BEGIN SHELL CONTROL\r?\n\. '+[regex]::Escape("'"+$expectedEntry+"'")+'\r?\n# END SHELL CONTROL\r?\n?'
    $updated=[regex]::Replace($text,$pattern,'')
    if($updated -eq $text){continue}
    if($PSCmdlet.ShouldProcess($path,'Remove Shell Control profile import')){Write-ShellAtomicText -Path $path -Text $updated -ExpectedHash $snapshot.Hash -Bom}
}
Write-Host 'Profile imports removed. Runtime files, fonts, Terminal profiles, backups and dependencies are retained.'
Write-Host ('Restore earlier Terminal settings from '+(Join-Path $InstallPath 'backups')+' if desired.')
