# Profiles load shared hosts once and let ConsoleHost initialize after other prompt setup.
& {
    $profileFixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-profiles-'+[guid]::NewGuid().ToString('N'))
    $profileDocuments=Join-Path $profileFixture 'Documents'
    $profileRuntime=Join-Path $profileFixture "runtime's scripts"
    $savedRoot=$global:ShellControlRoot
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
        foreach($version in @('PowerShell','WindowsPowerShell')){
            $folder=Join-Path $profileDocuments $version
            New-Item -ItemType Directory -Path $folder -Force|Out-Null
            $shared=Join-Path $folder 'profile.ps1'
            $hostProfile=Join-Path $folder 'Microsoft.PowerShell_profile.ps1'
            $sharedText="`$global:ToolkitLoads++`r`nfunction global:tk { 'kept' }`r`n# BEGIN SHELL CONTROL`r`n. '$entry'`r`n# END SHELL CONTROL`r`n"
            $hostText="function global:prompt { 'other-prompt' }`r`nfunction ExistingHost { 'kept' }`r`n"
            [IO.File]::WriteAllText($shared,$sharedText)
            [IO.File]::WriteAllText($hostProfile,$hostText)
            $originals[$version+'-profile.ps1']=$sharedText
            $originals[$version+'-Microsoft.PowerShell_profile.ps1']=$hostText
        }
        $firstBackup=Join-Path $profileFixture 'backup1'
        Install-ShellProfiles -DocumentsPath $profileDocuments -BackupRoot $firstBackup
        Install-ShellProfiles -DocumentsPath $profileDocuments -BackupRoot (Join-Path $profileFixture 'backup2')
        foreach($version in @('PowerShell','WindowsPowerShell')){
            foreach($name in @('profile.ps1','Microsoft.PowerShell_profile.ps1')){
                $path=Join-Path $profileDocuments ($version+'/'+$name)
                $text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
                Assert ([regex]::Matches($text,'# BEGIN SHELL CONTROL').Count -eq 1) 'Profile setup duplicated its import'
                Assert ([IO.File]::ReadAllText((Join-Path $firstBackup ($version+'-'+$name))) -eq $originals[$version+'-'+$name]) 'Profile setup did not back up the original startup code'
                if($name -eq 'profile.ps1'){
                    Assert ($text.Contains("if (`$Host.Name -ne 'ConsoleHost')")) 'ConsoleHost still initializes from the earlier shared profile'
                    Assert ($text.Contains('function global:tk')) 'Shared toolkit functions were removed'
                }else{
                    Assert ($text.Contains('function ExistingHost')) 'Host-specific startup code was removed'
                    Assert ($text.IndexOf(". '$entry'") -gt $text.IndexOf("function global:prompt")) 'Shell Control does not initialize after existing prompt setup'
                }
            }
        }
        $shared=(Join-Path $profileDocuments 'PowerShell/profile.ps1').Replace("'","''")
        $hostProfile=(Join-Path $profileDocuments 'PowerShell/Microsoft.PowerShell_profile.ps1').Replace("'","''")
        $command=". '$shared'; . '$hostProfile'; [pscustomobject]@{ToolkitLoads=`$global:ToolkitLoads;InitCount=`$global:ShellControlInitCount;Prompt=(prompt);HasTk=[bool](Get-Command tk -ErrorAction SilentlyContinue)}|ConvertTo-Json -Compress"
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $profileHost=(Get-Process -Id $PID).Path
        $output=& $profileHost -NoLogo -NoProfile -EncodedCommand $encoded|Out-String
        Assert ($LASTEXITCODE -eq 0) 'The installed profile sequence failed in a fresh shell'
        $result=$output|ConvertFrom-Json
        Assert ($result.InitCount -eq 1 -and $result.Prompt -eq 'shell-control-test-prompt') 'A later user profile replaced the prompt or initialization ran twice'
        Assert ($result.ToolkitLoads -eq 1 -and $result.HasTk) 'The existing toolkit stopped loading'

        # Removal must recognize both shared conditional blocks and host-specific direct imports.
        $foreignEntry=(Join-Path $profileFixture 'foreign/Initialize.ps1').Replace("'","''")
        $beforeRemoval=@{}
        foreach($version in @('PowerShell','WindowsPowerShell')){
            foreach($name in @('profile.ps1','Microsoft.PowerShell_profile.ps1')){
                $path=Join-Path $profileDocuments ($version+'/'+$name)
                $text=[IO.File]::ReadAllText($path)+"`r`n# BEGIN SHELL CONTROL`r`n. '$foreignEntry'`r`n# END SHELL CONTROL`r`n"
                [IO.File]::WriteAllText($path,$text)
                $beforeRemoval[$path]=(Read-ShellTextSnapshot $path).Hash
            }
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
    } finally {
        $global:ShellControlRoot=$savedRoot
        if(Test-Path -LiteralPath $profileFixture){Remove-Item -LiteralPath $profileFixture -Recurse -Force}
    }
}
Write-Host 'PASS profiles: host ordering, one initialization, preserved toolkit, backups and scoped removal'
