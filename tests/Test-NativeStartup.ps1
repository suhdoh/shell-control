# Exercise the real interactive startup contract without loading external profiles.
& {
    $nativeFixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-native-startup-'+[guid]::NewGuid().ToString('N'))
    $nativeRuntime=Join-Path $nativeFixture "runtime's startup"
    try {
        $project=Split-Path $PSScriptRoot
        New-Item -ItemType Directory -Path $nativeRuntime -Force|Out-Null
        Copy-Item -Path (Join-Path $project 'runtime/*') -Destination $nativeRuntime -Recurse
        Copy-Item -LiteralPath (Join-Path $project 'assets') -Destination (Join-Path $nativeRuntime 'assets') -Recurse
        @{language='en';promptEngine='native';fastfetch=$true}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $nativeRuntime 'menu-settings.json') -Encoding UTF8
        $inputFile=Join-Path $nativeFixture 'input.txt'
        [IO.File]::WriteAllText($inputFile,"exit 0`r`n",(New-Object Text.UTF8Encoding($false)))
        $stdout=Join-Path $nativeFixture 'startup.out.log'
        $stderr=Join-Path $nativeFixture 'startup.err.log'
        $entry=Join-Path $nativeRuntime 'Initialize.ps1'
        $hostPath=(Get-Process -Id $PID).Path
        $arguments=@('-NoLogo','-NoProfile','-NoExit','-File',('"'+$entry+'"'))
        $savedGreeting=$env:SHELL_NO_GREETING
        try {
            # Redirected input cannot exercise the interactive Fastfetch renderer.
            # Suppress that greeting only for this child, while keeping its saved preference enabled.
            $env:SHELL_NO_GREETING='1'
            $child=Microsoft.PowerShell.Management\Start-Process -FilePath $hostPath -ArgumentList $arguments -WorkingDirectory ([Environment]::GetFolderPath('UserProfile')) -RedirectStandardInput $inputFile -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
            $null=$child.Handle
        } finally {$env:SHELL_NO_GREETING=$savedGreeting}
        if(-not $child.WaitForExit(30000)){
            $child.Kill()
            throw 'The clean startup process did not consume its exit command'
        }
        $child.WaitForExit()
        $output=[IO.File]::ReadAllText($stdout)
        $errors=[IO.File]::ReadAllText($stderr)
        Assert ($child.ExitCode -eq 0) ('The clean startup process failed: '+$output+[Environment]::NewLine+$errors)
        Assert ([string]::IsNullOrWhiteSpace($errors)) ('The clean startup process emitted errors: '+$errors)
        $plain=[regex]::Replace($output,'\x1b\[[0-?]*[ -/]*[@-~]','').Replace("`r`n","`n")
        $expected='^'+[regex]::Escape([Environment]::UserName)+' in ~  \d{2}:\d{2}:\d{2}\n'+[regex]::Escape([string][char]0x276F)+' (?:exit 0\n?)?$'
        Assert ($plain -match $expected) ('Clean startup did not render only the native two-line prompt: '+$plain)
        Assert ($plain -notmatch 'BitHawk|Loading personal and system profiles|PowerShell [0-9]') 'Clean startup leaked a foreign banner or profile-load message'
    } finally {
        if(Test-Path -LiteralPath $nativeFixture){Remove-Item -LiteralPath $nativeFixture -Recurse -Force}
    }
}
Write-Host 'PASS native startup: real clean host, exact two-line prompt and no startup banners'
