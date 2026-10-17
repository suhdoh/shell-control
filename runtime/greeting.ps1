# Fastfetch greeting for interactive PowerShell consoles only.
# Set SHELL_NO_GREETING=1 to suppress it for an individual session.
if ($Host.Name -eq 'ConsoleHost' -and
    [Environment]::UserInteractive -and
    -not [Console]::IsOutputRedirected -and
    -not [Console]::IsInputRedirected -and
    $env:SHELL_NO_GREETING -ne '1') {
    $ffExecutable = (Find-ShellExecutable fastfetch.exe)
    if ($ffExecutable -and (Test-Path -LiteralPath $ffExecutable)) {
        Show-ShellFastfetch
    }
}
