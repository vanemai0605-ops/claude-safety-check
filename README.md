# Claude 安心检查

一个面向 Windows 初次使用者的 Codex skill，用本地只读检查和桌面“安心灯”帮助区分：已验证、需要处理、尚未验证与不适用。

它不会保证账号安全，也不会通过修改位置、身份或付款资料来规避服务条款。使用 Claude 前，请先确认自己的实际所在地属于 [Claude 官方支持地区](https://support.claude.com/en/articles/8461763-where-can-i-access-claude)。Firefox 应从 [Mozilla 官方渠道](https://www.mozilla.org/firefox/windows/) 安装。

## 包含内容

- 7 类本地检查：账号与付款、设备环境、浏览器隔离、网络链路、隐私权限、Claude Code、第三方内容。
- 可移动、置顶的三色“安心灯”：绿为已有证据，红为需要处理，灰为未知、人工未确认或不适用。
- Firefox `ClaudeSafe` 独立 Profile 与桌面入口。
- DigiLink 本地代理端口的 fail-closed 配置模板。
- 人工确认复选框；确认结果只保存在本机，不上传敏感资料。
- 中文首次使用流程图和逐步说明。

## 安装

### 让 Codex 安装

把本仓库的 `claude-safety-check` 子目录作为 skill 安装。可以在 Codex 中说：

> 请安装 https://github.com/vanemai0605-ops/claude-safety-check 中的 claude-safety-check 子目录作为 skill。

安装完成后，在下一轮对话中说：

> 使用 claude-safety-check 帮我完成首次配置。

### 手动安装

需要 Windows 10/11 和 Windows PowerShell 5.1。首次安装在 PowerShell 中运行：

```powershell
git clone https://github.com/vanemai0605-ops/claude-safety-check.git
Set-Location .\claude-safety-check
$skillBase = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$skillDest = Join-Path $skillBase 'skills\claude-safety-check'
if (Test-Path -LiteralPath $skillDest) { throw '已有安装，请先备份本机配置和人工确认记录再更新。' }
New-Item -ItemType Directory -Path (Split-Path $skillDest -Parent) -Force | Out-Null
Copy-Item -LiteralPath .\claude-safety-check -Destination $skillDest -Recurse
```

创建安心灯桌面快捷方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$skillDest\scripts\Install-DesktopShortcut.ps1"
```

## 使用

以下命令从克隆后的仓库根目录执行。只做离线检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-safety-check\scripts\Collect-ClaudeSafety.ps1
```

打开安心灯：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-safety-check\scripts\Show-ClaudeSafetyDashboard.ps1
```

首次使用请阅读 [首次使用流程](claude-safety-check/references/first-use-guide.md)。完整状态含义见 [检查模型](claude-safety-check/references/check-model.md)。

安心灯的使用方式：按住顶部标题区域拖动；点击“详情”打开完整面板；点击“查看本类详情”查看证据；确实完成人工核对后才能勾选确认，取消勾选恢复未知。窗口每 60 秒自动复查，可手动刷新或关闭自动复查。

人工确认保存在 `claude-safety-check/state/manual-confirmations.json`，不随发布包提供。它是你上次核对的记录，环境改变后应取消旧勾选并重新检查。

## 重要限制

- 自动检查默认离线，不主动把公网 IP、DNS 或账号资料发给第三方。
- 外部 IP、DNS 泄漏与断线测试必须在用户知情后单独进行。
- 绿色表示“这项检查已有证据”，不是账号安全保证。
- 当前版本提供代理配置和断线检查指引；不会在 DigiLink 断线时自动关闭 Firefox，也不是整台电脑的断网开关。
- 网页版用户不使用 Claude Code 时，Claude Code 灯保持灰色“不适用”是正常结果。
- 防火墙、代理、IPv6、定位和浏览器设置均不得在未解释影响并取得同意时修改。

## License

MIT

