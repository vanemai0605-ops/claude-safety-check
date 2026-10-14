[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$ConfigPath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

function Read-JsonFile([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json }
    catch { return $null }
}

function Add-Check {
    param([string]$Id,[string]$Category,[string]$Title,[string]$Status,[string]$Summary,[object[]]$Evidence,[string]$Remediation,[bool]$Automated=$true)
    $script:Checks.Add([pscustomobject]@{
        id=$Id; category=$Category; title=$Title; status=$Status; summary=$Summary
        evidence=@($Evidence | Where-Object { $_ -ne $null -and "$_" -ne '' })
        remediation=$Remediation; automated=$Automated
    })
}

function Mask-Ip([string]$Ip) {
    if (-not $Ip) { return $Ip }
    if ($Ip -match '^\d+\.\d+\.\d+\.\d+$') {
        $p=$Ip.Split('.'); return "$($p[0]).$($p[1]).x.x"
    }
    if ($Ip.Contains(':')) { return (($Ip.Split(':') | Select-Object -First 3) -join ':') + ':…' }
    return $Ip
}

function Redact-Proxy([string]$Value) {
    if (-not $Value) { return $Value }
    return ($Value -replace '(?i)(https?://)[^/@\s]+@','$1***@')
}

function Get-IniProfiles([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $result=@(); $current=$null
    foreach($line in Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue) {
        if($line -match '^\[Profile') { if($current){$result += [pscustomobject]$current}; $current=@{} }
        elseif($current -and $line -match '^([^=]+)=(.*)$') { $current[$matches[1]]=$matches[2] }
    }
    if($current){$result += [pscustomobject]$current}
    return @($result)
}

function Get-FirefoxPrefValue([string[]]$Files,[string]$Name) {
    $escaped=[regex]::Escape($Name)
    $pattern='user_pref\("' + $escaped + '",\s*(.+?)\s*\);'
    foreach($file in $Files){
        if(-not (Test-Path -LiteralPath $file)){continue}
        $hits=Select-String -LiteralPath $file -Pattern $pattern -AllMatches -ErrorAction SilentlyContinue
        if($hits){
            $raw=$hits[-1].Matches[-1].Groups[1].Value.Trim()
            if($raw -eq 'true'){return $true}
            if($raw -eq 'false'){return $false}
            if($raw -match '^\"(.*)\"$'){return $matches[1]}
            $number=0
            if([int]::TryParse($raw,[ref]$number)){return $number}
            return $raw
        }
    }
    return $null
}

$Config = Read-JsonFile $ConfigPath
$script:Checks = [System.Collections.Generic.List[object]]::new()

Add-Check 'account-review' '账号与付款' '账号资料与付款真实性' 'unknown' '本机检查不会读取账号、付款或账单资料。' @('需人工核对；不要把敏感付款资料写入报告') '确认资料真实且付款方式受官方支持。' $false

$tz=(Get-TimeZone).Id
$expectedTz=$Config.expected.timeZoneId
$tzStatus=if($expectedTz){if($tz -eq $expectedTz){'pass'}else{'risk'}}else{'info'}
$tzSummary=if($expectedTz){"当前 $tz；期望 $expectedTz"}else{"当前 $tz；未配置期望值"}
Add-Check 'timezone' '设备环境' '系统时区' $tzStatus $tzSummary @("TimeZoneId=$tz") '在配置文件中填写期望时区；不一致时先确认实际所在地和工作需求。'

$culture=[System.Globalization.CultureInfo]::CurrentCulture.Name
$uiCulture=[System.Globalization.CultureInfo]::CurrentUICulture.Name
$langList=@($culture,$uiCulture | Select-Object -Unique)
$expectedLang=@($Config.expected.languages | Where-Object {$_})
$langStatus=if($expectedLang.Count -gt 0){if(@($langList | Where-Object {$_ -notin $expectedLang}).Count -eq 0){'pass'}else{'review'}}else{'info'}
Add-Check 'language' '设备环境' '系统与界面语言' $langStatus "当前语言：$($langList -join ', ')" @($langList | ForEach-Object {"Language=$_"}) '核对系统语言、浏览器语言和键盘布局是否仍符合你的实际使用环境。'

$keyboardEvidence=@()
try{
    $preload=Get-ItemProperty -LiteralPath 'HKCU:\Keyboard Layout\Preload' -ErrorAction Stop
    $keyboardEvidence=@($preload.PSObject.Properties | Where-Object {$_.Name -match '^\d+$'} | ForEach-Object {"Layout $($_.Name)=$($_.Value)"})
}catch{}
$keyboardStatus=if($keyboardEvidence.Count){'info'}else{'unknown'}
Add-Check 'keyboard-layout' '设备环境' '键盘布局' $keyboardStatus '已盘点当前用户的预加载键盘布局。' $keyboardEvidence '确认旧设备或重装系统遗留的布局是否仍符合实际使用。'

$profilesIni=Join-Path $env:APPDATA 'Mozilla\Firefox\profiles.ini'
$profiles=Get-IniProfiles $profilesIni
$claudeSafePath=Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles\ClaudeSafe'
if((Test-Path -LiteralPath $claudeSafePath) -and -not @($profiles | Where-Object {$_.Path -eq $claudeSafePath}).Count){
    $profiles += [pscustomobject]@{Name='ClaudeSafe';IsRelative='0';Path=$claudeSafePath;Default='0';Direct='1'}
}
$pattern=if($Config.firefox.dedicatedProfileNamePattern){$Config.firefox.dedicatedProfileNamePattern}else{'claude|private'}
$namedMatches=@($profiles | Where-Object {$_.Name -match $pattern -or $_.Path -eq $claudeSafePath})
$claudeSafeExists=Test-Path -LiteralPath $claudeSafePath
$profileStatus=if($claudeSafeExists){'pass'}elseif(-not (Test-Path -LiteralPath $profilesIni)){'unknown'}elseif($pattern -and $namedMatches.Count -gt 0){'review'}else{'review'}
$profileEvidence=@($profiles | ForEach-Object {"Profile=$($_.Name); Default=$($_.Default); Path=$($_.Path)"})
$profileSummary=if($claudeSafeExists){'已找到独立 ClaudeSafe Profile。'}elseif($namedMatches.Count){'发现名称相似的 Profile，但未确认是预期的 ClaudeSafe 目录。'}else{'未找到 ClaudeSafe 专用 Profile。'}
Add-Check 'firefox-profile' '浏览器隔离' 'Firefox 专用 Profile' $profileStatus $profileSummary $profileEvidence '使用独立 Profile 隔离 Claude 登录、Cookie、权限和扩展。'

$httpProgId=$null
try{$httpProgId=(Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice' -ErrorAction Stop).ProgId}catch{}
$shortcutPath=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude 安心使用.lnk'
$shortcutArgs=$null
try{if(Test-Path -LiteralPath $shortcutPath){$shortcutArgs=(New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath).Arguments}}catch{}
$shortcutValid=$shortcutArgs -match '(?i)--profile' -and $shortcutArgs -match [regex]::Escape($claudeSafePath)
$defaultStatus=if($shortcutValid){'pass'}else{'review'}
$defaultSummary=if($shortcutValid){'专用快捷方式会强制启动 ClaudeSafe；无需更改默认浏览器。'}else{'未验证到正确的 ClaudeSafe 专用快捷方式。'}
Add-Check 'default-browser' '浏览器隔离' 'Claude 专用启动入口' $defaultStatus $defaultSummary @("DefaultHTTP=$httpProgId","Shortcut=$shortcutPath") '始终从“Claude 安心使用”快捷方式打开；普通外链继续进入默认浏览器不构成失败。'

$claudePrefFiles=@((Join-Path $claudeSafePath 'user.js'),(Join-Path $claudeSafePath 'prefs.js'))
$webrtcValue=Get-FirefoxPrefValue $claudePrefFiles 'media.peerconnection.enabled'
$webrtcEvidence=if($null -ne $webrtcValue){@("ClaudeSafe media.peerconnection.enabled=$webrtcValue")}else{@()}
$webrtcStatus=if($webrtcValue -eq $false){'pass'}elseif($claudeSafeExists){'review'}else{'unknown'}
$webrtcSummary=if($webrtcValue -eq $false){'ClaudeSafe Profile 已关闭 WebRTC PeerConnection。'}elseif($claudeSafeExists){'ClaudeSafe Profile 未确认关闭 WebRTC。'}else{'没有 ClaudeSafe Profile，无法核对。'}
Add-Check 'webrtc' '浏览器隔离' 'Firefox WebRTC' $webrtcStatus $webrtcSummary $webrtcEvidence '仅在不依赖 WebRTC 时关闭；应针对实际 Claude 专用 Profile 核对。'

$proxyType=Get-FirefoxPrefValue $claudePrefFiles 'network.proxy.type'
$proxyHost=Get-FirefoxPrefValue $claudePrefFiles 'network.proxy.http'
$proxyPort=Get-FirefoxPrefValue $claudePrefFiles 'network.proxy.http_port'
$proxySslHost=Get-FirefoxPrefValue $claudePrefFiles 'network.proxy.ssl'
$proxySslPort=Get-FirefoxPrefValue $claudePrefFiles 'network.proxy.ssl_port'
$failoverDirect=Get-FirefoxPrefValue $claudePrefFiles 'network.proxy.failover_direct'
$allowBypass=Get-FirefoxPrefValue $claudePrefFiles 'network.proxy.allow_bypass'
$proxyGuardConfigured=($proxyType -eq 1 -and $proxyHost -in @('127.0.0.1','localhost') -and $proxyPort -gt 0 -and $proxySslHost -in @('127.0.0.1','localhost') -and $proxySslPort -eq $proxyPort -and $failoverDirect -eq $false -and $allowBypass -eq $false)
$proxyGuardEvidence=@("type=$proxyType","HTTP=$proxyHost`:$proxyPort","HTTPS=$proxySslHost`:$proxySslPort","failover_direct=$failoverDirect","allow_bypass=$allowBypass")
$proxyGuardStatus=if($proxyGuardConfigured){'pass'}elseif($claudeSafeExists){'risk'}else{'unknown'}
$proxyGuardSummary=if($proxyGuardConfigured){'ClaudeSafe 已固定使用本地代理，并禁止失败后直接联网。'}elseif($claudeSafeExists){'ClaudeSafe 未形成完整的本地代理闭锁配置。'}else{'没有 ClaudeSafe Profile，无法核对代理闭锁。'}
Add-Check 'firefox-proxy-guard' '网络链路' 'ClaudeSafe 代理闭锁' $proxyGuardStatus $proxyGuardSummary $proxyGuardEvidence '必须同时固定 HTTP/HTTPS 本地代理并关闭直连回退；不要用“存在代理”代替断线实测。'

$inet=$null
try{$inet=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop}catch{}
$proxyEvidence=@(); $proxyListeners=@()
if($inet){$proxyEvidence += "ProxyEnable=$($inet.ProxyEnable)"; if($inet.ProxyServer){$proxyEvidence += 'ProxyServer='+(Redact-Proxy "$($inet.ProxyServer)")}; if($inet.AutoConfigURL){$proxyEvidence += 'PAC='+(Redact-Proxy "$($inet.AutoConfigURL)")}}
try{$winHttp=(netsh winhttp show proxy 2>$null | Out-String).Trim(); if($winHttp){$proxyEvidence += ($winHttp -replace '\r?\n',' | ')}}catch{}
foreach($n in 'HTTP_PROXY','HTTPS_PROXY','NO_PROXY'){$v=[Environment]::GetEnvironmentVariable($n,'Process'); if($v){$proxyEvidence += "$n=$(Redact-Proxy $v)"}}
try{
    $commonProxyPorts=@(1080,3128,7890,7891,7892,8080,8118,9090)
    if($proxyPort -gt 0){$commonProxyPorts += [int]$proxyPort}
    $proxyListeners=@(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object {$_.LocalPort -in ($commonProxyPorts | Select-Object -Unique)})
    foreach($listener in $proxyListeners){
        $owner=Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
        $ownerName=if($owner){$owner.ProcessName}else{'unknown'}
        $proxyEvidence += "LocalListener=$($listener.LocalAddress):$($listener.LocalPort); Process=$ownerName"
    }
}catch{}
$proxyStatus=if($proxyEvidence.Count -gt 0){'info'}else{'unknown'}
Add-Check 'proxy-layers' '网络链路' 'Proxy 多层配置' $proxyStatus '已盘点 Windows、PAC、WinHTTP 与当前进程环境变量。' $proxyEvidence '核对遗留代理、应用内代理与本地代理程序；存在配置不代表流量一定经过它。'

$configuredListener=@($proxyListeners | Where-Object {$_.LocalPort -eq $proxyPort -and $_.LocalAddress -in @('127.0.0.1','0.0.0.0','::','::1')})
$listenerStatus=if(-not $proxyGuardConfigured){'unknown'}elseif($configuredListener.Count){'pass'}else{'review'}
$listenerSummary=if($configuredListener.Count){"DigiLink 本地代理端口 $proxyPort 正在监听。"}elseif($proxyGuardConfigured){"ClaudeSafe 已配置端口 $proxyPort，但当前没有监听；现在不要打开 Claude。"}else{'未形成可核对的 ClaudeSafe 代理配置。'}
$listenerEvidence=@($configuredListener | ForEach-Object {
    $owner=Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
    "Listener=$($_.LocalAddress):$($_.LocalPort); Process=$(if($owner){$owner.ProcessName}else{'unknown'})"
})
Add-Check 'proxy-listener' '网络链路' 'DigiLink 本地代理状态' $listenerStatus $listenerSummary $listenerEvidence '先启动并连接 DigiLink，再打开 ClaudeSafe；端口存在只证明本地代理运行，不证明公网出口位置。'

$dnsEvidence=@()
try{$dnsEvidence=@(Get-DnsClientServerAddress -ErrorAction Stop | Where-Object {$_.ServerAddresses.Count -gt 0} | ForEach-Object {"$($_.InterfaceAlias) [$($_.AddressFamily)]: $($_.ServerAddresses -join ', ')"})}catch{}
$dnsStatus=if($dnsEvidence.Count){'info'}else{'unknown'}
Add-Check 'dns' '网络链路' '系统 DNS' $dnsStatus '记录系统网卡 DNS；浏览器安全 DNS 仍需单独核对。' $dnsEvidence '对照预期解析器，并用独立 DNS 泄漏测试验证实际路径。'

$ipEvidence=@()
try{$ipEvidence=@(Get-NetIPAddress -AddressFamily IPv4,IPv6 -ErrorAction Stop | Where-Object {$_.AddressState -eq 'Preferred' -and $_.IPAddress -notmatch '^(127\.|::1|fe80:)'} | ForEach-Object {"$($_.InterfaceAlias): $(Mask-Ip $_.IPAddress) [$($_.AddressFamily)]"})}catch{}
$ipStatus=if($ipEvidence.Count){'info'}else{'unknown'}
Add-Check 'ip-stack' '网络链路' 'IPv4 / IPv6 接口' $ipStatus '仅盘点本机接口；不能替代公网出口检查。' $ipEvidence '同时验证 IPv4、IPv6 和实际出口，避免只检查一种协议。'

Add-Check 'public-egress' '网络链路' '公网出口' 'unknown' '离线守卫不会联系公网查询服务，因此不采集公网 IP。' @('本次检查没有为此项目发送网络请求') '若确实需要出口验证，请在浏览器中自行选择可信服务；其结果也只代表该应用的一次请求。' $false

$routeEvidence=@()
try{
    $routeEvidence=@(Get-NetRoute -ErrorAction Stop | Where-Object {$_.DestinationPrefix -in '0.0.0.0/0','::/0'} | Sort-Object RouteMetric | ForEach-Object {"$($_.DestinationPrefix) via $($_.InterfaceAlias); metric=$($_.RouteMetric)"})
}catch{}
$routeStatus=if($routeEvidence.Count){'info'}else{'unknown'}
Add-Check 'default-routes' '网络链路' '默认路由' $routeStatus '自动盘点 IPv4 与 IPv6 默认路由，不向外发包。' $routeEvidence '确认实际受保护的接口同时覆盖 IPv4 与 IPv6。'

$processEvidence=@(); $processPaths=@(); $processCounts=@{}
foreach($processName in 'firefox','claude','claude-code'){
    foreach($process in @(Get-Process -Name $processName -ErrorAction SilentlyContinue)){
        $path=$null; try{$path=$process.Path}catch{}
        $processCounts[$process.ProcessName]=1+[int]$processCounts[$process.ProcessName]
        if($path){$processPaths += $path}
    }
}
$processEvidence=@($processCounts.GetEnumerator() | Sort-Object Name | ForEach-Object {"$($_.Name): $($_.Value) 个进程"})
$processStatus='info'
$processSummary=if($processEvidence.Count){'检测到相关进程，已纳入防火墙规则比对。'}else{'当前未检测到相关进程。'}
Add-Check 'protected-processes' '网络链路' 'Claude / Firefox 相关进程' $processStatus $processSummary $processEvidence '进程存在不代表发生了联网；用于核对保护规则是否覆盖实际可执行文件。'

$firewallEvidence=@(); $matchedPrograms=@(); $firewallRead=$false
try{
    $blockRules=Get-NetFirewallRule -Enabled True -Direction Outbound -Action Block -ErrorAction Stop
    $firewallRead=$true
    foreach($rule in $blockRules){
        $filter=$rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
        if($filter.Program -and $filter.Program -ne 'Any'){
            $firewallEvidence += "Rule=$($rule.DisplayName); Program=$([IO.Path]::GetFileName($filter.Program))"
            if($processPaths -contains $filter.Program){$matchedPrograms += $filter.Program}
        }
    }
}catch{}
$firewallStatus=if($firewallRead){'info'}else{'unknown'}
$firewallSummary=if($matchedPrograms.Count){"$($matchedPrograms.Count) 个运行中程序路径匹配已启用的出站阻止规则。"}elseif($processPaths.Count){'未观察到运行中相关程序与出站阻止规则的路径匹配。'}else{'未运行相关程序，无法按实际路径比对。'}
Add-Check 'firewall-coverage' '网络链路' '防火墙规则盘点' $firewallStatus $firewallSummary ($firewallEvidence | Select-Object -First 8) '阻止规则通常优先于允许规则；规则存在不等于断线保护成立，不能据此显示“通过”。'

Add-Check 'kill-switch' '网络链路' '断线保护实测' 'unknown' '为避免主动中断连接，自动检查不会执行断线测试。' @('需要在关闭 Claude 后用普通测试页单独验证') '断开专用网络后，受保护程序应无法打开新网页；任何防火墙改动都需单独授权。' $false

$locValue=$null
try{$locValue=(Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -ErrorAction Stop).Value}catch{}
$locStatus=if($locValue -eq 'Deny'){'pass'}elseif($locValue -eq 'Allow'){'info'}else{'unknown'}
$locSummary=if($locValue){"当前用户设置：$locValue"}else{'未读取到明确设置'}
Add-Check 'windows-location' '定位权限' 'Windows 定位权限' $locStatus $locSummary @("ConsentStore=$locValue") '按实际需要管理系统定位；权限开放不等于功能被调用。'

$geoValue=Get-FirefoxPrefValue $claudePrefFiles 'geo.enabled'
$geoDefault=Get-FirefoxPrefValue $claudePrefFiles 'permissions.default.geo'
$geoEvidence=@("ClaudeSafe geo.enabled=$geoValue","ClaudeSafe permissions.default.geo=$geoDefault")
$geoDisabled=($geoValue -eq $false -and $geoDefault -eq 2)
$geoStatus=if($geoDisabled){'pass'}elseif($claudeSafeExists){'review'}else{'unknown'}
$geoSummary=if($geoDisabled){'ClaudeSafe 已关闭网页定位，并默认拒绝新的定位请求。'}elseif($claudeSafeExists){'ClaudeSafe 的网页定位保护不完整。'}else{'没有 ClaudeSafe Profile，无法核对。'}
Add-Check 'firefox-location' '定位权限' 'Firefox 定位' $geoStatus $geoSummary $geoEvidence '打开 Firefox 网站权限，核对 Claude 站点和不必要的第三方定位授权。'

$settingsPaths=@(
    (Join-Path $env:USERPROFILE '.claude\settings.json'),
    (Join-Path $env:USERPROFILE '.claude\settings.local.json'),
    (Join-Path (Get-Location) '.claude\settings.json'),
    (Join-Path (Get-Location) '.claude\settings.local.json')
) | Select-Object -Unique
$permissionEvidence=@(); $allowCount=0; $denyCount=0; $askCount=0
foreach($sp in $settingsPaths){$s=Read-JsonFile $sp; if($s){foreach($key in 'allow','deny','ask'){$vals=@($s.permissions.$key); if($vals.Count){$permissionEvidence += "$sp :: $key=$($vals.Count)"; if($key -eq 'allow'){$allowCount += $vals.Count}; if($key -eq 'deny'){$denyCount += $vals.Count}; if($key -eq 'ask'){$askCount += $vals.Count}}}}}
$claudeCommand=Get-Command claude -ErrorAction SilentlyContinue
$projectsRoot=Join-Path $env:USERPROFILE '.claude\projects'
$hasClaudeSettings=@($settingsPaths | Where-Object {Test-Path -LiteralPath $_}).Count -gt 0
$hasProjectLogs=(Test-Path -LiteralPath $projectsRoot) -and [bool](Get-ChildItem -LiteralPath $projectsRoot -Filter '*.jsonl' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)
$claudePresent=[bool]$claudeCommand -or $hasClaudeSettings -or $hasProjectLogs
$permStatus=if(-not $claudePresent){'na'}elseif($allowCount -gt 0){'review'}elseif($denyCount+$askCount -gt 0){'pass'}else{'unknown'}
Add-Check 'claude-permissions' 'Claude Code' '配置的工具权限' $permStatus "allow=$allowCount, ask=$askCount, deny=$denyCount" $permissionEvidence '逐条核对授权范围。allow 表示配置能力，不表示已执行或已传输内容。'

$lookback=if($Config.claudeCode.activityLookbackDays){[int]$Config.claudeCode.activityLookbackDays}else{7}
$activityEvidence=@(); $toolCounts=@{}
if(Test-Path -LiteralPath $projectsRoot){
    $files=Get-ChildItem -LiteralPath $projectsRoot -Filter '*.jsonl' -Recurse -File -ErrorAction SilentlyContinue | Where-Object {$_.LastWriteTime -ge (Get-Date).AddDays(-$lookback)} | Select-Object -First 200
    foreach($f in $files){
        foreach($m in Select-String -LiteralPath $f.FullName -Pattern '"name"\s*:\s*"(Bash|Read|Write|Edit|Glob|Grep|WebFetch|WebSearch|NotebookEdit|Task)"' -AllMatches -ErrorAction SilentlyContinue){foreach($hit in $m.Matches){$name=$hit.Groups[1].Value; $toolCounts[$name]=1+[int]$toolCounts[$name]}}
    }
    $activityEvidence=@($toolCounts.GetEnumerator() | Sort-Object Name | ForEach-Object {"$($_.Name)=$($_.Value)"})
}
$activityStatus=if(-not $claudePresent){'na'}elseif($activityEvidence.Count){'review'}else{'unknown'}
Add-Check 'claude-activity' 'Claude Code' '近期工具活动摘要' $activityStatus "最近 $lookback 天仅按工具名计数，不读取或展示参数与内容。" $activityEvidence '活动计数不证明具体数据已传输；需要结合实际任务、调用记录和授权范围判断。'

Add-Check 'connectors' '第三方内容' '连接器、插件与外部 API' 'unknown' '本机检查无法可靠枚举所有云端授权及其带入内容。' @('需人工检查连接器权限与实际任务') '移除不需要的连接器权限；区分可读取、已调用、已进入对话。' $false

$counts=@{pass=0;review=0;risk=0;unknown=0;info=0;na=0;manual=0;indeterminate=0}; foreach($c in $Checks){$counts[$c.status]++; if(-not $c.automated){$counts.manual++}; if($c.automated -and $c.status -eq 'unknown'){$counts.indeterminate++}}
$overall=if($counts.risk){'risk'}elseif($counts.review){'review'}elseif($counts.unknown){'unknown'}elseif($counts.pass){'pass'}else{'info'}
$readiness=if($counts.risk -or $counts.review){'hold'}else{'proceed-with-limits'}
$report=[ordered]@{
    schemaVersion=2; generatedAt=(Get-Date).ToString('o'); host=[Environment]::MachineName
    mode='offline-local'; overall=$overall; readiness=$readiness; counts=$counts; checks=$Checks
    disclaimer='这是基于可见证据的检查结果，不保证账号安全、服务可用性或政策合规。'
}
if($OutputPath){
    $parent=Split-Path -Parent $OutputPath
    if($parent -and -not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force | Out-Null}
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}
if($Json){$report | ConvertTo-Json -Depth 8 -Compress}else{[pscustomobject]$report}

