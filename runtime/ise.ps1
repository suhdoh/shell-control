# ISE uses its own persisted appearance and a WPF settings dialog.
function global:Test-ShellIse {
    $variable=Get-Variable -Name psISE -Scope Global -ErrorAction SilentlyContinue
    return ($null -ne $variable -and $null -ne $variable.Value -and $null -ne $variable.Value.Options)
}
function global:Get-ShellIseSchemes {
    # Windows PowerShell 5.1 emits a root JSON array as one pipeline object.
    $schemes=Get-Content -LiteralPath (Join-Path $global:ShellControlRoot 'assets/themes.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $schemes
}
function global:Get-ShellIseAppearance {
    if(-not (Test-ShellIse)){throw 'Diese Einstellung erfordert Windows PowerShell ISE.'}
    $preferences=Get-ShellControlPreferences
    [pscustomobject]@{ProfileId='ISE';ProfileName='Windows PowerShell ISE';Font=$global:psISE.Options.FontName;Size=$global:psISE.Options.FontSize;Theme=$(if($preferences.iseTheme){$preferences.iseTheme}else{'Amber 340'});CRT=$false;CRTConfigured=$false;ShaderPath=$null}
}
function global:Apply-ShellIseTheme {
    param([Parameter(Mandatory)]$Scheme)
    if(-not (Test-ShellIse)){throw 'Diese Einstellung erfordert Windows PowerShell ISE.'}
    $options=$global:psISE.Options
    # Property names vary between old ISE versions. Only assign properties present on this host.
    foreach($name in @('ConsolePaneBackgroundColor','ConsolePaneTextBackgroundColor','OutputPaneBackground')){
        if($options.PSObject.Properties[$name]){
            $value=$Scheme.background
            if($null -ne $options.$name -and $options.$name.GetType().FullName -eq 'System.Windows.Media.Color'){$value=[Windows.Media.ColorConverter]::ConvertFromString($value)}
            $options.$name=$value
        }
    }
    foreach($name in @('ConsolePaneForegroundColor','OutputPaneForeground')){
        if($options.PSObject.Properties[$name]){
            $value=$Scheme.foreground
            if($null -ne $options.$name -and $options.$name.GetType().FullName -eq 'System.Windows.Media.Color'){$value=[Windows.Media.ColorConverter]::ConvertFromString($value)}
            $options.$name=$value
        }
    }
}
function global:Initialize-ShellIse {
    if(-not (Test-ShellIse)){return}
    $preferences=Get-ShellControlPreferences
    if($preferences.iseFont){$global:psISE.Options.FontName=[string]$preferences.iseFont}
    elseif(@(Get-ShellFontChoices|Where-Object Family -eq 'Terminess Nerd Font').Count){
        $global:psISE.Options.FontName='Terminess Nerd Font'
        if(-not $preferences.iseFontSize){$global:psISE.Options.FontSize=16}
    }
    if($preferences.iseFontSize){$global:psISE.Options.FontSize=[double]$preferences.iseFontSize}
    $theme=if($preferences.iseTheme){$preferences.iseTheme}else{'Amber 340'}
    $scheme=Get-ShellIseSchemes|Where-Object name -eq $theme|Select-Object -First 1
    if($scheme){Apply-ShellIseTheme $scheme}
}
function global:Set-ShellIseTheme {
    [CmdletBinding()]
    param([string]$Name='status')
    if($Name -in @('list','ls')){Get-ShellIseSchemes|Sort-Object name|Select-Object -ExpandProperty name;return}
    $appearance=Get-ShellIseAppearance
    if($Name -eq 'status'){Write-Host ('Theme: {0} · {1}' -f $appearance.Theme,$appearance.ProfileName);return}
    $target=switch($Name.ToLowerInvariant()){
        'amber'{'Amber 340'} 'jade'{'Osaka Jade'} 'matrix'{'Matrix'} 'green'{'Matrix'}
        'red'{'Dark Crimson'} 'crimson'{'Dark Crimson'} 'pink'{'SynthWave 84'} 'synthwave'{'SynthWave 84'}
        'rose'{'rose-pine'} 'rosepine'{'rose-pine'} 'moon'{'rose-pine-moon'} 'dawn'{'rose-pine-dawn'}
        'latte'{'Catppuccin Latte'} 'frappe'{'Catppuccin Frappe'} 'macchiato'{'Catppuccin Macchiato'}
        'mocha'{'Catppuccin Mocha'} 'catppuccin'{'Catppuccin Mocha'} 'gruvbox'{'Gruvbox Dark Medium'}
        'gruvbox-dark'{'Gruvbox Dark Medium'} 'gruvbox-dark-hard'{'Gruvbox Dark Hard'}
        'gruvbox-dark-medium'{'Gruvbox Dark Medium'} 'gruvbox-dark-soft'{'Gruvbox Dark Soft'}
        'gruvbox-light'{'Gruvbox Light Medium'} 'gruvbox-light-hard'{'Gruvbox Light Hard'}
        'gruvbox-light-medium'{'Gruvbox Light Medium'} 'gruvbox-light-soft'{'Gruvbox Light Soft'}
        default{$Name}
    }
    $scheme=Get-ShellIseSchemes|Where-Object name -eq $target|Select-Object -First 1
    if(-not $scheme){throw ('Theme nicht gefunden: '+$Name+'. Auswahl: theme list')}
    Apply-ShellIseTheme $scheme
    Set-ShellControlPreference iseTheme $scheme.name
    Write-Host ('Theme: {0} · Windows PowerShell ISE' -f $scheme.name)
}
function global:Set-ShellIseFont {
    [CmdletBinding()]
    param([string]$Name='status',[ValidateRange(6,72)][double]$Size)
    $appearance=Get-ShellIseAppearance
    $catalog=@(Get-ShellFontChoices)
    if($Name -in @('list','ls')){$catalog|Select-Object Shortcut,Family;return}
    if($Name -eq 'status' -and -not $PSBoundParameters.ContainsKey('Size')){
        Write-Host ('Schrift: {0} · {1} pt · Windows PowerShell ISE' -f $appearance.Font,$appearance.Size);return
    }
    $family=$appearance.Font
    if($Name -ne 'status' -and $Name -ne $appearance.Font){
        $lookup=if($Name -eq 'ibm'){'plex'}else{$Name}
        $choice=$catalog|Where-Object { $_.Shortcut -eq $lookup -or $_.Family -eq $lookup }|Select-Object -First 1
        if(-not $choice){throw ('Schrift nicht gefunden: '+$Name+'. Auswahl: font list')}
        $family=$choice.Family
    }
    $newSize=if($PSBoundParameters.ContainsKey('Size')){$Size}else{$appearance.Size}
    $global:psISE.Options.FontName=[string]$family
    $global:psISE.Options.FontSize=[double]$newSize
    Set-ShellControlPreference iseFont $family
    Set-ShellControlPreference iseFontSize $newSize
    Write-Host ('Schrift: {0} · {1} pt · Windows PowerShell ISE' -f $family,$newSize)
}
function global:New-ShellIseMenuWindow {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    [xml]$markup=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Shell Control · PowerShell ISE" Width="520" Height="580" WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
  <StackPanel Margin="20">
    <TextBlock FontSize="20" Margin="0,0,0,16" Text="PowerShell ISE"/>
    <TextBlock Text="Theme"/><ComboBox Name="Theme" Margin="0,4,0,12"/>
    <TextBlock Text="Schrift / Font"/><ComboBox Name="Font" Margin="0,4,0,12"/>
    <TextBlock Text="Schriftgröße / Font size"/><ComboBox Name="Size" IsEditable="True" Margin="0,4,0,12"/>
    <TextBlock Text="Sprache / Language"/><ComboBox Name="Language" Margin="0,4,0,12"/>
    <CheckBox Name="Fastfetch" Content="Fastfetch beim Start / at startup" Margin="0,0,0,12"/>
    <TextBlock Text="Prompt: Benutzer in Pfad + Uhrzeit, danach ❯"/>
    <TextBlock Text="CRT wird von Windows Terminal unterstützt." Margin="0,6,0,12"/>
    <TextBlock Name="Status" TextWrapping="Wrap" Foreground="DarkRed" MinHeight="30"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button Name="Save" Content="Speichern / Save" Padding="12,6" Margin="0,0,8,0"/>
      <Button Name="Close" Content="Schließen / Close" Padding="12,6"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $reader=New-Object Xml.XmlNodeReader $markup
    try{return [Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Close()}
}
function global:Show-ShellIseMenu {
    if(-not (Test-ShellIse)){throw 'Dieses Fenster erfordert Windows PowerShell ISE.'}
    $window=New-ShellIseMenuWindow
    $theme=$window.FindName('Theme');$font=$window.FindName('Font');$size=$window.FindName('Size')
    $language=$window.FindName('Language');$fastfetch=$window.FindName('Fastfetch');$status=$window.FindName('Status')
    $preferences=Get-ShellControlPreferences;$appearance=Get-ShellIseAppearance
    foreach($item in @(Get-ShellIseSchemes|Sort-Object name|Select-Object -ExpandProperty name)){[void]$theme.Items.Add($item)}
    $theme.SelectedItem=if($preferences.iseTheme){$preferences.iseTheme}else{'Amber 340'}
    foreach($item in @(@(Get-ShellFontChoices|Select-Object -ExpandProperty Family)+@($appearance.Font)|Sort-Object -Unique)){[void]$font.Items.Add($item)}
    $font.SelectedItem=$appearance.Font
    foreach($item in @(8,10,12,14,16,18,20,24,28,32)){[void]$size.Items.Add([string]$item)}
    $size.Text=[string]$appearance.Size
    foreach($item in @('de','en')){[void]$language.Items.Add($item)}
    $language.SelectedItem=if($preferences.language){$preferences.language}else{'en'}
    $fastfetch.IsChecked=($preferences.fastfetch -ne $false)
    $window.FindName('Save').Add_Click({
        try {
            $chosenSize=[double]::Parse($size.Text,[Globalization.CultureInfo]::CurrentCulture)
            if($chosenSize -lt 6 -or $chosenSize -gt 72){throw 'Schriftgröße muss zwischen 6 und 72 liegen.'}
            Set-ShellIseFont -Name ([string]$font.SelectedItem) -Size $chosenSize
            Set-ShellIseTheme -Name ([string]$theme.SelectedItem)
            Set-ShellMenuLanguage ([string]$language.SelectedItem)
            Set-ShellControlPreference fastfetch ([bool]$fastfetch.IsChecked)
            Set-ShellPromptEngine native
            $status.Foreground='DarkGreen';$status.Text='Gespeichert / Saved. Die Auswahl gilt auch nach dem Neustart.'
        } catch {$status.Foreground='DarkRed';$status.Text=$_.Exception.Message}
    })
    $window.FindName('Close').Add_Click({$window.Close()})
    [void]$window.ShowDialog()
}
