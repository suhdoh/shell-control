# Windows Terminal profile controls shared by PowerShell 5.1 and 7.
function global:Get-ShellAppearanceProfiles {
    param([Parameter(Mandatory)]$Settings,[string]$ProfileId=$env:WT_PROFILE_ID)
    # A repaired ordinary entry and its Shell Control entry launch the same shell.
    # Keep their appearance choices together when users switch between those launch routes.
    $ids=@($ProfileId)
    switch($ProfileId){
        '{2947bb6d-5661-4ace-9b6d-842eab823451}'{$ids+='{574e775e-4f2a-5b96-ac1e-a2962a402336}'}
        '{574e775e-4f2a-5b96-ac1e-a2962a402336}'{$ids+='{2947bb6d-5661-4ace-9b6d-842eab823451}'}
        '{2947bb6d-5661-4ace-9b6d-842eab823452}'{$ids+='{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'}
        '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'{$ids+='{2947bb6d-5661-4ace-9b6d-842eab823452}'}
    }
    foreach($id in $ids){
        $Settings.profiles.list|Where-Object guid -eq $id|Select-Object -First 1
    }
}
function global:Get-ShellTerminalAppearance {
    if(Test-ShellIse){return (Get-ShellIseAppearance)}
    if (-not $env:WT_PROFILE_ID) { throw 'Kein Windows-Terminal-Tab aktiv. Starte das Profil Shell Control in Windows Terminal, um Themes, Fonts und CRT zu verwenden.' }
    $settingsPath = (Get-ShellTerminalSettingsPath)
    $settings = Read-ShellTerminalJson $settingsPath
    $profileId = $env:WT_PROFILE_ID
    $profile = $settings.profiles.list | Where-Object guid -eq $profileId | Select-Object -First 1
    if (-not $profile) { throw 'Das aktuelle Terminal-Profil wurde nicht gefunden.' }
    $face = $settings.profiles.defaults.font.face
    $size = $settings.profiles.defaults.font.size
    if ($profile.font.face) { $face = $profile.font.face }
    if ($profile.font.size) { $size = $profile.font.size }
    $crt = [bool]$settings.profiles.defaults.'experimental.retroTerminalEffect'
    if ($profile.PSObject.Properties['experimental.retroTerminalEffect']) {
        $crt = [bool]$profile.'experimental.retroTerminalEffect'
    }
    $shader=$settings.profiles.defaults.'experimental.pixelShaderPath'
    if ($profile.PSObject.Properties['experimental.pixelShaderPath']) {
        $shader=$profile.'experimental.pixelShaderPath'
    }
    $theme=if($profile.colorScheme){$profile.colorScheme}else{$settings.profiles.defaults.colorScheme}
    [pscustomobject]@{ ProfileId=$profile.guid; ProfileName=$profile.name; Font=$face; Size=$size; CRT=($crt -and -not $shader); CRTConfigured=$crt; ShaderPath=$shader; Theme=$theme }
}
function global:Set-TerminalCrt {
    [CmdletBinding()]
    param([Parameter(Position=0)][ValidateSet('on','off','toggle','status')][string]$Mode='status', [switch]$Reload)
    if(Test-ShellIse){
        if($Mode -in @('status','off')){Write-Host 'CRT: nicht verfügbar in PowerShell ISE (Windows Terminal erforderlich).';return}
        throw 'PowerShell ISE unterstützt keinen CRT-Effekt. CRT erfordert Windows Terminal.'
    }
    if (-not $env:WT_PROFILE_ID) { throw 'Bitte crt in einem Windows-Terminal-Tab ausfuehren.' }
    $appearance = Get-ShellTerminalAppearance
    if ($Mode -ne 'status') {
        $settingsPath = (Get-ShellTerminalSettingsPath)
        $snapshot=$null
        $settings = Read-ShellTerminalJson $settingsPath -Snapshot ([ref]$snapshot)
        $profiles = @(Get-ShellAppearanceProfiles -Settings $settings -ProfileId $appearance.ProfileId)
        $enabled = if ($Mode -eq 'toggle') { -not $appearance.CRT } else { $Mode -eq 'on' }
        foreach($profile in $profiles){
            $shader=$settings.profiles.defaults.'experimental.pixelShaderPath'
            if($profile.PSObject.Properties['experimental.pixelShaderPath']){$shader=$profile.'experimental.pixelShaderPath'}
            if ($enabled -and $shader) {
                throw ('CRT kann nicht aktiviert werden: Ein benutzerdefinierter Pixelshader ist im Profil '+$profile.name+' aktiv und hat in Windows Terminal Vorrang. Deaktiviere ihn zuerst in den Terminal-Einstellungen.')
            }
        }
        foreach($profile in $profiles){
            $profile | Add-Member -NotePropertyName 'experimental.retroTerminalEffect' -NotePropertyValue ([bool]$enabled) -Force
        }
        Write-ShellTerminalSettings -Path $settingsPath -Settings $settings -Snapshot $snapshot
        $appearance = Get-ShellTerminalAppearance
    }
    $state = if ($appearance.CRT) { 'Ein' } else { 'Aus' }
    Write-Host ('CRT: {0} · {1}' -f $state, $appearance.ProfileName)
    if ($Reload) { Open-FreshTerminalTab }
}
function global:Enable-TerminalCrt { Set-TerminalCrt on @args }
function global:Disable-TerminalCrt { Set-TerminalCrt off @args }
function global:Open-FreshTerminalTab {
    if (-not $env:WT_PROFILE_ID) { throw 'Bitte treload in einem Windows-Terminal-Tab ausfuehren.' }
    $appearance = Get-ShellTerminalAppearance
    $folder = [Environment]::GetFolderPath('UserProfile')
    if ($PWD.Provider.Name -eq 'FileSystem') { $folder = $PWD.Path }
    & (Find-ShellExecutable wt.exe) -w 0 new-tab -p $appearance.ProfileId -d $folder
}
Set-Alias -Name crt -Value Set-TerminalCrt -Scope Global
Set-Alias -Name crton -Value Enable-TerminalCrt -Scope Global
Set-Alias -Name crtoff -Value Disable-TerminalCrt -Scope Global
Set-Alias -Name treload -Value Open-FreshTerminalTab -Scope Global

function global:Set-TerminalTheme {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][string]$Name='status',
        [switch]$Reload
    )
    if(Test-ShellIse){Set-ShellIseTheme -Name $Name;return}
    $settingsPath = (Get-ShellTerminalSettingsPath)
    $snapshot=$null
    $settings = Read-ShellTerminalJson $settingsPath -Snapshot ([ref]$snapshot)
    if ($Name -in @('list','ls')) {
        Get-ShellTerminalSchemes -Settings $settings | Sort-Object name | Select-Object -ExpandProperty name
        return
    }
    if (-not $env:WT_PROFILE_ID) { throw 'Bitte theme in einem Windows-Terminal-Tab ausfuehren.' }
    $profile = $settings.profiles.list | Where-Object guid -eq $env:WT_PROFILE_ID | Select-Object -First 1
    if (-not $profile) { throw 'Das aktuelle Terminal-Profil wurde nicht gefunden.' }
    $active = if ($profile.colorScheme) { $profile.colorScheme } else { $settings.profiles.defaults.colorScheme }
    if ($Name -eq 'status') {
        Write-Host ('Theme: {0} · {1}' -f $active, $profile.name)
        return
    }
    $target = switch ($Name.ToLowerInvariant()) {
        'amber' { 'Amber 340' }
        'jade' { 'Osaka Jade' }
        'matrix' { 'Matrix' }
        'green' { 'Matrix' }
        'red' { 'Dark Crimson' }
        'crimson' { 'Dark Crimson' }
        'pink' { 'SynthWave 84' }
        'synthwave' { 'SynthWave 84' }
        'rose' { 'rose-pine' }
        'rosepine' { 'rose-pine' }
        'moon' { 'rose-pine-moon' }
        'dawn' { 'rose-pine-dawn' }
        'latte' { 'Catppuccin Latte' }
        'frappe' { 'Catppuccin Frappe' }
        'macchiato' { 'Catppuccin Macchiato' }
        'mocha' { 'Catppuccin Mocha' }
        'catppuccin' { 'Catppuccin Mocha' }
        'gruvbox' { 'Gruvbox Dark Medium' }
        'gruvbox-dark' { 'Gruvbox Dark Medium' }
        'gruvbox-dark-hard' { 'Gruvbox Dark Hard' }
        'gruvbox-dark-medium' { 'Gruvbox Dark Medium' }
        'gruvbox-dark-soft' { 'Gruvbox Dark Soft' }
        'gruvbox-light' { 'Gruvbox Light Medium' }
        'gruvbox-light-hard' { 'Gruvbox Light Hard' }
        'gruvbox-light-medium' { 'Gruvbox Light Medium' }
        'gruvbox-light-soft' { 'Gruvbox Light Soft' }
        default { $Name }
    }
    $scheme = Get-ShellTerminalSchemes -Settings $settings | Where-Object name -eq $target | Select-Object -First 1
    if (-not $scheme) { throw ('Theme nicht gefunden: {0}. Verfuegbare Themes: theme list' -f $target) }
    if (-not @($settings.schemes|Where-Object name -eq $scheme.name).Count) {
        $settings | Add-Member -NotePropertyName schemes -NotePropertyValue (@($settings.schemes|Where-Object {$_})+@($scheme)) -Force
    }
    foreach($appearanceProfile in (Get-ShellAppearanceProfiles -Settings $settings)){
        $appearanceProfile | Add-Member -NotePropertyName colorScheme -NotePropertyValue $scheme.name -Force
        if ($scheme.cursorColor) {
            $appearanceProfile | Add-Member -NotePropertyName cursorColor -NotePropertyValue $scheme.cursorColor -Force
        }
    }
    Write-ShellTerminalSettings -Path $settingsPath -Settings $settings -Snapshot $snapshot
    Write-Host ('Theme: {0} · {1}' -f $scheme.name, $profile.name)
    if ($Reload) { Open-FreshTerminalTab }
}
Set-Alias -Name theme -Value Set-TerminalTheme -Scope Global

function global:Set-TerminalFont {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][string]$Name='status',
        [ValidateRange(6,72)][double]$Size,
        [switch]$Reload
    )
    if(Test-ShellIse){
        $iseParameters=@{Name=$Name}
        if($PSBoundParameters.ContainsKey('Size')){$iseParameters.Size=$Size}
        Set-ShellIseFont @iseParameters
        return
    }
    $catalog = @(Get-ShellFontChoices)
    if ($Name -in @('list','ls')) {
        $catalog | Sort-Object Family | Select-Object @{Name='Befehl';Expression={'font '+$_.Shortcut}},Family,Description
        return
    }
    $appearance = Get-ShellTerminalAppearance
    if ($Name -eq 'status' -and -not $PSBoundParameters.ContainsKey('Size')) {
        Write-Host ('Schrift: {0} · {1} pt · {2}' -f $appearance.Font, $appearance.Size, $appearance.ProfileName)
        return
    }
    if (-not $env:WT_PROFILE_ID) { throw 'Bitte font in einem Windows-Terminal-Tab ausfuehren.' }
    $resolvedName = switch ($Name.ToLowerInvariant()) {
        'ibm' { 'plex' }
        default { $Name }
    }
    $choice = $catalog | Where-Object { $_.Shortcut -eq $resolvedName -or $_.Family -eq $resolvedName } | Select-Object -First 1
    if ($Name -eq 'status') { $choice = $catalog | Where-Object Family -eq $appearance.Font | Select-Object -First 1 }
    if (-not $choice) { throw ('Schrift nicht gefunden: {0}. Auswahl: font list' -f $Name) }
    $settingsPath = (Get-ShellTerminalSettingsPath)
    $snapshot=$null
    $settings = Read-ShellTerminalJson $settingsPath -Snapshot ([ref]$snapshot)
    $profile = $settings.profiles.list | Where-Object guid -eq $appearance.ProfileId | Select-Object -First 1
    $newSize = if ($PSBoundParameters.ContainsKey('Size')) { $Size } else { $appearance.Size }
    foreach($appearanceProfile in (Get-ShellAppearanceProfiles -Settings $settings -ProfileId $appearance.ProfileId)){
        if (-not $appearanceProfile.font) { $appearanceProfile | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) -Force }
        $appearanceProfile.font | Add-Member -NotePropertyName face -NotePropertyValue $choice.Family -Force
        if ($null -ne $newSize) {
            $appearanceProfile.font | Add-Member -NotePropertyName size -NotePropertyValue $newSize -Force
        } else { $appearanceProfile.font.PSObject.Properties.Remove('size') }
        # Use each font's natural metrics. "1" is 1 em, not the default cell width.
        foreach ($metric in @('cellWidth','cellHeight')) {
            if ($choice.$metric) {
                $appearanceProfile.font | Add-Member -NotePropertyName $metric -NotePropertyValue $choice.$metric -Force
            } else { $appearanceProfile.font.PSObject.Properties.Remove($metric) }
        }
        $appearanceProfile.font | Add-Member -NotePropertyName weight -NotePropertyValue 'normal' -Force
        $appearanceProfile.font | Add-Member -NotePropertyName builtinGlyphs -NotePropertyValue $true -Force
    }
    Write-ShellTerminalSettings -Path $settingsPath -Settings $settings -Snapshot $snapshot
    $sizeLabel=if($null -ne $newSize){[string]$newSize+' pt'}else{'Terminal-Standard'}
    Write-Host ('Schrift: {0} · {1} · {2}' -f $choice.Family, $sizeLabel, $profile.name)
    if ($Reload) { Open-FreshTerminalTab }
}
Set-Alias -Name font -Value Set-TerminalFont -Scope Global
