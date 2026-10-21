# ISE settings use real persistence and host option assignments without opening a GUI in CI.
& {
    $iseFixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-ise-'+[guid]::NewGuid().ToString('N'))
    $savedRoot=$global:ShellControlRoot
    $savedIseVariable=Get-Variable -Name psISE -Scope Global -ErrorAction SilentlyContinue
    $savedIseValue=if($null -ne $savedIseVariable){$savedIseVariable.Value}else{$null}
    try {
        $project=Split-Path $PSScriptRoot
        New-Item -ItemType Directory -Path $iseFixture -Force|Out-Null
        Copy-Item -Path (Join-Path $project 'runtime/*') -Destination $iseFixture -Recurse
        Copy-Item -LiteralPath (Join-Path $project 'assets') -Destination (Join-Path $iseFixture 'assets') -Recurse
        $global:ShellControlRoot=$iseFixture
        . (Join-Path $iseFixture 'common.ps1')
        . (Join-Path $iseFixture 'ise.ps1')
        . (Join-Path $iseFixture 'terminal-controls.ps1')
        . (Join-Path $iseFixture 'shell-menu.ps1')
        # psISE.Options is a host API. The fixture exposes those documented properties.
        $global:psISE=[pscustomobject]@{Options=[pscustomobject]@{
            FontName='Consolas';FontSize=12
            ConsolePaneBackgroundColor='#012456';ConsolePaneTextBackgroundColor='#012456';ConsolePaneForegroundColor='#FFFFFF'
        }}
        function Get-ShellFontChoices {
            [pscustomobject]@{Shortcut='fixture-ise';Family='Fixture ISE Mono'}
            [pscustomobject]@{Shortcut='term';Family='Terminess Nerd Font'}
        }
        $iseSchemes=@(Get-ShellIseSchemes)
        Assert ($iseSchemes.Count -eq 18) 'ISE theme catalog did not enumerate all 18 schemes'
        foreach($iseScheme in $iseSchemes){
            Assert ($iseScheme -isnot [array] -and $iseScheme.name -is [string] -and -not [string]::IsNullOrWhiteSpace($iseScheme.name)) 'ISE theme catalog emitted an array instead of an individual named scheme'
        }
        Assert (@(Set-ShellIseTheme list).Count -eq 18) 'ISE theme list did not expose every scheme'
        Assert (Test-ShellIse) 'ISE host was not recognized'
        Initialize-ShellIse
        Assert ($global:psISE.Options.FontName -eq 'Terminess Nerd Font' -and $global:psISE.Options.FontSize -eq 16) 'ISE did not apply the installed default font and size'
        Set-ShellControlPreference language de
        Set-TerminalFont fixture-ise -Size 14 6>$null
        Set-TerminalFontSize 19 6>$null
        Set-TerminalTheme rose 6>$null
        $appearance=Get-ShellTerminalAppearance
        Assert ($appearance.ProfileId -eq 'ISE' -and $appearance.Font -eq 'Fixture ISE Mono' -and $appearance.Size -eq 19 -and $appearance.Theme -eq 'rose-pine') 'ISE font/theme commands did not route to host options'
        $scheme=Get-ShellIseSchemes|Where-Object name -eq 'rose-pine'
        Assert ($global:psISE.Options.ConsolePaneBackgroundColor -eq $scheme.background -and $global:psISE.Options.ConsolePaneTextBackgroundColor -eq $scheme.background -and $global:psISE.Options.ConsolePaneForegroundColor -eq $scheme.foreground) 'ISE theme did not apply the saved palette'
        $prefs=Get-ShellControlPreferences
        Assert ($prefs.iseFont -eq 'Fixture ISE Mono' -and $prefs.iseFontSize -eq 19 -and $prefs.iseTheme -eq 'rose-pine' -and $prefs.language -eq 'de') 'ISE setters lost settings or unrelated preferences'
        $crtRejected=$false
        try{Set-TerminalCrt on 6>$null}catch{$crtRejected=$_.Exception.Message -match 'ISE'}
        Assert $crtRejected 'ISE incorrectly claimed CRT support'
        $badFontRejected=$false
        try{Set-TerminalFont 'Uninstalled fixture font' 6>$null}catch{$badFontRejected=$true}
        Assert $badFontRejected 'ISE accepted an uninstalled font'
        $common=(Join-Path $iseFixture 'common.ps1').Replace("'","''")
        $ise=(Join-Path $iseFixture 'ise.ps1').Replace("'","''")
        $fixtureRoot=$iseFixture.Replace("'","''")
        $command=@"
`$ErrorActionPreference='Stop'
`$global:ShellControlRoot='$fixtureRoot'
. '$common'
. '$ise'
`$global:psISE=[pscustomobject]@{Options=[pscustomobject]@{FontName='Consolas';FontSize=12;ConsolePaneBackgroundColor='old';ConsolePaneTextBackgroundColor='old';ConsolePaneForegroundColor='old'}}
Initialize-ShellIse
[pscustomobject]@{Appearance=(Get-ShellIseAppearance);Options=`$global:psISE.Options;Preferences=(Get-ShellControlPreferences)}|ConvertTo-Json -Depth 10 -Compress
"@
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $output=& (Get-Process -Id $PID).Path -NoLogo -NoProfile -EncodedCommand $encoded|Out-String
        Assert ($LASTEXITCODE -eq 0) 'Fresh ISE preference initialization failed'
        $fresh=$output|ConvertFrom-Json
        Assert ($fresh.Appearance.Font -eq 'Fixture ISE Mono' -and $fresh.Appearance.Size -eq 19 -and $fresh.Appearance.Theme -eq 'rose-pine') 'ISE appearance did not survive a new process'
        Assert ($fresh.Options.ConsolePaneBackgroundColor -eq $scheme.background -and $fresh.Options.ConsolePaneForegroundColor -eq $scheme.foreground) 'Fresh ISE startup did not restore theme colors'
        Assert ($fresh.Preferences.language -eq 'de') 'Fresh ISE startup lost shared language settings'

        # The real prompt must return its full text to ISE, whose host is not a terminal.
        Assert ([bool]('ShellControlTestIseHost' -as [type])) 'ISE startup test host is missing'
        $runspace=[Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace((New-Object ShellControlTestIseHost))
        $pipeline=[Management.Automation.PowerShell]::Create()
        try {
            $runspace.Open();$pipeline.Runspace=$runspace
            $promptPath=(Join-Path $iseFixture 'prompt.ps1').Replace("'","''")
            $homePath=([Environment]::GetFolderPath('UserProfile')).Replace("'","''")
            $null=$pipeline.AddScript(". '$promptPath'; Set-Location -LiteralPath '$homePath'; prompt")
            $promptOutput=$pipeline.Invoke()
            Assert (-not $pipeline.HadErrors) ('ISE prompt failed: '+($pipeline.Streams.Error|Out-String))
            $expected='\A'+[regex]::Escape([Environment]::UserName)+' in ~  \d{2}:\d{2}:\d{2}\n'+[char]0x276F+' \z'
            Assert ($promptOutput.Count -eq 1 -and [string]$promptOutput[0] -match $expected) 'ISE did not receive the exact two-line prompt'
        }finally{$pipeline.Dispose();$runspace.Dispose()}

        if($env:OS -eq 'Windows_NT'){
            # Instantiate the actual WPF controls in STA, without showing a window or touching the desktop.
            $wpfCommand=@"
`$ErrorActionPreference='Stop'
. '$ise'
`$window=New-ShellIseMenuWindow
`$global:psISE=[pscustomobject]@{Options=[pscustomobject]@{ConsolePaneBackgroundColor=[Windows.Media.Colors]::Black;ConsolePaneForegroundColor=[Windows.Media.Colors]::White}}
Apply-ShellIseTheme ([pscustomobject]@{background='#123456';foreground='#ABCDEF'})
if(`$global:psISE.Options.ConsolePaneBackgroundColor.ToString() -ne '#FF123456' -or `$global:psISE.Options.ConsolePaneForegroundColor.ToString() -ne '#FFABCDEF'){throw 'ISE WPF Color conversion failed'}
`$names=@('Theme','Font','Size','Language','Fastfetch','Status','Save','Close')
foreach(`$name in `$names){if(`$null -eq `$window.FindName(`$name)){throw ('Missing ISE control: '+`$name)}}
[pscustomobject]@{WindowType=`$window.GetType().FullName;ControlCount=`$names.Count;Visible=`$window.IsVisible}|ConvertTo-Json -Compress
`$window.Close()
"@
            $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wpfCommand))
            $output=& (Get-Process -Id $PID).Path -NoLogo -NoProfile -STA -EncodedCommand $encoded|Out-String
            Assert ($LASTEXITCODE -eq 0) 'ISE settings dialog failed to build in WPF'
            $dialog=$output|ConvertFrom-Json
            Assert ($dialog.WindowType -eq 'System.Windows.Window' -and $dialog.ControlCount -eq 8 -and -not $dialog.Visible) 'ISE settings controls did not initialize without displaying a window'
        }
    } finally {
        $global:ShellControlRoot=$savedRoot
        if($null -ne $savedIseVariable){$global:psISE=$savedIseValue}else{Remove-Variable -Name psISE -Scope Global -ErrorAction SilentlyContinue}
        if(Test-Path -LiteralPath $iseFixture){Remove-Item -LiteralPath $iseFixture -Recurse -Force}
    }
}
Write-Host 'PASS ISE: appearance routing, installed fonts, palette, fresh-process persistence and CRT limitation'
