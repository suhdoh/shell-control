# Dependency orchestration checks use real child processes, without installing software.
& {
    $dependencyHost=(Get-Process -Id $PID).Path
    $dependencyExit=0
    $dependencyCalls=0
    function Find-ShellExecutable {param($Name) 'Invoke-TestWinget'}
    function Invoke-TestWinget {$global:LASTEXITCODE=1}
    function Start-Process {
        param($FilePath,$ArgumentList,$WindowStyle,$RedirectStandardOutput,$RedirectStandardError,[switch]$PassThru)
        $script:dependencyCalls++
        $command="Write-Output 'simulated WinGet output'; [Console]::Error.WriteLine('simulated WinGet error'); exit $script:dependencyExit"
        Microsoft.PowerShell.Management\Start-Process -FilePath $dependencyHost -ArgumentList @('-NoLogo','-NoProfile','-Command',('"'+$command+'"')) -RedirectStandardOutput $RedirectStandardOutput -RedirectStandardError $RedirectStandardError -PassThru
    }
    $savedPath=$env:PATH
    try {
        $script:dependencyExit=0
        $script:dependencyCalls=0
        Install-ShellDependencies
        Assert ($script:dependencyCalls -eq 6) 'Dependency installation stopped despite successful child processes'
        $script:dependencyExit=7
        $script:dependencyCalls=0
        $failure=$null
        try {Install-ShellDependencies}catch{$failure=$_.Exception.Message}
        Assert ($script:dependencyCalls -eq 1) 'Dependency installation continued after failure'
        Assert ($failure -like '*WinGet exit code: 7*') 'WinGet exit code was omitted'
        Assert ($failure -like '*simulated WinGet output*' -and $failure -like '*simulated WinGet error*') 'WinGet output was omitted'
        Assert ($failure -like '*.out.log*' -and $failure -like '*.err.log*') 'Dependency log paths were omitted'
    } finally {$env:PATH=$savedPath}
}
Write-Host 'PASS dependency checks: successful children, failed children and WinGet diagnostics'
