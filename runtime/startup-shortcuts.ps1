function global:Read-ShellShortcutSnapshot {
    param([Parameter(Mandatory)][string]$Path)
    $full=[IO.Path]::GetFullPath($Path)
    if(-not [IO.File]::Exists($full)){return [pscustomobject]@{Path=$full;Bytes=$null;Hash='MISSING';Exists=$false}}
    $bytes=[IO.File]::ReadAllBytes($full)
    [pscustomobject]@{Path=$full;Bytes=$bytes;Hash=(Get-ShellBytesHash $bytes);Exists=$true}
}
function global:Write-ShellShortcutBytes {
    param([Parameter(Mandatory)][string]$Path,[byte[]]$Bytes,[Parameter(Mandatory)][string]$ExpectedHash,[switch]$Remove)
    $full=[IO.Path]::GetFullPath($Path)
    $key=Get-ShellBytesHash ([Text.Encoding]::UTF8.GetBytes($full.ToUpperInvariant()))
    $mutex=New-Object Threading.Mutex($false,('Local\ShellControlShortcutWrite-'+$key))
    $held=$false;$temp=$null
    try {
        try {$held=$mutex.WaitOne(5000)}catch [Threading.AbandonedMutexException]{$held=$true}
        if(-not $held){throw 'Another Shell Control process is updating this shortcut. Retry shortly.'}
        $snapshot=Read-ShellShortcutSnapshot $full
        if($snapshot.Hash -ne $ExpectedHash){throw ('The shortcut changed; no changes were saved: '+$full)}
        if($Remove){if($snapshot.Exists){[IO.File]::Delete($full)};return}
        $parent=[IO.Path]::GetDirectoryName($full)
        [void][IO.Directory]::CreateDirectory($parent)
        $temp=Join-Path $parent ('.shell-control-'+[guid]::NewGuid().ToString('N')+'.lnk')
        [IO.File]::WriteAllBytes($temp,$Bytes)
        if((Read-ShellShortcutSnapshot $full).Hash -ne $snapshot.Hash){throw ('The shortcut changed while saving: '+$full)}
        if($snapshot.Exists){[IO.File]::Replace($temp,$full,[NullString]::Value,$false)}else{[IO.File]::Move($temp,$full)}
        $temp=$null
    } finally {
        if($temp -and [IO.File]::Exists($temp)){[IO.File]::Delete($temp)}
        if($held){$mutex.ReleaseMutex()}
        $mutex.Dispose()
    }
}
function global:Test-ShellDefaultShortcutArguments {
    param([AllowEmptyString()][string]$Arguments)
    # These are the ordinary MSI/Store interactive launchers. Any script, command,
    # other directory or additional option belongs to a customized shortcut.
    $tokens=@($Arguments.Trim() -split '\s+'|Where-Object {$_})
    for($i=0;$i -lt $tokens.Count;$i++){
        switch($tokens[$i].ToLowerInvariant()){
            '-nologo' {continue}
            '-noexit' {continue}
            '-noprofile' {continue}
            '-workingdirectory' {
                $i++
                if($i -ge $tokens.Count -or $tokens[$i] -notin @('~','"~"')){return $false}
            }
            default {return $false}
        }
    }
    $true
}
function global:Get-ShellStartupShortcutFiles {
    param([string]$Root)
    if(-not $Root -or -not [IO.Directory]::Exists($Root)){return}
    $pending=New-Object 'Collections.Generic.Queue[string]'
    $pending.Enqueue([IO.Path]::GetFullPath($Root))
    while($pending.Count){
        foreach($item in (Get-ChildItem -LiteralPath $pending.Dequeue() -Force -ErrorAction Stop)){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            if($item.PSIsContainer){$pending.Enqueue($item.FullName)}elseif($item.Extension -eq '.lnk'){$item.FullName}
        }
    }
}
function global:Install-ShellStartupShortcuts {
    [CmdletBinding()]
    param(
        [string]$UserProgramsPath=([Environment]::GetFolderPath('Programs')),
        [string]$DesktopPath=([Environment]::GetFolderPath('DesktopDirectory')),
        [string]$TaskbarPath,
        [string]$CommonProgramsPath=([Environment]::GetFolderPath('CommonPrograms')),
        [string]$TerminalPath,[string]$BackupRoot,[string]$ManifestPath
    )
    if($env:OS -ne 'Windows_NT'){throw 'Windows shortcuts can only be repaired on Windows.'}
    if(-not $TaskbarPath){$TaskbarPath=Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'}
    if(-not $TerminalPath){$TerminalPath=Find-ShellExecutable wt.exe}
    if(-not $TerminalPath -or -not [IO.File]::Exists($TerminalPath)){throw 'Windows Terminal (wt.exe) is required to repair PowerShell shortcuts.'}
    $TerminalPath=[IO.Path]::GetFullPath($TerminalPath)
    if(-not $ManifestPath){$ManifestPath=Join-Path $global:ShellControlRoot 'startup-shortcuts.json'}
    if(-not $BackupRoot){$BackupRoot=Join-Path $global:ShellControlRoot ('backups\shortcuts-'+(Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N'))}
    $manifestSnapshot=Read-ShellTextSnapshot $ManifestPath
    $manifest=[pscustomobject]@{Version=1;Entries=@()}
    if($manifestSnapshot.Exists){
        $manifest=$manifestSnapshot.Text|ConvertFrom-Json -ErrorAction Stop
        if($manifest.Version -ne 1 -or -not $manifest.PSObject.Properties['Entries']){throw 'The startup shortcut backup manifest is invalid.'}
    }
    $candidates=New-Object 'Collections.Generic.List[object]'
    $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($folder in @($UserProgramsPath,$DesktopPath,$TaskbarPath)){
        foreach($path in (Get-ShellStartupShortcutFiles $folder)){
            if($seen.Add($path)){$candidates.Add([pscustomobject]@{Source=$path;Destination=$path;Created=$false})}
        }
    }
    if($UserProgramsPath -and $CommonProgramsPath){
        $commonRoot=[IO.Path]::GetFullPath($CommonProgramsPath).TrimEnd('\')+'\'
        foreach($path in (Get-ShellStartupShortcutFiles $CommonProgramsPath)){
            $destination=Join-Path $UserProgramsPath $path.Substring($commonRoot.Length)
            # An existing user entry has precedence, including a customized link.
            if([IO.File]::Exists($destination) -or -not $seen.Add($destination)){continue}
            $candidates.Add([pscustomobject]@{Source=$path;Destination=$destination;Created=$true})
        }
    }
    $repaired=New-Object 'Collections.Generic.List[object]'
    $skipped=New-Object 'Collections.Generic.List[object]'
    $shell=New-Object -ComObject WScript.Shell
    try {
        foreach($candidate in $candidates){
            try {$source=Read-ShellShortcutSnapshot $candidate.Source}catch{
                $skipped.Add([pscustomobject]@{Path=$candidate.Source;Reason=('Cannot read shortcut: '+$_.Exception.Message)})
                continue
            }
            # Validate the ShellLinkHeader before reading flags. RunAsUser and
            # advertised MSI shortcuts retain their original launch semantics.
            if($source.Bytes.Length -lt 76 -or [BitConverter]::ToUInt32($source.Bytes,0) -ne 76 -or [BitConverter]::ToString($source.Bytes,4,16) -ne '01-14-02-00-00-00-00-00-C0-00-00-00-00-00-00-46'){continue}
            $link=$null;$temp=$null
            try {
                try {
                    $link=$shell.CreateShortcut($candidate.Source)
                    $target=[IO.Path]::GetFileName([string]$link.TargetPath)
                }catch{
                    $skipped.Add([pscustomobject]@{Path=$candidate.Source;Reason=('Cannot inspect shortcut: '+$_.Exception.Message)})
                    continue
                }
                $profile=switch($target.ToLowerInvariant()){
                    'pwsh.exe' {'{2947bb6d-5661-4ace-9b6d-842eab823451}'}
                    'powershell.exe' {'{2947bb6d-5661-4ace-9b6d-842eab823452}'}
                    default {$null}
                }
                # ISE and other applications keep their own shortcuts.
                if(-not $profile){continue}
                $flags=[BitConverter]::ToUInt32($source.Bytes,20)
                $reason=$null
                if($flags -band 0x2000){$reason='Administrator shortcut'}
                elseif($flags -band 0x1000){$reason='Advertised installer shortcut'}
                elseif(-not (Test-ShellDefaultShortcutArguments $link.Arguments)){$reason='Custom PowerShell arguments'}
                if($reason){$skipped.Add([pscustomobject]@{Path=$candidate.Source;Reason=$reason});continue}
                $originalTarget=$link.TargetPath
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link);$link=$null
                $temp=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-shortcut-'+[guid]::NewGuid().ToString('N')+'.lnk')
                [IO.File]::WriteAllBytes($temp,$source.Bytes)
                $link=$shell.CreateShortcut($temp)
                if(-not $link.IconLocation -or $link.IconLocation -match '^\s*,\s*0\s*$'){$link.IconLocation=$originalTarget+',0'}
                $link.TargetPath=$TerminalPath
                $link.Arguments='-p '+$profile
                $link.Save()
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link);$link=$null
                $installed=Read-ShellShortcutSnapshot $temp
                $before=Read-ShellShortcutSnapshot $candidate.Destination
                if(($candidate.Created -and $before.Exists) -or (-not $candidate.Created -and $before.Hash -ne $source.Hash)){throw ('The shortcut changed during repair: '+$candidate.Destination)}
                if($candidate.Created -and (Read-ShellShortcutSnapshot $candidate.Source).Hash -ne $source.Hash){throw ('The common Start Menu shortcut changed during repair: '+$candidate.Source)}
                [void][IO.Directory]::CreateDirectory($BackupRoot)
                $backup=Join-Path $BackupRoot ([guid]::NewGuid().ToString('N')+'.lnk')
                [IO.File]::WriteAllBytes($backup,$source.Bytes)
                $entry=[pscustomobject]@{Path=$candidate.Destination;SourcePath=$candidate.Source;BackupPath=$backup;OriginalHash=$before.Hash;SourceHash=$source.Hash;InstalledHash=$installed.Hash;Created=$candidate.Created;ProfileId=$profile}
                # Save recovery information before replacing the live shortcut.
                $manifest.Entries=@($manifest.Entries)+@($entry)
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ManifestPath)))
                Write-ShellAtomicText -Path $ManifestPath -Text ($manifest|ConvertTo-Json -Depth 8) -ExpectedHash $manifestSnapshot.Hash -Json
                $manifestSnapshot=Read-ShellTextSnapshot $ManifestPath
                Write-ShellShortcutBytes -Path $candidate.Destination -Bytes $installed.Bytes -ExpectedHash $before.Hash
                $repaired.Add($entry)
            } finally {
                if($link){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)}
                if($temp -and [IO.File]::Exists($temp)){[IO.File]::Delete($temp)}
            }
        }
    } finally {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
    # Windows 11 may retain an older taskbar pin identity in its own cache.
    # We intentionally do not rewrite Taskband or restart the user's Explorer.
    [pscustomobject]@{Repaired=@($repaired.ToArray());Skipped=@($skipped.ToArray());ManifestPath=$ManifestPath;TaskbarMayRequireRepin=$true}
}
function global:Restore-ShellStartupShortcuts {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ManifestPath=(Join-Path $global:ShellControlRoot 'startup-shortcuts.json'))
    $snapshot=Read-ShellTextSnapshot $ManifestPath
    if(-not $snapshot.Exists){return [pscustomobject]@{Restored=@();Skipped=@()}}
    $manifest=$snapshot.Text|ConvertFrom-Json -ErrorAction Stop
    if($manifest.Version -ne 1 -or -not $manifest.PSObject.Properties['Entries']){throw 'The startup shortcut backup manifest is invalid.'}
    $restored=New-Object 'Collections.Generic.List[string]'
    $skipped=New-Object 'Collections.Generic.List[string]'
    $entries=@($manifest.Entries)
    for($i=$entries.Count-1;$i -ge 0;$i--){
        $entry=$entries[$i]
        $current=Read-ShellShortcutSnapshot $entry.Path
        if($current.Hash -ne $entry.InstalledHash){$skipped.Add($entry.Path);continue}
        if($entry.Created){
            if($PSCmdlet.ShouldProcess($entry.Path,'Remove Shell Control shortcut override')){Write-ShellShortcutBytes -Path $entry.Path -ExpectedHash $entry.InstalledHash -Remove;$restored.Add($entry.Path)}
        }else{
            $backup=Read-ShellShortcutSnapshot $entry.BackupPath
            if(-not $backup.Exists -or $backup.Hash -ne $entry.OriginalHash){$skipped.Add($entry.Path);continue}
            if($PSCmdlet.ShouldProcess($entry.Path,'Restore original PowerShell shortcut')){Write-ShellShortcutBytes -Path $entry.Path -Bytes $backup.Bytes -ExpectedHash $entry.InstalledHash;$restored.Add($entry.Path)}
        }
    }
    [pscustomobject]@{Restored=@($restored.ToArray());Skipped=@($skipped.ToArray())}
}
