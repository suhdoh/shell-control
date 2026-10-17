# Windows Terminal profile controls shared by PowerShell 5.1 and 7.
function global:Get-ShellTerminalAppearance {
    $settingsPath = (Get-ShellTerminalSettingsPath)
    $settings = Read-ShellTerminalJson $settingsPath
    $profileId = $env:WT_PROFILE_ID
    if (-not $profileId) { $profileId = $settings.defaultProfile }
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
    [pscustomobject]@{ ProfileId=$profile.guid; ProfileName=$profile.name; Font=$face; Size=$size; CRT=$crt }
}
function global:Set-TerminalCrt {
    [CmdletBinding()]
    param([Parameter(Position=0)][ValidateSet('on','off','toggle','status')][string]$Mode='status', [switch]$Reload)
    if (-not $env:WT_PROFILE_ID) { throw 'Bitte crt in einem Windows-Terminal-Tab ausfuehren.' }
    $appearance = Get-ShellTerminalAppearance
    if ($Mode -ne 'status') {
        $settingsPath = (Get-ShellTerminalSettingsPath)
        $snapshot=$null
        $settings = Read-ShellTerminalJson $settingsPath -Snapshot ([ref]$snapshot)
        $profile = $settings.profiles.list | Where-Object guid -eq $appearance.ProfileId | Select-Object -First 1
        $enabled = if ($Mode -eq 'toggle') { -not $appearance.CRT } else { $Mode -eq 'on' }
        $profile | Add-Member -NotePropertyName 'experimental.retroTerminalEffect' -NotePropertyValue ([bool]$enabled) -Force
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
    $settingsPath = (Get-ShellTerminalSettingsPath)
    $snapshot=$null
    $settings = Read-ShellTerminalJson $settingsPath -Snapshot ([ref]$snapshot)
    if ($Name -in @('list','ls')) {
        $settings.schemes | Sort-Object name | Select-Object -ExpandProperty name
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
    $scheme = $settings.schemes | Where-Object name -eq $target | Select-Object -First 1
    if (-not $scheme) { throw ('Theme nicht gefunden: {0}. Verfuegbare Themes: theme list' -f $target) }
    $profile | Add-Member -NotePropertyName colorScheme -NotePropertyValue $scheme.name -Force
    if ($scheme.cursorColor) {
        $profile | Add-Member -NotePropertyName cursorColor -NotePropertyValue $scheme.cursorColor -Force
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
    if (-not $profile.font) { $profile | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) -Force }
    $newSize = if ($PSBoundParameters.ContainsKey('Size')) { $Size } else { $appearance.Size }
    $profile.font | Add-Member -NotePropertyName face -NotePropertyValue $choice.Family -Force
    $profile.font | Add-Member -NotePropertyName size -NotePropertyValue $newSize -Force
    # Use each font's natural metrics. "1" is 1 em, not the default cell width.
    foreach ($metric in @('cellWidth','cellHeight')) {
        if ($choice.$metric) {
            $profile.font | Add-Member -NotePropertyName $metric -NotePropertyValue $choice.$metric -Force
        } else { $profile.font.PSObject.Properties.Remove($metric) }
    }
    $profile.font | Add-Member -NotePropertyName weight -NotePropertyValue 'normal' -Force
    $profile.font | Add-Member -NotePropertyName builtinGlyphs -NotePropertyValue $true -Force
    Write-ShellTerminalSettings -Path $settingsPath -Settings $settings -Snapshot $snapshot
    Write-Host ('Schrift: {0} · {1} pt · {2}' -f $choice.Family, $newSize, $profile.name)
    if ($Reload) { Open-FreshTerminalTab }
}
Set-Alias -Name font -Value Set-TerminalFont -Scope Global
