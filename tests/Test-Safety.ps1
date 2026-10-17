# Invoked by Test-Project.ps1 against its isolated fixture and runtime copy.
function Assert-ShellRejected {
    param([scriptblock]$Action,[string]$Message)
    $rejected=$false
    try {& $Action|Out-Null}catch{$rejected=$true}
    Assert $rejected $Message
}
$safetyFile=Join-Path $fixture 'safe-write.json'
Write-ShellAtomicText -Path $safetyFile -Text '{"value":1}' -ExpectedHash MISSING -Json
$original=Read-ShellTextSnapshot $safetyFile
Write-ShellAtomicText -Path $safetyFile -Text '{"value":2}' -ExpectedHash $original.Hash -Json
$backups=@(Get-ChildItem -LiteralPath (Join-Path $fixture '.shell-control-backups') -Filter 'safe-write.json.*.bak')
Assert ($backups.Count -eq 1 -and [IO.File]::ReadAllText($backups[0].FullName) -eq $original.Text) 'Atomic replacement did not preserve the original file'
Assert-ShellRejected {Write-ShellAtomicText -Path $safetyFile -Text '{"value":3}' -ExpectedHash $original.Hash -Json} 'A stale writer overwrote a newer edit'
$current=Read-ShellTextSnapshot $safetyFile
Assert ($current.Text -eq '{"value":2}') 'Concurrent edit was lost'
Assert-ShellRejected {Write-ShellAtomicText -Path $safetyFile -Text '{invalid' -ExpectedHash $current.Hash -Json} 'Invalid JSON was saved'
Assert ((Read-ShellTextSnapshot $safetyFile).Hash -eq $current.Hash) 'JSON validation changed the original'
$locked=[IO.File]::Open($safetyFile,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {Assert-ShellRejected {Write-ShellAtomicText -Path $safetyFile -Text '{"value":4}' -ExpectedHash $current.Hash -Json} 'An exclusively locked destination was overwritten'}finally{$locked.Dispose()}
Assert ((Read-ShellTextSnapshot $safetyFile).Hash -eq $current.Hash) 'Failed save damaged the original'
Assert (@(Get-ChildItem -LiteralPath $fixture -Force -Filter '.safe-write.json.*.tmp').Count -eq 0) 'Failed save left a temporary replacement'

# Simulate a failure in the replacement operation after the temporary file was written.
[IO.File]::SetAttributes($safetyFile,[IO.FileAttributes]::ReadOnly)
try {Assert-ShellRejected {Write-ShellAtomicText -Path $safetyFile -Text '{"value":5}' -ExpectedHash $current.Hash -Json} 'A read-only destination was overwritten'}finally{[IO.File]::SetAttributes($safetyFile,[IO.FileAttributes]::Normal)}
Assert ((Read-ShellTextSnapshot $safetyFile).Hash -eq $current.Hash) 'Replacement failure damaged the original'
Assert (@(Get-ChildItem -LiteralPath $fixture -Force -Filter '.safe-write.json.*.tmp').Count -eq 0) 'Replacement failure left a temporary file'
$statusFile=Join-Path $fixture 'progress.json'
Write-ShellAtomicText -Path $statusFile -Text '{"percent":0}' -Json -SkipBackup
Write-ShellAtomicText -Path $statusFile -Text '{"percent":100}' -Json -SkipBackup
Assert ((Read-ShellTextSnapshot $statusFile).Text -eq '{"percent":100}') 'Replacing a transient status file failed'
Assert (@(Get-ChildItem -LiteralPath (Join-Path $fixture '.shell-control-backups') -Filter 'progress.json.*.bak').Count -eq 0) 'Transient progress generated backups'

$foreign=Join-Path $fixture 'unrelated-directory'
New-Item -ItemType Directory -Path $foreign|Out-Null
[IO.File]::WriteAllText((Join-Path $foreign 'common.ps1'),'personal file')
foreach($unsafe in @([IO.Path]::GetPathRoot($fixture),$env:WINDIR,($env:WINDIR+'.\ShellControl'),$env:USERPROFILE,$env:LOCALAPPDATA,$foreign,$project,(Join-Path $project 'nested-install'),(Join-Path $fixture 'NUL'),'\\server\share\ShellControl')){
    Assert-ShellRejected {Assert-ShellInstallTarget -Path $unsafe -SourceRoot $project} ('Unsafe install target accepted: '+$unsafe)
}
$emptyTarget=Join-Path $fixture 'empty-install'
Assert ((Assert-ShellInstallTarget $emptyTarget -SourceRoot $project) -eq $emptyTarget) 'A dedicated new destination was rejected'
New-Item -ItemType Directory -Path $emptyTarget|Out-Null
[IO.File]::WriteAllText((Join-Path $emptyTarget '.shell-control-root'),'ShellControl')
Assert ((Assert-ShellInstallTarget $emptyTarget -SourceRoot $project) -eq $emptyTarget) 'A recognized installation could not be updated'
$junction=Join-Path $fixture 'junction-install'
New-Item -ItemType Junction -Path $junction -Target $emptyTarget|Out-Null
Assert-ShellRejected {Assert-ShellInstallTarget $junction -SourceRoot $project} 'A junction bypassed target validation'

# Exercise the real installer guard and prove it fails before writing into an unrelated directory.
$guardLog=Join-Path $fixture 'guard.log'
$nativePolicy=$ErrorActionPreference
try {
    $ErrorActionPreference='Continue'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'Install.ps1') -InstallPath $foreign -SkipDependencies -SkipFonts -NoProfiles -NoTerminal -NoInteractive *> $guardLog
    $guardExit=$LASTEXITCODE
} finally {$ErrorActionPreference=$nativePolicy}
Assert ($guardExit -ne 0) 'Installer accepted an unrelated populated directory'
Assert (@(Get-ChildItem -LiteralPath $foreign -Force).Count -eq 1 -and [IO.File]::ReadAllText((Join-Path $foreign 'common.ps1')) -eq 'personal file') 'Rejected install changed the unrelated directory'

foreach($component in @('Dependencies','Fonts','Profiles','Terminal')){
    foreach($adminState in @($false,$true)){
        $launch=Get-ShellSetupLaunchParameters -Component $component -StatusPath (Join-Path $fixture 'status.json') -IsAdministrator $adminState
        Assert ($launch.ContainsKey('Verb') -eq ($component -eq 'Dependencies' -and -not $adminState)) ('Unexpected elevation policy for '+$component)
    }
}
& {
    $calls=New-Object 'Collections.Generic.List[string]'
    $orchestrate=(Get-Command Invoke-ShellSetup).ScriptBlock
    function Invoke-ShellSetup {param($Component,$Pack) [void]$calls.Add($Component)}
    & $orchestrate -Component All
    Assert (($calls -join ',') -eq 'Dependencies,Fonts,Profiles,Terminal') 'Full setup did not split privileged and user configuration stages'
}

# Real menu controls must use the guarded settings writer and preserve unrelated preferences.
$savedProfileId=$env:WT_PROFILE_ID
try {
    $env:WT_PROFILE_ID='{00000000-0000-0000-0000-000000000001}'
    $priorBackups=@(Get-ChildItem -LiteralPath (Join-Path $fixture '.shell-control-backups') -Filter 'terminal.json.*.bak').Count
    Set-TerminalTheme amber 6>$null
    Set-TerminalCrt toggle 6>$null
    Set-TerminalFontSize 17 6>$null
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $fixture '.shell-control-backups') -Filter 'terminal.json.*.bak').Count -eq $priorBackups+3) 'Menu controls omitted backups'
    Assert ((Read-ShellTerminalJson $terminal).exampleUrl -eq 'https://example.test/a//b') 'Menu controls changed unrelated settings'
} finally {$env:WT_PROFILE_ID=$savedProfileId}

# Removal must target only the selected installation and honor -WhatIf.
$beforeRemoval=Read-ShellTextSnapshot $profilePath
& (Join-Path $project 'Uninstall.ps1') -InstallPath (Join-Path $fixture 'different-install') -DocumentsPath $documents *> $null
Assert ((Read-ShellTextSnapshot $profilePath).Hash -eq $beforeRemoval.Hash) 'Uninstall removed another installation import'
& (Join-Path $project 'Uninstall.ps1') -InstallPath $runtime -DocumentsPath $documents -WhatIf *> $null
Assert ((Read-ShellTextSnapshot $profilePath).Hash -eq $beforeRemoval.Hash) '-WhatIf changed the profile'
& (Join-Path $project 'Uninstall.ps1') -InstallPath $runtime -DocumentsPath $documents *> $null
$removed=Read-ShellTextSnapshot $profilePath
Assert ($removed.Text -notmatch '# BEGIN SHELL CONTROL' -and $removed.Text.Contains('function Existing')) 'Uninstall lost personal code or retained its import'
Write-Host 'PASS safety checks: backups, conflicts, failed writes, install targets, elevation boundaries and scoped uninstall'
