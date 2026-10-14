---
name: claude-safety-check
description: Guide first-time Windows and Firefox setup for Claude, audit the local safety and privacy posture, and present evidence in a movable desktop light dashboard. Use for Claude setup, environment checks, leak-risk reviews, permission audits, or post-update rechecks; do not use to promise account safety, bypass regional terms, or silently change system settings.
---

# Claude Safety Check

Assess the whole chain: account context, device, browser, network, location permissions, third-party inputs, and Claude Code permissions. Report evidence and uncertainty; never reduce the result to only the exit IP. This skill also guides a Windows beginner through first-time Firefox setup without handling credentials or fabricating location signals.

## Workflow

1. For first-time setup, read [references/first-use-guide.md](references/first-use-guide.md). For report interpretation or dashboard changes, read [references/check-model.md](references/check-model.md).
2. Before login, confirm that the user's actual location is currently supported using Claude's official support list. Stop when unsupported or uncertain; do not propose a workaround.
3. Install Firefox only through Mozilla or Microsoft Store. After Firefox exists, create or repair the dedicated profile only with user authorization:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}\scripts\Install-ClaudeFirefox.ps1" -ProxyPort 7892
   ```

   Confirm the real DigiLink listener port before choosing `-ProxyPort`. Explain that this changes only the dedicated Firefox profile.
4. Run the read-only collector:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}\scripts\Collect-ClaudeSafety.ps1"
   ```

   Claude Code expands `${CLAUDE_SKILL_DIR}` to the installed skill directory. In another compatible agent, resolve the directory containing this `SKILL.md` before running the script. The default run is offline and returns results without writing a report. Export JSON only when the user explicitly requests a saved report by passing `-OutputPath`.
5. Explain failed and review items first, cite the returned evidence, and keep `unknown`, `info`, `na`, and manual checks distinct from `pass`. Never summarize an untested category as “no action needed.” Do not paste the report into Claude or any external service unless the user explicitly requests that transmission.
6. When a visual check is useful, launch the local dashboard. The dashboard is part of this skill. It opens as an always-on-top, movable floating light panel; click any light or “详情” for the complete dashboard:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}\scripts\Show-ClaudeSafetyDashboard.ps1"
   ```

7. Ask whether the user wants to keep or disable IPv6 only after explaining the observed IPv6 path and side effects. Never disable IPv6 automatically.
8. Public exit-IP, DNS-leak, or WebRTC tests contact third parties. Open them only after informed user consent, and never equate a third-party score with Claude's own decision.
9. Open Claude only with `scripts/Open-ClaudeSafe.ps1` or the `Claude 安心使用` shortcut. Hand control to the user for Google/email login, passwords, emailed links, codes, CAPTCHA, age checks, and payment.
10. Offer remediation as instructions. Do not alter proxy, firewall, location, browser, DNS, or Claude permissions unless the user explicitly asks. A kill-switch test deliberately interrupts connectivity and is always a separate, explicit action.

## Interpretation rules

- Say "no issue detected by this check", never "safe" or "guaranteed".
- Treat account, billing, physical location, browser site permissions, connector data, and kill-switch behavior as locally unverifiable unless direct evidence exists. Do not ask the user to disclose those values merely to make the dashboard green.
- Keep three concepts separate: permission configured, feature invoked, and content actually entered a conversation.
- A Claude Code allow rule means capability is configured. A summarized tool-use count means activity was observed. Neither alone proves what data was transmitted.
- Mask public IP addresses and redact credentials embedded in proxy URLs.
- Keep automatic checks offline. Public exit-IP and DNS-leak services reveal a request to a third party and are outside the automatic audit.
- Treat the ClaudeSafe fail-closed proxy configuration, the local DigiLink listener, and a real disconnect test as three separate facts. None substitutes for the others.
- Keep the overview compact. Summarize process families and counts; put paths, rule names, and other technical evidence behind details.
- In the floating panel use exactly three category-lamp states: green only when the category has explicit passing evidence and no unknown or unconfirmed manual item, red for `risk` or `review`, and gray for unknown, unverified, informational-only, or not-applicable categories.
- The local dashboard may offer a reversible checkbox for checks that genuinely require human judgment. A checked item is green only as an explicit `人工确认`, is stored under the local `state` directory, and must never be described as automatically verified or committed to a repository.
- Do not infer policy compliance or eligibility from network geography. Refer the user to current service terms when that judgment matters.
- Re-run after browser, operating-system, network-tool, firewall-rule, or Claude updates.

## Configuration

Copy `references/config.example.json` to a private path and pass it with `-ConfigPath`. Expected values convert otherwise ambiguous observations such as timezone, language, and dedicated Firefox profile naming into explicit comparisons. Do not commit personal configuration or full reports.

