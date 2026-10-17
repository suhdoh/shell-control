[CmdletBinding(SupportsShouldProcess)]
param([string]$InstallPath=(Join-Path $env:LOCALAPPDATA 'ShellControl'),[string]$DocumentsPath=([Environment]::GetFolderPath('MyDocuments')))
$ErrorActionPreference='Stop'
foreach($version in @('PowerShell','WindowsPowerShell')){
    $path=Join-Path $DocumentsPath ($version+'\profile.ps1')
    if(-not(Test-Path -LiteralPath $path)){continue}
    $text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $updated=[regex]::Replace($text,'(?ms)^# BEGIN SHELL CONTROL\r?\n.*?^# END SHELL CONTROL\r?\n?','')
    if($PSCmdlet.ShouldProcess($path,'Remove Shell Control profile import')){[IO.File]::WriteAllText($path,$updated,(New-Object Text.UTF8Encoding($true)))}
}
Write-Host 'Profile imports removed. Runtime files, fonts, Terminal profiles, backups and dependencies are retained.'
Write-Host ('Restore earlier Terminal settings from '+(Join-Path $InstallPath 'backups')+' if desired.')
