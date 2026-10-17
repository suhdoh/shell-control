# Consistent file listings for Windows PowerShell 5.1 and PowerShell 7.
# ANSI palette colors follow the active Windows Terminal theme.
$global:ShellEzaPath = (Find-ShellExecutable eza.exe)
$env:EZA_COLORS = 'reset:fi=37:di=33:ex=32:ln=36:or=31:sn=35:sb=34:da=34:hd=36:xx=90:uu=34:un=34:gu=34:gn=34:im=36:vi=31:mu=35:lo=35:do=37:co=35:tm=90:cm=34:bu=33:sc=32:*.ps1=32:*.cmd=32:*.bat=32:*.json=36:*.jsonc=36:*.yaml=36:*.yml=36:*.zip=35:*.7z=35:*.exe=31:*.msi=31:*.log=34'
if (Test-Path -LiteralPath $global:ShellEzaPath) {
    foreach ($listingName in @('l','la','ll','ls')) {
        Remove-Item -LiteralPath ('Alias:' + $listingName) -Force -ErrorAction SilentlyContinue
    }
    function global:ls { & $global:ShellEzaPath --grid --icons=auto --color=auto --group-directories-first @args }
    function global:l  { & $global:ShellEzaPath --oneline --icons=auto --color=auto --group-directories-first @args }
    function global:la { & $global:ShellEzaPath --grid --all --icons=auto --color=auto --group-directories-first @args }
    function global:ll { & $global:ShellEzaPath --long --all --header --no-permissions --no-user --time-style=long-iso --icons=auto --color=auto --group-directories-first @args }
}
