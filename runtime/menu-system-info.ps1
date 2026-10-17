function global:Get-ShellSystemSnapshot {
    $previousEncoding=[Console]::OutputEncoding
    try {
        [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
    $exe=(Find-ShellExecutable fastfetch.exe)
    $cfgPath=(Join-Path $global:ShellControlRoot 'fastfetch.jsonc')
    $raw=& $exe --config $cfgPath --format json
    if($LASTEXITCODE -ne 0){throw 'Fastfetch could not read system information.'}
    $modules=($raw -join "`n")|ConvertFrom-Json
    $ramRaw=& $exe --config none --structure PhysicalMemory --format json
    $ram=($ramRaw -join "`n")|ConvertFrom-Json
    $values=@{}
    foreach($module in $modules){if($module.type -notin @('Custom','Break')){$values[$module.type]=$module.result}}
    [pscustomobject]@{Values=$values;Ram=@($ram|Where-Object type -eq 'PhysicalMemory'|ForEach-Object result);Config=(Get-Content $cfgPath -Raw -Encoding UTF8|ConvertFrom-Json);Time=(Get-Date)}
    } finally {[Console]::OutputEncoding=$previousEncoding}
}
function global:Format-ShellSystemGB {
    param([double]$Bytes)
    ($Bytes/1GB).ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)
}
function global:Get-ShellSystemRecords {
    param($Snapshot)
    $d=$Snapshot.Values
    $hardware=Get-ShellHardwareCache
    function Section($name,$color){[pscustomobject]@{Kind='Section';Label=(ConvertTo-ShellMenuText $name);Value='';Icon='';Color=$color;Percent=0}}
    function Row($label,$icon,$value,$color){
        if(-not $value){$value=ConvertTo-ShellMenuText 'Nicht verfügbar'}
        [pscustomobject]@{Kind='Row';Label=(ConvertTo-ShellMenuText $label);Value=[string]$value;Icon=$icon;Color=$color;Percent=0}
    }
    function Usage($label,$icon,$used,$total){
        if($total -le 0){Row $label $icon (ConvertTo-ShellMenuText 'Nicht verfügbar') 32;return}
        $percent=[math]::Min(100,[math]::Max(0,[math]::Round(100*$used/$total)))
        $of=ConvertTo-ShellMenuText 'von'
        Row $label $icon ((Format-ShellSystemGB $used)+' '+$of+' '+(Format-ShellSystemGB $total)+' GB · '+$percent+'%') 32
        [pscustomobject]@{Kind='Bar';Label='';Icon='';Value='';Color=32;Percent=$percent}
    }
    Section 'System' 35
    Row 'Windows' '' ($d.OS.prettyName+' · '+$d.Kernel.architecture) 35
    Row 'Build' '' $d.Kernel.release 35
    Row 'BIOS' '' ($d.BIOS.version+' · '+$d.BIOS.type) 35
    $up=[timespan]::FromMilliseconds([double]$d.Uptime.uptime)
    Row 'Laufzeit' '' ('{0}d {1}h {2}m' -f $up.Days,$up.Hours,$up.Minutes) 35
    Section 'Sitzung' 36
    Row 'Shell' '' ('PowerShell '+$PSVersionTable.PSVersion) 36
    Row 'Terminal' '' ($d.Terminal.prettyName+' '+$d.Terminal.version) 36
    Section 'Hardware' 32
    Row 'CPU' '' ($d.CPU.cpu+' · '+$d.CPU.cores.physical+'C/'+$d.CPU.cores.logical+'T') 32
    Row 'Board' '' $d.Board.name 32
    foreach($gpu in @($d.GPU)){
        if(-not $gpu){continue}
        $value=$gpu.name+' · '+(Format-ShellSystemGB $gpu.memory.dedicated.total)+' GB'
        if($null -ne $gpu.temperature){$value+=' · '+([double]$gpu.temperature).ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)+'°C'}
        Row 'GPU' '' $value 32
    }
    $ram=@($Snapshot.Ram|Where-Object installed)
    if($ram.Count){
        $sizes=@($ram|Group-Object size|ForEach-Object {[string]$_.Count+' × '+(Format-ShellSystemGB ([double]$_.Name))+' GB'}) -join ' + '
        Row 'RAM-Kit' '' ($sizes+' · '+(@($ram.type|Select-Object -Unique) -join '/')+' · '+(@($ram.runningSpeed|Select-Object -Unique) -join '/')+' MT/s') 32
    }
    Usage 'RAM' '' ([double]$d.Memory.used) ([double]$d.Memory.total)
    foreach($disk in @($d.PhysicalDisk)){if($disk){Row 'SSD' '' ($disk.name+' · '+$disk.interconnect) 32}}
    foreach($disk in @($d.Disk)){
        if($disk){Usage ('SSD '+$disk.mountpoint.TrimEnd('\')) '' ([double]$disk.bytes.total-[double]$disk.bytes.free) ([double]$disk.bytes.total)}
    }
    foreach($display in @($d.Display)){
        if(-not $display){continue}
        $hdr=ConvertTo-ShellMenuText $(if($display.hdrStatus -eq 'Enabled'){'an'}else{'aus'})
        Row 'Monitor' '' ($display.output.width.ToString()+'×'+$display.output.height+' · '+[math]::Round($display.output.refreshRate)+' Hz · '+[math]::Round([math]::Sqrt([math]::Pow($display.physical.width,2)+[math]::Pow($display.physical.height,2))/25.4)+'" · HDR '+$hdr) 32
    }
    Section 'Netzwerk' 36
    $lan=$Snapshot.Config.modules|Where-Object {$_ -isnot [string] -and $_.key -match '^\s*LAN-Karte'}|Select-Object -First 1
    Row 'LAN-Karte' '' $hardware.Lan 36
    foreach($net in @($d.LocalIp)){
        if(-not $net){continue}
        $speed=if($net.speed -ge 1000){([double]$net.speed/1000).ToString('0.#',[Globalization.CultureInfo]::InvariantCulture)+' Gbps'}else{[string]$net.speed+' Mbps'}
        Row 'LAN' '' ($net.name+' · '+$net.ipv4+' · '+$speed) 36
    }
    $wifiCard=$Snapshot.Config.modules|Where-Object {$_ -isnot [string] -and $_.key -match '^\s*WLAN-Karte'}|Select-Object -First 1
    Row 'WLAN-Karte' '' $hardware.Wifi 36
    foreach($wifi in @($d.Wifi)){
        if(-not $wifi){continue}
        $value=if($wifi.conn.ssid){$wifi.conn.ssid+' · '+$wifi.conn.signalQuality+'%'}else{ConvertTo-ShellMenuText 'Nicht verbunden'}
        Row 'WLAN' '' $value 36
    }
    Section 'Medien' 35
    foreach($radio in @($d.BluetoothRadio)){
        if($radio){
            # Same LMP-to-version mapping used by Fastfetch's BluetoothRadio module.
            $versions=@('1.0b','1.1','1.2','2.0','2.1','3.0','4.0','4.1','4.2','5.0','5.1','5.2','5.3','5.4','6.0','6.1','6.2','6.3')
            $lmp=if($null -ne $radio.lmpVersion){[math]::Abs([int]$radio.lmpVersion)}else{-1}
            $protocol=if($lmp -ge 0 -and $lmp -lt $versions.Count){' · Bluetooth '+$versions[$lmp]}else{''}
            Row 'Bluetooth' '' ($radio.vendor+$protocol+' · '+(ConvertTo-ShellMenuText $(if($radio.enabled){'Eingeschaltet'}else{'Ausgeschaltet'}))) 35
        }
    }
    foreach($audio in @($d.Sound)){if($audio){Row 'Audio' '' ($audio.name+' · '+$audio.volume+'%') 35}}
}
function global:ConvertTo-ShellSystemLines {
    param([object[]]$Records,[ValidateRange(30,200)][int]$Width)
    $esc=[char]27
    $indent=[math]::Min(18,[math]::Max(12,[int]($Width/3)))
    $valueWidth=$Width-$indent
    $lines=New-Object 'Collections.Generic.List[object]'
    foreach($record in $Records){
        if($record.Kind -eq 'Section'){
            if($lines.Count){$lines.Add([pscustomobject]@{Plain='';Text='';Section=$false})}
            $title=' '+$record.Label+' '
            $left=[math]::Max(1,[math]::Floor(($Width-$title.Length)/2))
            $plain=('─'*$left)+$title+('─'*([math]::Max(0,$Width-$left-$title.Length)))
            $lines.Add([pscustomobject]@{Plain=$plain;Text=($esc+'['+$record.Color+'m'+$plain+$esc+'[0m');Section=$true})
        } elseif($record.Kind -eq 'Bar'){
            $length=[math]::Min(36,$valueWidth)
            $filled=[int][math]::Round($length*$record.Percent/100)
            $plain=(' '*$indent)+('█'*$length)
            $text=(' '*$indent)+$esc+'[32m'+('█'*$filled)+$esc+'[90m'+('█'*($length-$filled))+$esc+'[0m'
            $lines.Add([pscustomobject]@{Plain=$plain;Text=$text;Section=$false})
        } else {
            $keyWidth=$indent-4
            $label=$record.Label
            if($label.Length -gt $keyWidth){$label=$label.Substring(0,$keyWidth-1)+'…'}
            $prefix=$label.PadLeft($keyWidth)+' '+$record.Icon+'  '
            $rest=$record.Value
            $first=$true
            while($rest.Length){
                $take=[math]::Min($valueWidth,$rest.Length)
                if($take -lt $rest.Length){$space=$rest.LastIndexOf(' ',$take-1,$take);if($space -gt [math]::Floor($valueWidth/2)){$take=$space}}
                $part=$rest.Substring(0,$take)
                $plainPrefix=if($first){$prefix}else{' '*$indent}
                $plain=$plainPrefix+$part
                $text=if($first){$esc+'['+$record.Color+'m'+$prefix+$esc+'[0m'+$part}else{$plain}
                $lines.Add([pscustomobject]@{Plain=$plain;Text=$text;Section=$false})
                $rest=$rest.Substring($take).TrimStart();$first=$false
            }
        }
    }
    $lines.ToArray()
}
function global:Show-ShellSystemInfo {
    Write-ShellMenuFrame 'Systeminfo' (ConvertTo-ShellMenuText 'Systeminformationen werden geladen …') -Hint 'R aktualisiert die Werte · Esc kehrt zur Übersicht zurück'
    $snapshot=Get-ShellSystemSnapshot
    $records=@(Get-ShellSystemRecords $snapshot)
    $offset=0;$dirty=$true;$lastSize='';$esc=[char]27
    $previousCtrlC=[Console]::TreatControlCAsInput
    try {
        [Console]::TreatControlCAsInput=$true
        while($true){
            $layout=Get-ShellMenuLayout
            $size=[string]$layout.Columns+'x'+$layout.Rows
            if($size -ne $lastSize){$dirty=$true;$lastSize=$size}
            if($dirty){
                Write-ShellMenuFrame 'Systeminfo' ((ConvertTo-ShellMenuText 'Momentaufnahme: ')+$snapshot.Time.ToString('HH:mm:ss')) -Hint 'R aktualisiert die Werte · Esc kehrt zur Übersicht zurück'
                $width=[math]::Max(30,[math]::Min(120,$layout.Columns-6))
                $margin=[math]::Max(2,[int][math]::Floor(($layout.Columns-$width)/2))
                $lines=@(ConvertTo-ShellSystemLines -Records $records -Width $width)
                $height=[math]::Max(1,$layout.Rows-12)
                $offset=[math]::Min($offset,[math]::Max(0,$lines.Count-$height))
                $out=New-Object Text.StringBuilder
                [void]$out.Append("$esc[?25l")
                for($row=8;$row -lt $layout.Rows;$row++){[void]$out.Append("$esc[$($row);1H$esc[0m$esc[2K")}
                for($i=0;$i -lt $height -and $offset+$i -lt $lines.Count;$i++){
                    [void]$out.Append("$esc[$(8+$i);$($margin+1)H$($lines[$offset+$i].Text)$esc[0m")
                }
                $bottom=$layout.Rows-4
                $rule='─'*$layout.Width
                $range=[string]($offset+1)+'–'+[math]::Min($lines.Count,$offset+$height)+' / '+$lines.Count
                $refresh=ConvertTo-ShellMenuText '↑↓ / PgUp / PgDn · R neu laden'
                $back=ConvertTo-ShellMenuText '← Zurück · Esc / Q / Enter'
                [void]$out.Append("$esc[$($bottom);3H$esc[90m$rule$esc[0m")
                $footer=$range+'  ·  '+$refresh
                if($footer.Length -gt $layout.Width){$footer=$footer.Substring(0,$layout.Width)}
                [void]$out.Append("$esc[$($bottom+1);3H$esc[90m$footer$esc[0m")
                [void]$out.Append("$esc[$($bottom+2);3H$esc[36m$back$esc[0m")
                [Console]::Write($out.ToString());$dirty=$false
            }
            if(-not [Console]::KeyAvailable){Start-Sleep -Milliseconds 40;continue}
            $key=[Console]::ReadKey($true)
            if($key.Key -in @([ConsoleKey]::Escape,[ConsoleKey]::Q,[ConsoleKey]::Enter) -or (($key.Modifiers -band [ConsoleModifiers]::Control) -and $key.Key -eq [ConsoleKey]::C)){return}
            switch($key.Key){
                'UpArrow' {$offset=[math]::Max(0,$offset-1)}
                'DownArrow' {$offset++}
                'PageUp' {$offset=[math]::Max(0,$offset-$height)}
                'PageDown' {$offset+=$height}
                'Home' {$offset=0}
                'End' {$offset=$lines.Count}
                'R' {$snapshot=Get-ShellSystemSnapshot;$records=@(Get-ShellSystemRecords $snapshot)}
            }
            $dirty=$true
        }
    } finally {[Console]::TreatControlCAsInput=$previousCtrlC;[Console]::Write("$esc[0m$esc[?25h")}
}
