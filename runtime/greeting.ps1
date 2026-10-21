# Fastfetch greeting in interactive console and ISE hosts.
# Set SHELL_NO_GREETING=1 to suppress it for an individual session.
$shellControlInteractiveHost=$Host.Name -eq 'Windows PowerShell ISE Host'
if($Host.Name -eq 'ConsoleHost'){
    $shellControlInteractiveHost=-not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected
}
if ($shellControlInteractiveHost -and [Environment]::UserInteractive -and $env:SHELL_NO_GREETING -ne '1') {
    $ffExecutable = (Find-ShellExecutable fastfetch.exe)
    if ($ffExecutable -and (Test-Path -LiteralPath $ffExecutable)) { Show-ShellFastfetch }
}
