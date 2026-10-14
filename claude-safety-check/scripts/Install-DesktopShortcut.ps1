[CmdletBinding(SupportsShouldProcess)]
param([string]$Name='Claude 安心检查')

$dashboard=Join-Path $PSScriptRoot 'Show-ClaudeSafetyDashboard.ps1'
$desktop=[Environment]::GetFolderPath('Desktop')
$shortcut=Join-Path $desktop "$Name.lnk"
if($PSCmdlet.ShouldProcess($shortcut,'Create desktop shortcut')){
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut($shortcut)
    $link.TargetPath=(Get-Command powershell.exe).Source
    $link.Arguments="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dashboard`""
    $link.WorkingDirectory=(Split-Path $dashboard)
    $link.Description='打开 Claude 使用环境安全检查面板'
    $link.Save()
    Write-Output $shortcut
}

