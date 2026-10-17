$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
function Assert($condition,[string]$message){if(-not $condition){throw $message}}
foreach($file in (Get-ChildItem -LiteralPath $project -Recurse -File -Filter *.ps1)){
    $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$null,[ref]$errors)
    Assert (-not $errors) ('Parse failed: '+$file.Name+' '+($errors.Message -join '; '))
    $bytes=[IO.File]::ReadAllBytes($file.FullName)
    Assert ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) ('UTF-8 BOM missing: '+$file.Name)
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('shell-control-tests-'+[guid]::NewGuid().ToString('N'))
$runtime=Join-Path $fixture 'runtime'
New-Item -ItemType Directory -Path $runtime -Force|Out-Null
Copy-Item -Path (Join-Path $project 'runtime\*') -Destination $runtime -Recurse
Copy-Item -LiteralPath (Join-Path $project 'assets') -Destination (Join-Path $runtime 'assets') -Recurse
$terminal=Join-Path $fixture 'terminal.json'
@'
{
  // Existing settings must survive.
  "defaultProfile": "{00000000-0000-0000-0000-000000000001}",
  "profiles": {"defaults":{"font":{"face":"Consolas","size":12}},"list":[
    {"guid":"{00000000-0000-0000-0000-000000000001}","name":"Existing","commandline":"powershell.exe","font":{"face":"Consolas","size":12}},
  ]},
  "schemes": [],
  "exampleUrl":"https://example.test/a//b", // trailing comma with a comment
}
'@ | Set-Content -LiteralPath $terminal -Encoding UTF8
$global:ShellControlSettingsPath=$terminal
$env:SHELL_NO_GREETING='1'
. (Join-Path $runtime 'Initialize.ps1')
$settings=Read-ShellTerminalJson $terminal
Assert ($settings.exampleUrl -eq 'https://example.test/a//b') 'JSONC string/comment parsing failed'
$documents=Join-Path $fixture 'Documents'
New-Item -ItemType Directory -Path (Join-Path $documents 'PowerShell'),(Join-Path $documents 'WindowsPowerShell') -Force|Out-Null
$profilePath=Join-Path $documents 'PowerShell\profile.ps1'
"function Existing { 'kept' }"|Set-Content -LiteralPath $profilePath -Encoding UTF8
New-Item -ItemType File -Path (Join-Path $documents 'WindowsPowerShell\profile.ps1')|Out-Null
Install-ShellProfiles -DocumentsPath $documents -BackupRoot (Join-Path $fixture 'backup1')
Install-ShellProfiles -DocumentsPath $documents -BackupRoot (Join-Path $fixture 'backup2')
$profileText=Get-Content $profilePath -Raw -Encoding UTF8
Assert ($profileText.Contains('function Existing')) 'Existing profile code was lost'
Assert ([regex]::Matches($profileText,'# BEGIN SHELL CONTROL').Count -eq 1) 'Profile install is not idempotent'
Assert (Test-Path -LiteralPath (Join-Path $fixture 'backup1\PowerShell-profile.ps1')) 'Profile backup missing'
Install-ShellTerminal -SetDefault
$settings=Read-ShellTerminalJson $terminal
$managed=$settings.profiles.list|Where-Object guid -eq '{2947bb6d-5661-4ace-9b6d-842eab823451}'
$managed.font.size=19
$managed.opacity=42
[IO.File]::WriteAllText($terminal,($settings|ConvertTo-Json -Depth 60),(New-Object Text.UTF8Encoding($false)))
Install-ShellTerminal -SetDefault
$settings=Read-ShellTerminalJson $terminal
$managed=$settings.profiles.list|Where-Object guid -eq '{2947bb6d-5661-4ace-9b6d-842eab823451}'
Assert ($managed.font.size -eq 19 -and $managed.opacity -eq 42) 'Reinstall reset the customized Terminal profile'
Assert (@($settings.profiles.list).Count -eq 4) 'Terminal profiles duplicated or existing profile lost'
Assert (@($settings.schemes).Count -eq 18) 'Theme import duplicated or missing'
Assert ($settings.exampleUrl -eq 'https://example.test/a//b') 'Unrelated Terminal preference changed'
$families=@(Get-ShellThemeFamilies)
Assert (($families|Where-Object Name -eq Catppuccin).Variants.Count -eq 4) 'Catppuccin hierarchy incorrect'
Assert (($families|Where-Object Name -eq Gruvbox).Variants.Count -eq 6) 'Gruvbox hierarchy incorrect'
Assert (($families|Where-Object Name -eq 'Rosé Pine').Variants.Count -eq 3) 'Rosé Pine hierarchy incorrect'
foreach($language in @('en','de')){
    Set-ShellMenuLanguage $language
    $script:ShellMenuLanguage=$null
    Assert ((Get-ShellMenuLanguage) -eq $language) 'Language does not persist'
    foreach($query in @('font','Schrift','size','Größe','setup','Installation')){
        Assert (@(Get-ShellMenuMatches -Items @('Schriften','Schriftgröße','Installation') -Query $query).Count -gt 0) ('Bilingual search failed: '+$query)
    }
    foreach($query in @('font','Schrift','theme','CRT','commands','Befehle','language','Sprache','dependencies','Programme')){
        Assert (@(Get-ShellMenuMatches -Items @('Ansicht','Werkzeuge','Installation','Einstellungen') -Query $query).Count -gt 0) ('Nested category search failed: '+$query)
    }
    Assert (@(Get-ShellMenuOrderedItems @('← Zurück','A','B'))[-1] -eq '← Zurück') 'Back is not last'
    $refs=@(Get-CustomCommand)
    foreach($width in @(40,72,104)){
        $table=Get-ShellCommandTableLayout $refs $width
        foreach($row in $refs){Assert ((Format-ShellCommandTableRow $row $table).Length -le $width) 'Command table wraps'}
    }
}
$catalog=Get-Content (Join-Path $runtime 'font-catalog.json') -Raw -Encoding UTF8|ConvertFrom-Json
$fonts=Get-Content (Join-Path $project 'assets\fonts.json') -Raw -Encoding UTF8|ConvertFrom-Json
$available=@($fonts.Packages|ForEach-Object Fonts|ForEach-Object Family|Select-Object -Unique)
Assert (@($catalog).Count -eq 85) 'Unexpected catalog size'
foreach($font in $catalog){Assert ($font.Verified -and $font.Family -in $available) ('Font lacks verified package: '+$font.Family)}
foreach($package in $fonts.Packages){
    Assert ($package.Sha256 -match '^[a-fA-F0-9]{64}$') 'Missing SHA-256 digest'
    Assert ($package.Url.StartsWith('https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/')) 'Unpinned font download'
    foreach($font in $package.Fonts){Assert ($font.File -notmatch '[\\/]') 'Font filename is not a basename'}
    $notices=Join-Path $project ('assets\licenses\fonts\'+$package.Name)
    Assert (@(Get-ChildItem -LiteralPath $notices -Recurse -File|Where-Object Length -gt 0).Count -gt 0) ('Font notices missing: '+$package.Name)
}
# Synthetic data checks layout without probing the machine or changing its settings.
$records=@(
    [pscustomobject]@{Kind='Section';Label='Hardware';Color=32;Value='';Percent=0;Icon=''},
    [pscustomobject]@{Kind='Row';Label='Motherboard';Color=32;Value=('Example component '*8);Percent=0;Icon=''},
    [pscustomobject]@{Kind='Bar';Label='';Color=32;Value='';Percent=49;Icon=''}
)
foreach($width in @(40,74,114)){
    foreach($line in (ConvertTo-ShellSystemLines $records $width)){Assert ($line.Plain.Length -le $width) 'System information wraps'}
}
Install-ShellCmd
Assert (Test-Path -LiteralPath (Join-Path $runtime 'cmd-terminal.cmd')) 'CMD entry missing'
$textFiles=Get-ChildItem -LiteralPath $project -Recurse -File|Where-Object {$_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.Extension -in @('.ps1','.json','.jsonc','.md')}
foreach($file in $textFiles){
    $text=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    Assert ($text -notmatch '(?i)C:\\Users\\[^\\"\s]+') ('Machine-specific data: '+$file.Name)
}
Write-Progress -Activity 'Shell Control setup' -Completed
Write-Host ('PASS PowerShell '+$PSVersionTable.PSVersion+' · syntax, UTF-8, JSONC, profiles, idempotence, themes, languages, font manifest, responsive layouts and CMD')
Write-Host ('Fixture: '+$fixture)
