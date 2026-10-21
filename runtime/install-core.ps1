function global:Send-ShellSetupProgress {
    param([int]$Percent,[string]$Message)
    $Percent=[math]::Min(100,[math]::Max(0,$Percent))
    if($script:ShellSetupProgress){& $script:ShellSetupProgress $Percent $Message}
    else{Write-Progress -Activity 'Shell Control setup' -Status $Message -PercentComplete $Percent}
}
function global:Invoke-ShellSetupStages {
    param([Parameter(Mandatory)][Collections.IDictionary]$Stages)
    $ErrorActionPreference='Stop'
    $failures=@()
    foreach($stage in $Stages.GetEnumerator()){
        try {& $stage.Value} catch {$failures+=($stage.Key+': '+$_.Exception.Message)}
    }
    if($failures.Count){
        throw ('Setup is incomplete. Independent configuration stages were attempted; resolve these errors and rerun setup:'+ [Environment]::NewLine+($failures -join [Environment]::NewLine))
    }
}
function global:Install-ShellDependencies {
    $winget=Find-ShellExecutable winget.exe
    if(-not $winget){throw 'WinGet is missing. Install Microsoft App Installer from Microsoft Store first.'}
    $packages=@('Microsoft.WindowsTerminal','Microsoft.PowerShell','Fastfetch-cli.Fastfetch','eza-community.eza','charmbracelet.gum','JanDeDobbeleer.OhMyPosh')
    $logRoot=Join-Path $global:ShellControlRoot 'logs'
    New-Item -ItemType Directory -Path $logRoot -Force|Out-Null
    for($i=0;$i -lt $packages.Count;$i++){
        $id=$packages[$i]
        Send-ShellSetupProgress ([int](100*$i/$packages.Count)) ('Checking '+$id)
        & $winget list --id $id --exact --accept-source-agreements --disable-interactivity *> $null
        if($LASTEXITCODE -eq 0){continue}
        $out=Join-Path $logRoot ($id+'.out.log');$err=Join-Path $logRoot ($id+'.err.log')
        $process=Start-Process -FilePath $winget -ArgumentList @('install','--id',$id,'--exact','--source','winget','--silent','--accept-source-agreements','--accept-package-agreements','--disable-interactivity') -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
        # Retain the native handle before polling; Windows can otherwise lose the exit code.
        $null=$process.Handle
        while(-not $process.HasExited){Send-ShellSetupProgress ([int](100*$i/$packages.Count)) ('Installing '+$id);Start-Sleep -Milliseconds 200;$process.Refresh()}
        $process.WaitForExit()
        if($null -eq $process.ExitCode -or $process.ExitCode -ne 0){
            $details=@(foreach($log in @($out,$err)){
                if(Test-Path -LiteralPath $log){Get-Content -LiteralPath $log -Tail 12 -ErrorAction SilentlyContinue}
            }) -join [Environment]::NewLine
            $code=if($null -eq $process.ExitCode){'unavailable'}else{[string]$process.ExitCode}
            throw ('Installation failed: '+$id+' (WinGet exit code: '+$code+').'+[Environment]::NewLine+$details+[Environment]::NewLine+'Logs: '+$out+'; '+$err)
        }
    }
    # Pick up per-user and machine PATH changes for this setup session.
    $env:PATH=[Environment]::GetEnvironmentVariable('PATH','Machine')+';'+[Environment]::GetEnvironmentVariable('PATH','User')
    Send-ShellSetupProgress 100 'Dependencies ready'
}
function global:Get-ShellDownloadedArchive {
    param($Package,[string]$Cache)
    $path=Join-Path $Cache ($Package.Name+'.tar.xz')
    if(Test-Path -LiteralPath $path){if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $Package.Sha256){return $path}}
    # TLS settings are process-local; do not alter system policy.
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Package.Url -OutFile $path -UseBasicParsing -ErrorAction Stop
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Package.Sha256){throw ('Checksum failed: '+$Package.Name)}
    $path
}
function global:Save-ShellFontReceipt {
    param([Parameter(Mandatory)][object[]]$Fonts)
    $path=Join-Path $global:ShellControlRoot 'installed-fonts.json'
    $snapshot=Read-ShellTextSnapshot $path
    $existing=@()
    if($snapshot.Exists){
        $parsed=ConvertFrom-Json -InputObject $snapshot.Text -ErrorAction Stop
        if($null -ne $parsed){$existing=$parsed}
    }
    $byPath=@{}
    foreach($font in (@($existing)+@($Fonts))){
        if(-not $font.Path -or -not $font.Family){throw 'The installed font receipt contains an invalid entry.'}
        $byPath[[IO.Path]::GetFullPath([string]$font.Path)]=$font
    }
    $receipt=@($byPath.Values|Sort-Object Family,Style,Path)
    Write-ShellAtomicText -Path $path -Text (ConvertTo-Json -InputObject $receipt -Depth 5) -ExpectedHash $snapshot.Hash -Json
}
function global:Install-ShellFonts {
    param([ValidateSet('Recommended','All')][string]$Pack='Recommended')
    $manifest=Get-Content (Join-Path $global:ShellControlRoot 'assets\fonts.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $packages=@($manifest.Packages|Where-Object {$Pack -eq 'All' -or $_.Recommended})
    $cache=Join-Path $env:LOCALAPPDATA 'ShellControl\Cache\Fonts'
    New-Item -ItemType Directory -Path $cache -Force|Out-Null
    $fontsRoot=Join-Path $global:ShellControlRoot 'Fonts'
    $registry='HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    New-Item -Path $registry -Force|Out-Null
    if(-not ('ShellControlFontApi' -as [type])){
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ShellControlFontApi {
 [DllImport("gdi32.dll",CharSet=CharSet.Unicode)] public static extern int AddFontResourceEx(string path,uint flags,IntPtr reserved);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint msg,UIntPtr wp,IntPtr lp,uint flags,uint timeout,out UIntPtr result);
}
"@
    }
    for($i=0;$i -lt $packages.Count;$i++){
        $package=$packages[$i]
        Send-ShellSetupProgress ([int](100*$i/$packages.Count)) ('Fonts: '+$package.Name+' · '+($i+1)+'/'+$packages.Count)
        $folder=Join-Path $fontsRoot $package.Name
        $missing=@($package.Fonts|Where-Object {-not(Test-Path -LiteralPath (Join-Path $folder $_.File))})
        if($missing.Count){
            $archive=Get-ShellDownloadedArchive $package $cache
            $extract=Join-Path $cache ($package.Name+'-'+$manifest.Version)
            New-Item -ItemType Directory -Path $extract -Force|Out-Null
            & tar.exe -xf $archive -C $extract
            if($LASTEXITCODE -ne 0){throw ('Could not extract '+$package.Name)}
            New-Item -ItemType Directory -Path $folder -Force|Out-Null
            foreach($font in $missing){
                $file=Get-ChildItem -LiteralPath $extract -Recurse -File|Where-Object Name -eq $font.File|Select-Object -First 1
                if(-not $file){throw ('Font archive does not contain '+$font.File)}
                Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $folder $font.File)
            }
        }
        $notices=Join-Path $global:ShellControlRoot ('assets\licenses\fonts\'+$package.Name)
        Copy-Item -Path (Join-Path $notices '*') -Destination $folder -Recurse -Force -ErrorAction Stop
        foreach($font in $package.Fonts){
            $path=Join-Path $folder $font.File
            New-ItemProperty -LiteralPath $registry -Name ($font.Family+' '+$font.Style+' (TrueType)') -Value $path -PropertyType String -Force|Out-Null
            if([ShellControlFontApi]::AddFontResourceEx($path,0,[IntPtr]::Zero) -lt 1){throw ('Windows could not load '+$font.File)}
            # Persist each successful registration so a later package failure retains progress.
            Save-ShellFontReceipt -Fonts @([pscustomobject]@{Family=$font.Family;Style=$font.Style;Path=$path})
        }
    }
    $result=[UIntPtr]::Zero
    [void][ShellControlFontApi]::SendMessageTimeout([IntPtr]0xffff,0x001D,[UIntPtr]::Zero,[IntPtr]::Zero,2,200,[ref]$result)
    Send-ShellSetupProgress 100 ('Fonts ready: '+$Pack)
}
function global:Install-ShellProfiles {
    param([string]$DocumentsPath=([Environment]::GetFolderPath('MyDocuments')),[string]$BackupRoot=(Join-Path $global:ShellControlRoot ('backups\'+(Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N'))))
    New-Item -ItemType Directory -Path $BackupRoot -Force|Out-Null
    $entry=(Join-Path $global:ShellControlRoot 'Initialize.ps1').Replace("'","''")
    foreach($version in @('PowerShell','WindowsPowerShell')){
        $folder=Join-Path $DocumentsPath $version
        New-Item -ItemType Directory -Path $folder -Force|Out-Null
        foreach($name in @('profile.ps1','Microsoft.PowerShell_profile.ps1')){
            $path=Join-Path $folder $name
            $snapshot=Read-ShellTextSnapshot $path
            $text=$snapshot.Text
            if($snapshot.Exists){Copy-Item -LiteralPath $path -Destination (Join-Path $BackupRoot ($version+'-'+$name))}
            # Do not let an incomplete outer marker consume a later managed block.
            $text=[regex]::Replace($text,'(?ms)^# BEGIN SHELL CONTROL\r?\n(?:(?!^# BEGIN SHELL CONTROL\r?$).)*?^# END SHELL CONTROL\r?\n?','')
            # Migrate this installation's earlier direct imports, retaining unrelated user functions.
            $legacy=[regex]::Escape($global:ShellControlRoot.TrimEnd('\').Replace("'","''"))
            $text=[regex]::Replace($text,"(?m)^\s*\.\s+'"+$legacy+"[\\/](?:Initialize|prompt|listing|terminal-controls|system-info|shell-menu|greeting)\.ps1'\s*\r?$",'')
            $body=if($name -eq 'profile.ps1'){
                # ConsoleHost loads its host-specific profile later, after other prompt initializers.
                "if (`$Host.Name -ne 'ConsoleHost') {`r`n    . '$entry'`r`n}`r`n"
            }else{". '$entry'`r`n"}
            $block="# BEGIN SHELL CONTROL`r`n"+$body+"# END SHELL CONTROL`r`n"
            Write-ShellAtomicText -Path $path -Text ($text.TrimEnd()+"`r`n`r`n"+$block) -ExpectedHash $snapshot.Hash -Bom
        }
    }
    Send-ShellSetupProgress 100 'PowerShell 5.1, ISE and PowerShell 7 profiles ready'
}
function global:Install-ShellTerminal {
    param([switch]$PreserveProfiles,[switch]$SetDefault,[switch]$RepairStartup)
    if($RepairStartup -and $PreserveProfiles){throw '-RepairStartup cannot be combined with -PreserveProfiles.'}
    try {$path=Get-ShellTerminalSettingsPath} catch [IO.FileNotFoundException] {
        if(-not(Find-ShellExecutable wt.exe)){throw}
        $path=Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        New-Item -ItemType Directory -Path (Split-Path $path) -Force|Out-Null
        Write-ShellAtomicText -Path $path -Text '{"profiles":{"defaults":{},"list":[]},"schemes":[]}' -ExpectedHash 'MISSING' -Json
    }
    $snapshot=$null
    $settings=Read-ShellTerminalJson $path -Snapshot ([ref]$snapshot)
    $backup=Join-Path $global:ShellControlRoot ('backups\terminal-'+(Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N')+'.json')
    New-Item -ItemType Directory -Path (Split-Path $backup) -Force|Out-Null
    Copy-Item -LiteralPath $path -Destination $backup
    if(-not $settings.profiles){$settings|Add-Member profiles ([pscustomobject]@{defaults=[pscustomobject]@{};list=@()})}
    if(-not $settings.profiles.list){$settings.profiles|Add-Member -NotePropertyName list -NotePropertyValue @() -Force}
    $schemes=Get-Content (Join-Path $global:ShellControlRoot 'assets\themes.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $names=@($schemes|ForEach-Object name)
    $settings|Add-Member -NotePropertyName schemes -NotePropertyValue (@($settings.schemes|Where-Object {$_ -and $_.name -notin $names})+@($schemes)) -Force
    if(-not $PreserveProfiles){
        $entry=Join-Path $global:ShellControlRoot 'Initialize.ps1'
        $profiles=@(
            @{guid='{2947bb6d-5661-4ace-9b6d-842eab823451}';name='Shell Control · PowerShell 7';commandline=('pwsh.exe -NoLogo -NoProfile -NoExit -File "'+$entry+'"')},
            @{guid='{2947bb6d-5661-4ace-9b6d-842eab823452}';name='Shell Control · PowerShell 5';commandline=('powershell.exe -NoLogo -NoProfile -NoExit -File "'+$entry+'"')},
            @{guid='{2947bb6d-5661-4ace-9b6d-842eab823453}';name='Shell Control · CMD';commandline=('%SystemRoot%\System32\cmd.exe /d /k "'+(Join-Path $global:ShellControlRoot 'cmd-terminal.cmd')+'"')}
        )
        foreach($definition in $profiles){
            # Upgrade only our known legacy launchers; retain customized commands and appearance.
            $managed=$settings.profiles.list|Where-Object guid -eq $definition.guid|Select-Object -First 1
            if($managed){
                $legacy=switch($definition.guid){
                    '{2947bb6d-5661-4ace-9b6d-842eab823451}'{'pwsh.exe -NoLogo'}
                    '{2947bb6d-5661-4ace-9b6d-842eab823452}'{'powershell.exe -NoLogo'}
                    default {$null}
                }
                if($legacy -and ($RepairStartup -or -not $managed.commandline -or $managed.commandline -eq $legacy)){
                    $managed|Add-Member -NotePropertyName commandline -NotePropertyValue $definition.commandline -Force
                }
                continue
            }
            $profile=[pscustomobject]$definition
            $profile|Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{face='Terminess Nerd Font';size=16;cellWidth='0.54';cellHeight='1';weight='normal'})
            $profile|Add-Member colorScheme 'Amber 340'
            $profile|Add-Member useAcrylic $true
            $profile|Add-Member opacity 75
            $settings.profiles.list=@($settings.profiles.list|Where-Object guid -ne $profile.guid)+@($profile)
        }
        if($SetDefault){$settings|Add-Member -NotePropertyName defaultProfile -NotePropertyValue $profiles[0].guid -Force}
    }
    Write-ShellTerminalSettings -Path $path -Settings $settings -Snapshot $snapshot
    Send-ShellSetupProgress 100 'Terminal themes and profiles ready'
}
function global:Install-ShellCmd {
    $root=$global:ShellControlRoot
    $eza=Find-ShellExecutable eza.exe
    $batch=@('@echo off','chcp 65001 >nul','cls','set "EZA_COLORS=reset:fi=37:di=33:ex=32:ln=36:sn=35:sb=34:da=34:hd=36"','prompt $e[93m%USERNAME%$e[0m in $e[96m$p$e[0m$e[s$e[999C$e[12D$e[90m$t$e[0m$e[u$_$e[92m❯$e[0m$s')
    if($eza){
        foreach($item in @(@{n='ls';flags='--grid'},@{n='l';flags='--oneline'},@{n='la';flags='--grid --all'},@{n='ll';flags='--long --all --header --no-permissions --no-user --time-style=long-iso'})){
            $batch+=('doskey '+$item.n+'="'+$eza+'" '+$item.flags+' --icons=auto --color=auto --group-directories-first $*')
        }
    }
    $entry=Join-Path $root 'cmd-menu.ps1'
    $batch+=('doskey shell-menu=powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$entry+'"')
    Write-ShellAtomicText -Path (Join-Path $root 'cmd-terminal.cmd') -Text (($batch -join "`r`n")+"`r`n")
}
function global:Get-ShellSetupLaunchParameters {
    param([ValidateSet('Dependencies','Fonts','Profiles','Terminal')][string]$Component,
        [ValidateSet('Recommended','All')][string]$Pack='Recommended',[string]$StatusPath,[bool]$IsAdministrator,[string]$TerminalSettingsPath=$global:ShellControlSettingsPath)
    $arguments=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $global:ShellControlRoot 'SetupWorker.ps1')+'"'),'-Root',('"'+$global:ShellControlRoot+'"'),'-Component',$Component,'-Pack',$Pack,'-StatusPath',('"'+$StatusPath+'"'))
    if($TerminalSettingsPath){$arguments+=@('-TerminalSettingsPath',('"'+$TerminalSettingsPath+'"'))}
    $launch=@{FilePath=(Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe');ArgumentList=$arguments;WindowStyle='Hidden';PassThru=$true}
    if($Component -eq 'Dependencies' -and -not $IsAdministrator){$launch.Verb='RunAs'}
    $launch
}
function global:Invoke-ShellSetup {
    param([ValidateSet('Dependencies','Fonts','Profiles','Terminal','All')][string]$Component,[ValidateSet('Recommended','All')][string]$Pack='Recommended')
    if($Component -eq 'All'){
        $stages=[ordered]@{
            Dependencies={Invoke-ShellSetup -Component Dependencies -Pack $Pack}
            Fonts={Invoke-ShellSetup -Component Fonts -Pack $Pack}
            Profiles={Invoke-ShellSetup -Component Profiles -Pack $Pack}
            Terminal={Invoke-ShellSetup -Component Terminal -Pack $Pack}
        }
        Invoke-ShellSetupStages -Stages $stages
        return
    }
    $folder=Join-Path $global:ShellControlRoot ('logs\setup-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $folder -Force|Out-Null
    $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $statusPath=Join-Path $folder 'status.json'
    $params=Get-ShellSetupLaunchParameters -Component $Component -Pack $Pack -StatusPath $statusPath -IsAdministrator $admin
    Show-ShellSetupProgress 0 'Starting setup'
    $process=Start-Process @params
    $null=$process.Handle
    while(-not $process.HasExited){
        if(Test-Path -LiteralPath $statusPath){try{$status=Get-Content $statusPath -Raw -Encoding UTF8|ConvertFrom-Json;Show-ShellSetupProgress $status.Percent $status.Message}catch{}}
        Start-Sleep -Milliseconds 150;$process.Refresh()
    }
    $process.WaitForExit()
    $status=if(Test-Path -LiteralPath $statusPath){Get-Content $statusPath -Raw -Encoding UTF8|ConvertFrom-Json}else{$null}
    if($process.ExitCode -ne 0 -or -not $status -or $status.Error){throw $(if($status.Error){$status.Error}else{'Setup did not complete. See '+$folder})}
}
