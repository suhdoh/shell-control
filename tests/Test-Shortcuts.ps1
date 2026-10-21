# Shortcut fixtures use real Windows Shell Link COM objects, never live launchers.
& {
    . (Join-Path (Split-Path $PSScriptRoot) 'runtime\startup-shortcuts.ps1')
    foreach($arguments in @('','  ','-NoLogo','-NoExit -NoProfile','-WorkingDirectory ~','-NoLogo -WorkingDirectory "~" -NoExit','-workingdirectory ~ -noprofile')){
        Assert (Test-ShellDefaultShortcutArguments $arguments) ('Default shortcut arguments rejected: '+$arguments)
    }
    foreach($arguments in @('-File toolkit.ps1','-Command exit','-EncodedCommand QQ==','-WorkingDirectory C:\Temp','-WorkingDirectory','-WorkingDirectory "~"; exit','-WorkingDirectory ~/scripts','-NoExitAnything','-ExecutionPolicy Bypass','-NoLogo -File x.ps1')){
        Assert (-not (Test-ShellDefaultShortcutArguments $arguments)) ('Custom shortcut arguments accepted: '+$arguments)
    }
    if($env:OS -ne 'Windows_NT'){Write-Host 'SKIP Windows COM shortcut fixtures (Windows required)';return}
    $shortcutFixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-shortcuts-'+[guid]::NewGuid().ToString('N'))
    $shell=$null
    try {
        New-Item -ItemType Directory $shortcutFixture|Out-Null
        $folders=@{}
        foreach($name in @('Programs','Desktop','Taskbar','CommonPrograms','Backups','Bin')){
            $folders[$name]=Join-Path $shortcutFixture $name
            New-Item -ItemType Directory $folders[$name]|Out-Null
        }
        foreach($name in @('pwsh.exe','powershell.exe','powershell_ise.exe','wt.exe','other.exe')){
            [IO.File]::WriteAllText((Join-Path $folders.Bin $name),'fixture executable; never launched')
        }
        $pwsh=Join-Path $folders.Bin 'pwsh.exe'
        $powershell=Join-Path $folders.Bin 'powershell.exe'
        $terminal=Join-Path $folders.Bin 'wt.exe'
        $shell=New-Object -ComObject WScript.Shell
        function New-ShortcutFixture([string]$Path,[string]$Target,[string]$Arguments=''){
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
            $link=$shell.CreateShortcut($Path)
            try {
                $link.TargetPath=$Target
                $link.Arguments=$Arguments
                $link.WorkingDirectory=$shortcutFixture
                $link.Description='Preserve fixture description'
                $link.IconLocation=$Target+',1'
                $link.WindowStyle=3
                $link.Save()
            } finally {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)}
            $Path
        }
        $normal=New-ShortcutFixture (Join-Path $folders.Programs 'PowerShell\PowerShell 7.lnk') $pwsh
        $defaultIcon=$shell.CreateShortcut($normal)
        try {$defaultIcon.IconLocation=',0';$defaultIcon.Save()}finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($defaultIcon)}
        $legacy=New-ShortcutFixture (Join-Path $folders.Desktop 'Windows PowerShell.lnk') $powershell '-NoLogo -NoExit -NoProfile'
        $pin=New-ShortcutFixture (Join-Path $folders.Taskbar 'PowerShell 7.lnk') $pwsh '-WorkingDirectory ~'
        $common=New-ShortcutFixture (Join-Path $folders.CommonPrograms 'PowerShell\PowerShell common.lnk') $pwsh '-NoLogo -WorkingDirectory "~"'
        $collisionSource=New-ShortcutFixture (Join-Path $folders.CommonPrograms 'PowerShell\Custom.lnk') $pwsh
        $collision=New-ShortcutFixture (Join-Path $folders.Programs 'PowerShell\Custom.lnk') $pwsh '-File personal.ps1'
        $script=New-ShortcutFixture (Join-Path $folders.Programs 'Run script.lnk') $pwsh '-File "toolkit.ps1"'
        $command=New-ShortcutFixture (Join-Path $folders.Desktop 'Run command.lnk') $powershell '-Command "Get-Date"'
        $encoded=New-ShortcutFixture (Join-Path $folders.Desktop 'Encoded.lnk') $pwsh '-EncodedCommand QQ=='
        $customDirectory=New-ShortcutFixture (Join-Path $folders.Programs 'Custom directory.lnk') $pwsh '-WorkingDirectory C:\Temp'
        $ise=New-ShortcutFixture (Join-Path $folders.Programs 'Windows PowerShell ISE.lnk') (Join-Path $folders.Bin 'powershell_ise.exe')
        $other=New-ShortcutFixture (Join-Path $folders.Programs 'Other.lnk') (Join-Path $folders.Bin 'other.exe')
        $admin=New-ShortcutFixture (Join-Path $folders.Programs 'PowerShell administrator.lnk') $powershell
        $adminBytes=[IO.File]::ReadAllBytes($admin)
        $adminFlags=[BitConverter]::ToUInt32($adminBytes,20) -bor 0x2000
        [Array]::Copy([BitConverter]::GetBytes([uint32]$adminFlags),0,$adminBytes,20,4)
        [IO.File]::WriteAllBytes($admin,$adminBytes)
        $originals=@{}
        foreach($path in @($normal,$legacy,$pin,$common,$collisionSource,$collision,$script,$command,$encoded,$customDirectory,$ise,$other,$admin)){
            $originals[$path]=Read-ShellShortcutSnapshot $path
        }
        $manifest=Join-Path $shortcutFixture 'startup-shortcuts.json'
        $parameters=@{UserProgramsPath=$folders.Programs;DesktopPath=$folders.Desktop;TaskbarPath=$folders.Taskbar;CommonProgramsPath=$folders.CommonPrograms;TerminalPath=$terminal;BackupRoot=$folders.Backups;ManifestPath=$manifest}
        $result=Install-ShellStartupShortcuts @parameters
        Assert (@($result.Repaired).Count -eq 4) 'Expected regular PowerShell 5/7 shortcuts and common Start Menu shadow to be repaired'
        $shadow=Join-Path $folders.Programs 'PowerShell\PowerShell common.lnk'
        foreach($pair in @(
            @{Path=$normal;Guid='{2947bb6d-5661-4ace-9b6d-842eab823451}';Icon=($pwsh+',0')},
            @{Path=$legacy;Guid='{2947bb6d-5661-4ace-9b6d-842eab823452}';Icon=($powershell+',1')},
            @{Path=$pin;Guid='{2947bb6d-5661-4ace-9b6d-842eab823451}';Icon=($pwsh+',1')},
            @{Path=$shadow;Guid='{2947bb6d-5661-4ace-9b6d-842eab823451}';Icon=($pwsh+',1')}
        )){
            $link=$shell.CreateShortcut($pair.Path)
            try {
                Assert ($link.TargetPath -eq $terminal -and $link.Arguments -eq ('-p '+$pair.Guid)) ('Shortcut does not select the clean matching Terminal profile: '+$pair.Path)
                Assert ($link.IconLocation -eq $pair.Icon) 'PowerShell shortcut icon changed'
                Assert ($link.WorkingDirectory -eq $shortcutFixture -and $link.Description -eq 'Preserve fixture description' -and $link.WindowStyle -eq 3) 'Shortcut metadata was lost'
            } finally {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)}
        }
        foreach($path in @($common,$collisionSource,$collision,$script,$command,$encoded,$customDirectory,$ise,$other,$admin)){
            Assert ((Read-ShellShortcutSnapshot $path).Hash -eq $originals[$path].Hash) ('Specialized/admin/ISE or machine shortcut changed: '+$path)
        }
        $records=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8|ConvertFrom-Json
        Assert (@($records.Entries).Count -eq 4) 'Recovery manifest did not record every shortcut'
        foreach($entry in $records.Entries){
            Assert ((Read-ShellShortcutSnapshot $entry.BackupPath).Hash -eq $originals[$entry.SourcePath].Hash) 'Shortcut backup does not contain exact original bytes'
            Assert ((Read-ShellShortcutSnapshot $entry.Path).Hash -eq $entry.InstalledHash) 'Shortcut recovery manifest has an incorrect installed hash'
        }
        $manifestHash=(Read-ShellTextSnapshot $manifest).Hash
        $again=Install-ShellStartupShortcuts @parameters
        Assert (@($again.Repaired).Count -eq 0 -and (Read-ShellTextSnapshot $manifest).Hash -eq $manifestHash) 'Shortcut repair is not idempotent'
        # A user edit after repair must survive uninstall/recovery.
        $edited=New-ShortcutFixture $pin $pwsh '-File personal-after-repair.ps1'
        $editedHash=(Read-ShellShortcutSnapshot $edited).Hash
        $preview=Restore-ShellStartupShortcuts -ManifestPath $manifest -WhatIf
        Assert (@($preview.Restored).Count -eq 0 -and [IO.File]::Exists($shadow)) 'Recovery WhatIf changed shortcuts'
        $restored=Restore-ShellStartupShortcuts -ManifestPath $manifest
        Assert (@($restored.Restored).Count -eq 3 -and @($restored.Skipped).Count -eq 1) 'Recovery did not preserve a subsequent user edit'
        foreach($path in @($normal,$legacy)){
            Assert ((Read-ShellShortcutSnapshot $path).Hash -eq $originals[$path].Hash) 'Recovery did not restore exact original shortcut bytes'
        }
        Assert (-not [IO.File]::Exists($shadow)) 'Recovery retained the common Start Menu user override'
        Assert ((Read-ShellShortcutSnapshot $pin).Hash -eq $editedHash) 'Recovery overwrote a subsequent user shortcut edit'
        $repeat=Restore-ShellStartupShortcuts -ManifestPath $manifest
        Assert (@($repeat.Restored).Count -eq 0) 'Shortcut recovery is not idempotent'
        # The binary writer rejects stale snapshots before touching a live link.
        $staleHash=$originals[$pin].Hash
        $failure=$null
        try {Write-ShellShortcutBytes -Path $pin -Bytes $originals[$pin].Bytes -ExpectedHash $staleHash}catch{$failure=$_.Exception.Message}
        Assert ($failure -like '*changed*' -and (Read-ShellShortcutSnapshot $pin).Hash -eq $editedHash) 'Concurrent shortcut edit was overwritten'
    } finally {
        if($shell){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
        if([IO.Directory]::Exists($shortcutFixture)){Remove-Item -LiteralPath $shortcutFixture -Recurse -Force}
    }
}
Write-Host 'PASS shortcut checks: ordinary PowerShell 5/7 launchers, safe arguments and Windows recovery fixtures'
