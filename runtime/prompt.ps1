# Minimal shared prompt for Windows PowerShell 5.1 and PowerShell 7.
function global:prompt {
    $promptLocation = $executionContext.SessionState.Path.CurrentLocation.Path
    $promptHome = [Environment]::GetFolderPath('UserProfile')
    if ($promptLocation.Equals($promptHome, [StringComparison]::OrdinalIgnoreCase)) {
        $promptLocation = '~'
    } elseif ($promptLocation.StartsWith($promptHome + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $promptLocation = '~' + $promptLocation.Substring($promptHome.Length)
    }
    $promptUser = [Environment]::UserName
    $promptTime = [DateTime]::Now.ToString('HH:mm:ss')
    Write-Host $promptUser -ForegroundColor Yellow -NoNewline
    Write-Host ' in ' -ForegroundColor Gray -NoNewline
    Write-Host $promptLocation -ForegroundColor Cyan -NoNewline
    Write-Host ('  ' + $promptTime) -ForegroundColor DarkGray
    Write-Host ([char]0x276F) -ForegroundColor Green -NoNewline
    return ' '
}
