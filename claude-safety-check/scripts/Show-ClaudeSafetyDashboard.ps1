[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Full
)

$ErrorActionPreference='Stop'
$createdNew=$false
$script:singleInstanceMutex=[System.Threading.Mutex]::new($true,'Local\ClaudeSafetyLight',[ref]$createdNew)
if(-not $createdNew){exit}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

$collector=Join-Path $PSScriptRoot 'Collect-ClaudeSafety.ps1'
$colors=@{pass='#2BB673';review='#E45454';risk='#E45454';unknown='#7E8794';info='#3B82F6';na='#596273'}
$labels=@{pass='已验证通过';review='需要处理';risk='风险';unknown='无法确定';info='状态说明';na='不适用'}
$lampColors=@{pass='#2ED47A';risk='#EF4444';unknown='#8A94A3'}
$categoryOrder=@('账号与付款','设备环境','浏览器隔离','网络链路','定位权限','Claude Code','第三方内容')
$categoryNames=@{
    '账号与付款'='账号与付款'; '设备环境'='设备环境'; '浏览器隔离'='浏览器隔离'
    '网络链路'='网络链路'; '定位权限'='隐私权限'; 'Claude Code'='Claude Code'; '第三方内容'='第三方内容'
}
$categoryShort=@{
    '账号与付款'='账号'; '设备环境'='设备'; '浏览器隔离'='浏览器'; '网络链路'='网络'
    '定位权限'='隐私'; 'Claude Code'='Code'; '第三方内容'='第三方'
}
$categoryHints=@{
    '账号与付款'='登录、账号资料和付款方式'
    '设备环境'='时间、语言与键盘布局'
    '浏览器隔离'='专用 Profile、启动入口与 WebRTC'
    '网络链路'='代理、DNS、出口、路由与断线保护'
    '定位权限'='Windows 与 Firefox 定位权限'
    'Claude Code'='本地工具权限与近期活动；网页版用户通常不适用'
    '第三方内容'='连接器、插件与外部 API'
}

$script:auditRunning=$false
$script:latestReport=$null
$script:shuttingDown=$false
$script:lights=@{}
$script:manualStatePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'state\manual-confirmations.json'
$script:manualConfirmations=@{}
if(Test-Path -LiteralPath $script:manualStatePath){
    try{
        $saved=Get-Content -Raw -LiteralPath $script:manualStatePath | ConvertFrom-Json
        foreach($property in $saved.PSObject.Properties){$script:manualConfirmations[$property.Name]=[bool]$property.Value}
    }catch{}
}

function Get-Brush([string]$value){
    return [Windows.Media.BrushConverter]::new().ConvertFrom($value)
}

function Get-LampStatus($items){
    if(@($items | Where-Object {$_.status -in @('risk','review')}).Count){return 'risk'}
    if(@($items | Where-Object {($_.automated -eq $false -and $_.status -ne 'pass') -or $_.status -eq 'unknown'}).Count){return 'unknown'}
    if(@($items | Where-Object status -eq 'pass').Count){return 'pass'}
    return 'unknown'
}

function Save-ManualConfirmations {
    $parent=Split-Path -Parent $script:manualStatePath
    if(-not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force | Out-Null}
    $script:manualConfirmations | ConvertTo-Json | Set-Content -LiteralPath $script:manualStatePath -Encoding UTF8
}

function Update-ReportCounts {
    if(-not $script:latestReport){return}
    $checks=@($script:latestReport.checks)
    foreach($name in @('pass','review','risk','unknown','info','na')){
        $script:latestReport.counts.$name=@($checks | Where-Object status -eq $name).Count
    }
    $script:latestReport.counts.manual=@($checks | Where-Object {$_.automated -eq $false -and $_.status -ne 'pass'}).Count
    $script:latestReport.counts.indeterminate=@($checks | Where-Object {$_.automated -and $_.status -eq 'unknown'}).Count
    $script:latestReport.overall=if($script:latestReport.counts.risk){'risk'}elseif($script:latestReport.counts.review){'review'}elseif($script:latestReport.counts.unknown){'unknown'}elseif($script:latestReport.counts.pass){'pass'}else{'info'}
    $script:latestReport.readiness=if($script:latestReport.counts.risk -or $script:latestReport.counts.review){'hold'}else{'proceed-with-limits'}
}

function Apply-ManualConfirmations {
    if(-not $script:latestReport){return}
    foreach($check in @($script:latestReport.checks | Where-Object automated -eq $false)){
        if($script:manualConfirmations.ContainsKey([string]$check.id) -and $script:manualConfirmations[[string]$check.id]){$check.status='pass'}
        else{$check.status='unknown'}
    }
    Update-ReportCounts
}

function Set-ManualConfirmation([string]$id,[bool]$confirmed){
    if($confirmed){$script:manualConfirmations[$id]=$true}else{$script:manualConfirmations.Remove($id)}
    Save-ManualConfirmations
}

function Get-LampDescription([string]$status){
    switch($status){
        'pass' {'绿色：本类有明确证据通过'}
        'risk' {'红色：本类存在需要处理的项目'}
        default {'灰色：本类未知、未验证或不适用'}
    }
}

# Full dashboard. It is created once but remains hidden until the user asks for details.
$window=New-Object Windows.Window
$window.Title='Claude 安心检查 · 完整界面'
$window.Width=980; $window.Height=780; $window.MinWidth=820; $window.MinHeight=680
$window.Background=Get-Brush '#11151C'
$window.WindowStartupLocation='CenterScreen'

$root=New-Object Windows.Controls.DockPanel; $root.Margin='20'; $window.Content=$root
$header=New-Object Windows.Controls.StackPanel; [Windows.Controls.DockPanel]::SetDock($header,'Top'); $root.Children.Add($header)|Out-Null
$title=New-Object Windows.Controls.TextBlock; $title.Text='Claude 安心检查'; $title.FontSize=28; $title.FontWeight='SemiBold'; $title.Foreground='White'; $header.Children.Add($title)|Out-Null
$subtitle=New-Object Windows.Controls.TextBlock; $subtitle.Text='7 类本地检查总览 · 绿灯有证据，红灯需处理，灰灯仍未知'; $subtitle.Margin='0,4,0,12'; $subtitle.Foreground=Get-Brush '#AEB7C4'; $header.Children.Add($subtitle)|Out-Null
$toolbar=New-Object Windows.Controls.StackPanel; $toolbar.Orientation='Horizontal'; $header.Children.Add($toolbar)|Out-Null
$refresh=New-Object Windows.Controls.Button; $refresh.Content='重新检查'; $refresh.Padding='18,7'; $refresh.Margin='0,0,12,10'; $refresh.Background=Get-Brush '#6C63FF'; $refresh.Foreground='White'; $refresh.BorderThickness=0; $toolbar.Children.Add($refresh)|Out-Null
$autoRefresh=New-Object Windows.Controls.CheckBox; $autoRefresh.Content='每 60 秒自动复查'; $autoRefresh.IsChecked=$true; $autoRefresh.VerticalAlignment='Center'; $autoRefresh.Margin='0,0,18,10'; $autoRefresh.Foreground=Get-Brush '#D7DCE3'; $toolbar.Children.Add($autoRefresh)|Out-Null
$legend=New-Object Windows.Controls.TextBlock; $legend.Text='● 绿：已验证   ● 红：需处理   ● 灰：未知/未验证'; $legend.VerticalAlignment='Center'; $legend.Margin='0,0,0,10'; $legend.Foreground=Get-Brush '#AEB7C4'; $toolbar.Children.Add($legend)|Out-Null
$summary=New-Object Windows.Controls.TextBlock; $summary.FontSize=16; $summary.Margin='0,0,0,10'; $summary.Foreground='White'; $summary.TextWrapping='Wrap'; $header.Children.Add($summary)|Out-Null
$cards=New-Object Windows.Controls.Primitives.UniformGrid; $cards.Columns=2; $cards.Rows=4; $root.Children.Add($cards)|Out-Null

function Add-DetailCard($panel,$check){
    $border=New-Object Windows.Controls.Border; $border.Background=Get-Brush '#1B222D'; $border.CornerRadius=8; $border.Padding=12; $border.Margin='0,0,0,9'
    $body=New-Object Windows.Controls.StackPanel; $border.Child=$body
    $heading=New-Object Windows.Controls.TextBlock; $heading.Text="$(if(-not $check.automated -and $check.status -eq 'pass'){'人工确认'}else{$labels[$check.status]}) · $($check.title)"; $heading.FontSize=16; $heading.FontWeight='SemiBold'; $heading.Foreground=Get-Brush $colors[$check.status]; $body.Children.Add($heading)|Out-Null
    $desc=New-Object Windows.Controls.TextBlock; $desc.Text=$check.summary; $desc.TextWrapping='Wrap'; $desc.Margin='0,4,0,3'; $desc.Foreground=Get-Brush '#D7DCE3'; $body.Children.Add($desc)|Out-Null
    $evidence=@($check.evidence)
    if($evidence.Count){
        $shown=@($evidence | Select-Object -First 4)
        if($evidence.Count -gt 4){$shown += "……另有 $($evidence.Count-4) 条技术记录"}
        $ev=New-Object Windows.Controls.TextBlock; $ev.Text=($shown -join "`n"); $ev.TextWrapping='Wrap'; $ev.FontFamily='Consolas'; $ev.FontSize=11; $ev.Foreground=Get-Brush '#8FA0B5'; $body.Children.Add($ev)|Out-Null
    }
    $tip=New-Object Windows.Controls.TextBlock; $tip.Text="建议：$($check.remediation)"; $tip.TextWrapping='Wrap'; $tip.Margin='0,6,0,0'; $tip.Foreground=Get-Brush '#AEB7C4'; $body.Children.Add($tip)|Out-Null
    if(-not $check.automated){
        $confirm=New-Object Windows.Controls.CheckBox; $confirm.IsChecked=($check.status -eq 'pass'); $confirm.Margin='0,10,0,0'; $confirm.Foreground=Get-Brush '#D7DCE3'
        $confirmText=New-Object Windows.Controls.TextBlock; $confirmText.Text="我已人工核对并确认：$($check.remediation)"; $confirmText.TextWrapping='Wrap'; $confirm.Content=$confirmText
        $confirm.Tag=[pscustomobject]@{Check=$check;Heading=$heading}
        $confirm.Add_Click({
            param($sender,$eventArgs)
            $confirmed=($sender.IsChecked -eq $true); $target=$sender.Tag.Check
            Set-ManualConfirmation ([string]$target.id) $confirmed
            $target.status=if($confirmed){'pass'}else{'unknown'}
            $sender.Tag.Heading.Text="$(if($confirmed){'人工确认'}else{'无法确定'}) · $($target.title)"
            $sender.Tag.Heading.Foreground=Get-Brush $colors[$target.status]
            Apply-ManualConfirmations; Update-FullDashboard; Update-FloatingWindow
        })
        $body.Children.Add($confirm)|Out-Null
        $savedNote=New-Object Windows.Controls.TextBlock; $savedNote.Text='此选择仅保存在本机，可随时取消；不会上传账号或付款资料。'; $savedNote.FontSize=11; $savedNote.Margin='20,3,0,0'; $savedNote.Foreground=Get-Brush '#8FA0B5'; $body.Children.Add($savedNote)|Out-Null
    }
    $panel.Children.Add($border)|Out-Null
}

function Show-CategoryDetails([string]$category){
    if(-not $script:latestReport){return}
    $items=@($script:latestReport.checks | Where-Object category -eq $category)
    $detail=New-Object Windows.Window
    $detail.Title="$($categoryNames[$category]) · 详细项目"
    $detail.Width=760; $detail.Height=650; $detail.MinWidth=620; $detail.MinHeight=460
    $detail.Background=Get-Brush '#11151C'; $detail.WindowStartupLocation='CenterOwner'; $detail.Owner=$window
    $detailRoot=New-Object Windows.Controls.DockPanel; $detailRoot.Margin='18'; $detail.Content=$detailRoot
    $detailTitle=New-Object Windows.Controls.TextBlock; $detailTitle.Text="$($categoryNames[$category]) · 详细项目"; $detailTitle.FontSize=24; $detailTitle.FontWeight='SemiBold'; $detailTitle.Foreground='White'; $detailTitle.Margin='0,0,0,12'; [Windows.Controls.DockPanel]::SetDock($detailTitle,'Top'); $detailRoot.Children.Add($detailTitle)|Out-Null
    $detailScroll=New-Object Windows.Controls.ScrollViewer; $detailScroll.VerticalScrollBarVisibility='Auto'; $detailRoot.Children.Add($detailScroll)|Out-Null
    $detailPanel=New-Object Windows.Controls.StackPanel; $detailScroll.Content=$detailPanel
    foreach($item in @($items | Sort-Object @{Expression={switch($_.status){'risk'{0};'review'{1};'unknown'{2};'pass'{3};'info'{4};default{5}}}})){Add-DetailCard $detailPanel $item}
    $detail.ShowDialog()|Out-Null
}

function Add-CategoryCard([string]$category,$items){
    $risk=@($items | Where-Object status -eq 'risk').Count
    $review=@($items | Where-Object status -eq 'review').Count
    $pass=@($items | Where-Object status -eq 'pass').Count
    $info=@($items | Where-Object status -eq 'info').Count
    $unknown=@($items | Where-Object status -eq 'unknown').Count
    $na=@($items | Where-Object status -eq 'na').Count
    $manual=@($items | Where-Object {$_.automated -eq $false -and $_.status -ne 'pass'}).Count
    $indeterminate=@($items | Where-Object {$_.automated -and $_.status -eq 'unknown'}).Count
    $action=$risk+$review
    $lampStatus=Get-LampStatus $items
    $badgeLabel=if($lampStatus -eq 'risk'){'红灯 · 需要处理'}elseif($lampStatus -eq 'pass'){'绿灯 · 已验证'}else{'灰灯 · 尚未验证'}
    $badgeColor=$lampColors[$lampStatus]
    $resultText=if($action){"发现 $action 项需要处理"}elseif($manual){"有 $manual 项本机不能自动验证"}elseif($indeterminate){"有 $indeterminate 项已尝试检查但无法确定"}elseif($pass){'已检查的项目有明确通过证据'}elseif($na -eq $items.Count){'当前环境不使用此功能'}else{'仅完成状态盘点，不作安全结论'}

    $border=New-Object Windows.Controls.Border; $border.Background=Get-Brush '#1B222D'; $border.CornerRadius=9; $border.Padding=13; $border.Margin='0,0,10,10'
    $body=New-Object Windows.Controls.StackPanel; $border.Child=$body
    $top=New-Object Windows.Controls.DockPanel; $body.Children.Add($top)|Out-Null
    $badge=New-Object Windows.Controls.Border; $badge.Background=Get-Brush $badgeColor; $badge.CornerRadius=10; $badge.Padding='8,3'; $badge.HorizontalAlignment='Right'; [Windows.Controls.DockPanel]::SetDock($badge,'Right'); $top.Children.Add($badge)|Out-Null
    $badgeText=New-Object Windows.Controls.TextBlock; $badgeText.Text=$badgeLabel; $badgeText.Foreground='White'; $badgeText.FontWeight='Bold'; $badge.Child=$badgeText
    $heading=New-Object Windows.Controls.TextBlock; $heading.Text=$categoryNames[$category]; $heading.FontSize=19; $heading.FontWeight='SemiBold'; $heading.Foreground='White'; $top.Children.Add($heading)|Out-Null
    $hint=New-Object Windows.Controls.TextBlock; $hint.Text=$categoryHints[$category]; $hint.TextWrapping='Wrap'; $hint.Margin='0,5,0,3'; $hint.Foreground=Get-Brush '#AEB7C4'; $body.Children.Add($hint)|Out-Null
    $result=New-Object Windows.Controls.TextBlock; $result.Text=$resultText; $result.Foreground=Get-Brush $(if($action){$badgeColor}else{'#D7DCE3'}); $body.Children.Add($result)|Out-Null
    $counts=New-Object Windows.Controls.TextBlock; $counts.Text="通过 $pass · 说明 $info · 无法确定 $indeterminate · 人工 $manual · 不适用 $na"; $counts.FontSize=11; $counts.Margin='0,4,0,5'; $counts.Foreground=Get-Brush '#8FA0B5'; $body.Children.Add($counts)|Out-Null
    $button=New-Object Windows.Controls.Button; $button.Content='查看本类详情'; $button.Tag=$category; $button.HorizontalAlignment='Right'; $button.Margin='0,-8,6,0'; $button.Padding='12,2'; $button.Background=Get-Brush '#2A3442'; $button.Foreground='White'; $button.BorderThickness=0
    $button.Add_Click({param($sender,$eventArgs) Show-CategoryDetails ([string]$sender.Tag)})
    $body.Children.Add($button)|Out-Null
    $cards.Children.Add($border)|Out-Null
}

function Update-FullDashboard {
    if(-not $script:latestReport){return}
    $report=$script:latestReport
    $cards.Children.Clear()
    $stamp=([datetime]$report.generatedAt).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
    $readinessText=if($report.readiness -eq 'hold'){'当前建议：先处理红灯项目，暂不要打开 Claude'}else{'当前建议：可以继续，但灰灯项目仍未完整验证'}
    $summary.Text="$readinessText`n通过 $($report.counts.pass) · 人工验证 $($report.counts.manual) · 无法确定 $($report.counts.indeterminate) · 需处理 $($report.counts.review) · 风险 $($report.counts.risk)   |   $stamp"
    $summary.Foreground=Get-Brush $(if($report.readiness -eq 'hold'){$lampColors.risk}else{$lampColors.pass})
    foreach($category in $categoryOrder){
        $items=@($report.checks | Where-Object category -eq $category)
        Add-CategoryCard $category $items
    }
}

function Show-FullDashboard {
    Update-FullDashboard
    if(-not $window.IsVisible){$window.Show()}
    if($window.WindowState -eq 'Minimized'){$window.WindowState='Normal'}
    $window.Activate()|Out-Null
}

# Floating window shown by default.
$floating=New-Object Windows.Window
$script:floatingWindow=$floating
$floating.Title='Claude 安心灯'
$floating.Width=445; $floating.SizeToContent='Height'
$floating.WindowStyle='None'; $floating.ResizeMode='NoResize'; $floating.AllowsTransparency=$true
$floating.Background=[Windows.Media.Brushes]::Transparent; $floating.Topmost=$true; $floating.ShowInTaskbar=$false
$floating.WindowStartupLocation='Manual'

$shell=New-Object Windows.Controls.Border
$shell.Background=Get-Brush '#F211151C'; $shell.BorderBrush=Get-Brush '#445064'; $shell.BorderThickness=1
$shell.CornerRadius=14; $shell.Padding='10,7'; $floating.Content=$shell
$shadow=New-Object Windows.Media.Effects.DropShadowEffect; $shadow.BlurRadius=20; $shadow.ShadowDepth=4; $shadow.Opacity=.45; $shadow.Color=[Windows.Media.Colors]::Black; $shell.Effect=$shadow
$floatRoot=New-Object Windows.Controls.StackPanel; $shell.Child=$floatRoot

$floatHeader=New-Object Windows.Controls.DockPanel; $floatRoot.Children.Add($floatHeader)|Out-Null
$floatActions=New-Object Windows.Controls.StackPanel; $floatActions.Orientation='Horizontal'; [Windows.Controls.DockPanel]::SetDock($floatActions,'Right'); $floatHeader.Children.Add($floatActions)|Out-Null
$floatRefresh=New-Object Windows.Controls.Button; $floatRefresh.Content='↻'; $floatRefresh.ToolTip='立即重新检查'; $floatRefresh.Width=24; $floatRefresh.Height=22; $floatRefresh.Margin='3,0,0,0'; $floatRefresh.Background=Get-Brush '#2A3442'; $floatRefresh.Foreground='White'; $floatRefresh.BorderThickness=0; $floatActions.Children.Add($floatRefresh)|Out-Null
$openFull=New-Object Windows.Controls.Button; $openFull.Content='详情'; $openFull.ToolTip='打开完整检查界面'; $openFull.Padding='8,2'; $openFull.Margin='3,0,0,0'; $openFull.Background=Get-Brush '#6C63FF'; $openFull.Foreground='White'; $openFull.BorderThickness=0; $floatActions.Children.Add($openFull)|Out-Null
$closeFloat=New-Object Windows.Controls.Button; $closeFloat.Content='×'; $closeFloat.ToolTip='关闭安心灯'; $closeFloat.Width=24; $closeFloat.Height=22; $closeFloat.Margin='3,0,0,0'; $closeFloat.Background=Get-Brush '#2A3442'; $closeFloat.Foreground='White'; $closeFloat.BorderThickness=0; $floatActions.Children.Add($closeFloat)|Out-Null

$dragArea=New-Object Windows.Controls.StackPanel; $dragArea.Orientation='Horizontal'; $dragArea.Cursor='SizeAll'; $dragArea.Background=[Windows.Media.Brushes]::Transparent; $dragArea.ToolTip='按住这里可移动悬浮窗；双击打开完整界面'; $floatHeader.Children.Add($dragArea)|Out-Null
$overallDot=New-Object Windows.Shapes.Ellipse; $overallDot.Width=11; $overallDot.Height=11; $overallDot.Fill=Get-Brush $lampColors.unknown; $overallDot.Margin='0,3,6,0'; $dragArea.Children.Add($overallDot)|Out-Null
$floatTitle=New-Object Windows.Controls.TextBlock; $floatTitle.Text='Claude 安心灯'; $floatTitle.FontSize=15; $floatTitle.FontWeight='SemiBold'; $floatTitle.Foreground='White'; $dragArea.Children.Add($floatTitle)|Out-Null
$floatState=New-Object Windows.Controls.TextBlock; $floatState.Text='检查中…'; $floatState.Margin='7,2,0,0'; $floatState.FontSize=11; $floatState.Foreground=Get-Brush '#AEB7C4'; $dragArea.Children.Add($floatState)|Out-Null

$lampGrid=New-Object Windows.Controls.Primitives.UniformGrid; $lampGrid.Columns=7; $lampGrid.Margin='0,6,0,0'; $floatRoot.Children.Add($lampGrid)|Out-Null
foreach($category in $categoryOrder){
    $button=New-Object Windows.Controls.Button; $button.Tag=$category; $button.Background=[Windows.Media.Brushes]::Transparent; $button.BorderThickness=0; $button.Padding='1'; $button.Cursor='Hand'
    $stack=New-Object Windows.Controls.StackPanel; $button.Content=$stack
    $dot=New-Object Windows.Shapes.Ellipse; $dot.Width=13; $dot.Height=13; $dot.HorizontalAlignment='Center'; $dot.Fill=Get-Brush $lampColors.unknown; $stack.Children.Add($dot)|Out-Null
    $text=New-Object Windows.Controls.TextBlock; $text.Text=$categoryShort[$category]; $text.HorizontalAlignment='Center'; $text.Margin='0,2,0,0'; $text.FontSize=10; $text.Foreground=Get-Brush '#D7DCE3'; $stack.Children.Add($text)|Out-Null
    $button.ToolTip="$($categoryNames[$category])：等待检查。点击打开完整界面。"
    $button.Add_Click({Show-FullDashboard})
    $lampGrid.Children.Add($button)|Out-Null
    $script:lights[$category]=[pscustomobject]@{Button=$button;Dot=$dot}
}

function Update-FloatingWindow {
    if(-not $script:latestReport){return}
    $red=0; $green=0; $gray=0
    foreach($category in $categoryOrder){
        $items=@($script:latestReport.checks | Where-Object category -eq $category)
        $status=Get-LampStatus $items
        if($status -eq 'risk'){$red++}elseif($status -eq 'pass'){$green++}else{$gray++}
        $lamp=$script:lights[$category]
        $lamp.Dot.Fill=Get-Brush $lampColors[$status]
        $lamp.Button.ToolTip="$($categoryNames[$category])：$(Get-LampDescription $status)。点击打开完整界面。"
    }
    $overall=if($red){'risk'}elseif($gray){'unknown'}else{'pass'}
    $overallDot.Fill=Get-Brush $lampColors[$overall]
    $floatState.Text=if($red){"$red 个红灯，需要处理"}elseif($gray){"$green 个绿灯，$gray 个灰灯"}else{'全部项目均有通过证据'}
    $floatState.Foreground=Get-Brush $lampColors[$overall]
    $stamp=([datetime]$script:latestReport.generatedAt).ToLocalTime().ToString('HH:mm:ss')
    $floatState.ToolTip="最近更新 $stamp；每 60 秒自动复查"
}

function Run-Audit {
    if($script:auditRunning){return}
    $script:auditRunning=$true
    $refresh.IsEnabled=$false; $refresh.Content='检查中…'; $floatRefresh.IsEnabled=$false
    $floating.Cursor='Wait'; if($window.IsVisible){$window.Cursor='Wait'}
    try{
        $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$collector,'-Json')
        if($ConfigPath){$args += @('-ConfigPath',$ConfigPath)}
        $raw=& powershell @args
        if($LASTEXITCODE -ne 0){throw '采集器返回错误。'}
        $script:latestReport=($raw -join "`n") | ConvertFrom-Json
        Apply-ManualConfirmations
        Update-FloatingWindow
        Update-FullDashboard
    }catch{
        $overallDot.Fill=Get-Brush $lampColors.unknown
        $floatState.Text='检查失败，点击 ↻ 重试'; $floatState.Foreground=Get-Brush $lampColors.unknown
        if($window.IsVisible){[Windows.MessageBox]::Show("检查失败：$($_.Exception.Message)",'Claude 安心检查','OK','Error')|Out-Null}
    }finally{
        $refresh.IsEnabled=$true; $refresh.Content='重新检查'; $floatRefresh.IsEnabled=$true
        $floating.Cursor=$null; $window.Cursor=$null; $script:auditRunning=$false
    }
}

$refresh.Add_Click({Run-Audit})
$floatRefresh.Add_Click({Run-Audit})
$openFull.Add_Click({Show-FullDashboard})
$dragArea.Add_MouseLeftButtonDown({
    param($sender,$eventArgs)
    if($eventArgs.ClickCount -ge 2){Show-FullDashboard; $eventArgs.Handled=$true; return}
    if($eventArgs.LeftButton -eq [Windows.Input.MouseButtonState]::Pressed){
        try{$floating.DragMove()}catch{}
        $eventArgs.Handled=$true
    }
})
$closeFloat.Add_Click({
    $script:shuttingDown=$true
    $timer.Stop()
    if($window.IsVisible){$window.Close()}
    try{$script:singleInstanceMutex.ReleaseMutex()}catch{}
    $script:singleInstanceMutex.Dispose()
    $floating.Close()
})
$window.Add_Closing({param($sender,$eventArgs) if(-not $script:shuttingDown){$eventArgs.Cancel=$true; $sender.Hide()}})

$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromSeconds(60)
$timer.Add_Tick({if($autoRefresh.IsChecked){Run-Audit}})
$timer.Start()
$floating.Add_ContentRendered({
    $work=[Windows.SystemParameters]::WorkArea
    $floating.Left=$work.Right-$floating.ActualWidth-24
    $floating.Top=$work.Bottom-$floating.ActualHeight-24
    Run-Audit
    if($Full){Show-FullDashboard}
})
$floating.ShowDialog()|Out-Null
