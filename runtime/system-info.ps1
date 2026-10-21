# Shared fastfetch renderer: aggregate RAM modules without hard-coding their clock.
function global:Show-ShellFastfetch {
    $ffExe = (Find-ShellExecutable fastfetch.exe)
    $cfg = Get-Content -LiteralPath (Join-Path $global:ShellControlRoot 'fastfetch.jsonc') -Raw -Encoding UTF8 | ConvertFrom-Json
    $hardware=Get-ShellHardwareCache
    foreach($module in $cfg.modules){
        if($module -is [string]){continue}
        if($module.format -eq '__LAN_ADAPTER__'){$module.format=if($hardware.Lan){$hardware.Lan}else{'Ethernet'}}
        if($module.format -eq '__WIFI_ADAPTER__'){$module.format=if($hardware.Wifi){$hardware.Wifi}else{'Wi-Fi'}}
        if($module.format -eq '__HOST_FOOTER__'){
            $label=' '+[Environment]::UserName+'@'+[Environment]::MachineName+' '
            if($label.Length -gt 60){$label=$label.Substring(0,59)+' '}
            $left=[int][math]::Floor((74-$label.Length)/2)
            $module.format='  └'+('─'*$left)+'{#36}'+$label+'{#}'+('─'*(74-$left-$label.Length))+'┘'
        }
    }
    try {
        $detected = (& $ffExe --config none --structure PhysicalMemory --format json | Out-String | ConvertFrom-Json)
        $ramModules = @(@($detected)[0].result | Where-Object installed)
        if ($ramModules.Count -gt 0) {
            $sizes = @($ramModules | Group-Object size | ForEach-Object {
                '{0} × {1:0.#} GB' -f $_.Count, ([double]$_.Name / 1GB)
            }) -join ' + '
            $types = @($ramModules.type | Select-Object -Unique) -join '/'
            $speeds = @($ramModules.runningSpeed | Select-Object -Unique) -join '/'
            foreach ($module in $cfg.modules) {
                if ($module -isnot [string] -and $module.type -eq 'custom' -and $module.key -match 'RAM-Kit') {
                    $module.format = "$sizes · $types · $speeds MT/s"
                }
            }
        }
    } catch {
        # Keep the last detected RAM specification if a sensor query fails.
    }
    try {
        $terminalAppearance = Get-ShellTerminalAppearance
        $crtLabel = if ($terminalAppearance.CRT) { 'an' } else { 'aus' }
        foreach ($entry in $cfg.modules) {
            if ($entry -isnot [string] -and $entry.type -eq 'custom' -and $entry.key -match 'Schrift') {
                $entry.format = '{0} · {1} pt · CRT {2}' -f $terminalAppearance.Font, $terminalAppearance.Size, $crtLabel
            }
        }
    } catch {
        foreach ($entry in $cfg.modules) {
            if ($entry -isnot [string] -and $entry.type -eq 'custom' -and $entry.key -match 'Schrift') {
                $entry.format = 'Terminal-Profil nicht verfuegbar'
            }
        }
    }
    # The saved layout is centered in 80 columns; adapt wider consoles at render time.
    $consoleWidth = 80
    if ($Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected) {
        try { $consoleWidth = $Host.UI.RawUI.WindowSize.Width } catch {}
    }
    $extraIndent = [math]::Max(0, [int][math]::Floor(($consoleWidth - 76) / 2) - 2)
    if ($extraIndent -gt 0) {
        $padding = ' ' * $extraIndent
        $cfg.display.key.paddingLeft += $extraIndent
        $cfg.display.key.width += $extraIndent
        foreach ($entry in $cfg.modules) {
            if ($entry -is [string]) { continue }
            if ($entry.type -eq 'title' -or ($entry.type -eq 'custom' -and $entry.format -match '^\s*[┌├└]')) {
                $entry.format = $padding + $entry.format
            }
            if ($entry.type -in @('memory', 'disk')) {
                $entry.format = $entry.format.Replace(([string][char]27 + '[22G'), ([string][char]27 + '[' + (22 + $extraIndent) + 'G'))
            }
        }
    }
    if($Host.Name -eq 'Windows PowerShell ISE Host'){
        foreach($module in $cfg.modules){
            if($module -isnot [string] -and $module.format){
                $module.format=$module.format.Replace(([string][char]27+'[22G'),(' '*22))
            }
        }
    }
    $sessionConfig = Join-Path ([IO.Path]::GetTempPath()) ('fastfetch-session-' + [guid]::NewGuid().ToString('N') + '.jsonc')
    try {
        [IO.File]::WriteAllText($sessionConfig, ($cfg | ConvertTo-Json -Depth 15), (New-Object System.Text.UTF8Encoding($false)))
        if($Host.Name -eq 'Windows PowerShell ISE Host'){
            # ISE has no VT console. Read UTF-8 explicitly and render ordinary host text.
            $start=New-Object Diagnostics.ProcessStartInfo
            $start.FileName=$ffExe
            $start.Arguments='--config "'+$sessionConfig+'" --pipe true'
            $start.UseShellExecute=$false;$start.CreateNoWindow=$true
            $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
            $start.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
            $start.StandardErrorEncoding=New-Object Text.UTF8Encoding($false)
            $process=New-Object Diagnostics.Process
            $process.StartInfo=$start
            try {
                [void]$process.Start()
                $outputTask=$process.StandardOutput.ReadToEndAsync()
                $errorTask=$process.StandardError.ReadToEndAsync()
                if(-not $process.WaitForExit(30000)){$process.Kill();throw 'Fastfetch did not finish within 30 seconds.'}
                $process.WaitForExit()
                $output=$outputTask.GetAwaiter().GetResult()
                $errorText=$errorTask.GetAwaiter().GetResult()
                if($process.ExitCode -ne 0){throw ('Fastfetch failed ('+$process.ExitCode+'): '+$errorText)}
                $plain=[regex]::Replace($output,'\x1b\[[0-?]*[ -/]*[@-~]','')
                Write-Host $plain.TrimEnd()
            } finally {$process.Dispose()}
        }else{& $ffExe --config $sessionConfig}
    } finally {
        if (Test-Path -LiteralPath $sessionConfig) { Remove-Item -LiteralPath $sessionConfig -Force }
    }
}
function global:fastfetch {
    $ffExe = (Find-ShellExecutable fastfetch.exe)
    if ($args.Count -eq 0) { Show-ShellFastfetch; return }
    if ($args -contains '--all' -or $args -contains '-all' -or $args -contains '-a') {
        $filtered = @($args | Where-Object { $_ -notin @('--all','-all','-a') })
        & $ffExe -c all-categorized @filtered
    } else { & $ffExe @args }
}
