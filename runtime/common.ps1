. (Join-Path $PSScriptRoot 'safe-io.ps1')
function global:Find-ShellExecutable {
    param([string]$Name)
    $command=Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
    if($command){return $command.Source}
    $apps=Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    $aliasPath=Join-Path $apps $Name
    if(Test-Path -LiteralPath $aliasPath){return $aliasPath}
    $package=switch($Name){
        'fastfetch.exe'{'Fastfetch-cli.Fastfetch*'}
        'eza.exe'{'eza-community.eza*'}
        'gum.exe'{'charmbracelet.gum*'}
        default {$null}
    }
    if($package){
        $root=Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        foreach($folder in (Get-ChildItem -LiteralPath $root -Directory -Filter $package -ErrorAction SilentlyContinue)){
            $file=Get-ChildItem -LiteralPath $folder.FullName -File -Recurse -Filter $Name|Select-Object -First 1
            if($file){return $file.FullName}
        }
    }
}
function global:Get-ShellTerminalSettingsPath {
    if($global:ShellControlSettingsPath){return $global:ShellControlSettingsPath}
    $preferences=Get-ShellControlPreferences
    if($preferences.terminalSettingsPath){return $preferences.terminalSettingsPath}
    $paths=@()
    foreach($relative in @('Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json','Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json','Microsoft\Windows Terminal\settings.json')){
        $path=Join-Path $env:LOCALAPPDATA $relative
        if(Test-Path -LiteralPath $path){$paths+=$path}
    }
    if(-not $paths.Count){throw [IO.FileNotFoundException] 'Windows Terminal settings were not found. Install and open Windows Terminal once, then retry.'}
    # Setup outside Terminal retains the established stable/Preview/unpackaged order.
    if(-not $env:WT_PROFILE_ID){return $paths[0]}
    $matching=@();$unreadable=@()
    foreach($path in $paths){
        try {
            $settings=Read-ShellTerminalJson $path
            if(@($settings.profiles.list|Where-Object guid -eq $env:WT_PROFILE_ID).Count){$matching+=$path}
        } catch {$unreadable+=$path}
    }
    $guidance='Use Install.ps1 -TerminalSettingsPath <path> during setup, or set $global:ShellControlSettingsPath to the correct settings.json in this session.'
    if($unreadable.Count){
        throw ('Cannot safely select Windows Terminal settings because these files could not be read: '+($unreadable -join '; ')+'. '+$guidance)
    }
    if($matching.Count -eq 1){return $matching[0]}
    if($matching.Count -gt 1){throw ('The current Terminal profile appears in multiple settings files: '+($matching -join '; ')+'. '+$guidance)}
    throw ('The current Terminal profile was not found in these settings files: '+($paths -join '; ')+'. '+$guidance)
}
function global:Get-ShellControlPreferences {
    $path=Join-Path $global:ShellControlRoot 'menu-settings.json'
    if(Test-Path -LiteralPath $path){return (Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json)}
    [pscustomobject]@{language='en';promptEngine='native';fastfetch=$true}
}
function global:Set-ShellControlPreference {
    param([string]$Name,$Value)
    $path=Join-Path $global:ShellControlRoot 'menu-settings.json'
    $snapshot=Read-ShellTextSnapshot $path
    $settings=if($snapshot.Exists){$snapshot.Text|ConvertFrom-Json -ErrorAction Stop}else{[pscustomobject]@{}}
    $settings|Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    Write-ShellAtomicText -Path $path -Text ($settings|ConvertTo-Json -Depth 10) -ExpectedHash $snapshot.Hash -Json
}
function global:Update-ShellHardwareCache {
    $lan='';$wifi=''
    try {
        $adapters=Get-CimInstance Win32_NetworkAdapter -Filter 'PhysicalAdapter=True' -ErrorAction Stop
        $lan=($adapters|Where-Object {$_.AdapterTypeID -eq 0 -and $_.Name -notmatch 'Wireless|Wi-Fi|WiFi|802\.11'}|Sort-Object NetEnabled -Descending|Select-Object -First 1).Name
        $wifi=($adapters|Where-Object {$_.Name -match 'Wireless|Wi-Fi|WiFi|802\.11'}|Select-Object -First 1).Name
    } catch {}
    $wifi=([string]$wifi).Replace(' High Band Simultaneous (HBS) Network Adapter','').Replace(' Network Adapter','')
    $cache=[pscustomobject]@{Lan=$lan;Wifi=$wifi}
    Write-ShellAtomicText -Path (Join-Path $global:ShellControlRoot 'hardware-cache.json') -Text ($cache|ConvertTo-Json) -Json -SkipBackup
    $cache
}
function global:Get-ShellHardwareCache {
    $path=Join-Path $global:ShellControlRoot 'hardware-cache.json'
    if(Test-Path -LiteralPath $path){return (Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json)}
    Update-ShellHardwareCache
}
function global:Get-ShellTerminalSchemes {
    param($Settings)
    if(-not $PSBoundParameters.ContainsKey('Settings')){$Settings=Read-ShellTerminalJson (Get-ShellTerminalSettingsPath)}
    $existing=@($Settings.schemes|Where-Object {$_ -and $_.name})
    $names=@($existing|ForEach-Object name)
    $bundled=Get-Content -LiteralPath (Join-Path $global:ShellControlRoot 'assets/themes.json') -Raw -Encoding UTF8|ConvertFrom-Json
    @($existing)+@($bundled|Where-Object name -notin $names)
}
function global:Get-ShellThemeFamilies {
    $schemes=@(Get-ShellTerminalSchemes)
    $groups=[ordered]@{}
    foreach($scheme in ($schemes|Sort-Object name)){
        $name=$scheme.name
        $family=switch -Regex ($name){'^rose-pine'{'Rosé Pine';break} '^Catppuccin'{'Catppuccin';break} '^Gruvbox'{'Gruvbox';break} default{$name}}
        if(-not $groups.Contains($family)){$groups[$family]=@()}
        $groups[$family]+=$name
    }
    foreach($key in $groups.Keys){[pscustomobject]@{Name=$key;Variants=@($groups[$key])}}
}
function global:Set-ShellPromptEngine {
    param([ValidateSet('native','omp')][string]$Engine)
    if($Engine -eq 'omp' -and -not(Find-ShellExecutable oh-my-posh.exe)){throw 'Oh My Posh is not installed. Open Setup → Dependencies first.'}
    Set-ShellControlPreference promptEngine $Engine
    . (Join-Path $global:ShellControlRoot 'prompt.ps1')
    if($Engine -eq 'omp'){
        $exe=Find-ShellExecutable oh-my-posh.exe
        & $exe init pwsh --config (Join-Path $global:ShellControlRoot 'minimal.omp.json')|Out-String|Invoke-Expression
    }
}
