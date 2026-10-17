function global:Get-ShellBytesHash {
    param([byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {[BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','')}finally{$sha.Dispose()}
}
function global:Read-ShellTextSnapshot {
    param([Parameter(Mandatory)][string]$Path)
    $full=[IO.Path]::GetFullPath($Path)
    if(-not [IO.File]::Exists($full)){return [pscustomobject]@{Path=$full;Text='';Hash='MISSING';Exists=$false}}
    $bytes=[IO.File]::ReadAllBytes($full)
    $stream=New-Object IO.MemoryStream(,$bytes)
    $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true)
    try {$text=$reader.ReadToEnd()}finally{$reader.Dispose();$stream.Dispose()}
    [pscustomobject]@{Path=$full;Text=$text;Hash=(Get-ShellBytesHash $bytes);Exists=$true}
}
function global:Write-ShellAtomicText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[AllowEmptyString()][string]$Text,
        [string]$ExpectedHash,[switch]$Bom,[switch]$SkipBackup,[switch]$Json)
    if($Json){$null=ConvertFrom-Json -InputObject $Text -ErrorAction Stop}
    $full=[IO.Path]::GetFullPath($Path)
    $parent=[IO.Path]::GetDirectoryName($full)
    if(-not [IO.Directory]::Exists($parent)){throw ('Destination directory does not exist: '+$parent)}
    $key=Get-ShellBytesHash ([Text.Encoding]::UTF8.GetBytes($full.ToUpperInvariant()))
    $mutex=New-Object Threading.Mutex($false,('Local\ShellControlWrite-'+$key))
    $held=$false;$temp=$null
    try {
        try {$held=$mutex.WaitOne(5000)}catch [Threading.AbandonedMutexException]{$held=$true}
        if(-not $held){throw 'Another Shell Control process is saving this file. Retry shortly.'}
        $current=Read-ShellTextSnapshot $full
        if($PSBoundParameters.ContainsKey('ExpectedHash') -and $current.Hash -ne $ExpectedHash){throw ('The file changed since it was read; no changes were saved. Reload and retry: '+$full)}
        $temp=Join-Path $parent ('.'+[IO.Path]::GetFileName($full)+'.'+[guid]::NewGuid().ToString('N')+'.tmp')
        $encoding=New-Object Text.UTF8Encoding([bool]$Bom)
        $stream=New-Object IO.FileStream($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {
            $preamble=$encoding.GetPreamble();$bytes=$encoding.GetBytes($Text)
            $stream.Write($preamble,0,$preamble.Length);$stream.Write($bytes,0,$bytes.Length)
            $stream.Flush($true)
        } finally {$stream.Dispose()}
        if($current.Exists){
            # A sibling backup keeps File.Replace's source, destination and backup on one volume.
            $backup=[NullString]::Value
            if(-not $SkipBackup){
                $folder=Join-Path $parent '.shell-control-backups'
                [void][IO.Directory]::CreateDirectory($folder)
                $backup=Join-Path $folder ([IO.Path]::GetFileName($full)+'.'+(Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N')+'.bak')
            }
            # Recheck after preparing the replacement, before touching the destination.
            if((Read-ShellTextSnapshot $full).Hash -ne $current.Hash){throw ('The file changed during saving; reload and retry: '+$full)}
            [IO.File]::Replace($temp,$full,$backup,$false)
        } else {[IO.File]::Move($temp,$full)}
        $temp=$null
    } finally {
        if($temp -and [IO.File]::Exists($temp)){[IO.File]::Delete($temp)}
        if($held){$mutex.ReleaseMutex()}
        $mutex.Dispose()
    }
}
function global:Read-ShellTerminalJson {
    param([string]$Path,[ref]$Snapshot)
    $state=Read-ShellTextSnapshot $Path
    if(-not $state.Exists){throw ('Terminal settings were not found: '+$Path)}
    if($Snapshot){$Snapshot.Value=$state}
    $pattern='"(?:\\.|[^"\\])*"|(?<comment>//[^\r\n]*|/\*[\s\S]*?\*/)'
    $clean=[regex]::Replace($state.Text,$pattern,{param($m) if($m.Groups['comment'].Success){''}else{$m.Value}})
    $clean=[regex]::Replace($clean,'"(?:\\.|[^"\\])*"|(?<comma>,)(?=\s*[}\]])',{param($m) if($m.Groups['comma'].Success){''}else{$m.Value}})
    $clean|ConvertFrom-Json -ErrorAction Stop
}
function global:Write-ShellTerminalSettings {
    param([string]$Path,$Settings,[Parameter(Mandatory)]$Snapshot)
    if([IO.Path]::GetFullPath($Path) -ne $Snapshot.Path){throw 'Settings snapshot does not match the destination.'}
    Write-ShellAtomicText -Path $Path -Text ($Settings|ConvertTo-Json -Depth 60) -ExpectedHash $Snapshot.Hash -Json
}
function global:Assert-ShellInstallTarget {
    param([Parameter(Mandatory)][string]$Path,[string]$SourceRoot)
    if(-not [IO.Path]::IsPathRooted($Path) -or $Path -notmatch '^[A-Za-z]:\\'){throw 'Choose an absolute local drive path for the installation.'}
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if($full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\')){throw 'A drive root cannot be used as the installation directory.'}
    foreach($segment in ($full.Substring(3) -split '\\')){
        if($segment -match '[ .]$|[:*?"<>|]' -or $segment -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw 'The installation path contains an ambiguous or reserved Windows filename.'}
    }
    foreach($protected in @($env:WINDIR,$env:ProgramFiles,${env:ProgramFiles(x86)},$env:ProgramData)){
        if($protected -and ($full -eq $protected.TrimEnd('\') -or $full.StartsWith($protected.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase))){throw 'Choose a dedicated user-owned directory outside Windows and system program directories.'}
    }
    foreach($container in @($env:USERPROFILE,$env:LOCALAPPDATA,$env:APPDATA,[Environment]::GetFolderPath('MyDocuments'),[Environment]::GetFolderPath('Desktop'))){
        if($container -and $full -eq $container.TrimEnd('\')){throw 'Choose a dedicated subdirectory, not a user or application-data root.'}
    }
    if($SourceRoot){
        $source=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
        if($full -eq $source -or $full.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase) -or $source.StartsWith($full+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'The installation directory must not overlap the source checkout.'}
    }
    $ancestor=$full
    while($ancestor){
        if(Test-Path -LiteralPath $ancestor){
            $item=Get-Item -LiteralPath $ancestor -Force
            if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Installation through a file, junction or symbolic link is not supported.'}
        }
        $ancestor=[IO.Path]::GetDirectoryName($ancestor)
    }
    if([IO.Directory]::Exists($full) -and @(Get-ChildItem -LiteralPath $full -Force).Count){
        $owned=$false
        $marker=Join-Path $full '.shell-control-root'
        if([IO.File]::Exists($marker)){$owned=([IO.File]::ReadAllText($marker).Trim() -eq 'ShellControl')}
        $receipt=Join-Path $full 'installation.json'
        if(-not $owned -and [IO.File]::Exists($receipt)){
            try {
                $old=Get-Content -LiteralPath $receipt -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
                $owned=($old.Root -eq $full -and [IO.File]::Exists((Join-Path $full 'Initialize.ps1')) -and [IO.File]::Exists((Join-Path $full 'shell-menu.ps1')))
            }catch{}
        }
        if(-not $owned){throw 'The destination is not empty and is not a recognized Shell Control installation. Choose a new directory.'}
    }
    $full
}
