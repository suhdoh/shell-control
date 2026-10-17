function global:mkfile {param([Parameter(Mandatory,Position=0)][string]$Path) if(-not(Test-Path -LiteralPath $Path)){New-Item -ItemType File -Path $Path|Out-Null}}
function global:grep {param([Parameter(Mandatory,Position=0)][string]$Pattern,[Parameter(Position=1)][string]$Path='.') Get-ChildItem -Path $Path -Recurse -File|Select-String -Pattern $Pattern}
function global:df {Get-PSDrive -PSProvider FileSystem|Select-Object Name,@{n='Free GB';e={[math]::Round($_.Free/1GB,1)}},@{n='Used GB';e={[math]::Round($_.Used/1GB,1)}}}
# Standard PowerShell aliases provide cat/cp/mv/rm/mkdir/rmdir/pwd/h with native help.
