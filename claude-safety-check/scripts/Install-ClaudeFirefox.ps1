[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$FirefoxPath = 'C:\Program Files\Mozilla Firefox\firefox.exe',
    [string]$ProfilePath = (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles\ClaudeSafe'),
    [ValidateRange(1,65535)][int]$ProxyPort = 7892
)

$ErrorActionPreference='Stop'
if(-not (Test-Path -LiteralPath $FirefoxPath)){throw "Firefox not found: $FirefoxPath. Install it from Mozilla or Microsoft Store first."}

if(-not (Test-Path -LiteralPath $ProfilePath)){
    if($PSCmdlet.ShouldProcess($ProfilePath,'Create isolated Firefox profile directory')){New-Item -ItemType Directory -Path $ProfilePath -Force | Out-Null}
}

$template=Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\firefox\user.js'
$destination=Join-Path $ProfilePath 'user.js'
if($PSCmdlet.ShouldProcess($destination,"Apply privacy-first preferences and DigiLink port $ProxyPort")){
    $content=(Get-Content -Raw -LiteralPath $template).Replace('__PROXY_PORT__',[string]$ProxyPort)
    Set-Content -LiteralPath $destination -Value $content -Encoding UTF8
}

$shortcutName='Claude ' + [char]0x5B89 + [char]0x5FC3 + [char]0x4F7F + [char]0x7528 + '.lnk'
$shortcutPath=Join-Path ([Environment]::GetFolderPath('Desktop')) $shortcutName
if($PSCmdlet.ShouldProcess($shortcutPath,'Create dedicated Firefox shortcut')){
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath=$FirefoxPath
    $shortcut.Arguments="--no-remote --profile `"$ProfilePath`" https://claude.ai/"
    $shortcut.WorkingDirectory=Split-Path $FirefoxPath
    $shortcut.IconLocation="$FirefoxPath,0"
    $shortcut.Description='Open Claude with the isolated Firefox profile'
    $shortcut.Save()
}

[pscustomobject]@{ProfilePath=$ProfilePath;Preferences=$destination;ProxyPort=$ProxyPort;Shortcut=$shortcutPath}

