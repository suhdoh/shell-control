# ConsoleHost and ISE initialize once, after their host-specific startup code.
& {
    $profileFixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-profiles-'+[guid]::NewGuid().ToString('N'))
    $profileDocuments=Join-Path $profileFixture 'Documents'
    $profileRuntime=Join-Path $profileFixture "runtime's scripts"
    $savedRoot=$global:ShellControlRoot
    $profileEndpoints=@(
        @{Version='PowerShell';Name='profile.ps1'},
        @{Version='PowerShell';Name='Microsoft.PowerShell_profile.ps1'},
        @{Version='WindowsPowerShell';Name='profile.ps1'},
        @{Version='WindowsPowerShell';Name='Microsoft.PowerShell_profile.ps1'},
        @{Version='WindowsPowerShell';Name='Microsoft.PowerShellISE_profile.ps1'}
    )
    try {
        New-Item -ItemType Directory -Path $profileRuntime -Force|Out-Null
        @'
$global:ShellControlRoot=$PSScriptRoot
$global:ShellControlInitCount++
function global:prompt { 'shell-control-test-prompt' }
'@|Set-Content -LiteralPath (Join-Path $profileRuntime 'Initialize.ps1') -Encoding UTF8
        $global:ShellControlRoot=$profileRuntime
        $entry=(Join-Path $profileRuntime 'Initialize.ps1').Replace("'","''")
        $originals=@{}
        foreach($endpoint in $profileEndpoints){
            $folder=Join-Path $profileDocuments $endpoint.Version
            New-Item -ItemType Directory -Path $folder -Force|Out-Null
            $path=Join-Path $folder $endpoint.Name
            $text=if($endpoint.Name -eq 'profile.ps1'){
                "`$global:ToolkitLoads++`r`nfunction global:tk { 'kept' }`r`n# BEGIN SHELL CONTROL`r`n. '$entry'`r`n# END SHELL CONTROL`r`n"
            }else{"function global:prompt { 'other-prompt' }`r`nfunction ExistingHost { 'kept' }`r`n"}
            # Exercise byte-for-byte preservation for UTF-16 as well as UTF-8 profiles.
            $encoding=if($endpoint.Name -like '*ISE*'){[Text.Encoding]::Unicode}else{New-Object Text.UTF8Encoding($true)}
            [IO.File]::WriteAllText($path,$text,$encoding)
            $originals[$endpoint.Version+'-'+$endpoint.Name]=(Read-ShellTextSnapshot $path).Hash
        }
        $firstBackup=Join-Path $profileFixture 'backup1'
        Install-ShellProfiles -DocumentsPath $profileDocuments -BackupRoot $firstBackup
        Install-ShellProfiles -DocumentsPath $profileDocuments -BackupRoot (Join-Path $profileFixture 'backup2')
        foreach($endpoint in $profileEndpoints){
            $path=Join-Path $profileDocuments ($endpoint.Version+'/'+$endpoint.Name)
            $text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
            Assert ([regex]::Matches($text,'# BEGIN SHELL CONTROL').Count -eq 1) 'Profile setup duplicated its import'
            $backup=Join-Path $firstBackup ($endpoint.Version+'-'+$endpoint.Name)
            Assert ((Read-ShellTextSnapshot $backup).Hash -eq $originals[$endpoint.Version+'-'+$endpoint.Name]) 'Profile setup did not preserve original startup bytes'
            if($endpoint.Name -eq 'profile.ps1'){
                Assert ($text.Contains("`$Host.Name -ne 'ConsoleHost' -and `$Host.Name -ne 'Windows PowerShell ISE Host'")) 'A host initializes from both its shared and host-specific profile'
                Assert ($text.Contains('function global:tk')) 'Shared toolkit functions were removed without repair'
            }else{
                Assert ($text.Contains('function ExistingHost')) 'Host-specific startup code was removed without repair'
                Assert ($text.IndexOf(". '$entry'") -gt $text.IndexOf("function global:prompt")) 'Shell Control does not initialize after existing prompt setup'
            }
        }
        $profileHost=(Get-Process -Id $PID).Path
        foreach($version in @('PowerShell','WindowsPowerShell')){
            $shared=(Join-Path $profileDocuments ($version+'/profile.ps1')).Replace("'","''")
            $hostProfile=(Join-Path $profileDocuments ($version+'/Microsoft.PowerShell_profile.ps1')).Replace("'","''")
            $command=". '$shared'; . '$hostProfile'; [pscustomobject]@{ToolkitLoads=`$global:ToolkitLoads;InitCount=`$global:ShellControlInitCount;Prompt=(prompt);HasTk=[bool](Test-Path Function:tk)}|ConvertTo-Json -Compress"
            $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
            $output=& $profileHost -NoLogo -NoProfile -EncodedCommand $encoded|Out-String
            Assert ($LASTEXITCODE -eq 0) 'The installed profile sequence failed in a fresh shell'
            $result=$output|ConvertFrom-Json
            Assert ($result.InitCount -eq 1 -and $result.Prompt -eq 'shell-control-test-prompt') 'A later user profile replaced the prompt or initialization ran twice'
            Assert ($result.ToolkitLoads -eq 1 -and $result.HasTk) 'The existing toolkit stopped loading without repair'
        }

        # Removal recognizes shared conditional blocks, ConsoleHost and ISE imports.
        $foreignEntry=(Join-Path $profileFixture 'foreign/Initialize.ps1').Replace("'","''")
        $beforeRemoval=@{}
        foreach($endpoint in $profileEndpoints){
            $path=Join-Path $profileDocuments ($endpoint.Version+'/'+$endpoint.Name)
            $text=[IO.File]::ReadAllText($path)+"`r`n# BEGIN SHELL CONTROL`r`n. '$foreignEntry'`r`n# END SHELL CONTROL`r`n"
            [IO.File]::WriteAllText($path,$text)
            $beforeRemoval[$path]=(Read-ShellTextSnapshot $path).Hash
        }
        $project=Split-Path $PSScriptRoot
        & (Join-Path $project 'Uninstall.ps1') -InstallPath (Join-Path $profileFixture 'different') -DocumentsPath $profileDocuments *> $null
        foreach($path in $beforeRemoval.Keys){Assert ((Read-ShellTextSnapshot $path).Hash -eq $beforeRemoval[$path]) 'Removal changed a different installation'}
        & (Join-Path $project 'Uninstall.ps1') -InstallPath $profileRuntime -DocumentsPath $profileDocuments -WhatIf *> $null
        foreach($path in $beforeRemoval.Keys){Assert ((Read-ShellTextSnapshot $path).Hash -eq $beforeRemoval[$path]) '-WhatIf changed a startup profile'}
        & (Join-Path $project 'Uninstall.ps1') -InstallPath $profileRuntime -DocumentsPath $profileDocuments *> $null
        foreach($path in $beforeRemoval.Keys){
            $text=[IO.File]::ReadAllText($path)
            Assert (-not $text.Contains(". '$entry'")) 'Removal retained the selected runtime import'
            Assert ($text.Contains(". '$foreignEntry'")) 'Removal deleted a different runtime import'
            Assert ($text.Contains('function global:tk') -or $text.Contains('function ExistingHost')) 'Removal deleted user startup code'
        }
        $legacyDocuments=Join-Path $profileFixture 'legacy'
        $legacyProfile=Join-Path $legacyDocuments 'PowerShell/profile.ps1'
        New-Item -ItemType Directory -Path (Split-Path $legacyProfile) -Force|Out-Null
        [IO.File]::WriteAllText($legacyProfile,"function LegacyPersonal { 'kept' }`r`n# BEGIN SHELL CONTROL`r`n. '$entry'`r`n# END SHELL CONTROL`r`n")
        & (Join-Path $project 'Uninstall.ps1') -InstallPath $profileRuntime -DocumentsPath $legacyDocuments *> $null
        $legacyText=[IO.File]::ReadAllText($legacyProfile)
        Assert ($legacyText.Contains('function LegacyPersonal') -and $legacyText -notmatch '# BEGIN SHELL CONTROL') 'Removal did not migrate the legacy shared-only import'

        # An explicit repair disables all previous current-user startup code in all three hosts.
        $repairDocuments=Join-Path $profileFixture 'repair-documents'
        $repairOriginals=@{}
        foreach($endpoint in $profileEndpoints){
            $path=Join-Path $repairDocuments ($endpoint.Version+'/'+$endpoint.Name)
            New-Item -ItemType Directory -Path (Split-Path $path) -Force|Out-Null
            $old="Write-Output 'BitHawk Diagnose-Toolkit'`r`n`$global:ToolkitLoads++`r`nfunction global:tk { 'old toolkit' }`r`nfunction global:prompt { 'old prompt' }`r`n"
            [IO.File]::WriteAllText($path,$old,[Text.Encoding]::Unicode)
            $repairOriginals[$endpoint.Version+'-'+$endpoint.Name]=(Read-ShellTextSnapshot $path).Hash
        }
        $repairBackup=Join-Path $profileFixture 'repair-backup'
        Install-ShellProfiles -DocumentsPath $repairDocuments -BackupRoot $repairBackup -RepairStartup
        $repairedHashes=@{}
        foreach($endpoint in $profileEndpoints){
            $path=Join-Path $repairDocuments ($endpoint.Version+'/'+$endpoint.Name)
            $text=[IO.File]::ReadAllText($path)
            $repairedHashes[$path]=(Read-ShellTextSnapshot $path).Hash
            Assert ($text -notmatch 'BitHawk|ToolkitLoads|old prompt') 'Repair retained earlier startup code'
            Assert ((Read-ShellTextSnapshot (Join-Path $repairBackup ($endpoint.Version+'-'+$endpoint.Name))).Hash -eq $repairOriginals[$endpoint.Version+'-'+$endpoint.Name]) 'Repair did not back up the exact original startup bytes'
        }
        Install-ShellProfiles -DocumentsPath $repairDocuments -BackupRoot (Join-Path $profileFixture 'repair-backup2') -RepairStartup
        foreach($path in $repairedHashes.Keys){Assert ((Read-ShellTextSnapshot $path).Hash -eq $repairedHashes[$path]) 'Repeated repair changed an already repaired profile'}
        $blockedBackup=Join-Path $profileFixture 'blocked-backup'
        New-Item -ItemType Directory -Path $blockedBackup|Out-Null
        $existingBackup=Join-Path $blockedBackup 'WindowsPowerShell-Microsoft.PowerShellISE_profile.ps1'
        [IO.File]::WriteAllText($existingBackup,'existing backup must survive')
        $backupFailure=$null
        try {Install-ShellProfiles -DocumentsPath $repairDocuments -BackupRoot $blockedBackup -RepairStartup}catch{$backupFailure=$_}
        Assert ($null -ne $backupFailure -and [IO.File]::ReadAllText($existingBackup) -eq 'existing backup must survive') 'Repair overwrote an existing backup'
        foreach($path in $repairedHashes.Keys){Assert ((Read-ShellTextSnapshot $path).Hash -eq $repairedHashes[$path]) 'Repair modified startup before all backups succeeded'}
        foreach($version in @('PowerShell','WindowsPowerShell')){
            $shared=(Join-Path $repairDocuments ($version+'/profile.ps1')).Replace("'","''")
            $hostProfile=(Join-Path $repairDocuments ($version+'/Microsoft.PowerShell_profile.ps1')).Replace("'","''")
            $command=". '$shared'; . '$hostProfile'; [pscustomobject]@{InitCount=`$global:ShellControlInitCount;Prompt=(prompt);HasTk=[bool](Test-Path Function:tk)}|ConvertTo-Json -Compress"
            $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
            foreach($restart in @(1,2)){
                $output=& $profileHost -NoLogo -NoProfile -EncodedCommand $encoded|Out-String
                Assert ($LASTEXITCODE -eq 0 -and $output -notmatch 'BitHawk') 'Repaired startup failed after reopening the shell'
                $result=$output|ConvertFrom-Json
                Assert ($result.InitCount -eq 1 -and $result.Prompt -eq 'shell-control-test-prompt' -and -not $result.HasTk) 'Repaired startup did not retain the clean prompt after reopening'
            }
        }

        # Use the real ISE host name in an isolated runspace without launching a GUI.
        if(-not ('ShellControlTestIseHost' -as [type])){
            Add-Type -ReferencedAssemblies ([Management.Automation.Host.PSHost].Assembly.Location) -TypeDefinition @'
using System;
using System.Globalization;
using System.Management.Automation.Host;
public sealed class ShellControlTestIseHost : PSHost {
    private readonly Guid id = Guid.NewGuid();
    public override Guid InstanceId { get { return id; } }
    public override string Name { get { return "Windows PowerShell ISE Host"; } }
    public override Version Version { get { return new Version(5, 1); } }
    public override PSHostUserInterface UI { get { return null; } }
    public override CultureInfo CurrentCulture { get { return CultureInfo.InvariantCulture; } }
    public override CultureInfo CurrentUICulture { get { return CultureInfo.InvariantCulture; } }
    public override void SetShouldExit(int exitCode) { }
    public override void EnterNestedPrompt() { throw new NotSupportedException(); }
    public override void ExitNestedPrompt() { throw new NotSupportedException(); }
    public override void NotifyBeginApplication() { }
    public override void NotifyEndApplication() { }
}
'@
        }
        foreach($restart in @(1,2)){
            $iseHost=New-Object ShellControlTestIseHost
            $runspace=[Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iseHost)
            $pipeline=[Management.Automation.PowerShell]::Create()
            try {
                $runspace.Open();$pipeline.Runspace=$runspace
                $shared=(Join-Path $repairDocuments 'WindowsPowerShell/profile.ps1').Replace("'","''")
                $iseProfile=(Join-Path $repairDocuments 'WindowsPowerShell/Microsoft.PowerShellISE_profile.ps1').Replace("'","''")
                $command=". '$shared'; . '$iseProfile'; [pscustomobject]@{InitCount=`$global:ShellControlInitCount;Prompt=(prompt);HasTk=[bool](Test-Path Function:tk)}|ConvertTo-Json -Compress"
                $null=$pipeline.AddScript($command)
                $output=$pipeline.Invoke()
                Assert (-not $pipeline.HadErrors) ('ISE profile loading failed: '+($pipeline.Streams.Error|Out-String))
                Assert ($output.Count -eq 1) 'ISE startup printed an old banner'
                $result=[string]$output[0]|ConvertFrom-Json
                Assert ($result.InitCount -eq 1 -and $result.Prompt -eq 'shell-control-test-prompt' -and -not $result.HasTk) 'ISE did not retain clean startup after reopening'
            }finally{$pipeline.Dispose();$runspace.Dispose()}
        }
    } finally {
        $global:ShellControlRoot=$savedRoot
        if(Test-Path -LiteralPath $profileFixture){Remove-Item -LiteralPath $profileFixture -Recurse -Force}
    }
}
Write-Host 'PASS profiles: PS5/PS7/ISE ordering, clean repaired restarts, exact backups and scoped removal'
