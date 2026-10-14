[CmdletBinding()]
param(
    [string]$FirefoxPath = 'C:\Program Files\Mozilla Firefox\firefox.exe',
    [string]$ProfilePath = (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles\ClaudeSafe')
)

$ErrorActionPreference='Stop'
if(-not (Test-Path -LiteralPath $FirefoxPath)){throw 'Firefox is not installed at the expected path.'}
if(-not (Test-Path -LiteralPath (Join-Path $ProfilePath 'user.js'))){throw 'The ClaudeSafe profile is not installed. Run Install-ClaudeFirefox.ps1 first.'}
Start-Process -FilePath $FirefoxPath -ArgumentList "--no-remote --profile `"$ProfilePath`" https://claude.ai/"

