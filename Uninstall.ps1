[CmdletBinding(SupportsShouldProcess)]
param([string]$InstallPath=(Join-Path $env:LOCALAPPDATA 'ShellControl'),[string]$DocumentsPath=([Environment]::GetFolderPath('MyDocuments')))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'runtime\safe-io.ps1')
$expectedEntry=(Join-Path ([IO.Path]::GetFullPath($InstallPath)) 'Initialize.ps1').Replace("'","''")
$entryPattern=[regex]::Escape("'"+$expectedEntry+"'")
$directPattern='(?s)^\s*\.\s+'+$entryPattern+'\s*$'
$sharedPattern='(?s)^\s*if\s*\(\s*\$Host\.Name\s+-ne\s+''ConsoleHost''\s*\)\s*\{\s*\.\s+'+$entryPattern+'\s*\}\s*$'
$blockPattern='(?ms)^# BEGIN SHELL CONTROL\r?\n(?<body>(?:(?!^# BEGIN SHELL CONTROL\r?$).)*?)^# END SHELL CONTROL\r?\n?'
foreach($version in @('PowerShell','WindowsPowerShell')){
    foreach($name in @('profile.ps1','Microsoft.PowerShell_profile.ps1')){
        $path=Join-Path $DocumentsPath ($version+'\'+$name)
        if(-not(Test-Path -LiteralPath $path)){continue}
        $snapshot=Read-ShellTextSnapshot $path
        $updated=[regex]::Replace($snapshot.Text,$blockPattern,{
            param($match)
            if($match.Groups['body'].Value -match $directPattern -or $match.Groups['body'].Value -match $sharedPattern){return ''}
            return $match.Value
        })
        if($updated -eq $snapshot.Text){continue}
        if($PSCmdlet.ShouldProcess($path,'Remove Shell Control profile import')){Write-ShellAtomicText -Path $path -Text $updated -ExpectedHash $snapshot.Hash -Bom}
    }
}
Write-Host 'Profile imports removed. Runtime files, fonts, Terminal profiles, backups and dependencies are retained.'
Write-Host ('Restore earlier Terminal settings from '+(Join-Path $InstallPath 'backups')+' if desired.')
