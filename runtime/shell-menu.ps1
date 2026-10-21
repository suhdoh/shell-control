function global:Get-ShellCommandTableLayout {
    param([object[]]$Rows,[int]$Width)
    $categoryHeader=ConvertTo-ShellMenuText 'Kategorie'
    $commandHeader=ConvertTo-ShellMenuText 'Befehl'
    $descriptionHeader=ConvertTo-ShellMenuText 'Beschreibung'
    $categoryWidth=$categoryHeader.Length
    $commandWidth=$commandHeader.Length
    foreach($row in $Rows){
        $categoryWidth=[math]::Max($categoryWidth,(ConvertTo-ShellMenuText $row.Kategorie).Length)
        $commandWidth=[math]::Max($commandWidth,(ConvertTo-ShellMenuText $row.Befehl).Length)
    }
    $categoryWidth=[math]::Min($categoryWidth,[math]::Max(6,[int]($Width/4)))
    $available=[math]::Max(4,$Width-$categoryWidth-2)
    $descriptionWidth=0
    if($available-$commandWidth-2 -ge 18){$descriptionWidth=$available-$commandWidth-2}
    else{$commandWidth=$available}
    $header=$categoryHeader.PadRight($categoryWidth)+'  '+$commandHeader.PadRight($commandWidth)
    if($descriptionWidth){$header+='  '+$descriptionHeader}
    [pscustomobject]@{CategoryWidth=$categoryWidth;CommandWidth=$commandWidth;DescriptionWidth=$descriptionWidth;Header=$header}
}
function global:Format-ShellCommandTableRow {
    param($Row,$Layout)
    function FitCell([string]$text,[int]$width){
        if($text.Length -gt $width){return $text.Substring(0,[math]::Max(0,$width-1))+'…'}
        $text.PadRight($width)
    }
    $category=FitCell (ConvertTo-ShellMenuText $Row.Kategorie) $Layout.CategoryWidth
    $command=FitCell (ConvertTo-ShellMenuText $Row.Befehl) $Layout.CommandWidth
    $text=$category+'  '+$command
    if($Layout.DescriptionWidth){$text+='  '+(FitCell (ConvertTo-ShellMenuText $Row.Beschreibung) $Layout.DescriptionWidth)}
    $text
}

function global:Get-ShellMenuLanguage {
    if($script:ShellMenuLanguage -in @('en','de')){return $script:ShellMenuLanguage}
    $path=(Join-Path $global:ShellControlRoot 'menu-settings.json')
    $language='en'
    if(Test-Path -LiteralPath $path){
        try {$saved=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json;if($saved.language -in @('en','de')){$language=$saved.language}}catch{}
    }
    $script:ShellMenuLanguage=$language
    return $language
}
function global:Set-ShellMenuLanguage {
    param([ValidateSet('en','de')][string]$Language)
    Set-ShellControlPreference language $Language
    $script:ShellMenuLanguage=$Language
}
function global:ConvertTo-ShellMenuText {
    param([AllowEmptyString()][string]$Text,[ValidateSet('en','de')][string]$Language)
    if(-not $Language){$Language=Get-ShellMenuLanguage}
    if(-not $script:ShellMenuTranslations){
        $script:ShellMenuTranslations=Get-Content -LiteralPath (Join-Path $global:ShellControlRoot 'menu-translations.json') -Raw -Encoding UTF8|ConvertFrom-Json
    }
    $map=$script:ShellMenuTranslations.$Language
    $lines=@($Text -split "`r?`n")
    $translated=foreach($line in $lines){
        if([string]::IsNullOrEmpty($line)){'';continue}
        $property=$map.PSObject.Properties[$line]
        if($property){$property.Value;continue}
        if($Language -eq 'en'){
            if($line -like '*  ·  *'){
                $parts=$line -split '  ·  ',2
                $category=$map.PSObject.Properties[$parts[0]]
                if($category){$line=$category.Value+'  ·  '+$parts[1]}
            }
            foreach($pair in @(
                @('✓ Theme aktiv: ','✓ Active theme: '),@('✓ Schrift aktiv: ','✓ Active font: '),
                @('✓ Schriftgröße: ','✓ Font size: '),@('✓ Sprache: ','✓ Language: '),
                @('✓ CRT eingeschaltet','✓ CRT enabled'),@('✓ CRT ausgeschaltet','✓ CRT disabled'),
                @('Fehler: ','Error: '),@('Befehle / ','Commands / ')
            )){if($line.StartsWith($pair[0])){$line=$pair[1]+$line.Substring($pair[0].Length);break}}
            if($line.StartsWith('Commands / ')){
                $suffix=$line.Substring(11)
                $category=$map.PSObject.Properties[$suffix]
                if($category){$line='Commands / '+$category.Value}
            }
            $line=$line.Replace('<Zahl>','<number>').Replace('<Pfad>','<path>').Replace('<Quelle>','<source>').Replace('<Ziel>','<target>').Replace('<Muster>','<pattern>').Replace('[Pfad]','[path]')
        }
        $line
    }
    $translated -join "`n"
}
function global:Get-ShellMenuOrderedItems {
    param([string[]]$Items)
    # Keep caller values stable; only the visible ordering changes.
    $normalOptions=@();$homeOptions=@();$backOptions=@();$exitOptions=@()
    foreach($item in $Items){
        if($item -match '^Beenden|^Exit'){$exitOptions+=$item}
        elseif($item -match '^←|^Zur Befehlsliste|^Back(?:\s|$)'){$backOptions+=$item}
        elseif($item -match '^Zur Übersicht'){$homeOptions+=$item}
        else{$normalOptions+=$item}
    }
    $normalOptions+$homeOptions+$backOptions+$exitOptions
}

# Interactive controls are loaded only when requested. Gum uses the current ANSI palette.
function global:Set-TerminalFontSize {
    [CmdletBinding()]
    param([Parameter(Position=0)][ValidateRange(6,72)][double]$Size, [switch]$Reload)
    $appearance = Get-ShellTerminalAppearance
    if (-not $PSBoundParameters.ContainsKey('Size')) {
        Write-Host ('Schriftgroesse: {0} pt' -f $appearance.Size)
        return
    }
    if (-not $env:WT_PROFILE_ID) { throw 'Bitte font-size in Windows Terminal ausfuehren.' }
    $path = (Get-ShellTerminalSettingsPath)
    $snapshot=$null
    $settings = Read-ShellTerminalJson $path -Snapshot ([ref]$snapshot)
    $profile = $settings.profiles.list | Where-Object guid -eq $appearance.ProfileId | Select-Object -First 1
    if (-not $profile.font) { $profile | Add-Member font ([pscustomobject]@{}) }
    $profile.font | Add-Member -NotePropertyName size -NotePropertyValue $Size -Force
    Write-ShellTerminalSettings -Path $path -Settings $settings -Snapshot $snapshot
    Write-Host ('Schriftgroesse: {0} pt · {1}' -f $Size, $appearance.ProfileName)
    if ($Reload) { Open-FreshTerminalTab }
}
Set-Alias -Name font-size -Value Set-TerminalFontSize -Scope Global

function global:Get-CustomCommand {
    # Category | invocation | purpose | example. Reference only: commands are never evaluated.
    $rows = @(
        'Ansicht|crt [on/off/toggle/status]|CRT-Effekt steuern|crt toggle',
        'Ansicht|crtoff|CRT ausschalten|crtoff',
        'Ansicht|crton|CRT einschalten|crton',
        'Ansicht|font <Name>|Schrift wechseln; font list zeigt die Auswahl|font jetbrains',
        'Ansicht|font-size <Zahl>|Schriftgroesse von 6 bis 72 pt|font-size 14',
        'Ansicht|theme <Name>|Theme wechseln; theme list zeigt alle Varianten|theme rose',
        'Ansicht|treload|Neuen Tab mit aktuellem Profil und Ordner oeffnen|treload',
        'Dateien|cat <Pfad>|Textdatei lesen|cat .\notes.txt',
        'Dateien|cp <Quelle> <Ziel>|Datei kopieren|cp .\a.txt .\b.txt',
        'Dateien|grep <Muster> [Pfad]|Dateiinhalte rekursiv durchsuchen|grep TODO .\src',
        'Dateien|l [Pfad]|Dateinamen untereinander mit Icons|l',
        'Dateien|la [Pfad]|Raster inklusive versteckter Dateien|la',
        'Dateien|ll [Pfad]|Detaillierte Dateiliste inklusive versteckter Dateien|ll',
        'Dateien|ls [Pfad]|Kompaktes Raster mit Icons|ls',
        'Dateien|mkdir <Pfad>|Ordner anlegen|mkdir .\Demo',
        'Dateien|mkfile <Pfad>|Leere Datei anlegen|mkfile .\notes.txt',
        'Dateien|mv <Quelle> <Ziel>|Datei verschieben oder umbenennen|mv .\a.txt .\b.txt',
        'Dateien|pwd|Aktuellen Ordner anzeigen|pwd',
        'Dateien|rm <Pfad>|Datei loeschen; -Recurse fuer Unterordner|rm .\temp.txt -WhatIf',
        'Dateien|rmdir <Pfad>|Ordner loeschen; -Recurse fuer Inhalt|rmdir .\Demo -WhatIf',
        'Hilfe|commands [-Search Text]|Alle Custom-Befehle, kategorisiert und sortiert|commands -Search font',
        'Hilfe|commands-menu|Interaktives Shell-Menue starten|commands-menu',
        'Hilfe|h [-Count Zahl]|Befehlsverlauf dieser Sitzung|h -Count 20',
        'Hilfe|shell-menu|Interaktives Shell-Menue starten|shell-menu',
        'System|df|Freien und belegten Laufwerksspeicher anzeigen|df',
        'System|fastfetch|Kompakte Systemuebersicht mit Rahmen|fastfetch',
        'System|fastfetch --all|Ausfuehrliche Systeminformationen|fastfetch --all',
        'System|fastfetch-all|Ausfuehrliche Systeminformationen|fastfetch-all'
    )
    foreach ($row in $rows) {
        $parts = $row.Split('|')
        [pscustomobject]@{Kategorie=$parts[0];Befehl=$parts[1];Beschreibung=$parts[2];Beispiel=$parts[3]}
    }
}
function global:Show-CustomCommands {
    [CmdletBinding()]
    param([string]$Search, [switch]$Menu, [switch]$PassThru)
    if ($Menu) { Show-ShellMenu; return }
    $items = @(Get-CustomCommand | Where-Object { -not $Search -or (($_.Befehl+' '+$_.Beschreibung+' '+$_.Kategorie).IndexOf($Search,[StringComparison]::OrdinalIgnoreCase) -ge 0) } | Sort-Object Kategorie,Befehl)
    if ($PassThru) { $items; return }
    foreach ($group in ($items | Group-Object Kategorie)) {
        Write-Host ("`n"+$group.Name) -ForegroundColor Magenta
        foreach ($item in $group.Group) {
            Write-Host ('  '+$item.Befehl) -ForegroundColor Cyan
            Write-Host ('    '+$item.Beschreibung)
        }
    }
    if (-not $items.Count) { Write-Host 'Keine passenden Befehle.' }
    Write-Host "`nMenue: shell-menu · Alle Themes: theme list · Schriften: font list" -ForegroundColor DarkGray
}
Set-Alias -Name commands -Value Show-CustomCommands -Scope Global

function global:Get-ShellGumPath {
    $command = Get-Command gum.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $package = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\charmbracelet.gum_Microsoft.Winget.Source_8wekyb3d8bbwe'
    $binary = Get-ChildItem -LiteralPath $package -Filter gum.exe -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($binary) { return $binary.FullName }
    throw 'Gum fehlt. Installation: winget install charmbracelet.gum'
}
function global:Get-ShellMenuLayout {
    try { $columns = [Console]::WindowWidth; $rows = [Console]::WindowHeight }
    catch { $columns=80; $rows=24 }
    if ($columns -lt 1) { $columns = 80 }
    if ($rows -lt 1) { $rows = 24 }
    [pscustomobject]@{
        Columns=$columns; Rows=$rows
        Width=[Math]::Max(20,$columns-6)
        ListHeight=[Math]::Max(5,$rows-9)
    }
}
function global:Write-ShellMenuLine {
    param([string]$Text, [ConsoleColor]$Color='Gray')
    $Text=ConvertTo-ShellMenuText $Text
    $layout=Get-ShellMenuLayout
    if ($Text.Length -gt $layout.Width) { $Text=$Text.Substring(0,[Math]::Max(0,$layout.Width-1))+'…' }
    Write-Host ('  '+$Text) -ForegroundColor $Color
}
# Fixed-coordinate picker. No child renderer competes for the console cursor.
function global:ConvertTo-ShellSearchText {
    param([string]$Text)
    $text=$Text.ToLowerInvariant().Replace('ä','ae').Replace('ö','oe').Replace('ü','ue').Replace('ß','ss')
    $text -replace '[^\p{L}\p{Nd}]+',' '
}
function global:Get-ShellMenuMatches {
    param([string[]]$Items,[string]$Query,[hashtable]$SearchTerms)
    $queryText=ConvertTo-ShellSearchText $Query
    $tokens=@($queryText.Trim() -split '\s+'|Where-Object {$_})
    for($i=0;$i -lt $Items.Count;$i++){
        $label=$Items[$i]
        $aliases=switch -Regex ($label){
            '^←|^Zur ' {' back return zurueck overview home uebersicht ';break}
            '^Schriftgröße' {' font size fontsize schriftgroesse groesse size ';break}
            '^Schriftart' {' font type typeface schriftart ';break}
            '^Schriften' {' font fonts typeface schrift schriften ';break}
            '^Themes' {' theme colors colours farben design style ';break}
            '^CRT' {' crt retro glow effect effekt ';break}
            '^Befehle' {' commands command help hilfe befehle reference ';break}
            '^Systeminfo' {' system info hardware fastfetch status ';break}
            '^Neuer Tab' {' new tab reload terminal neuer ';break}
            '^Beenden' {' exit quit close beenden ende ';break}
            '^Ansicht' {' appearance display view ansicht theme colors colours farben font fonts schrift schriften prompt crt retro ';break}
            '^Werkzeuge' {' tools commands command reference befehle referenz hilfe help ';break}
            '^Installation|^Komponenten' {' setup install installation components komponenten dependencies programme profiles profile fonts schriften terminal ';break}
            '^Einstellungen' {' settings preferences einstellungen sprache language fastfetch startup start ';break}
            '^Dateien' {' files folders directory dateien ordner ';break}
            '^Hilfe' {' help docs reference hilfe ';break}
            '^Alle Befehle' {' all commands alle befehle ';break}
            '^Einschalten' {' on enable einschalten ';break}
            '^Ausschalten' {' off disable ausschalten ';break}
            '^Umschalten' {' toggle umschalten ';break}
            default {''}
        }
        $extra=if($SearchTerms -and $SearchTerms.ContainsKey($label)){$SearchTerms[$label]}else{''}
        $haystack=ConvertTo-ShellSearchText ($extra+' '+$label+' '+$aliases+' '+(ConvertTo-ShellMenuText $label -Language en)+' '+(ConvertTo-ShellMenuText $label -Language de))
        $matched=$true
        foreach($token in $tokens){if($haystack.IndexOf($token,[StringComparison]::Ordinal) -lt 0){$matched=$false;break}}
        if($matched){[pscustomobject]@{Label=$label;Index=$i}}
    }
}
function global:Get-ShellMenuPickerColors {
    # Keep setup and error navigation available even before Terminal is configured.
    $hex='#67B7BA'
    try {
        $path=(Get-ShellTerminalSettingsPath)
        $s=Read-ShellTerminalJson $path
        $id=if($env:WT_PROFILE_ID){$env:WT_PROFILE_ID}else{$s.defaultProfile}
        $p=$s.profiles.list|Where-Object guid -eq $id|Select-Object -First 1
        $name=if($p.colorScheme){$p.colorScheme}else{$s.profiles.defaults.colorScheme}
        $scheme=Get-ShellTerminalSchemes -Settings $s|Where-Object name -eq $name|Select-Object -First 1
        if($scheme.cyan -match '^#[0-9a-fA-F]{6}$'){$hex=$scheme.cyan}
    } catch {Write-Verbose ('Menu colors use the default palette. '+$_.Exception.Message)}
    $r=[Convert]::ToInt32($hex.Substring(1,2),16)
    $g=[Convert]::ToInt32($hex.Substring(3,2),16)
    $b=[Convert]::ToInt32($hex.Substring(5,2),16)
    $linear=@($r,$g,$b)|ForEach-Object {$v=$_/255.0;if($v -le 0.04045){$v/12.92}else{[math]::Pow(($v+0.055)/1.055,2.4)}}
    $luminance=0.2126*$linear[0]+0.7152*$linear[1]+0.0722*$linear[2]
    $fg=if($luminance -gt 0.179){'16;16;16'}else{'250;250;250'}
    [pscustomobject]@{Selection=([string][char]27+'[48;2;'+$r+';'+$g+';'+$b+';38;2;'+$fg+'m')}
}
function global:Get-ShellMenuPickerView {
    param([int]$Rows,[int]$Columns,[int]$StartRow,[int]$HeaderLines,[int]$Height)
    # Reserve bottom rows for a persistent query, result count and help.
    $searchRow=[Math]::Max(12,$Rows-4)
    $first=[Math]::Min([Math]::Max(6,$StartRow)+$HeaderLines+1,$searchRow-3)
    $available=[Math]::Max(1,$searchRow-$first-2)
    if($Height -gt 0){$available=[Math]::Min($available,$Height)}
    [pscustomobject]@{SearchRow=$searchRow;FirstRow=$first;Count=$available;Width=[Math]::Max(12,$Columns-6)}
}
function global:Select-ShellMenuItem {
    param([string]$Header,[string[]]$Items,[int]$Height=0,[object[]]$CommandRows,[string]$SelectedItem)
    $Items=@(Get-ShellMenuOrderedItems -Items $Items)
    $Header=ConvertTo-ShellMenuText $Header
    # Non-interactive single-choice path also supports regression checks.
    if($Items.Count -eq 1){return $Items[0]}
    if([Console]::IsInputRedirected){return}
    $esc=[char]27
    $colors=Get-ShellMenuPickerColors
    $baseHeaders=@($Header -split "`r?`n"|Where-Object {$_})
    $headers=$baseHeaders
    $commandMap=@{}
    $commandSearch=@{}
    foreach($row in $CommandRows){
        $key=$row.Kategorie+'  ·  '+$row.Befehl
        $commandMap[$key]=$row
        $commandSearch[$key]=$row.Beschreibung+' '+(ConvertTo-ShellMenuText $row.Beschreibung -Language en)+' '+(ConvertTo-ShellMenuText $row.Beschreibung -Language de)
    }
    $start=[Math]::Max(6,[Console]::CursorTop+1)
    $query='';$caret=0;$index=[Math]::Max(0,[Array]::IndexOf($Items,$SelectedItem));$offset=0;$dirty=$true;$lastSize=''
    $previousCtrlC=[Console]::TreatControlCAsInput
    try {
        [Console]::TreatControlCAsInput=$true
        while($true){
            $layout=Get-ShellMenuLayout
            $size=[string]$layout.Columns+'x'+$layout.Rows
            if($size -ne $lastSize){$dirty=$true;$lastSize=$size}
            if($dirty){
                $headers=$baseHeaders
                $table=$null
                if($CommandRows){
                    $table=Get-ShellCommandTableLayout -Rows $CommandRows -Width ($layout.Width-2)
                    $headers=@($baseHeaders)+@('',('  '+$table.Header))
                }
                $matches=@(Get-ShellMenuMatches -Items $Items -Query $query -SearchTerms $commandSearch)
                $view=Get-ShellMenuPickerView -Rows $layout.Rows -Columns $layout.Columns -StartRow $start -HeaderLines $headers.Count -Height $Height
                $width=$view.Width
                if($index -ge $matches.Count){$index=[Math]::Max(0,$matches.Count-1)}
                if($index -lt $offset){$offset=$index}
                if($index -ge $offset+$view.Count){$offset=$index-$view.Count+1}
                $offset=[Math]::Max(0,$offset)
                $out=New-Object Text.StringBuilder
                [void]$out.Append("$esc[?25l")
                # Address and clear every content row; never scroll or write at the last column.
                for($row=$start;$row -lt $layout.Rows;$row++){
                    [void]$out.Append("$esc[$($row);1H$esc[0m$esc[2K")
                }
                for($n=0;$n -lt $headers.Count;$n++){
                    $text=$headers[$n]
                    if($text.Length -gt $width){$text=$text.Substring(0,$width)}
                    [void]$out.Append("$esc[$($start+$n);3H$esc[35m$text$esc[0m")
                }
                if(-not $matches.Count){
                    [void]$out.Append("$esc[$($view.FirstRow);3H$esc[90m$(ConvertTo-ShellMenuText 'Keine Treffer / No matches')$esc[0m")
                }
                for($n=0;$n -lt $view.Count -and ($offset+$n) -lt $matches.Count;$n++){
                    $which=$offset+$n
                    $record=$commandMap[$matches[$which].Label]
                    $text=if($table -and $record){'  '+(Format-ShellCommandTableRow -Row $record -Layout $table)}else{'  '+(ConvertTo-ShellMenuText $matches[$which].Label)}
                    if($text.Length -gt $width){$text=$text.Substring(0,$width-1)+'…'}
                    $style=if($which -eq $index){$colors.Selection}else{"$esc[0m"}
                    [void]$out.Append("$esc[$($view.FirstRow+$n);3H$style$($text.PadRight($width))$esc[0m")
                }
                $line='─'*$width
                [void]$out.Append("$esc[$($view.SearchRow-1);3H$esc[36m$line$esc[0m")
                $prefix=ConvertTo-ShellMenuText 'Suche > '
                $space=[Math]::Max(1,$width-$prefix.Length-1)
                $queryOffset=[Math]::Max(0,$caret-$space)
                $visible=$query.Substring($queryOffset,[Math]::Min($space,$query.Length-$queryOffset))
                [void]$out.Append("$esc[$($view.SearchRow);3H$esc[36m$prefix$esc[0m$visible")
                $count=[string]$matches.Count+' / '+$Items.Count+' '+(ConvertTo-ShellMenuText 'Treffer')+' · '+(ConvertTo-ShellMenuText 'Suche: EN + DE')
                if($count.Length -gt $width){$count=$count.Substring(0,$width)}
                [void]$out.Append("$esc[$($view.SearchRow+1);3H$esc[90m$count$esc[0m")
                $help=ConvertTo-ShellMenuText '↑↓ Auswahl · Enter öffnen · Esc zurück · Ctrl+U leeren'
                if($help.Length -gt $width){$help=ConvertTo-ShellMenuText '↑↓ select · Enter open · Esc back'}
                [void]$out.Append("$esc[$($view.SearchRow+2);3H$esc[90m$help$esc[0m")
                $cursorColumn=3+$prefix.Length+$caret-$queryOffset
                [void]$out.Append("$esc[$($view.SearchRow);$($cursorColumn)H$esc[?25h")
                [Console]::Write($out.ToString())
                $dirty=$false
            }
            if(-not [Console]::KeyAvailable){Start-Sleep -Milliseconds 35;continue}
            $key=[Console]::ReadKey($true)
            $ctrl=($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0
            if($key.Key -eq [ConsoleKey]::Escape -or ($ctrl -and $key.Key -eq [ConsoleKey]::C)){return}
            switch($key.Key){
                'Enter' {if($matches.Count){return $matches[$index].Label}}
                'UpArrow' {$index=[Math]::Max(0,$index-1)}
                'DownArrow' {$index=[Math]::Min([Math]::Max(0,$matches.Count-1),$index+1)}
                'PageUp' {$index=[Math]::Max(0,$index-$view.Count)}
                'PageDown' {$index=[Math]::Min([Math]::Max(0,$matches.Count-1),$index+$view.Count)}
                'Tab' {if($matches.Count){$index=($index+1)%$matches.Count}}
                'LeftArrow' {$caret=[Math]::Max(0,$caret-1)}
                'RightArrow' {$caret=[Math]::Min($query.Length,$caret+1)}
                'Home' {$caret=0}
                'End' {$caret=$query.Length}
                'Backspace' {
                    if($caret -gt 0){
                        if($ctrl){$query=$query.Substring($caret);$caret=0}else{$query=$query.Remove($caret-1,1);$caret--}
                        $index=0;$offset=0
                    }
                }
                'Delete' {if($caret -lt $query.Length){$query=$query.Remove($caret,1);$index=0;$offset=0}}
                default {
                    if($ctrl -and $key.Key -eq [ConsoleKey]::U){$query='';$caret=0;$index=0;$offset=0}
                    elseif(-not [char]::IsControl($key.KeyChar) -and $query.Length -lt 200){
                        $query=$query.Insert($caret,[string]$key.KeyChar);$caret++;$index=0;$offset=0
                    }
                }
            }
            $dirty=$true
        }
    } finally {
        [Console]::TreatControlCAsInput=$previousCtrlC
        [Console]::Write("$esc[0m$esc[?25h")
    }
}

function global:Show-ShellMenuReference {
    param($Item)
    Write-ShellMenuFrame ('Befehle / '+$Item.Kategorie) 'Referenz · keine Ausführung von Befehlen'
    Write-ShellMenuLine $Item.Befehl Cyan
    Write-ShellMenuLine $Item.Beschreibung Gray
    Write-Host ''
    Write-ShellMenuLine 'Beispiel' Magenta
    Write-ShellMenuLine ('❯ '+$Item.Beispiel) Yellow
    Write-Host ''
    Select-ShellMenuItem 'Navigation' @('Zur Befehlsliste','Zur Übersicht') -Height 6
}
function global:Write-ShellMenuFrame {
    param([string]$Page,[string]$Notice,[string]$Hint)
    $layout=Get-ShellMenuLayout;$esc=[char]27
    [Console]::Write("$esc[2J$esc[H")
    Write-Host ''
    Write-ShellMenuLine '◆ Shell Control' Cyan
    $crumb=if($Page -and $Page -ne 'Übersicht'){ConvertTo-ShellMenuText $Page}else{''}
    Write-ShellMenuLine $crumb DarkGray
    Write-ShellMenuLine ('─'*$layout.Width) DarkGray
    if($Notice){Write-ShellMenuLine $Notice Yellow}
    if($Hint){Write-ShellMenuLine $Hint DarkGray}
    [Console]::Write("$esc[6;1H")
}
function global:Show-ShellSetupProgress {
    param([int]$Percent,[string]$Message)
    Write-ShellMenuFrame 'Installation' ''
    $esc=[char]27;$layout=Get-ShellMenuLayout
    $width=[math]::Max(10,[math]::Min(54,$layout.Width-8))
    $filled=[int][math]::Round($width*[math]::Min(100,[math]::Max(0,$Percent))/100)
    Write-ShellMenuLine $Message Gray
    Write-Host ''
    [Console]::Write('  '+$esc+'[32m'+('█'*$filled)+$esc+'[90m'+('█'*($width-$filled))+$esc+'[0m '+$Percent+'%')
}
function global:Get-ShellFontChoices {
    $catalog=Get-Content (Join-Path $global:ShellControlRoot 'font-catalog.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $families=@()
    $receipt=Join-Path $global:ShellControlRoot 'installed-fonts.json'
    if(Test-Path -LiteralPath $receipt){
        $registered=Get-Content $receipt -Raw -Encoding UTF8|ConvertFrom-Json
        $families+=@($registered|Where-Object {Test-Path -LiteralPath $_.Path}|ForEach-Object Family)
    }
    try {
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        $families+=@([Windows.Media.Fonts]::SystemFontFamilies|ForEach-Object Source)
    } catch {Write-Verbose ('System font discovery is unavailable; using registered font receipts. '+$_.Exception.Message)}
    $catalog|Where-Object Family -in $families|Sort-Object Family
}
function global:Show-ShellMenu {
    [CmdletBinding()]param()
    $ErrorActionPreference='Stop'
    if($Host.Name -ne 'ConsoleHost' -or [Console]::IsInputRedirected){Show-CustomCommands;return}
    $previousEncoding=[Console]::OutputEncoding;$esc=[char]27
    $script:ShellMenuLanguage=$null;[void](Get-ShellMenuLanguage)
    $page='Übersicht';$category='Alle Befehle';$themeFamily=$null;$notice='';$fontReturn='Schriften'
    try {
        [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
        [Console]::Write("$esc[?1049h$esc[H")
        while($true){
            try {
            $context=$notice
            if(-not $context -and $page -in @('Schriften','Schriftart','Schriftgröße')){
                $a=Get-ShellTerminalAppearance
                $context=(ConvertTo-ShellMenuText 'Aktuelle Schrift: ')+$a.Font+' · '+$a.Size+' pt'
            }
            if(-not $context -and $page -eq 'CRT'){
                $a=Get-ShellTerminalAppearance
                $context='CRT: '+$(if($a.CRT){ConvertTo-ShellMenuText 'an'}else{ConvertTo-ShellMenuText 'aus'})+' · '+$a.ProfileName
            }
            Write-ShellMenuFrame $page $context;$notice=''
                switch($page){
                    'Übersicht' {
                        $choice=Select-ShellMenuItem '' @('Ansicht','Systeminfo','Werkzeuge','Installation','Einstellungen','Beenden')
                        if(-not $choice -or $choice -eq 'Beenden'){return}
                        $page=$choice
                    }
                    'Ansicht' {
                        $choice=Select-ShellMenuItem '' @('Themes','Schriften','Prompt','CRT','← Zurück')
                        $page=if(-not $choice -or $choice -eq '← Zurück'){'Übersicht'}else{$choice}
                    }
                    'Themes' {
                        $families=@(Get-ShellThemeFamilies)
                        $activeTheme=(Get-ShellTerminalAppearance).Theme
                        $activeFamily=$families|Where-Object {$activeTheme -in $_.Variants}|Select-Object -First 1
                        $choice=Select-ShellMenuItem 'Theme-Familie wählen' (@($families|ForEach-Object Name)+@('← Zurück')) -SelectedItem $activeFamily.Name
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Ansicht';continue}
                        $themeFamily=$families|Where-Object Name -eq $choice|Select-Object -First 1
                        if($themeFamily.Variants.Count -eq 1){Set-TerminalTheme $themeFamily.Variants[0] 6>$null;$notice='✓ Theme aktiv: '+$themeFamily.Variants[0]}
                        else{$page='Varianten'}
                    }
                    'Varianten' {
                        Write-ShellMenuFrame ('Themes / '+$themeFamily.Name) ''
                        $choice=Select-ShellMenuItem 'Variante wählen' (@($themeFamily.Variants)+@('← Zurück')) -SelectedItem (Get-ShellTerminalAppearance).Theme
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Themes';continue}
                        Set-TerminalTheme $choice 6>$null;$notice='✓ Theme aktiv: '+$choice
                    }
                    'Schriften' {
                        $choice=Select-ShellMenuItem '' @('Schriftart','Schriftgröße','Schriften installieren','← Zurück')
                        $fontReturn='Schriften'
                        $page=if(-not $choice -or $choice -eq '← Zurück'){'Ansicht'}else{$choice}
                    }
                    'Schriftart' {
                        $catalog=@(Get-ShellFontChoices)
                        $options=@($catalog|ForEach-Object {$_.Shortcut+'  ·  '+$_.Family})
                        $available=Get-Content -LiteralPath (Join-Path $global:ShellControlRoot 'font-catalog.json') -Raw -Encoding UTF8|ConvertFrom-Json
                        $total=@($available).Count
                        $header=(ConvertTo-ShellMenuText 'Installierte Schriften: {0}/{1}') -f $catalog.Count,$total
                        if($catalog.Count -lt $total){$options+=@('Schriften installieren')}
                        $activeFont=$catalog|Where-Object Family -eq (Get-ShellTerminalAppearance).Font|Select-Object -First 1
                        $selectedFont=if($activeFont){$activeFont.Shortcut+'  ·  '+$activeFont.Family}else{$null}
                        $choice=Select-ShellMenuItem ($header+"`nAaBb 012345 · ┌─┬─┐ · ███ ·   ") ($options+@('← Zurück')) -SelectedItem $selectedFont
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Schriften';continue}
                        if($choice -eq 'Schriften installieren'){$fontReturn='Schriftart';$page='Schriften installieren';continue}
                        Set-TerminalFont (($choice -split '\s+',2)[0]) 6>$null;$notice='✓ Schrift aktiv: '+(Get-ShellTerminalAppearance).Font
                    }
                    'Schriftgröße' {
                        $currentSize=(Get-ShellTerminalAppearance).Size
                        $selectedSize=if($null -ne $currentSize){([double]$currentSize).ToString([Globalization.CultureInfo]::InvariantCulture)}else{$null}
                        $sizes=@('8','9','10','11','12','13','14','15','16','18','20','22','24','28','32','36')
                        if($selectedSize -and $selectedSize -notin $sizes){$sizes=@($sizes)+@($selectedSize)}
                        $sizes=@($sizes|Sort-Object {[double]$_})
                        $choice=Select-ShellMenuItem '' ($sizes+@('← Zurück')) -SelectedItem $selectedSize
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Schriften';continue}
                        Set-TerminalFontSize ([double]$choice) 6>$null;$notice='✓ Schriftgröße: '+$choice
                    }
                    'Schriften installieren' {
                        $choice=Select-ShellMenuItem 'Schriftpaket wählen' @('Empfohlene Schriften','Alle geprüften Schriften','← Zurück')
                        if(-not $choice -or $choice -eq '← Zurück'){$page=$fontReturn;continue}
                        $pack=if($choice -eq 'Empfohlene Schriften'){'Recommended'}else{'All'}
                        Invoke-ShellSetup -Component Fonts -Pack $pack;$notice='✓ Fertig'
                    }
                    'Prompt' {
                        $prefs=Get-ShellControlPreferences
                        $selectedEngine=if($prefs.promptEngine -eq 'omp'){'Oh My Posh'}else{'Nativ · schnell'}
                        $choice=Select-ShellMenuItem ('Engine: '+$prefs.promptEngine) @('Nativ · schnell','Oh My Posh','← Zurück') -SelectedItem $selectedEngine
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Ansicht';continue}
                        Set-ShellPromptEngine $(if($choice -eq 'Oh My Posh'){'omp'}else{'native'});$notice='✓ Fertig'
                    }
                    'Systeminfo' {Show-ShellSystemInfo;$page='Übersicht'}
                    'Werkzeuge' {
                        $choice=Select-ShellMenuItem '' @('Befehlsreferenz','Neuer Tab','← Zurück')
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Übersicht';continue}
                        if($choice -eq 'Neuer Tab'){Open-FreshTerminalTab;return}
                        $page='Befehle'
                    }
                    'Befehle' {
                        $categories=@(Get-CustomCommand|Select-Object -ExpandProperty Kategorie -Unique|Sort-Object)
                        $choice=Select-ShellMenuItem '' (@('Alle Befehle')+$categories+@('← Zurück'))
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Werkzeuge';continue}
                        $category=$choice;$page='Befehlsliste'
                    }
                    'Befehlsliste' {
                        Write-ShellMenuFrame ('Befehle / '+$category) ''
                        $refs=@(Get-CustomCommand|Where-Object {$category -eq 'Alle Befehle' -or $_.Kategorie -eq $category}|Sort-Object Kategorie,Befehl)
                        $options=@($refs|ForEach-Object {$_.Kategorie+'  ·  '+$_.Befehl})
                        $choice=Select-ShellMenuItem '' ($options+@('← Zurück')) -CommandRows $refs
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Befehle';continue}
                        $item=$refs|Where-Object {($_.Kategorie+'  ·  '+$_.Befehl) -eq $choice}|Select-Object -First 1
                        if($item){$nav=Show-ShellMenuReference $item;if($nav -eq 'Zur Übersicht'){$page='Übersicht'}}
                    }
                    'Installation' {
                        $choice=Select-ShellMenuItem '' @('Alles einrichten','Komponenten','← Zurück')
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Übersicht';continue}
                        if($choice -eq 'Komponenten'){$page='Komponenten';continue}
                        Invoke-ShellSetup All;$notice='✓ Fertig'
                    }
                    'Komponenten' {
                        $choice=Select-ShellMenuItem '' @('Programme installieren','Schriften installieren','Profile einrichten','Terminal einrichten','← Zurück')
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Installation';continue}
                        if($choice -eq 'Schriften installieren'){$fontReturn='Komponenten';$page='Schriften installieren';continue}
                        $component=switch($choice){'Programme installieren'{'Dependencies'} 'Profile einrichten'{'Profiles'} default{'Terminal'}}
                        Invoke-ShellSetup $component;$notice='✓ Fertig'
                    }
                    'Einstellungen' {
                        $choice=Select-ShellMenuItem '' @('Sprache / Language','Fastfetch beim Start','← Zurück')
                        $page=if(-not $choice -or $choice -eq '← Zurück'){'Übersicht'}else{$choice}
                    }
                    'CRT' {
                        $selectedCrt=if((Get-ShellTerminalAppearance).CRT){'Einschalten'}else{'Ausschalten'}
                        $choice=Select-ShellMenuItem '' @('Einschalten','Ausschalten','Umschalten','← Zurück') -SelectedItem $selectedCrt
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Ansicht';continue}
                        Set-TerminalCrt $(switch($choice){'Einschalten'{'on'} 'Ausschalten'{'off'} default{'toggle'}}) 6>$null
                        $notice=if((Get-ShellTerminalAppearance).CRT){'✓ CRT eingeschaltet'}else{'✓ CRT ausgeschaltet'}
                    }
                    'Fastfetch beim Start' {
                        $selectedGreeting=if((Get-ShellControlPreferences).fastfetch -ne $false){'Einschalten'}else{'Ausschalten'}
                        $choice=Select-ShellMenuItem '' @('Einschalten','Ausschalten','← Zurück') -SelectedItem $selectedGreeting
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Einstellungen';continue}
                        Set-ShellControlPreference fastfetch ($choice -eq 'Einschalten');$notice='✓ Fertig'
                    }
                    'Sprache / Language' {
                        $selectedLanguage=if((Get-ShellMenuLanguage) -eq 'de'){'Deutsch'}else{'English'}
                        $choice=Select-ShellMenuItem '' @('English','Deutsch','← Zurück') -SelectedItem $selectedLanguage
                        if(-not $choice -or $choice -eq '← Zurück'){$page='Einstellungen';continue}
                        Set-ShellMenuLanguage $(if($choice -eq 'English'){'en'}else{'de'});$notice='✓ Fertig'
                    }
                    default {$page='Übersicht'}
                }
            } catch {$notice='Fehler: '+$_.Exception.Message;$page='Übersicht'}
        }
    } finally {[Console]::Write("$esc[?25h$esc[?1049l");[Console]::OutputEncoding=$previousEncoding}
}
function global:commands-menu {Show-ShellMenu}
Set-Alias -Name shell-menu -Value Show-ShellMenu -Scope Global

. (Join-Path $global:ShellControlRoot 'menu-system-info.ps1')
